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
    private(set) var localPseudonym = Pseudonym.random()
    var onEvent: ((DiscoveryEvent) -> Void)?
    var started = false
    var rotations = 0
    func start() { if !started { localPseudonym = .random(); started = true } }
    func stop() { started = false }
    func rotate() { rotations += 1; stop(); start() }
}

@MainActor
final class FakeTimer: RotationTimer {
    var handler: (@MainActor () -> Void)?
    var interval: TimeInterval?
    func start(interval: TimeInterval, handler: @escaping @MainActor () -> Void) { self.interval = interval; self.handler = handler }
    func stop() { handler = nil }
    func fire() { handler?() }
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
        XCTAssertEqual(RotationPolicy.defaultInterval, 600)
    }

    func testCallDurationFormat() {
        XCTAssertEqual(CallView.format(65), "01:05")
    }
}

final class DiscoveryValidatorTests: XCTestCase {
    private let valid = "ABCDEFGHIJ234"
    private let info = ["v": "1"]

    func testValidAnnouncementAccepted() {
        XCTAssertEqual(DiscoveryValidator.peer(displayName: valid, info: info, local: nil)?.id, valid)
        // Clé inconnue mais taille bornée : ignorée (compatibilité ascendante).
        XCTAssertNotNil(DiscoveryValidator.peer(displayName: valid, info: ["v": "1", "x": "y"], local: nil))
    }

    func testInvalidDisplayNameIgnored() {
        for name in ["", "abcdefghij234", "ABCDEFGHIJ23", "ABCDEFGHIJ2345", "ABCDEFGHIJ018", "iPhone de Rico", "ABCDEFGHIJ23É"] {
            XCTAssertNil(DiscoveryValidator.peer(displayName: name, info: info, local: nil), name)
        }
    }

    func testInvalidOrOversizedInfoIgnored() {
        XCTAssertNil(DiscoveryValidator.peer(displayName: valid, info: nil, local: nil))
        XCTAssertNil(DiscoveryValidator.peer(displayName: valid, info: [:], local: nil))
        XCTAssertNil(DiscoveryValidator.peer(displayName: valid, info: ["v": "2"], local: nil))
        XCTAssertNil(DiscoveryValidator.peer(displayName: valid, info: ["v": "1", "pad": String(repeating: "A", count: 100)], local: nil))
        let many = Dictionary(uniqueKeysWithValues: (0..<5).map { ("k\($0)", "1") }).merging(["v": "1"]) { a, _ in a }
        XCTAssertNil(DiscoveryValidator.peer(displayName: valid, info: many, local: nil))
    }

    func testOwnPeerIgnored() {
        XCTAssertNil(DiscoveryValidator.peer(displayName: valid, info: info, local: Pseudonym(value: valid)))
    }

    func testListStableSortAndBounded() {
        var list = NearbyPeerList()
        let ps = (0..<100).map { _ in NearbyPeer(pseudonym: .random()) }
        ps.forEach { list.add($0) }
        XCTAssertEqual(list.peers.count, NearbyPeerList.maxPeers)
        var other = NearbyPeerList()
        ps.prefix(NearbyPeerList.maxPeers).reversed().forEach { other.add($0) }
        XCTAssertEqual(list.peers.map(\.id), other.peers.map(\.id)) // ordre indépendant de l'arrivée
    }
}

@MainActor
final class RotationTests: XCTestCase {
    private func make() -> (AppState, FakeDiscovery, FakeTimer) {
        let d = FakeDiscovery(), t = FakeTimer()
        return (AppState(discovery: d, microphone: FakeMicrophone(status: .granted), rotationTimer: t, rotationInterval: 600), d, t)
    }

    func testRotationProducesNewNeverReusedPseudonym() {
        let (state, d, t) = make()
        state.userRequestedSearch()
        XCTAssertEqual(t.interval, 600)
        var seen: Set<String> = [d.localPseudonym.value]
        for _ in 0..<50 {
            t.fire()
            XCTAssertTrue(seen.insert(d.localPseudonym.value).inserted)
            XCTAssertEqual(state.myAlias, d.localPseudonym.alias)
        }
        XCTAssertEqual(d.rotations, 50)
    }

    func testRotationClearsList() {
        let (state, d, t) = make()
        state.userRequestedSearch()
        d.onEvent?(.found(NearbyPeer(pseudonym: .random())))
        t.fire()
        XCTAssertTrue(state.nearby.peers.isEmpty)
    }

    func testNoRotationDuringCallThenRotateAtHangUp() async {
        let (state, d, t) = make()
        state.userRequestedSearch()
        let before = d.localPseudonym
        await state.requestCall(with: NearbyPeer(pseudonym: .random()))
        XCTAssertTrue(state.isInCall)
        t.fire(); t.fire()
        XCTAssertEqual(d.rotations, 0)
        XCTAssertEqual(d.localPseudonym, before)
        XCTAssertTrue(state.rotationPending)
        state.hangUp()
        XCTAssertEqual(d.rotations, 1)
        XCTAssertNotEqual(d.localPseudonym, before)
        XCTAssertFalse(state.rotationPending)
    }

    func testNoRotationWhenStopped() {
        let (state, d, t) = make()
        state.userRequestedSearch()
        state.stopDiscovery()
        t.fire()
        XCTAssertEqual(d.rotations, 0)
    }

    func testOwnPeerAndDuplicatesIgnoredByAppState() {
        let (state, d, _) = make()
        state.userRequestedSearch()
        d.onEvent?(.found(NearbyPeer(pseudonym: d.localPseudonym)))
        XCTAssertTrue(state.nearby.peers.isEmpty)
        let p = NearbyPeer(pseudonym: .random())
        d.onEvent?(.found(p)); d.onEvent?(.found(p))
        XCTAssertEqual(state.nearby.peers, [p])
        d.onEvent?(.lost(id: p.id))
        XCTAssertTrue(state.nearby.peers.isEmpty)
    }
    // Scan des API interdites : scripts/check-forbidden-apis.sh (les sources ne sont pas accessibles sur l'appareil).
}
