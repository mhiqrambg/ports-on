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

/// Known local services we can recognize by port or process name.
public struct ServiceInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let knownPorts: Set<UInt16>
    public let processNames: Set<String>
}

extension ServiceInfo {
    /// Identification relies primarily on the PROCESS NAME, which is stable regardless of
    /// what port a service is configured to listen on. `knownPorts` is only a fallback hint
    /// for processes we cannot see by name (e.g. the process shows a generic name), so it
    /// intentionally holds ONLY well-known IANA / documented-default ports. Dev servers
    /// (next, astro, vite, rails, django, php, opencode…) are deliberately left WITHOUT a
    /// knownPort because their port is user-configurable and routinely changes — guessing a
    /// fixed number produced false labels (opencode was mislabeled "omp" on 4096).
    public static let builtin: [ServiceInfo] = [
        ServiceInfo(id: "nginx", displayName: "nginx",
                    knownPorts: [80, 443],
                    processNames: ["nginx"]),
        ServiceInfo(id: "docker", displayName: "Docker",
                    knownPorts: [2375, 2376],
                    processNames: ["docker", "dockerd", "com.docker.backend", "com.docker"]),
        ServiceInfo(id: "postgres", displayName: "PostgreSQL",
                    knownPorts: [5432], processNames: ["postgres"]),
        ServiceInfo(id: "mysql", displayName: "MySQL",
                    knownPorts: [3306, 33060], processNames: ["mysqld"]),
        ServiceInfo(id: "redis", displayName: "Redis",
                    knownPorts: [6379], processNames: ["redis-server"]),
        ServiceInfo(id: "mongodb", displayName: "MongoDB",
                    knownPorts: [27017], processNames: ["mongod"]),
        ServiceInfo(id: "nodejs", displayName: "Node.js",
                    knownPorts: [], processNames: ["node"]),
        ServiceInfo(id: "nextjs", displayName: "Next.js",
                    knownPorts: [], processNames: ["next-server", "next"]),
        ServiceInfo(id: "astro", displayName: "Astro",
                    knownPorts: [], processNames: ["astro"]),
        ServiceInfo(id: "vite", displayName: "Vite",
                    knownPorts: [], processNames: ["vite"]),
        ServiceInfo(id: "django", displayName: "Django",
                    knownPorts: [], processNames: ["python", "manage.py"]),
        ServiceInfo(id: "rails", displayName: "Rails",
                    knownPorts: [], processNames: ["ruby", "rails"]),
        ServiceInfo(id: "php", displayName: "PHP",
                    knownPorts: [], processNames: ["php-fpm", "php"]),
        ServiceInfo(id: "opencode", displayName: "OpenCode",
                    knownPorts: [], processNames: ["opencode"]),
        // omp is a CLI/agent (stdio); identify by process name only — no fixed port.
        ServiceInfo(id: "omp", displayName: "omp",
                    knownPorts: [], processNames: ["omp"]),
        // AirPlay/Continuity are macOS system services on fixed ports.
        ServiceInfo(id: "airplay", displayName: "AirPlay",
                    knownPorts: [7000, 5000], processNames: ["ControlCenter"]),
        ServiceInfo(id: "rapport", displayName: "Rapport (Continuity)",
                    knownPorts: [], processNames: ["rapportd"]),
        // IANA well-known, genuinely fixed.
        ServiceInfo(id: "sshd", displayName: "SSH",
                    knownPorts: [22], processNames: ["sshd"]),
        ServiceInfo(id: "dnsmasq", displayName: "DNS (dnsmasq)",
                    knownPorts: [53], processNames: ["dnsmasq"]),
    ]
}
