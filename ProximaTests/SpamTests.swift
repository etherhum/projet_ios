import XCTest
@testable import Proxima

final class SpamTests: XCTestCase {
    private var clock: TimeInterval = 1_000
    private func makeGate() -> CallRequestGate { CallRequestGate(now: { [unowned self] in self.clock }) }

    func testFiftyRequestsInTenSecondsFromOnePeer() {
        let gate = makeGate()
        var allowed = 0
        let start = Date()
        for i in 0..<50 {
            clock = 1_000 + Double(i) * 0.2 // 50 demandes en 10 s
            if gate.allow(peer: "ATTACKER23456") { allowed += 1 }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05) // traitement total borné
        XCTAssertEqual(allowed, CallRequestGate.perPeerLimit)
    }

    func testFiftyPeersRespectGlobalLimit() {
        let gate = makeGate()
        var allowed = 0
        for i in 0..<50 {
            clock = 1_000 + Double(i) * 0.2
            if gate.allow(peer: "PEER\(i)") { allowed += 1 }
        }
        XCTAssertEqual(allowed, CallRequestGate.globalLimit)
    }

    func testBlockedPeerAlwaysRefused() {
        let gate = makeGate()
        gate.block(peer: "BLOCKED234567")
        for i in 0..<5 {
            clock += 3_600 * Double(i)
            XCTAssertFalse(gate.allow(peer: "BLOCKED234567"))
        }
        XCTAssertTrue(gate.allow(peer: "OTHER23456789"))
    }

    func testAllowedAgainAfterWindow() {
        let gate = makeGate()
        for _ in 0..<CallRequestGate.perPeerLimit { XCTAssertTrue(gate.allow(peer: "P")) }
        XCTAssertFalse(gate.allow(peer: "P"))
        clock += CallRequestGate.window + 0.1
        XCTAssertTrue(gate.allow(peer: "P"))
    }

    func testMemoryBoundedAfterTenThousandDistinctPseudonyms() {
        let gate = makeGate()
        for i in 0..<10_000 {
            clock += 0.01
            _ = gate.allow(peer: "SPAM\(i)")
            if i % 10 == 0 { gate.block(peer: "SPAM\(i)") }
        }
        let f = gate.footprint
        XCTAssertLessThanOrEqual(f.global, CallRequestGate.globalLimit)
        XCTAssertLessThanOrEqual(f.trackedPeers, CallRequestGate.maxTrackedPeers)
        XCTAssertLessThanOrEqual(f.blocked, CallRequestGate.maxBlocked)
    }

    func testThroughput() {
        let gate = makeGate()
        measure { for i in 0..<1_000 { _ = gate.allow(peer: "M\(i % 50)") } }
    }
}
