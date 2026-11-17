import Foundation

/// One listening TCP port and the process that owns it. A port bound on both IPv4 and
/// IPv6 is a single row (dual-stack), not two.
public struct PortEntry: Identifiable, Hashable, Equatable, Sendable {
    public let port: UInt16
    /// Every address family this socket is bound on.
    public let addressFamilies: Set<AddressFamily>
    /// Loopback, wildcard (all interfaces), or a specific address.
    public let bindAddress: String
    public let pid: pid_t?
    public let processName: String?
    public let user: String?

    public var id: String { "\(port)-\(pid.map(String.init) ?? "?")-\(bindAddress)" }

    /// True when the port is bound to all interfaces (not loopback-only).
    public var isPubliclyBound: Bool {
        bindAddress == "0.0.0.0" || bindAddress == "::"
    }

    /// Short label for the address families, e.g. "IPv4+IPv6", "IPv4".
    public var familyLabel: String {
        let order: [AddressFamily] = [.ipv4, .ipv6]
        let present = order.filter { addressFamilies.contains($0) }
        return present.map(\.label).joined(separator: "+")
    }

    public enum AddressFamily: String, Sendable, Hashable {
        case ipv4
        case ipv6

        var label: String {
            switch self {
            case .ipv4: return "IPv4"
            case .ipv6: return "IPv6"
            }
        }
    }
}

