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
/// NUL-delimited `-F` output.
///
/// lsof's `c` field in `-F0` mode carries the full, unescaped process name (e.g.
/// "Code Helper (Plugin)", "Google Chrome for Testing"). This is the cleanest source:
/// the human-column format truncates to ~9 chars and escapes spaces as `\x20`, and
/// `ps -o comm=` returns a full path while `ucomm=` truncates to 15 chars — so neither
/// ps variant is usable for display. We trust lsof's `c` field directly.
/// ADR-002's sysctl/libproc primary isn't safely doable in a first cut, so lsof ships
/// behind the `PortEnumerating` seam (swap later).
public struct LsofPortEnumerator: PortEnumerating {
    public init() {}

    public func listListeningTCP() async throws -> [PortEntry] {
        let raw = try Self.runLsof()
        return Self.parse(raw)
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
                addressFamilies: [family],
                bindAddress: bind,
                pid: pid,
                processName: command,
                user: user
            )
        }
    }

    /// Merge `other` into `base`: union the address families, prefer a wildcard bind.
    /// A service listening on both IPv4 (`*:port`) and IPv6 (`::port`) collapses to one
    /// row bound on all interfaces.
    private static func merge(_ base: inout PortEntry, _ other: PortEntry) {
        let families = base.addressFamilies.union(other.addressFamilies)
        let bind = (base.isPubliclyBound ? base.bindAddress : other.bindAddress)
        base = PortEntry(
            port: base.port,
            addressFamilies: families,
            bindAddress: bind,
            pid: base.pid,
            processName: base.processName,
            user: base.user
        )
    }

    /// Parse the NUL-delimited `lsof -F0` stream into entries. Fields are single-char
    /// prefixed: p(pid) c(command) L(login) t(type) n(name) f(fd). A `p` starts a new
    /// process record; each `f`+`t`+`n` after it is one socket. Sockets on the same
    /// (port, pid) are merged into a single dual-stack row.
    static func parse(_ text: String) -> [PortEntry] {
        var merged: [String: PortEntry] = [:]
        var order: [String] = []
        var pending = Pending()

        // The stream is NUL-separated; lsof starts each process record with a newline
        // before its `p` field, so split on NUL and trim leading newlines.
        for rawField in text.split(separator: "\0", omittingEmptySubsequences: true) {
            let field = rawField.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            guard let first = field.first else { continue }
            let value = String(field.dropFirst())
            switch first {
            case "p":
                // New process record; reset socket state.
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
                    let key = "\(entry.port)-\(entry.pid.map(String.init) ?? "?")-\(entry.user ?? "")"
                    if var existing = merged[key] {
                        merge(&existing, entry)
                        merged[key] = existing
                    } else {
                        merged[key] = entry
                        order.append(key)
                    }
                }
                pending.name = nil
            default:
                break // f (fd), and anything else, ignore
            }
        }
        return order.compactMap { merged[$0] }
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

}
