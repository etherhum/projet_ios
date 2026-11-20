import AVFoundation
import XCTest
@testable import Proxima

// MARK: Entrée/sortie audio factice

final class FakeAudioIO: AudioIO {
    private(set) var started = 0
    private(set) var stopped = 0
    private(set) var played: [AVAudioPCMBuffer] = []
    var onCapture: ((AVAudioPCMBuffer) -> Void)?
    func start(onCapture: @escaping (AVAudioPCMBuffer) -> Void) throws { started += 1; self.onCapture = onCapture }
    func stop() { stopped += 1; onCapture = nil }
    func play(_ buffer: AVAudioPCMBuffer) { played.append(buffer) }
    func setSpeaker(_ on: Bool) {}
}

private func sine(frames: Int, offset: Int = 0, freq: Float = 440) -> AVAudioPCMBuffer {
    let b = AVAudioPCMBuffer(pcmFormat: VoiceFormat.pcm, frameCapacity: AVAudioFrameCount(frames))!
    b.frameLength = AVAudioFrameCount(frames)
    for i in 0..<frames { b.floatChannelData![0][i] = 0.5 * sin(Float(offset + i) * 2 * .pi * freq / 16_000) }
    return b
}

private func entropy(_ bytes: [UInt8]) -> Double {
    var counts = [Int](repeating: 0, count: 256)
    for b in bytes { counts[Int(b)] += 1 }
    let n = Double(bytes.count)
    return counts.filter { $0 > 0 }.reduce(0) { $0 - Double($1) / n * log2(Double($1) / n) }
}

private func opened(_ counter: UInt64, _ payload: Data) -> OpenedPacket {
    OpenedPacket(header: PacketHeader(type: .audio, counter: counter, timestampMs: 0), plaintext: payload)
}

@MainActor
final class AudioTests: XCTestCase {

    // MARK: Codec

    /// Codec réellement disponible sur l'appareil de test (attendu : Opus natif).
    func testOpusIsAvailable() {
        XCTAssertEqual(VoiceCodecKind.resolved, .opus)
    }

    func testEncodeSealOpenDecodeRoundTripKeepsDuration() throws {
        let kind = VoiceCodecKind.resolved
        let enc = try VoiceEncoder(kind: kind), dec = try VoiceDecoder(kind: kind)
        let (sender, receiver) = try crypterPair()
        let fpp = Int(kind.framesPerPacket), n = 50
        var decodedFrames = 0, energy: Float = 0
        for i in 0..<n {
            guard let frame = try enc.encode(sine(frames: fpp, offset: i * fpp)) else { continue }
            XCTAssertLessThanOrEqual(frame.count, kind.maxFrameByteCount)
            let packet = try sender.seal(frame, type: .audio, timestampMs: UInt32(i * 20))
            XCTAssertLessThanOrEqual(packet.count, CryptoConstants.maxPacketByteCount)
            let pcm = try dec.decode(try receiver.open(packet).plaintext)
            decodedFrames += Int(pcm.frameLength)
            for s in 0..<Int(pcm.frameLength) { energy += abs(pcm.floatChannelData![0][s]) }
        }
        // Même durée à une trame près (délai d'amorçage du codec).
        XCTAssertEqual(Double(decodedFrames), Double(n * fpp), accuracy: Double(fpp))
        XCTAssertGreaterThan(energy / Float(decodedFrames), 0.1, "le signal décodé n'est pas du silence")
    }

    func testOversizedFrameRejectedBeforeDecoding() throws {
        let dec = try VoiceDecoder(kind: .resolved)
        XCTAssertThrowsError(try dec.decode(Data(count: VoiceCodecKind.resolved.maxFrameByteCount + 1))) {
            XCTAssertEqual($0 as? VoiceCodecError, .frameTooLarge)
        }
        XCTAssertThrowsError(try dec.decode(Data())) { XCTAssertEqual($0 as? VoiceCodecError, .frameTooLarge) }
        // Dans le pipeline : compté rejeté, rien n'est joué ni mis en tampon.
        let io = FakeAudioIO(), p = AudioPipeline(io: io)
        p.update(for: .active(code: "000 000"))
        p.receive(opened(0, Data(repeating: 7, count: 1_000)))
        XCTAssertEqual(p.stats.rejected, 1)
        XCTAssertEqual(p.bufferedItemCount, 0)
        XCTAssertTrue(io.played.isEmpty)
    }

    // MARK: Chiffrement sur le réseau

    func testTamperedAudioPacketRejectedAndNeverDecoded() throws {
        let (link, tI, tR) = MemoryTransport.pair()
        let caller = CallSession(transport: tI, scheduler: FakeScheduler())
        let callee = CallSession(transport: tR, scheduler: FakeScheduler())
        caller.call(peerID: tR.id); link.run()
        callee.accept(); link.run()
        caller.confirmCode(); callee.confirmCode(); link.run()
        guard case .active = callee.phase else { return XCTFail("pas actif : \(callee.phase)") }

        var delivered: [OpenedPacket] = [], rejected = 0
        callee.onAudioPacket = { delivered.append($0) }
        callee.onPacketRejected = { rejected += 1 }

        XCTAssertTrue(caller.sendAudio(Data([1, 2, 3, 4]))); link.run()
        XCTAssertEqual(delivered.map(\.plaintext), [Data([1, 2, 3, 4])])

        for index in [1, 5, 15, 20] { // type, compteur, chiffré, tag
            tI.tamper = { d in var m = d; m[m.startIndex + min(index, m.count - 1)] ^= 0x01; return m }
            XCTAssertTrue(caller.sendAudio(Data([9, 9, 9, 9]))); link.run()
        }
        XCTAssertEqual(delivered.count, 1, "aucun paquet altéré ne parvient au décodeur")
        XCTAssertEqual(rejected, 4)
        XCTAssertEqual(callee.phase, caller.phase, "paquets isolés ignorés, appel maintenu")
        // Hors état actif : aucun envoi audio.
        caller.hangUp(); link.run()
        XCTAssertFalse(caller.sendAudio(Data([1])))
    }

    /// Le flux émis n'a ni la structure ni l'entropie du PCM / Opus en clair.
    func testWireStreamLooksRandomAndHidesPlaintext() throws {
        let (sender, _) = try crypterPair()
        let pcmEncoder = try VoiceEncoder(kind: .pcm16)
        var clear: [UInt8] = [], wire: [UInt8] = []
        for i in 0..<200 {
            let frame = try XCTUnwrap(try pcmEncoder.encode(sine(frames: 320, offset: i * 320)))
            let packet = try sender.seal(frame, type: .audio, timestampMs: UInt32(i * 20))
            XCTAssertEqual(packet[1], PacketType.audio.rawValue) // seul l'en-tête est en clair
            XCTAssertNil(packet.range(of: frame.prefix(16)), "aucun morceau du clair dans le paquet")
            clear += frame
            wire += packet.dropFirst(CryptoConstants.headerByteCount)
        }
        XCTAssertLessThan(entropy(clear), 7.9)
        XCTAssertGreaterThan(entropy(wire), 7.99, "chiffré indistinguable d'aléa")
    }

    // MARK: Tampon de gigue

    func testJitterBufferReordersAndIgnoresDuplicates() {
        var j = JitterBuffer(depth: 3, capacity: 8)
        let d = { (i: UInt8) in Data([i]) }
        XCTAssertEqual(j.insert(counter: 11, payload: d(11)), [])
        XCTAssertEqual(j.insert(counter: 10, payload: d(10)), [])
        XCTAssertEqual(j.insert(counter: 10, payload: d(10)), [], "doublon en attente ignoré")
        XCTAssertEqual(j.insert(counter: 12, payload: d(12)), [.frame(d(10))])
        XCTAssertEqual(j.insert(counter: 10, payload: d(10)), [], "doublon déjà joué ignoré")
        XCTAssertEqual(j.insert(counter: 13, payload: d(13)), [.frame(d(11))])
    }

    func testJitterBufferGapBecomesSilenceAndStaysBounded() {
        var j = JitterBuffer(depth: 3, capacity: 8)
        var out: [JitterBuffer.Output] = []
        for c: UInt64 in [0, 1, 2, 4, 5, 6] { out += j.insert(counter: c, payload: Data([UInt8(c)])) }
        XCTAssertEqual(out, [.frame(Data([0])), .frame(Data([1])), .frame(Data([2])), .lost, .frame(Data([4]))])
        XCTAssertLessThan(j.count, j.depth)
        // Long trou : saut sans générer des centaines de trames de silence.
        out = []
        for c: UInt64 in 500...510 { out += j.insert(counter: c, payload: Data([1])) }
        XCTAssertLessThanOrEqual(out.filter { $0 == .lost }.count, 2)
        XCTAssertLessThan(j.count, j.capacity)
        j.reset()
        XCTAssertEqual(j.count, 0)
    }

    // MARK: Pipeline

    func testPipelineStartsOnlyWhenActiveAndStopClearsBuffers() async throws {
        let io = FakeAudioIO(), p = AudioPipeline(io: io)
        var sent: [Data] = []
        p.sendFrame = { sent.append($0); return true }
        for phase: CallPhase in [.idle, .outgoingRequest, .incomingRequest, .handshaking, .verifying(code: "1"), .failed(.timeout)] {
            p.update(for: phase)
        }
        XCTAssertEqual(io.started, 0)
        XCTAssertFalse(p.isRunning)
        p.receive(opened(0, Data([1])))
        XCTAssertEqual(p.stats.received, 0, "rien n'est reçu hors appel actif")

        p.update(for: .active(code: "1"))
        p.update(for: .active(code: "1"))
        XCTAssertEqual(io.started, 1)
        // Capture : 2,5 trames → 2 trames envoyées, ½ trame en attente.
        let fpp = Int(p.codec.framesPerPacket)
        io.onCapture?(sine(frames: fpp * 5 / 2))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThanOrEqual(sent.count, 1)
        // Micro coupé : on continue d'envoyer (silence) à débit constant.
        p.isMuted = true
        let before = sent.count
        io.onCapture?(sine(frames: fpp * 2))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(sent.count, before + 2)

        p.receive(opened(5, Data([1, 2])))
        p.receive(opened(6, Data([1, 2])))
        XCTAssertGreaterThan(p.bufferedItemCount, 0)

        p.update(for: .ended(.localHangUp))
        XCTAssertEqual(io.stopped, 1)
        XCTAssertFalse(p.isRunning)
        XCTAssertEqual(p.bufferedItemCount, 0, "aucun PCM ni trame en mémoire après l'appel")
        XCTAssertFalse(p.isMuted)
    }

    // MARK: Utilitaires

    private func crypterPair() throws -> (PacketCrypter, PacketCrypter) {
        let i = EphemeralKeyPair(), r = EphemeralKeyPair()
        let t = Data("transcript-test".utf8)
        let ki = try i.deriveSessionKeys(role: .initiator, peerPublicKey: PeerPublicKey(x963Representation: r.publicKeyX963), transcript: t)
        let kr = try r.deriveSessionKeys(role: .responder, peerPublicKey: PeerPublicKey(x963Representation: i.publicKeyX963), transcript: t)
        return (PacketCrypter(keys: ki), PacketCrypter(keys: kr))
    }
}
