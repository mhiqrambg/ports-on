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

/// Primary implementation: run `lsof -nP -iTCP -sTCP:LISTEN -F0pnLct` and parse its
/// NUL-delimited `-F` output, then resolve full process names via `ps`.
///
/// Why not the human-column format: lsof truncates the COMMAND column to ~9 chars and
/// escapes spaces as `\x20`, so a process like "Code Helper" rendered as `Code\x20H` and
/// broke naive space-splitting. The `-F0` format carries each field verbatim (spaces and
/// all) with no truncation ambiguity, and `ps -p PID -o comm=` gives the full name.
/// ADR-002's sysctl/libproc primary isn't safely doable in a first cut, so lsof ships
/// behind the `PortEnumerating` seam (swap later).
public struct LsofPortEnumerator: PortEnumerating {
    public init() {}

    public func listListeningTCP() async throws -> [PortEntry] {
        let raw = try Self.runLsof()
        var entries = Self.parse(raw)
        Self.resolveProcessNames(&entries)
        return entries
    }

    // MARK: - lsof invocation

    static func runLsof() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // -0: NUL field separator; -F: emit only selected fields.
        // p=pid, n=name(host:port), L=login(user), c=command, t=type(IPv4/IPv6)
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F0pnLct"]
        let pipe = Pipe()
        process.standardOutput = pipe
        let errPipe = Pipe()
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            throw PortScanError.lsofUnavailable
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PortScanError.lsofFailed(err)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw PortScanError.lsofFailed("non-UTF8 output")
        }
        return text
    }

    private struct Pending {
        var pid: pid_t?
        var command: String?
        var user: String?
        var family: PortEntry.AddressFamily = .ipv4
        var name: String?

        /// Build a PortEntry from the current process + the socket's last-seen name.
        func makeEntry() -> PortEntry? {
            guard let name, let (port, bind) = LsofPortEnumerator.parseAddress(name) else { return nil }
            return PortEntry(
                port: port,
                addressFamily: family,
                bindAddress: bind,
                pid: pid,
                processName: command,
                user: user
            )
        }
    }

    /// Parse the NUL-delimited `lsof -F0` stream into entries. Fields are single-char
    /// prefixed: p(pid) c(command) L(login) t(type) n(name) f(fd). A `p` starts a new
    /// process record; each `f`+`t`+`n` after it is one socket.
    static func parse(_ text: String) -> [PortEntry] {
        var entries: [PortEntry] = []
        var seen = Set<String>()
        var pending = Pending()

        // The stream is NUL-separated; lsof starts each process record with a newline
        // before its `p` field, so split on NUL and trim leading newlines.
        for rawField in text.split(separator: "\0", omittingEmptySubsequences: true) {
            let field = rawField.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            guard let first = field.first else { continue }
            let value = String(field.dropFirst())
            switch first {
            case "p":
                // New process: flush nothing (sockets emit as we go), reset socket state.
                pending.pid = pid_t(value)
                pending.family = .ipv4
                pending.name = nil
            case "c":
                pending.command = value
            case "L":
                pending.user = value
            case "t":
                pending.family = value.uppercased().contains("V6") ? .ipv6 : .ipv4
            case "n":
                pending.name = value
                if let entry = pending.makeEntry() {
                    let id = "\(entry.addressFamily.rawValue)-\(entry.port)-\(entry.pid.map(String.init) ?? "?")-\(entry.bindAddress)"
                    if seen.insert(id).inserted {
                        entries.append(entry)
                    }
                }
                pending.name = nil
            default:
                break // f (fd), and anything else, ignore
            }
        }
        return entries
    }


    // MARK: - address parsing

    /// Parse "127.0.0.1:49532", "*:7000", or "[::1]:8787" into (port, bindAddress).
    static func parseAddress(_ name: String) -> (UInt16, String)? {
        guard let idx = name.lastIndex(of: ":") else { return nil }
        let portPart = String(name[name.index(after: idx)...])
        guard let port = UInt16(portPart) else { return nil }
        var host = String(name[name.startIndex..<idx])
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        let bind = (host == "*") ? "0.0.0.0" : host
        return (port, bind)
    }

    // MARK: - full process-name resolution

    /// lsof's `c` field truncates long command names. For each distinct PID, ask `ps` for
    /// the full name and patch it in. Missing PIDs (exited between scans) keep lsof's value.
    static func resolveProcessNames(_ entries: inout [PortEntry]) {
        let pids = Array(Set(entries.compactMap(\.pid)))
        guard !pids.isEmpty else { return }
        let names = fullNames(for: pids)
        guard !names.isEmpty else { return }
        entries = entries.map { entry in
            guard let pid = entry.pid, let full = names[pid] else { return entry }
            return PortEntry(
                port: entry.port, addressFamily: entry.addressFamily,
                bindAddress: entry.bindAddress, pid: pid,
                processName: full, user: entry.user
            )
        }
    }

    /// One `ps` call for all PIDs. Returns pid -> full command name.
    static func fullNames(for pids: [pid_t]) -> [pid_t: String] {
        var result: [pid_t: String] = [:]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", pids.map(String.init).joined(separator: ","), "-o", "pid=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return result }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return result }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " ") else { continue }
            let pidPart = String(trimmed[trimmed.startIndex..<space])
            let namePart = String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            guard let pid = pid_t(pidPart) else { continue }
            result[pid] = namePart
        }
        return result
    }
}
