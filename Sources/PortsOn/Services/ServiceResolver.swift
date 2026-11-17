import Foundation

/// Resolves a PortEntry to the best-known friendly service name.
/// Layered registry (ADR-007): process fingerprint > known-port > fallback.
public struct ServiceResolver: Sendable {
    public let registry: [ServiceInfo]

    public init(registry: [ServiceInfo] = ServiceInfo.builtin) {
        self.registry = registry
    }

    /// Returns a display label and the matched service (if any).
    ///
    /// Precedence per ADR-007: process fingerprint > known-port > fallback. The process
    /// actually listening is stronger evidence than the port number — a dev server on
    /// port 4096 is opencode, not "omp", even though 4096 is a known omp port.
    public func resolve(_ entry: PortEntry) -> (label: String, service: ServiceInfo?) {
        // 1. process-name fingerprint (strongest signal)
        if let name = entry.processName?.lowercased(),
           let byProc = registry.first(where: { svc in
               svc.processNames.contains { p in name == p || name.hasPrefix(p) }
           }) {
            return (byProc.displayName, byProc)
        }
        // 2. known-port match
        if let byPort = registry.first(where: { $0.knownPorts.contains(entry.port) }) {
            return (byPort.displayName, byPort)
        }
        // 3. fallback: short basename of the process (lsof already gives a clean name,
        //    but be defensive in case a path ever sneaks in).
        let raw = entry.processName ?? "unknown"
        let base = (raw as NSString).lastPathComponent
        return (base.isEmpty ? raw : base, nil)
    }
}
