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
final class FakeMicrophone: MicrophonePermission {
    var status: MicrophoneAuthorization
    let answer: Bool
    var requestCount = 0
    init(status: MicrophoneAuthorization = .undetermined, answer: Bool = true) {
        self.status = status; self.answer = answer
    }
    func request() async -> Bool {
        requestCount += 1
        status = answer ? .granted : .denied
        return answer
    }
}

@MainActor
final class AppStateTests: XCTestCase {
    private func make(_ micOrNil: FakeMicrophone? = nil) -> (AppState, FakeDiscovery, FakeMicrophone) {
        let mic = micOrNil ?? FakeMicrophone()
        let fake = FakeDiscovery()
        return (AppState(discovery: fake, microphone: mic), fake, mic)
    }

    func testNoPermissionRequestedAtLaunch() {
        let (state, fake, mic) = make()
        XCTAssertFalse(fake.started)
        XCTAssertFalse(state.searchRequested)
        XCTAssertEqual(mic.requestCount, 0)
        state.resumeDiscoveryIfRequested() // passage au premier plan sans action utilisateur
        XCTAssertFalse(fake.started)
    }

    func testDiscoveryStartsAfterUserAction() {
        let (state, fake, _) = make()
        state.userRequestedSearch()
        XCTAssertTrue(fake.started)
        state.stopDiscovery()
        state.resumeDiscoveryIfRequested()
        XCTAssertTrue(fake.started)
    }

    func testMicrophoneDeniedOpensNoCall() async {
        let (state, _, mic) = make(FakeMicrophone(answer: false))
        await state.requestCall(with: NearbyPeer(pseudonym: .random()))
        XCTAssertNil(state.activeCall)
        XCTAssertTrue(state.showMicrophoneDeniedAlert)
        XCTAssertEqual(mic.requestCount, 1)
    }

    func testMicrophoneAlreadyDeniedIsNotAskedAgain() async {
        let (state, _, mic) = make(FakeMicrophone(status: .denied))
        await state.requestCall(with: NearbyPeer(pseudonym: .random()))
        XCTAssertNil(state.activeCall)
        XCTAssertTrue(state.showMicrophoneDeniedAlert)
        XCTAssertEqual(mic.requestCount, 0)
    }

    func testMicrophoneGrantedOpensCall() async {
        let (state, fake, mic) = make()
        state.userRequestedSearch()
        let p = NearbyPeer(pseudonym: .random())
        fake.onEvent?(.found(p))
        XCTAssertEqual(state.nearby.peers, [p])
        await state.requestCall(with: p)
        XCTAssertEqual(state.activeCall, p)
        XCTAssertFalse(state.showMicrophoneDeniedAlert)
        XCTAssertEqual(mic.requestCount, 1)
        state.hangUp()
        await state.requestCall(with: p) // déjà accordé : pas de nouvelle demande
        XCTAssertEqual(mic.requestCount, 1)
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
