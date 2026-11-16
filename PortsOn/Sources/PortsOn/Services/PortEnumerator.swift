import Foundation

/// Errors from the enumeration layer.
public enum PortScanError: Error, Sendable {
    case lsofUnavailable
    case lsofFailed(String)
}

/// Protocol so the scan engine can be swapped (libproc later, mocks in tests).
public protocol PortEnumerating: Sendable {
    func listListeningTCP() async throws -> [PortEntry]
}

/// Primary implementation: parse `lsof -nP -iTCP -sTCP:LISTEN`. Validated on Tahoe 26.7.3.
/// ADR-002 chose sysctl/libproc as primary; on this host libproc needs deeper private-struct
/// parsing that a first cut can't safely do, so lsof is primary with a clean seam to swap.
public struct LsofPortEnumerator: PortEnumerating {
    public init() {}

    public func listListeningTCP() async throws -> [PortEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw PortScanError.lsofUnavailable
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(data: (process.standardError as! Pipe).fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PortScanError.lsofFailed(err)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw PortScanError.lsofFailed("non-UTF8 output")
        }
        return Self.parse(text)
    }

    /// Pure parser, unit-testable without spawning lsof.
    static func parse(_ text: String) -> [PortEntry] {
        var entries: [PortEntry] = []
        var seen = Set<String>()
        for line in text.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // Real lsof LISTEN columns: 0 COMMAND,1 PID,2 USER,3 FD,4 TYPE(IPv4/IPv6),
            // 5 DEVICE,6 SIZE/OFF,7 NODE(TCP),8 NAME(host:port),9 (LISTEN)
            guard cols.count >= 9 else { continue }
            let command = cols[0]
            let pid = Int32(cols[1])
            let user = cols[2]
            guard cols[7].uppercased() == "TCP" else { continue }
            let af: PortEntry.AddressFamily = cols[4].uppercased().contains("V6") ? .ipv6 : .ipv4
            guard let (port, bind) = parseAddress(cols[8]) else { continue }
            let id = "\(af.rawValue)-\(port)-\(pid.map(String.init) ?? "?")-\(bind)"
            guard seen.insert(id).inserted else { continue }
            entries.append(PortEntry(
                port: port, addressFamily: af, bindAddress: bind,
                pid: pid, processName: command, user: user
            ))
        }
        return entries
    }

    /// Parse "127.0.0.1:49532" or "*:7000" into (port, bindAddress).
    static func parseAddress(_ name: String) -> (UInt16, String)? {
        guard let idx = name.lastIndex(of: ":") else { return nil }
        let host = String(name[name.startIndex..<idx])
        let portPart = String(name[name.index(after: idx)...])
        guard let port = UInt16(portPart) else { return nil }
        let bind = (host == "*") ? "0.0.0.0" : host
        return (port, bind)
    }
}
