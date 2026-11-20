import XCTest
@testable import Proxima

final class PseudonymTests: XCTestCase {
    func testPseudonymFormat() {
        let p = Pseudonym.random()
        XCTAssertEqual(p.value.count, 13)
        XCTAssertNil(p.value.range(of: "[^A-Z2-7]", options: .regularExpression))
    }

    func testPseudonymsAreUnique() {
        let values = Set((0..<10_000).map { _ in Pseudonym.random().value })
        XCTAssertEqual(values.count, 10_000)
    }

    func testAliasIsDeterministic() {
        let p = Pseudonym(value: "ABCDEFGHIJKLM")
        XCTAssertEqual(p.alias, Pseudonym(value: "ABCDEFGHIJKLM").alias)
        XCTAssertTrue(p.alias.hasSuffix("-KLM"))
    }

    func testBase32() {
        XCTAssertEqual(Base32.encode(Array("foobar".utf8)), "MZXW6YTBOI")
    }
}

final class NearbyPeerListTests: XCTestCase {
    private func peer(_ v: String) -> NearbyPeer { NearbyPeer(pseudonym: Pseudonym(value: v)) }

    func testAddRemoveNoDuplicate() {
        var list = NearbyPeerList()
        list.add(peer("AAAAAAAAAAAAA"))
        list.add(peer("AAAAAAAAAAAAA"))
        list.add(peer("BBBBBBBBBBBBB"))
        XCTAssertEqual(list.peers.count, 2)
        list.remove(id: "AAAAAAAAAAAAA")
        XCTAssertEqual(list.peers.map(\.id), ["BBBBBBBBBBBBB"])
        list.remove(id: "inconnu")
        XCTAssertEqual(list.peers.count, 1)
    }
}

@MainActor
final class FakeDiscovery: PeerDiscovering {
    let localPseudonym = Pseudonym.random()
    var onEvent: ((DiscoveryEvent) -> Void)?
    var started = false
    func start() { started = true }
    func stop() { started = false }
}

@MainActor
final class AppStateTests: XCTestCase {
    func testEventsUpdateListAndMockCall() {
        let fake = FakeDiscovery()
        let state = AppState(discovery: fake)
        state.startDiscovery()
        XCTAssertTrue(fake.started)
        let p = NearbyPeer(pseudonym: .random())
        fake.onEvent?(.found(p))
        XCTAssertEqual(state.nearby.peers, [p])
        state.startMockCall(with: p)
        XCTAssertEqual(state.activeCall, p)
        state.hangUp()
        XCTAssertNil(state.activeCall)
        fake.onEvent?(.lost(id: p.id))
        XCTAssertTrue(state.nearby.peers.isEmpty)
    }

    func testServiceConstants() {
        XCTAssertTrue((1...15).contains(NearbyService.serviceType.count))
        XCTAssertEqual(NearbyService.discoveryInfo, ["v": "1"])
    }

    func testCallDurationFormat() {
        XCTAssertEqual(CallView.format(65), "01:05")
    }
}
