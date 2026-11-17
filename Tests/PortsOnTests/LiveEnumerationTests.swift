import Testing
import Foundation
@testable import PortsOn

/// Integration test against the REAL lsof on this host.
/// Proves the enumeration pipeline works end-to-end on Tahoe 26.7.3.
@Suite("LiveEnumeration", .serialized)
struct LiveEnumerationTests {
    @Test("Live lsof scan returns at least one listener")
    func liveScan() async throws {
        let enumerator = LsofPortEnumerator()
        let entries = try await enumerator.listListeningTCP()
        // A normal dev Mac always has at least one listening socket.
        #expect(!entries.isEmpty, "Expected live listeners, got none — enumeration is broken")
    }

    @Test("Every live entry has a valid port and parsed address")
    func entriesWellFormed() async throws {
        let entries = try await LsofPortEnumerator().listListeningTCP()
        for entry in entries {
            #expect(entry.port != 0, "port 0 is not a real listener")
            #expect(!entry.bindAddress.isEmpty)
        }
    }



    @Test("Resolved process names contain no lsof \\x20 escapes")
    func noEscapedSpaces() async throws {
        let entries = try await LsofPortEnumerator().listListeningTCP()
        for entry in entries {
            if let name = entry.processName {
                #expect(!name.contains("\\x20"),
                        "process name '\(name)' still has a raw \\x20 escape")
            }
        }
    }

    @Test("Spaces in process names are preserved literally through the F0 parser")
    func preservesSpacesInName() {
        let raw = "\np1234\0cCode Helper\0Lme\0tIPv4\0n127.0.0.1:3000\0"
        let entries = LsofPortEnumerator.parse(raw)
        #expect(entries.count == 1)
        #expect(entries.first?.processName == "Code Helper")
        #expect(entries.first?.port == 3000)
        #expect(entries.first?.pid == 1234)
    }

    @Test("Parses IPv6 bracketed addresses")
    func parsesIPv6() {
        #expect(LsofPortEnumerator.parseAddress("[::1]:8787")?.0 == 8787)
        #expect(LsofPortEnumerator.parseAddress("[::1]:8787")?.1 == "::1")
    }
}
