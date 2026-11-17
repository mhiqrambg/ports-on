import Foundation

/// Resolves a PortEntry to the best-known friendly service name.
/// Layered registry (ADR-007): overrides > process fingerprint > known-port.
public struct ServiceResolver: Sendable {
    public let registry: [ServiceInfo]

    public init(registry: [ServiceInfo] = ServiceInfo.builtin) {
        self.registry = registry
    }

    /// Returns a display label and the matched service (if any).
    public func resolve(_ entry: PortEntry) -> (label: String, service: ServiceInfo?) {
        // 1. known-port match
        if let byPort = registry.first(where: { $0.knownPorts.contains(entry.port) }) {
            return (byPort.displayName, byPort)
        }
        // 2. process-name fingerprint
        if let name = entry.processName?.lowercased(),
           let byProc = registry.first(where: { svc in
               svc.processNames.contains { p in name == p || name.hasPrefix(p) }
           }) {
            return (byProc.displayName, byProc)
        }
        // 3. fallback: short basename of the process (lsof already gives a clean name,
        //    but be defensive in case a path ever sneaks in).
        let raw = entry.processName ?? "unknown"
        let base = (raw as NSString).lastPathComponent
        return (base.isEmpty ? raw : base, nil)
    }
}
