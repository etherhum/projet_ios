import XCTest
import SwiftUI
@testable import Proxima

@MainActor
final class FakeSecretHolder: SessionSecretHolder {
    var wipeCount = 0
    var key: [UInt8]? = Array(repeating: 0xAB, count: 32)
    func wipeSecrets() { wipeCount += 1; key = nil }
}

@MainActor
final class PrivacyTests: XCTestCase {
    private func janitor(_ policy: BackgroundCallPolicy = .endCall) -> SecretsJanitor {
        SecretsJanitor(backgroundPolicy: policy, observeTermination: false)
    }

    func testCallDidEndWipesAllHolders() {
        let j = janitor()
        let a = FakeSecretHolder(), b = FakeSecretHolder()
        j.register(a); j.register(b); j.register(a) // pas de doublon
        j.callDidEnd()
        XCTAssertEqual(a.wipeCount, 1)
        XCTAssertEqual(b.wipeCount, 1)
        XCTAssertNil(a.key); XCTAssertNil(b.key)
        XCTAssertEqual(j.liveHolderCount, 0)
        j.callDidEnd() // déjà oubliés : pas de second effacement
        XCTAssertEqual(a.wipeCount, 1)
    }

    func testJanitorDoesNotRetainHolders() {
        let j = janitor()
        weak var weakHolder: FakeSecretHolder?
        do {
            let h = FakeSecretHolder()
            weakHolder = h
            j.register(h)
            XCTAssertEqual(j.liveHolderCount, 1)
        }
        XCTAssertNil(weakHolder)
        XCTAssertEqual(j.liveHolderCount, 0)
        j.callDidEnd() // ne plante pas
    }

    func testBackgroundPolicyEndCallWipes() {
        XCTAssertEqual(BackgroundCallPolicy.current, .endCall)
        let j = janitor(.endCall)
        let h = FakeSecretHolder(); j.register(h)
        XCTAssertTrue(j.appDidEnterBackground())
        XCTAssertEqual(h.wipeCount, 1)
    }

    func testBackgroundPolicyKeepCallDoesNotWipe() {
        let j = janitor(.keepCall)
        let h = FakeSecretHolder(); j.register(h)
        XCTAssertFalse(j.appDidEnterBackground())
        XCTAssertEqual(h.wipeCount, 0)
    }

    func testTerminationWipes() {
        let j = janitor()
        let h = FakeSecretHolder(); j.register(h)
        j.appWillTerminate()
        XCTAssertEqual(h.wipeCount, 1)
    }

    private func makeState(_ j: SecretsJanitor, transport: CallTransport? = nil) -> AppState {
        AppState(discovery: FakeDiscovery(), microphone: FakeMicrophone(status: .granted),
                 rotationTimer: FakeTimer(), callTransport: transport, janitor: j)
    }

    func testHangUpResetsCallStateAndWipes() async {
        let j = janitor()
        let state = makeState(j)
        let h = FakeSecretHolder(); j.register(h)
        await state.requestCall(with: NearbyPeer(pseudonym: Pseudonym(value: "ABCDEFGHIJKLM")))
        XCTAssertTrue(state.isInCall)
        XCTAssertTrue(state.call.holdsKeyMaterial)
        XCTAssertEqual(j.liveHolderCount, 2) // la session d'appel est enregistrée dès le début de l'appel
        state.hangUp()
        XCTAssertFalse(state.isInCall)
        XCTAssertFalse(state.call.holdsKeyMaterial)
        XCTAssertEqual(h.wipeCount, 1)
        XCTAssertEqual(j.liveHolderCount, 0)
        state.dismissCall()
        XCTAssertNil(state.callPeer) // alias du pair plus référencé
    }

    /// Fin d'appel distante / perte du pair : `callDidEnd()` est aussi appelé (changement de phase).
    func testRemoteEndWipes() async {
        let (link, a, b) = MemoryTransport.pair()
        _ = link
        let j = janitor()
        let state = makeState(j, transport: a)
        let h = FakeSecretHolder(); j.register(h)
        await state.requestCall(with: NearbyPeer(pseudonym: Pseudonym(value: b.id)))
        XCTAssertTrue(state.isInCall)
        a.onCallEvent?(.disconnected)
        XCTAssertFalse(state.isInCall)
        XCTAssertFalse(state.call.holdsKeyMaterial)
        XCTAssertEqual(h.wipeCount, 1)
    }

    func testEnterBackgroundEndsCall() async {
        let j = janitor()
        let state = makeState(j)
        let h = FakeSecretHolder(); j.register(h)
        state.userRequestedSearch()
        await state.requestCall(with: NearbyPeer(pseudonym: Pseudonym(value: "ABCDEFGHIJKLM")))
        state.enterBackground()
        XCTAssertEqual(state.callPhase, .ended(.localHangUp))
        XCTAssertFalse(state.call.holdsKeyMaterial)
        XCTAssertEqual(h.wipeCount, 1)
        XCTAssertTrue(state.nearby.peers.isEmpty)
    }

    func testShieldPolicyCoversInactiveAndBackground() {
        XCTAssertFalse(PrivacyShieldPolicy.isShielded(.active))
        XCTAssertTrue(PrivacyShieldPolicy.isShielded(.inactive))
        XCTAssertTrue(PrivacyShieldPolicy.isShielded(.background))
    }
}
