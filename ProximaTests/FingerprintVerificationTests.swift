import CryptoKit
import XCTest
@testable import Proxima

/// M3-06 : vérification d'empreinte (code SAS / QR, M2-06). Critère : une empreinte fausse fait échouer la session.
@MainActor
final class FingerprintVerificationTests: XCTestCase {
    private var link: MemoryLink!
    private var tI: MemoryTransport!, tR: MemoryTransport!
    private var sI: FakeScheduler!, sR: FakeScheduler!
    private var caller: CallSession!, callee: CallSession!

    override func setUp() async throws { makeSessions() }

    private func makeSessions(callerFake: Bool = false, calleeFake: Bool = false) {
        (link, tI, tR) = MemoryTransport.pair()
        sI = FakeScheduler(); sR = FakeScheduler()
        caller = CallSession(transport: tI, scheduler: sI, fakeFingerprint: callerFake)
        callee = CallSession(transport: tR, scheduler: sR, fakeFingerprint: calleeFake)
    }

    private func connect() {
        caller.call(peerID: tR.id); link.run()
        callee.accept(); link.run()
    }

    private func code(_ s: CallSession, file: StaticString = #filePath, line: UInt = #line) -> String {
        guard case .verifying(let c) = s.phase else { XCTFail("\(s.phase)", file: file, line: line); return "" }
        return c
    }

    private func assertNoKeys(_ sessions: CallSession..., file: StaticString = #filePath, line: UInt = #line) {
        for s in sessions {
            XCTAssertFalse(s.holdsKeyMaterial, file: file, line: line)
            XCTAssertFalse(s.canExchangeAudio, file: file, line: line)
        }
    }

    /// Paquet CONTROL SAS_OK authentique scellé par `crypter`.
    private func sasOK(_ crypter: PacketCrypter?) throws -> Data {
        try XCTUnwrap(crypter).seal(Data([ControlCode.sasOK.rawValue]), type: .control, timestampMs: 0)
    }

    // MARK: (a) Homme du milieu → codes différents → « Ne correspondent pas » → échec

    func testRelayMitMProducesDifferentCodesAndMismatchFailsBothSides() {
        // L'attaquant joue l'appelé face à I et l'appelant face à R (deux sessions distinctes, M2-06).
        let (link1, tI, tMr) = MemoryTransport.pair()
        let (link2, tMi, tR) = MemoryTransport.pair()
        let caller = CallSession(transport: tI, scheduler: FakeScheduler())
        let callee = CallSession(transport: tR, scheduler: FakeScheduler())
        let mitmAsCallee = CallSession(transport: tMr, scheduler: FakeScheduler())
        let mitmAsCaller = CallSession(transport: tMi, scheduler: FakeScheduler())
        caller.call(peerID: tMr.id); link1.run()
        mitmAsCaller.call(peerID: tR.id); link2.run()
        callee.accept(); mitmAsCallee.accept()
        for _ in 0..<3 { link1.run(); link2.run() }
        let codeI = code(caller), codeR = code(callee)
        XCTAssertEqual(codeI, code(mitmAsCallee)) // l'attaquant partage une session avec chacun…
        XCTAssertEqual(codeR, code(mitmAsCaller))
        XCTAssertNotEqual(codeI, codeR, "…mais les deux victimes voient des codes différents")
        // Les utilisateurs comparent à voix haute et répondent « Ne correspondent pas ».
        caller.rejectCode(); callee.rejectCode()
        link1.run(); link2.run()
        XCTAssertEqual(caller.phase, .failed(.codeMismatch))
        XCTAssertEqual(callee.phase, .failed(.codeMismatch))
        assertNoKeys(caller, callee)
    }

    func testSubstitutedHelloKeyGivesDifferentCodesAndMismatchFails() {
        // L'attaquant remplace pkR dans le HELLO par sa propre clé (valide) : I et R n'ont plus la même session.
        let attacker = EphemeralKeyPair().publicKeyX963
        tR.tamper = { d in
            guard case .hello(_, let n)? = HandshakeMessage.decode(d) else { return d }
            return HandshakeMessage.hello(publicKey: attacker, nonce: n).bytes
        }
        connect()
        XCTAssertNotEqual(code(caller), code(callee))
        callee.rejectCode(); link.run()
        XCTAssertEqual(callee.phase, .failed(.codeMismatch))
        // Sous MitM, les clés diffèrent : le HANGUP de R n'est pas authentifiable par I, qui ferme en erreur de protocole.
        XCTAssertEqual(caller.phase, .failed(.protocolError))
        assertNoKeys(caller, callee)
    }

    func testOneSideConfirmingUnderMitMNeverActivates() {
        let attacker = EphemeralKeyPair().publicKeyX963
        tR.tamper = { d in
            guard case .hello(_, let n)? = HandshakeMessage.decode(d) else { return d }
            return HandshakeMessage.hello(publicKey: attacker, nonce: n).bytes
        }
        connect()
        // I confirme par erreur : son SAS_OK n'est pas authentique pour R (autre clé) → R ferme.
        caller.confirmCode(); link.run()
        XCTAssertEqual(callee.phase, .failed(.protocolError))
        XCTAssertEqual(caller.phase, .failed(.disconnected))
        XCTAssertFalse(caller.canExchangeAudio)
        assertNoKeys(caller, callee)
    }

    // MARK: (b) L'engagement empêche de forcer un code identique

    func testRevealKeySubstitutionChosenAfterHelloIsRejectedByCommitment() {
        // L'attaquant voit pkR (HELLO) puis remplace pkI/nonceI dans le REVEAL pour viser un code choisi :
        // SHA256(pkM ‖ nonceM) ≠ C engagé avant → abandon, aucun code affiché.
        for _ in 0..<5 {
            makeSessions()
            tI.tamper = { d in
                guard case .reveal? = HandshakeMessage.decode(d) else { return d }
                return HandshakeMessage.reveal(publicKey: EphemeralKeyPair().publicKeyX963, nonce: Handshake.randomNonce()).bytes
            }
            connect()
            XCTAssertEqual(callee.phase, .failed(.protocolError))
            XCTAssertEqual(caller.phase, .failed(.disconnected))
            assertNoKeys(caller, callee)
        }
    }

    func testCommitmentBindsKeyForManyAttempts() throws {
        let pk = EphemeralKeyPair().publicKeyX963, n = Handshake.randomNonce()
        let c = try Handshake.commitment(publicKeyX963: pk, nonce: n)
        XCTAssertNoThrow(try Handshake.verifyCommitment(c, publicKeyX963: pk, nonce: n))
        for _ in 0..<500 { // clés / nonces choisis après coup : tous refusés
            XCTAssertThrowsError(try Handshake.verifyCommitment(c, publicKeyX963: EphemeralKeyPair().publicKeyX963,
                                                                nonce: Handshake.randomNonce()))
            XCTAssertThrowsError(try Handshake.verifyCommitment(c, publicKeyX963: pk, nonce: Handshake.randomNonce()))
        }
    }

    // MARK: (c) SAS_OK falsifié, rejoué, hors séquence

    func testForgedSASOKFails() {
        tI.tamper = { d in
            guard HandshakeMessage.decode(d) == nil else { return d }
            var m = d; m[m.count - 1] ^= 0x01; return m // tag modifié
        }
        connect()
        caller.confirmCode(); link.run()
        XCTAssertEqual(callee.phase, .failed(.protocolError))
        XCTAssertEqual(caller.phase, .failed(.disconnected))
        assertNoKeys(caller, callee)
    }

    func testSASOKFromAnotherSessionFails() throws {
        connect()
        let other = SessionKeys(role: .initiator, sharedSecret: try P256DummySecret.make(), transcript: Data(count: 32))
        tR.onCallEvent?(.received(try sasOK(PacketCrypter(keys: other))))
        XCTAssertEqual(callee.phase, .failed(.protocolError))
        assertNoKeys(callee)
    }

    func testReplayedSASOKFails() throws {
        var captured: Data?
        tI.tamper = { d in
            if HandshakeMessage.decode(d) == nil { captured = d }
            return d
        }
        connect()
        caller.confirmCode(); link.run()
        let replay = try XCTUnwrap(captured)
        tR.onCallEvent?(.received(replay)) // même paquet une 2ᵉ fois
        XCTAssertEqual(callee.phase, .failed(.protocolError))
        XCTAssertFalse(callee.canExchangeAudio)
        link.run()
        XCTAssertEqual(caller.phase, .failed(.disconnected))
        assertNoKeys(caller, callee)
    }

    func testSASOKReplayedInActivePhaseFails() throws {
        var captured: Data?
        tI.tamper = { d in
            if HandshakeMessage.decode(d) == nil { captured = d }
            return d
        }
        connect()
        let c = code(caller)
        caller.confirmCode(); callee.confirmCode(); link.run()
        XCTAssertEqual(callee.phase, .active(code: c))
        tR.onCallEvent?(.received(try XCTUnwrap(captured)))
        XCTAssertEqual(callee.phase, .failed(.protocolError))
        assertNoKeys(callee)
    }

    func testSASOKBeforeVerifyingFails() throws {
        // R envoie un SAS_OK (scellé avec des clés quelconques) à la place du HELLO : I est en poignée de main.
        let forged = try sasOK(PacketCrypter(keys: SessionKeys(role: .responder, sharedSecret: try P256DummySecret.make(),
                                                                transcript: Data(count: 32))))
        tR.tamper = { d in HandshakeMessage.decode(d) != nil ? forged : d }
        connect()
        XCTAssertEqual(caller.phase, .failed(.protocolError))
        assertNoKeys(caller, callee)
    }

    func testSASOKInIncomingRequestIgnoredWithoutKeys() throws {
        caller.call(peerID: tR.id); link.run()
        let forged = try sasOK(PacketCrypter(keys: SessionKeys(role: .initiator, sharedSecret: try P256DummySecret.make(),
                                                                transcript: Data(count: 32))))
        tR.onCallEvent?(.received(forged))
        XCTAssertEqual(callee.phase, .incomingRequest)
        XCTAssertFalse(callee.holdsKeyMaterial)
    }

    // MARK: (d) Une seule confirmation avant le délai → échec, pas d'audio

    func testAudioAllowedOnlyAfterBothConfirmations() {
        connect()
        let c = code(caller)
        XCTAssertFalse(caller.canExchangeAudio); XCTAssertFalse(callee.canExchangeAudio)
        caller.confirmCode(); link.run()
        XCTAssertTrue(caller.localCodeConfirmed)
        XCTAssertEqual(caller.phase, .verifying(code: c))
        XCTAssertEqual(callee.phase, .verifying(code: c), "le SAS_OK distant seul n'active pas")
        XCTAssertFalse(caller.canExchangeAudio); XCTAssertFalse(callee.canExchangeAudio)
        callee.confirmCode(); link.run()
        XCTAssertTrue(caller.canExchangeAudio); XCTAssertTrue(callee.canExchangeAudio)
    }

    func testOneSideConfirmsOtherTimesOut() {
        connect()
        caller.confirmCode(); link.run()
        sR.fire() // R ne répond pas pendant 30 s : défaut de réponse = refus
        link.run()
        XCTAssertEqual(callee.phase, .failed(.timeout))
        XCTAssertEqual(caller.phase, .failed(.disconnected))
        assertNoKeys(caller, callee)
    }

    func testConfirmedSideTimesOutIfPeerNeverConfirms() {
        connect()
        caller.confirmCode(); link.run()
        sI.fire() // délai de l'appelant, qui a confirmé mais n'a rien reçu
        link.run()
        XCTAssertEqual(caller.phase, .failed(.timeout))
        XCTAssertEqual(callee.phase, .failed(.disconnected))
        assertNoKeys(caller, callee)
    }

    // MARK: (e) Mode démonstration DEBUG -ProximaFakeFingerprint

    func testFakeFingerprintDemoAltersEveryDigit() {
        XCTAssertEqual(FingerprintDemo.alter(code: "482 915"), "593 026")
        XCTAssertEqual(FingerprintDemo.alter(code: "999 999"), "000 000")
        XCTAssertEqual(FingerprintDemo.launchArgument, "-ProximaFakeFingerprint")
        XCTAssertFalse(FingerprintDemo.isEnabled, "absent des arguments des tests")
    }

    func testFakeFingerprintMakesSessionFail() {
        makeSessions(callerFake: true)
        connect()
        XCTAssertNotEqual(code(caller), code(callee))
        callee.rejectCode(); caller.rejectCode(); link.run()
        XCTAssertEqual(callee.phase, .failed(.codeMismatch))
        XCTAssertEqual(caller.phase, .failed(.codeMismatch))
        assertNoKeys(caller, callee)
    }

    // MARK: Variante QR (M2-06)

    func testQRPayloadCodec() {
        let c = Data((0..<32).map { UInt8($0) })
        let p = VerificationQR.payload(commitment: c)
        XCTAssertEqual(p?.count, 66)
        XCTAssertEqual(p?.prefix(2), "01")
        XCTAssertEqual(VerificationQR.commitment(fromPayload: p ?? ""), c)
        XCTAssertNil(VerificationQR.payload(commitment: Data(count: 31)))
        for bad in ["", "01", String(repeating: "Z", count: 66), "02" + String(repeating: "0", count: 64),
                    (p ?? "") + "0", String((p ?? "").dropLast())] {
            XCTAssertNil(VerificationQR.commitment(fromPayload: bad), bad)
        }
    }

    func testScannedQRMatchingConfirmsCallee() throws {
        connect()
        let c = code(caller)
        XCTAssertNil(callee.verificationQRPayload, "seul l'appelant affiche le QR")
        let payload = try XCTUnwrap(caller.verificationQRPayload)
        callee.submitScannedQR(payload); link.run()
        XCTAssertTrue(callee.localCodeConfirmed)
        caller.confirmCode(); link.run()
        XCTAssertEqual(callee.phase, .active(code: c))
        XCTAssertEqual(caller.phase, .active(code: c))
    }

    func testScannedQRFromAnotherSessionFails() throws {
        connect()
        let foreign = try XCTUnwrap(VerificationQR.payload(commitment: Data(repeating: 7, count: 32)))
        callee.submitScannedQR(foreign); link.run()
        XCTAssertEqual(callee.phase, .failed(.codeMismatch))
        XCTAssertEqual(caller.phase, .ended(.remoteHangUp))
        assertNoKeys(caller, callee)
    }

    func testUnreadableQRFails() {
        connect()
        callee.submitScannedQR("https://exemple.invalid/")
        XCTAssertEqual(callee.phase, .failed(.codeMismatch))
    }

    func testFakeFingerprintQRFails() throws {
        makeSessions(callerFake: true)
        connect()
        callee.submitScannedQR(try XCTUnwrap(caller.verificationQRPayload)); link.run()
        XCTAssertEqual(callee.phase, .failed(.codeMismatch))
        assertNoKeys(caller, callee)
    }
}

/// Secret ECDH quelconque (autre session) pour forger des paquets authentiques… pour de mauvaises clés.
enum P256DummySecret {
    static func make() throws -> SharedSecret {
        try P256.KeyAgreement.PrivateKey().sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PrivateKey().publicKey)
    }
}
