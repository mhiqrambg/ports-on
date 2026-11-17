import Testing
import Foundation
@testable import PortsOn

@Suite("LsofParser")
struct LsofParserTests {
    @Test("Parses an lsof -F0 LISTEN record into PortEntry values")
    func parseRecords() {
        // Mirrors real `lsof -nP -iTCP -sTCP:LISTEN -F0pnLct` output.
        let text = "\0p660\0cControlCenter\0Lmhiqrambg\0f10\0tIPv4\0n*:7000\0"
                 + "\0f11\0tIPv6\0n*:7000\0"
                 + "\0p13372\0cnode\0Lmhiqrambg\0f22\0tIPv4\0n127.0.0.1:49532\0"
                 + "\0p702\0crapportd\0Lroot\0f5\0tIPv6\0n*:58687\0"

        let entries = LsofPortEnumerator.parse(text)
        // ControlCenter's IPv4+IPv6 on 7000 merges into ONE dual-stack row;
        // node and rapportd stay separate. 3 distinct rows total.
        #expect(entries.count == 3)

        let control = entries.first { $0.processName == "ControlCenter" }!
        #expect(control.port == 7000)
        #expect(control.bindAddress == "0.0.0.0")
        #expect(control.isPubliclyBound)
        #expect(control.addressFamilies == [.ipv4, .ipv6])
        #expect(control.familyLabel == "IPv4+IPv6")

        let node = entries.first { $0.processName == "node" }!
        #expect(node.port == 49532)
        #expect(node.bindAddress == "127.0.0.1")
        #expect(!node.isPubliclyBound)
        #expect(node.addressFamilies == [.ipv4])
    }

    @Test("Merges IPv4/IPv6 dual-stack listeners on the same port into one row")
    func mergesDualStack() {
        let text = "\0p1\0ca\0Lu\0tIPv4\0n*:80\0\0tIPv6\0n*:80\0"
        let entries = LsofPortEnumerator.parse(text)
        #expect(entries.count == 1)
        #expect(entries.first?.addressFamilies == [.ipv4, .ipv6])
    }

    @Test("Keeps two different ports on the same pid as separate rows")
    func distinctPorts() {
        let text = "\0p1\0ca\0Lu\0tIPv4\0n*:80\0\0tIPv4\0n*:81\0"
        let entries = LsofPortEnumerator.parse(text)
        #expect(entries.count == 2)
    }

    @Test("Skips garbage fields and rows with no parseable address")
    func skipsMalformed() {
        let entries = LsofPortEnumerator.parse("garbage\0\0p1\0ca\0nnonsense\0")
        #expect(entries.isEmpty)
    }

    @Test("Spaces in process names are preserved literally")
    func preservesSpaces() {
        let text = "\0p1234\0cCode Helper\0Lme\0tIPv4\0n127.0.0.1:3000\0"
        let entries = LsofPortEnumerator.parse(text)
        #expect(entries.count == 1)
        #expect(entries.first?.processName == "Code Helper")
        #expect(entries.first?.port == 3000)
    }

    @Test("parseAddress handles loopback, wildcard, and IPv6 brackets")
    func parseAddress() {
        let loopback = LsofPortEnumerator.parseAddress("127.0.0.1:3000")
        #expect(loopback?.0 == 3000 && loopback?.1 == "127.0.0.1")
        let wildcard = LsofPortEnumerator.parseAddress("*:80")
        #expect(wildcard?.0 == 80 && wildcard?.1 == "0.0.0.0")
        let v6 = LsofPortEnumerator.parseAddress("[::1]:8787")
        #expect(v6?.0 == 8787 && v6?.1 == "::1")
        #expect(LsofPortEnumerator.parseAddress("nope") == nil)
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
        let pub = PortEntry(port: 80, addressFamilies: [.ipv4], bindAddress: "0.0.0.0", pid: 1, processName: "a", user: "u")
        let priv = PortEntry(port: 80, addressFamilies: [.ipv4], bindAddress: "127.0.0.1", pid: 1, processName: "a", user: "u")
        #expect(pub.isPubliclyBound)
        #expect(!priv.isPubliclyBound)
    }

    @Test("familyLabel renders combined families")
    func familyLabel() {
        let dual = PortEntry(port: 80, addressFamilies: [.ipv4, .ipv6], bindAddress: "0.0.0.0", pid: 1, processName: "a", user: "u")
        let v4 = PortEntry(port: 80, addressFamilies: [.ipv4], bindAddress: "127.0.0.1", pid: 1, processName: "a", user: "u")
        #expect(dual.familyLabel == "IPv4+IPv6")
        #expect(v4.familyLabel == "IPv4")
    }
}
