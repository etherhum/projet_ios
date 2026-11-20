import AVFoundation
import XCTest
@testable import Proxima

/// Échéancier qui mémorise la durée de chaque échéance (pour déclencher la durée maximale de session).
@MainActor
final class RecordingScheduler: DeadlineScheduler {
    final class Token: DeadlineToken {
        let seconds: TimeInterval
        var handler: (@MainActor () -> Void)?
        init(_ seconds: TimeInterval, _ handler: @escaping @MainActor () -> Void) { self.seconds = seconds; self.handler = handler }
        func cancel() { handler = nil }
    }
    private(set) var tokens: [Token] = []
    func schedule(after seconds: TimeInterval, _ handler: @escaping @MainActor () -> Void) -> DeadlineToken {
        let t = Token(seconds, handler); tokens.append(t); return t
    }
    func fire(after seconds: TimeInterval) { tokens.last(where: { $0.seconds == seconds && $0.handler != nil })?.handler?() }
}

/// M3-10 : échouer en sécurité. Toute erreur crypto ou doute ⇒ `failed`, clés détruites, audio arrêté.
@MainActor
final class FailSafeTests: XCTestCase {
    private var link: MemoryLink!
    private var tI: MemoryTransport!, tR: MemoryTransport!
    private var sI: RecordingScheduler!, sR: RecordingScheduler!
    private var caller: CallSession!, callee: CallSession!
    private var now: TimeInterval = 1_000

    private func makeSessions(sendCounterLimit: UInt64 = CryptoConstants.maxPacketCounter) {
        (link, tI, tR) = MemoryTransport.pair()
        sI = RecordingScheduler(); sR = RecordingScheduler()
        caller = CallSession(transport: tI, scheduler: sI, clock: { [unowned self] in self.now },
                             sendCounterLimit: sendCounterLimit)
        callee = CallSession(transport: tR, scheduler: sR, clock: { [unowned self] in self.now })
    }

    override func setUp() async throws { makeSessions() }

    private func toVerifying() {
        caller.call(peerID: tR.id); link.run()
        callee.accept(); link.run()
        guard case .verifying = callee.phase, case .verifying = caller.phase else {
            return XCTFail("vérification attendue : \(caller.phase) / \(callee.phase)")
        }
    }

    private func toActive() {
        toVerifying()
        caller.confirmCode(); callee.confirmCode(); link.run()
        XCTAssertTrue(caller.canExchangeAudio); XCTAssertTrue(callee.canExchangeAudio)
    }

    /// Injecte des octets bruts chez l'appelé (attaquant sur le lien).
    private func inject(_ data: Data) { tR.onCallEvent?(.received(data)) }

    /// Paquet valide de l'appelant vers l'appelé (chiffré avec la vraie clé I→R).
    private func validPacket(_ type: PacketType = .audio, _ payload: Data = Data([1, 2, 3])) throws -> Data {
        try XCTUnwrap(caller.crypter).seal(payload, type: type, timestampMs: 0)
    }

    private func assertFailedSecurely(_ s: CallSession, crypter c: PacketCrypter, _ failure: CallFailure = .protocolError,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.phase, .failed(failure), file: file, line: line)
        XCTAssertFalse(s.holdsKeyMaterial, file: file, line: line)
        XCTAssertNil(s.crypter, file: file, line: line)
        XCTAssertTrue(c.isDestroyed, "clé supprimée", file: file, line: line)
        XCTAssertFalse(s.canExchangeAudio, file: file, line: line)
        XCTAssertFalse(s.sendAudio(Data([1])), file: file, line: line)
        XCTAssertThrowsError(try c.seal(Data([1]), type: .audio, timestampMs: 0), file: file, line: line) {
            XCTAssertEqual($0 as? CryptoError, .keyDestroyed)
        }
        XCTAssertThrowsError(try c.open(Data(count: 40)), file: file, line: line) {
            XCTAssertEqual($0 as? CryptoError, .keyDestroyed)
        }
    }

    // MARK: Critère de l'issue : paquet invalide ⇒ fermeture et clé supprimée

    func testInvalidPacketDuringVerificationClosesCallAndDeletesKey() throws {
        let mutations: [(String, (inout Data) -> Void)] = [
            ("tag altéré", { $0[$0.count - 1] ^= 0x01 }),
            ("chiffré altéré", { $0[14] ^= 0x80 }),
            ("version inconnue", { $0[0] = 0x02 }),
            ("type inconnu", { $0[1] = 0x7F }),
            ("trop court", { $0 = $0.prefix(29) }),
            ("trop long", { $0.append(Data(count: 1_201 - $0.count)) }),
        ]
        for (name, mutate) in mutations {
            makeSessions()
            toVerifying()
            let c = try XCTUnwrap(callee.crypter)
            var packet = try validPacket()
            mutate(&packet)
            inject(packet)
            assertFailedSecurely(callee, crypter: c)
            XCTAssertFalse(tR.connected, "transport fermé (\(name))")
            link.run()
            XCTAssertFalse(caller.holdsKeyMaterial, "le pair aussi ferme (déconnexion) : \(name)")
        }
    }

    func testReplayedPacketDuringVerificationCloses() throws {
        toVerifying()
        let c = try XCTUnwrap(callee.crypter)
        let p = try validPacket(.audio)
        inject(p) // AUDIO authentique : ignoré hors appel actif
        XCTAssertEqual(callee.phase.isBusy, true)
        inject(p) // rejoué
        assertFailedSecurely(callee, crypter: c)
    }

    // MARK: Politique de rejets en appel actif (M2-07 : plus de 20 rejets en 5 s)

    func testIsolatedRejectsToleratedInActiveCall() throws {
        toActive()
        var bad = try validPacket(); bad[bad.count - 1] ^= 1
        for _ in 0..<CallSession.rejectionLimit { inject(bad) }
        XCTAssertTrue(callee.canExchangeAudio, "20 rejets en 5 s : toléré (M2-07)")
        now += CallSession.rejectionWindow // la fenêtre glisse
        for _ in 0..<CallSession.rejectionLimit { inject(bad) }
        XCTAssertTrue(callee.canExchangeAudio)
    }

    func testRejectThresholdInActiveCallClosesAndDeletesKey() throws {
        toActive()
        let c = try XCTUnwrap(callee.crypter)
        var bad = try validPacket(); bad[bad.count - 1] ^= 1
        for i in 0..<CallSession.rejectionLimit { now += 0.1; inject(i % 2 == 0 ? bad : Data([0x02]) + bad.dropFirst()) }
        XCTAssertTrue(callee.canExchangeAudio)
        inject(bad) // 21ᵉ rejet en moins de 5 s
        assertFailedSecurely(callee, crypter: c)
    }

    func testControlCodeAfterSASInActiveCloses() throws {
        toActive()
        let c = try XCTUnwrap(callee.crypter)
        inject(try validPacket(.control, Data([ControlCode.sasOK.rawValue])))
        assertFailedSecurely(callee, crypter: c)
    }

    // MARK: Audio

    func testAudioDecodingErrorCountsAsInvalidPacket() async throws {
        let io = FakeAudioIO(), p = AudioPipeline(io: io, codec: .pcm16)
        var invalid = 0
        p.onInvalidFrame = { invalid += 1 }
        p.update(for: .active(code: "1"))
        // PCM 16 attend exactement 640 o : 5 o ⇒ erreur de décodage (après authentification).
        for i in 0..<6 {
            p.receive(OpenedPacket(header: PacketHeader(type: .audio, counter: UInt64(i), timestampMs: 0), plaintext: Data(count: 5)))
        }
        XCTAssertGreaterThan(invalid, 0)
        // Trame trop grande : rejetée avant décodage, comptée aussi.
        let before = invalid
        p.receive(OpenedPacket(header: PacketHeader(type: .audio, counter: 99, timestampMs: 0), plaintext: Data(count: 641)))
        XCTAssertEqual(invalid, before + 1)

        // Branché sur la session : au-delà du seuil, l'appel se ferme.
        toActive()
        let c = try XCTUnwrap(callee.crypter)
        for _ in 0...CallSession.rejectionLimit { callee.noteInvalidAudioFrame() }
        assertFailedSecurely(callee, crypter: c)
    }

    func testAudioSessionActivationFailureClosesCall() async throws {
        let (link, a, b) = MemoryTransport.pair()
        let ioA = FakeAudioIO(), ioB = FakeAudioIO()
        ioB.failStart = true
        let mic = FakeMicrophone(status: .granted)
        let stateA = AppState(discovery: FakeDiscovery(), microphone: mic, rotationTimer: FakeTimer(), callTransport: a,
                              callScheduler: RecordingScheduler(), janitor: SecretsJanitor(observeTermination: false), audioIO: ioA)
        let stateB = AppState(discovery: FakeDiscovery(), microphone: mic, rotationTimer: FakeTimer(), callTransport: b,
                              callScheduler: RecordingScheduler(), janitor: SecretsJanitor(observeTermination: false), audioIO: ioB)
        await stateA.requestCall(with: NearbyPeer(pseudonym: Pseudonym(value: b.id))); link.run()
        await stateB.acceptIncomingCall(); link.run()
        stateA.confirmCode(); stateB.confirmCode(); link.run()
        XCTAssertTrue(stateA.audio.isRunning)
        XCTAssertFalse(stateB.audio.isRunning)
        try await Task.sleep(for: .milliseconds(50)) // fermeture différée d'un tour de boucle
        XCTAssertEqual(stateB.callPhase, .failed(.audioUnavailable))
        XCTAssertFalse(stateB.call.holdsKeyMaterial)
        XCTAssertFalse(stateB.call.canExchangeAudio)
        link.run()
        XCTAssertEqual(stateA.callPhase, .failed(.disconnected))
        XCTAssertFalse(stateA.audio.isRunning, "audio arrêté chez le pair")
        XCTAssertEqual(stateA.audio.bufferedItemCount, 0)
        XCTAssertFalse(stateA.call.holdsKeyMaterial)
    }

    func testAudioEngineFailureDuringCallStopsAudio() {
        let io = FakeAudioIO(), p = AudioPipeline(io: io)
        var failures = 0
        p.onFailure = { failures += 1 }
        p.update(for: .active(code: "1"))
        XCTAssertTrue(p.isRunning)
        io.onFailure?()
        XCTAssertFalse(p.isRunning)
        XCTAssertEqual(p.bufferedItemCount, 0)
        XCTAssertEqual(failures, 1)
    }

    // MARK: Limites de session

    func testSendCounterExhaustedCloses() throws {
        makeSessions(sendCounterLimit: 3) // SAS_OK = 0, puis 2 trames audio
        toActive()
        let c = try XCTUnwrap(caller.crypter)
        XCTAssertTrue(caller.sendAudio(Data([1])))
        XCTAssertTrue(caller.sendAudio(Data([2])))
        XCTAssertFalse(caller.sendAudio(Data([3])))
        assertFailedSecurely(caller, crypter: c, .sessionLimitReached)
        link.run()
        XCTAssertFalse(callee.holdsKeyMaterial)
    }

    func testMaxSessionDurationCloses() throws {
        toActive()
        let c = try XCTUnwrap(callee.crypter)
        XCTAssertEqual(CallSession.maxSessionDuration, 3_600)
        sR.fire(after: CallSession.maxSessionDuration)
        assertFailedSecurely(callee, crypter: c, .sessionLimitReached)
    }

    func testVerificationTimeoutDeletesKey() throws {
        toVerifying()
        let c = try XCTUnwrap(callee.crypter)
        sR.fire(after: CallSession.stepTimeout)
        assertFailedSecurely(callee, crypter: c, .timeout)
    }

    // MARK: Transport

    func testTransportDisconnectionDeletesKeys() throws {
        toActive()
        let c = try XCTUnwrap(callee.crypter)
        tR.onCallEvent?(.disconnected)
        assertFailedSecurely(callee, crypter: c, .disconnected)
    }

    func testFailedSessionNeverReturnsToActive() throws {
        toVerifying()
        let c = try XCTUnwrap(callee.crypter)
        inject(Data(count: 40))
        assertFailedSecurely(callee, crypter: c)
        // Aucune entrée ne ranime la session.
        callee.confirmCode()
        inject(try validPacket(.control, Data([ControlCode.sasOK.rawValue])))
        tR.onCallEvent?(.connected)
        XCTAssertEqual(callee.phase, .failed(.protocolError))
        XCTAssertFalse(callee.canExchangeAudio)
        XCTAssertNil(callee.crypter)
    }

    func testFailureEventsAreLoggedStatically() {
        for f: CallFailure in [.sessionLimitReached, .audioUnavailable] {
            XCTAssertNotNil(AppLog.Event.forCallPhase(.failed(f)))
            XCTAssertFalse(CallView.message(for: f).isEmpty)
        }
        for e: AppLog.Event in [.rejectionThresholdExceeded, .sessionMaxDurationReached, .sendCounterExhausted,
                                .sealFailed, .transportSendFailed, .audioFrameRejected, .audioFailureClosedCall] {
            XCTAssertFalse(e.message.description.isEmpty)
        }
    }
}

/// Corrections après tests manuels : rotation de fin d'appel (M3-09) et guidage de la confirmation (M3-06).
@MainActor
final class PostManualTestFixesTests: XCTestCase {
    private func makeState(_ d: FakeDiscovery, _ t: MemoryTransport) -> AppState {
        AppState(discovery: d, microphone: FakeMicrophone(status: .granted), rotationTimer: FakeTimer(),
                 rotationInterval: 600, callTransport: t, callScheduler: RecordingScheduler(),
                 janitor: SecretsJanitor(observeTermination: false), audioIO: FakeAudioIO())
    }

    func testDeclinedCallDoesNotRotatePseudonym() async {
        let (link, a, b) = MemoryTransport.pair()
        let d = FakeDiscovery(), state = makeState(d, a)
        let other = CallSession(transport: b, scheduler: RecordingScheduler())
        state.userRequestedSearch()
        let before = d.localPseudonym
        await state.requestCall(with: NearbyPeer(pseudonym: Pseudonym(value: b.id))); link.run()
        other.decline(); link.run()
        XCTAssertEqual(state.callPhase, .failed(.declinedOrNoAnswer))
        XCTAssertEqual(d.rotations, 0, "refus / blocage : pas de nouveau pseudonyme (sinon blocage contourné)")
        XCTAssertEqual(d.localPseudonym, before)
    }

    func testOutgoingTimeoutDoesNotRotatePseudonym() async {
        let (link, a, b) = MemoryTransport.pair()
        _ = b
        let d = FakeDiscovery(), sched = RecordingScheduler()
        let state = AppState(discovery: d, microphone: FakeMicrophone(status: .granted), rotationTimer: FakeTimer(),
                             callTransport: a, callScheduler: sched, janitor: SecretsJanitor(observeTermination: false),
                             audioIO: FakeAudioIO())
        state.userRequestedSearch()
        await state.requestCall(with: NearbyPeer(pseudonym: .random())); link.run()
        sched.fire(after: CallSession.stepTimeout)
        XCTAssertFalse(state.isInCall)
        XCTAssertEqual(d.rotations, 0)
    }

    func testEstablishedCallThenHangUpRotates() async {
        let (link, a, b) = MemoryTransport.pair()
        let d = FakeDiscovery(), state = makeState(d, a)
        let other = CallSession(transport: b, scheduler: RecordingScheduler())
        state.userRequestedSearch()
        await state.requestCall(with: NearbyPeer(pseudonym: Pseudonym(value: b.id))); link.run()
        other.accept(); link.run()
        guard case .verifying = state.callPhase else { return XCTFail("\(state.callPhase)") }
        state.hangUp(); link.run()
        XCTAssertEqual(d.rotations, 1, "appel établi puis raccroché : nouveau pseudonyme (M2-03)")
    }

    func testPeerConfirmationExposedUntilLocalConfirms() async {
        let (link, a, b) = MemoryTransport.pair()
        let stateA = makeState(FakeDiscovery(), a), stateB = makeState(FakeDiscovery(), b)
        await stateA.requestCall(with: NearbyPeer(pseudonym: Pseudonym(value: b.id))); link.run()
        await stateB.acceptIncomingCall(); link.run()
        XCTAssertFalse(stateA.codeConfirmedByPeer)
        // B confirme (ex. QR de A scanné) : A est invité à vérifier à son tour.
        if let qr = stateA.verificationQRPayload { stateB.submitScannedQR(qr) } else { stateB.confirmCode() }
        link.run()
        XCTAssertTrue(stateA.codeConfirmedByPeer)
        XCTAssertFalse(stateA.codeConfirmedLocally)
        guard case .verifying = stateA.callPhase else { return XCTFail("A doit encore confirmer") }
        stateA.confirmCode(); link.run()
        guard case .active = stateA.callPhase else { return XCTFail("\(stateA.callPhase)") }
        stateA.hangUp(); link.run()
        XCTAssertFalse(stateA.codeConfirmedByPeer, "réinitialisé en fin d'appel")
    }
}
