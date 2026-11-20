import XCTest
@testable import Proxima

// MARK: Transport factice en mémoire (livraison différée, déterministe)

@MainActor
final class MemoryLink {
    var queue: [() -> Void] = []
    func run() {
        var steps = 0
        while !queue.isEmpty, steps < 1_000 { queue.removeFirst()(); steps += 1 }
    }
}

@MainActor
final class MemoryTransport: CallTransport {
    let id = Pseudonym.random().value
    let link: MemoryLink
    weak var other: MemoryTransport?
    var onCallEvent: ((CallTransportEvent) -> Void)?
    private var pending = false
    private(set) var connected = false
    private(set) var answers: [Bool] = []
    /// Permet de modifier / remplacer les données envoyées (attaquant actif).
    var tamper: ((Data) -> Data)?
    /// Simule la règle d'appels croisés de `NearbyService` : notre invitation arrive chez le pair qui nous appelait.
    var deliverAsCrossed = false

    init(link: MemoryLink) { self.link = link }

    static func pair() -> (MemoryLink, MemoryTransport, MemoryTransport) {
        let link = MemoryLink()
        let a = MemoryTransport(link: link), b = MemoryTransport(link: link)
        a.other = b; b.other = a
        return (link, a, b)
    }

    func invite(peerID: String, context: Data) {
        link.queue.append { [weak self] in
            guard let self, let other = self.other, peerID == other.id else { return }
            other.pending = true
            other.onCallEvent?(self.deliverAsCrossed ? .crossedInvitation(from: self.id, context: context)
                                                     : .invitation(from: self.id, context: context))
        }
    }

    func answerInvitation(accept: Bool) {
        answers.append(accept)
        guard pending else { return }
        pending = false
        link.queue.append { [weak self] in
            guard let self, let other = self.other else { return }
            if accept {
                self.connected = true; other.connected = true
                self.onCallEvent?(.connected)
                other.onCallEvent?(.connected)
            } else {
                other.onCallEvent?(.disconnected)
            }
        }
    }

    func send(_ data: Data) {
        guard connected else { return }
        let d = tamper?(data) ?? data
        link.queue.append { [weak self] in self?.other?.onCallEvent?(.received(d)) }
    }

    func disconnect() {
        pending = false
        guard connected else { return }
        connected = false
        link.queue.append { [weak self] in
            guard let other = self?.other, other.connected else { return }
            other.connected = false
            other.onCallEvent?(.disconnected)
        }
    }
}

@MainActor
final class FakeScheduler: DeadlineScheduler {
    final class Token: DeadlineToken {
        var handler: (@MainActor () -> Void)?
        func cancel() { handler = nil }
    }
    private(set) var tokens: [Token] = []
    func schedule(after seconds: TimeInterval, _ handler: @escaping @MainActor () -> Void) -> DeadlineToken {
        XCTAssertTrue(seconds == 30 || seconds == CallSession.maxSessionDuration)
        let t = Token(); t.handler = handler; tokens.append(t)
        return t
    }
    /// Déclenche l'échéance encore active (la plus récente).
    func fire() { tokens.last(where: { $0.handler != nil })?.handler?() }
}

// MARK: Tests M3-05

@MainActor
final class CallSessionTests: XCTestCase {
    private var link: MemoryLink!
    private var tI: MemoryTransport!, tR: MemoryTransport!
    private var sI: FakeScheduler!, sR: FakeScheduler!
    private var caller: CallSession!, callee: CallSession!

    override func setUp() async throws {
        (link, tI, tR) = MemoryTransport.pair()
        sI = FakeScheduler(); sR = FakeScheduler()
        caller = CallSession(transport: tI, scheduler: sI)
        callee = CallSession(transport: tR, scheduler: sR)
    }

    private func ring() {
        caller.call(peerID: tR.id)
        link.run()
        XCTAssertEqual(caller.phase, .outgoingRequest)
        XCTAssertEqual(callee.phase, .incomingRequest)
        XCTAssertEqual(callee.peerID, tI.id)
        XCTAssertFalse(callee.holdsKeyMaterial, "aucune clé chez l'appelé avant acceptation")
    }

    private func establish() -> String {
        ring()
        callee.accept()
        link.run()
        guard case .verifying(let code) = caller.phase else { XCTFail("appelant : \(caller.phase)"); return "" }
        XCTAssertEqual(callee.phase, .verifying(code: code))
        return code
    }

    private func assertNoKeys(_ file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(caller.holdsKeyMaterial, file: file, line: line)
        XCTAssertFalse(callee.holdsKeyMaterial, file: file, line: line)
        XCTAssertNil(caller.keyPair, file: file, line: line); XCTAssertNil(callee.keyPair, file: file, line: line)
        XCTAssertNil(caller.crypter, file: file, line: line); XCTAssertNil(callee.crypter, file: file, line: line)
    }

    func testAcceptedCallDerivesSameKeysAndCode() throws {
        let code = establish()
        XCTAssertEqual(code.count, 7) // « 123 456 »
        // Mêmes clés de direction des deux côtés : I→R et R→I s'ouvrent chez l'autre.
        let ci = try XCTUnwrap(caller.crypter), cr = try XCTUnwrap(callee.crypter)
        let p = try ci.seal(Data([1, 2, 3]), type: .audio, timestampMs: 0)
        XCTAssertEqual(try cr.open(p).plaintext, Data([1, 2, 3]))
        XCTAssertEqual(try ci.open(try cr.seal(Data([9]), type: .audio, timestampMs: 0)).plaintext, Data([9]))
        XCTAssertNil(caller.keyPair, "clé privée éphémère consommée")
        XCTAssertNil(callee.keyPair)
        // Confirmation des codes des deux côtés (SAS_OK chiffré) → actif.
        caller.confirmCode(); link.run()
        XCTAssertEqual(caller.phase, .verifying(code: code))
        callee.confirmCode(); link.run()
        XCTAssertEqual(caller.phase, .active(code: code))
        XCTAssertEqual(callee.phase, .active(code: code))
    }

    func testDeclinedCallEstablishesNoKey() {
        ring()
        weak var callerPair = caller.keyPair
        XCTAssertNotNil(callerPair) // nécessaire pour l'engagement C
        callee.decline()
        link.run()
        XCTAssertEqual(callee.phase, .ended(.declined))
        XCTAssertEqual(caller.phase, .failed(.declinedOrNoAnswer))
        XCTAssertEqual(tR.answers, [false])
        XCTAssertFalse(tR.connected)
        assertNoKeys()
        XCTAssertNil(callerPair, "paire éphémère de l'appelant détruite et libérée")
    }

    func testIncomingRequestTimeoutEstablishesNoKey() {
        ring()
        sR.fire() // 30 s sans réponse de l'utilisateur : refus
        link.run()
        XCTAssertEqual(callee.phase, .failed(.timeout))
        XCTAssertEqual(caller.phase, .failed(.declinedOrNoAnswer))
        XCTAssertEqual(tR.answers, [false])
        assertNoKeys()
    }

    func testOutgoingNoAnswerTimeout() {
        caller.call(peerID: Pseudonym.random().value) // personne ne répond
        link.run()
        XCTAssertTrue(caller.holdsKeyMaterial)
        sI.fire()
        XCTAssertEqual(caller.phase, .failed(.declinedOrNoAnswer))
        assertNoKeys()
    }

    func testHandshakeTimeoutDestroysKeys() {
        tR.tamper = { _ in Data() } // HELLO perdu / remplacé
        ring()
        callee.accept()
        link.queue.removeAll() // rien n'arrive
        sI.fire(); sR.fire()
        XCTAssertEqual(caller.phase, .failed(.declinedOrNoAnswer))
        XCTAssertEqual(callee.phase, .failed(.timeout))
        assertNoKeys()
    }

    func testOutOfSequenceMessageFails() throws {
        // R envoie un REVEAL à la place du HELLO.
        tR.tamper = { d in
            var m = d; if m.count == HandshakeMessage.keyNonceByteCount { m[1] = HandshakeMessage.revealType }; return m
        }
        ring(); callee.accept(); link.run()
        XCTAssertEqual(caller.phase, .failed(.protocolError))
        XCTAssertEqual(callee.phase, .failed(.disconnected))
        assertNoKeys()
    }

    func testMalformedMessagesFail() {
        let mutations: [(Data) -> Data] = [
            { $0.prefix(40) },                          // tronqué
            { $0 + Data([0]) },                         // trop long d'un octet
            { var m = $0; m[0] = 0x02; return m },      // version inconnue
            { var m = $0; m[1] = 0x07; return m },      // type inconnu
            { _ in Data(count: 5_000) },                // hors borne
            { var m = $0; m[2] = 0x02; return m },      // clé publique invalide (préfixe ≠ 0x04)
        ]
        for mutate in mutations {
            (link, tI, tR) = MemoryTransport.pair()
            sI = FakeScheduler(); sR = FakeScheduler()
            caller = CallSession(transport: tI, scheduler: sI)
            callee = CallSession(transport: tR, scheduler: sR)
            tR.tamper = mutate
            ring(); callee.accept(); link.run()
            XCTAssertEqual(caller.phase, .failed(.protocolError))
            assertNoKeys()
        }
    }

    func testWrongCommitmentAborts() {
        // Attaquant : REVEAL modifié (nonceI) → SHA256(pkI ‖ nonceI) ≠ C.
        tI.tamper = { d in
            var m = d; if m.count == HandshakeMessage.keyNonceByteCount { m[m.count - 1] ^= 0xFF }; return m
        }
        ring(); callee.accept(); link.run()
        XCTAssertEqual(callee.phase, .failed(.protocolError))
        XCTAssertEqual(caller.phase, .failed(.disconnected))
        assertNoKeys()
    }

    func testHangUpClosesBothSidesAndDestroysKeys() {
        _ = establish()
        weak var ci = caller.crypter, cr = callee.crypter
        XCTAssertNotNil(ci); XCTAssertNotNil(cr)
        caller.hangUp()
        link.run()
        XCTAssertEqual(caller.phase, .ended(.localHangUp))
        XCTAssertEqual(callee.phase, .ended(.remoteHangUp))
        assertNoKeys()
        XCTAssertNil(ci); XCTAssertNil(cr)
        caller.reset(); callee.reset()
        XCTAssertEqual(caller.phase, .idle)
    }

    func testCodeMismatchClosesSession() {
        _ = establish()
        callee.rejectCode()
        link.run()
        XCTAssertEqual(callee.phase, .failed(.codeMismatch))
        XCTAssertEqual(caller.phase, .ended(.remoteHangUp))
        assertNoKeys()
    }

    func testSecondRequestDuringCallIsDeclined() throws {
        let code = establish()
        let commit = HandshakeMessage.commit(commitment: Data(count: 32)).bytes
        tR.onCallEvent?(.invitation(from: Pseudonym.random().value, context: commit))
        XCTAssertEqual(tR.answers, [true, false])
        XCTAssertEqual(callee.phase, .verifying(code: code))
        XCTAssertEqual(callee.peerID, tI.id)
        // Demande sortante pendant un appel : ignorée.
        callee.call(peerID: Pseudonym.random().value)
        XCTAssertEqual(callee.phase, .verifying(code: code))
    }

    func testInvalidInvitationDeclined() {
        let commit = HandshakeMessage.commit(commitment: Data(count: 32)).bytes
        tR.onCallEvent?(.invitation(from: "pas-un-pseudo", context: commit))
        tR.onCallEvent?(.invitation(from: Pseudonym.random().value, context: commit.prefix(20)))
        tR.onCallEvent?(.invitation(from: Pseudonym.random().value, context: Data()))
        XCTAssertEqual(tR.answers, [false, false, false])
        XCTAssertEqual(callee.phase, .idle)
        XCTAssertFalse(callee.holdsKeyMaterial)
    }

    func testUnexpectedDataBeforeAcceptanceIgnored() {
        ring()
        tR.onCallEvent?(.received(Data(repeating: 1, count: 83)))
        XCTAssertEqual(callee.phase, .incomingRequest)
        XCTAssertFalse(callee.holdsKeyMaterial)
    }

    func testHandshakeMessageCodec() {
        let pk = EphemeralKeyPair().publicKeyX963, n = Handshake.randomNonce()
        for m in [HandshakeMessage.commit(commitment: Data(count: 32)), .hello(publicKey: pk, nonce: n), .reveal(publicKey: pk, nonce: n)] {
            XCTAssertEqual(HandshakeMessage.decode(m.bytes), m)
            XCTAssertTrue(HandshakeMessage.isHandshakeType(m.bytes))
        }
        XCTAssertEqual(HandshakeMessage.commit(commitment: Data(count: 32)).bytes.prefix(2), Data([0x01, 0x01]))
        XCTAssertEqual(HandshakeMessage.hello(publicKey: pk, nonce: n).bytes.count, 83)
        XCTAssertNil(HandshakeMessage.decode(Data()))
        XCTAssertNil(HandshakeMessage.decode(Data([0x01, 0x01]) + Data(count: 31)))
        XCTAssertNil(HandshakeMessage.decode(Data([0x01, 0x02]) + Data(count: 80)))
        XCTAssertNil(HandshakeMessage.decode(Data(count: 1_000)))
    }

    func testAppStateRotationOnlyAfterCallEnds() async {
        let d = FakeDiscovery(), t = FakeTimer()
        let (link, a, b) = MemoryTransport.pair()
        let state = AppState(discovery: d, microphone: FakeMicrophone(status: .granted), rotationTimer: t,
                             rotationInterval: 600, callTransport: a, callScheduler: FakeScheduler())
        let other = CallSession(transport: b, scheduler: FakeScheduler())
        state.userRequestedSearch()
        await state.requestCall(with: NearbyPeer(pseudonym: Pseudonym(value: b.id)))
        link.run()
        XCTAssertTrue(state.isInCall)
        await state.requestCall(with: NearbyPeer(pseudonym: .random())) // 2ᵉ appel : ignoré
        XCTAssertEqual(state.callPeer?.id, b.id)
        other.accept(); link.run()
        guard case .verifying = state.callPhase else { return XCTFail("\(state.callPhase)") }
        t.fire()
        XCTAssertEqual(d.rotations, 0)
        state.hangUp(); link.run()
        XCTAssertFalse(state.isInCall)
        XCTAssertEqual(d.rotations, 1)
        XCTAssertEqual(other.phase, .ended(.remoteHangUp))
        XCTAssertFalse(state.call.holdsKeyMaterial)
    }

    // MARK: Appels croisés (A appelle B pendant que B appelle A)

    func testCrossedCallsResolveToSingleIncomingCall() {
        callee.call(peerID: tI.id)      // R appelle I…
        caller.call(peerID: tR.id)      // …pendant que I appelle R
        XCTAssertEqual(link.queue.count, 2)
        link.queue.removeFirst()        // l'invitation de R est refusée par le transport de I (I reste l'appelant)
        tI.deliverAsCrossed = true      // celle de I arrive chez R comme invitation croisée
        link.run()
        XCTAssertEqual(caller.phase, .outgoingRequest)
        XCTAssertEqual(callee.phase, .incomingRequest, "l'appel croisé devient un appel entrant, pas un refus")
        XCTAssertEqual(callee.peerID, tI.id)
        XCTAssertFalse(callee.holdsKeyMaterial, "clé éphémère de l'appel sortant abandonné détruite")
        callee.accept()
        link.run()
        guard case .verifying(let code) = caller.phase else { return XCTFail("appelant : \(caller.phase)") }
        XCTAssertEqual(callee.phase, .verifying(code: code))
    }

    func testCrossedInvitationFromAnotherPeerIsDeclined() {
        caller.call(peerID: tR.id)
        let commit = HandshakeMessage.commit(commitment: Data(repeating: 7, count: 32)).bytes
        tI.onCallEvent?(.crossedInvitation(from: Pseudonym.random().value, context: commit))
        XCTAssertEqual(caller.phase, .outgoingRequest, "un autre pair ne peut pas interrompre notre appel")
        XCTAssertEqual(tI.answers, [false])
    }
}
