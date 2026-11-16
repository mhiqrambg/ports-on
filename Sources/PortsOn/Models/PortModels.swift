import Foundation

/// A single listening TCP endpoint and the process that owns it.
public struct PortEntry: Identifiable, Hashable, Equatable, Sendable {
    public let port: UInt16
    public let addressFamily: AddressFamily
    public let bindAddress: String
    public let pid: pid_t?
    public let processName: String?
    public let user: String?

    public var id: String { "\(addressFamily.rawValue)-\(port)-\(pid.map(String.init) ?? "?")" }

    /// True when the port is bound to all interfaces (not loopback-only).
    public var isPubliclyBound: Bool {
        bindAddress == "0.0.0.0" || bindAddress == "::"
    }

    public enum AddressFamily: String, Sendable { case ipv4, ipv6 }
}

/// Known local services we can recognize by port or process name.
public struct ServiceInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let knownPorts: Set<UInt16>
    public let processNames: Set<String>
}

extension ServiceInfo {
    public static let builtin: [ServiceInfo] = [
        ServiceInfo(id: "nginx", displayName: "nginx",
                    knownPorts: [80, 443, 8080, 8000],
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
                    knownPorts: [3000], processNames: ["next-server", "next"]),
        ServiceInfo(id: "astro", displayName: "Astro",
                    knownPorts: [4321], processNames: ["astro"]),
        ServiceInfo(id: "vite", displayName: "Vite",
                    knownPorts: [5173], processNames: ["vite", "node"]),
        ServiceInfo(id: "django", displayName: "Django",
                    knownPorts: [8000, 8001], processNames: ["python", "manage.py"]),
        ServiceInfo(id: "rails", displayName: "Rails",
                    knownPorts: [3000], processNames: ["ruby", "rails"]),
        ServiceInfo(id: "php", displayName: "PHP",
                    knownPorts: [9000, 9003], processNames: ["php-fpm", "php"]),
        ServiceInfo(id: "opencode", displayName: "OpenCode",
                    knownPorts: [4848], processNames: ["opencode"]),
        ServiceInfo(id: "omp", displayName: "omp",
                    knownPorts: [4096], processNames: ["omp"]),
        ServiceInfo(id: "airplay", displayName: "AirPlay",
                    knownPorts: [7000, 5000], processNames: ["ControlCe"]),
        ServiceInfo(id: "rapport", displayName: "Rapport (Continuity)",
                    knownPorts: [], processNames: ["rapportd"]),
        ServiceInfo(id: "sshd", displayName: "SSH",
                    knownPorts: [22], processNames: ["sshd"]),
        ServiceInfo(id: "dnsmasq", displayName: "DNS (dnsmasq)",
                    knownPorts: [53], processNames: ["dnsmasq"]),
    ]
}
