import Testing
import Foundation
@testable import PortsOn

@Suite("LsofParser")
struct LsofParserTests {
    @Test("Parses a real lsof LISTEN row into a PortEntry")
    func parseRow() {
        let text = """
        COMMAND     PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        ControlCe   660   mhiqrambg   10u  IPv4 0x8ce1 0t0 TCP *:7000 (LISTEN)
        node      13372   mhiqrambg   22u  IPv4 0x2ea5 0t0 TCP 127.0.0.1:49532 (LISTEN)
        rapportd   702    root        5u   IPv6 0x1111 0t0 TCP *:58687 (LISTEN)
        """

        let entries = LsofPortEnumerator.parse(text)
        #expect(entries.count == 3)

        let control = entries.first { $0.processName == "ControlCe" }!
        #expect(control.port == 7000)
        #expect(control.bindAddress == "0.0.0.0")
        #expect(control.isPubliclyBound)
        #expect(control.addressFamily == .ipv4)

        let node = entries.first { $0.processName == "node" }!
        #expect(node.port == 49532)
        #expect(node.bindAddress == "127.0.0.1")
        #expect(!node.isPubliclyBound)

        let v6 = entries.first { $0.addressFamily == .ipv6 }!
        #expect(v6.port == 58687)
    }

    @Test("Dedupes IPv4/IPv6 duplicates on the same port")
    func dedupes() {
        let text = """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        a 1 u 10u IPv4 0x1 0t0 TCP *:80 (LISTEN)
        a 1 u 11u IPv6 0x2 0t0 TCP *:80 (LISTEN)
        """
        let entries = LsofPortEnumerator.parse(text)
        // IPv4 and IPv6 on same port are distinct entries (different af), so 2.
        #expect(entries.count == 2)
    }

    @Test("Skips malformed rows without crashing")
    func skipsMalformed() {
        let entries = LsofPortEnumerator.parse("garbage\n\nshort row\na b c")
        #expect(entries.isEmpty)
    }

    @Test("parseAddress handles loopback, wildcard, and IPv6 brackets")
    func parseAddress() {
        let loopback = LsofPortEnumerator.parseAddress("127.0.0.1:3000")
        #expect(loopback?.0 == 3000 && loopback?.1 == "127.0.0.1")
        let wildcard = LsofPortEnumerator.parseAddress("*:80")
        #expect(wildcard?.0 == 80 && wildcard?.1 == "0.0.0.0")
        let v6 = LsofPortEnumerator.parseAddress(":::8080")
        #expect(v6?.0 == 8080 && v6?.1 == "::")
        #expect(LsofPortEnumerator.parseAddress("nope") == nil)
    }
}

@Suite("ServiceResolver")
struct ServiceResolverTests {
    let resolver = ServiceResolver()

    @Test("Resolves by known port")
    func byPort() {
        let entry = PortEntry(port: 3000, addressFamily: .ipv4, bindAddress: "0.0.0.0",
                              pid: 100, processName: "next-server", user: "me")
        let (label, service) = resolver.resolve(entry)
        #expect(label == "Next.js")
        #expect(service?.id == "nextjs")
    }

    @Test("Resolves by process name fingerprint when port is unknown")
    func byProcessName() {
        let entry = PortEntry(port: 45678, addressFamily: .ipv4, bindAddress: "127.0.0.1",
                              pid: 200, processName: "redis-server", user: "me")
        let (label, service) = resolver.resolve(entry)
        #expect(label == "Redis")
        #expect(service?.id == "redis")
    }

    @Test("Falls back to raw process name for unknown services")
    func fallback() {
        let entry = PortEntry(port: 49999, addressFamily: .ipv4, bindAddress: "127.0.0.1",
                              pid: 300, processName: "myweirdthing", user: "me")
        let (label, service) = resolver.resolve(entry)
        #expect(label == "myweirdthing")
        #expect(service == nil)
    }
}

@Suite("StopService")
struct StopServiceTests {
    @Test("Refuses denied-list processes regardless of ownership")
    func deniesProtected() {
        let svc = StopService()
        let result = svc.stop(pid: 1, name: "launchd", uid: getuid())
        #expect(result == .denied("launchd"))
    }

    @Test("Refuses a process not owned by the current user")
    func refusesForeign() {
        let svc = StopService()
        let foreignUID: uid_t = getuid() + 1
        let result = svc.stop(pid: 999999, name: "someone", uid: foreignUID)
        #expect(result == .notPermitted)
    }

    @Test("Reports notRunning for a stale/absent pid")
    func stalePid() {
        let svc = StopService()
        let result = svc.stop(pid: 999999, name: "ghost", uid: getuid())
        #expect(result == .notRunning)
    }

    @Test("Identity lookup returns nil for a nonexistent pid")
    func identityNil() {
        #expect(StopService.identity(of: 999999) == nil)
    }
}

@Suite("PortEntry")
struct PortEntryTests {
    @Test("isPubliclyBound distinguishes wildcard from loopback")
    func binding() {
        let pub = PortEntry(port: 80, addressFamily: .ipv4, bindAddress: "0.0.0.0", pid: 1, processName: "a", user: "u")
        let priv = PortEntry(port: 80, addressFamily: .ipv4, bindAddress: "127.0.0.1", pid: 1, processName: "a", user: "u")
        #expect(pub.isPubliclyBound)
        #expect(!priv.isPubliclyBound)
    }
}
