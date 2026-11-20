import CryptoKit
import XCTest
@testable import Proxima

/// Tests M3-08 : anti-rejeu, fraîcheur et validation des paquets reçus (M2-07).
final class ReplayTests: XCTestCase {

    /// Horloge manuelle injectable (ms).
    private final class Clock { var ms: UInt64 = 100_000 }

    private func session() throws -> (i: SessionKeys, r: SessionKeys) {
        let kpI = EphemeralKeyPair(), nI = Handshake.randomNonce()
        let c = try Handshake.commitment(publicKeyX963: kpI.publicKeyX963, nonce: nI)
        let kpR = EphemeralKeyPair(), nR = Handshake.randomNonce()
        let t = try Handshake.transcript(commitment: c, responderPublicKeyX963: kpR.publicKeyX963, responderNonce: nR,
                                         initiatorPublicKeyX963: kpI.publicKeyX963, initiatorNonce: nI)
        let i = try kpI.deriveSessionKeys(role: .initiator, peerPublicKey: PeerPublicKey(x963Representation: kpR.publicKeyX963), transcript: t)
        let r = try kpR.deriveSessionKeys(role: .responder, peerPublicKey: PeerPublicKey(x963Representation: kpI.publicKeyX963), transcript: t)
        return (i, r)
    }

    private let msg = Data("trame audio de test".utf8)

    /// Émetteur I, récepteur R avec horloge contrôlée.
    private func pair() throws -> (tx: PacketCrypter, rx: PacketCrypter, clock: Clock) {
        let (i, r) = try session()
        let clock = Clock()
        return (PacketCrypter(keys: i), PacketCrypter(keys: r, replayWindow: ReplayWindow { clock.ms }), clock)
    }

    private func assertReplay(_ e: Error, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(e as? ReplayError, .replayedOrOutOfWindow, file: file, line: line)
    }

    // MARK: Rejeu

    func testReplayedPacketRejected() throws {
        let (tx, rx, _) = try pair()
        let p = try tx.seal(msg, type: .audio, timestampMs: 0)
        XCTAssertEqual(try rx.open(p).plaintext, msg)
        XCTAssertThrowsError(try rx.open(p)) { assertReplay($0) }
        XCTAssertThrowsError(try rx.open(p)) { assertReplay($0) }
    }

    func testOutOfOrderWithinWindowAcceptedOnce() throws {
        let (tx, rx, _) = try pair()
        let ps = try (0..<10).map { _ in try tx.seal(msg, type: .audio, timestampMs: 0) }
        for k in [9, 0, 5, 3, 8, 1, 2, 7, 4, 6] { XCTAssertNoThrow(try rx.open(ps[k]), "paquet \(k)") }
        for p in ps { XCTAssertThrowsError(try rx.open(p)) { assertReplay($0) } }
    }

    func testTooOldPacketRejected() throws {
        let (tx, rx, _) = try pair()
        let ps = try (0...70).map { _ in try tx.seal(msg, type: .audio, timestampMs: 0) }
        XCTAssertNoThrow(try rx.open(ps[70]))
        XCTAssertThrowsError(try rx.open(ps[6])) { assertReplay($0) }  // 70 − 64 : hors fenêtre
        XCTAssertNoThrow(try rx.open(ps[7]))                          // 70 − 63 : dans la fenêtre
    }

    func testAbusiveJumpRejected() {
        let w = ReplayWindow { 0 }
        XCTAssertThrowsError(try w.check(counter: 1_000)) { assertReplay($0) }
        XCTAssertNoThrow(try w.accept(counter: 10, timestampMs: 0))
        XCTAssertNoThrow(try w.check(counter: 1_010))
        XCTAssertThrowsError(try w.check(counter: 1_011)) { assertReplay($0) }
        XCTAssertThrowsError(try w.check(counter: .max)) { assertReplay($0) }
    }

    func testWindowBitmapUnit() throws {
        let w = ReplayWindow { 0 }
        try w.accept(counter: 0, timestampMs: 0)
        try w.accept(counter: 64, timestampMs: 0)
        XCTAssertThrowsError(try w.check(counter: 0)) { assertReplay($0) }
        XCTAssertNoThrow(try w.check(counter: 1))
        try w.accept(counter: 200, timestampMs: 0) // saut > 64 : masque remis à zéro
        XCTAssertThrowsError(try w.check(counter: 136)) { assertReplay($0) }
        XCTAssertNoThrow(try w.check(counter: 137))
        XCTAssertThrowsError(try w.check(counter: 200)) { assertReplay($0) }
    }

    // MARK: Fraîcheur

    func testStaleTimestampRejected() throws {
        let (tx, rx, clock) = try pair()
        XCTAssertNoThrow(try rx.open(try tx.seal(msg, type: .audio, timestampMs: 1_000)))
        // Paquet valide retenu 10 s puis rejoué : compteur neuf, horodatage ancien.
        let held = try tx.seal(msg, type: .audio, timestampMs: 1_020)
        clock.ms += 10_000
        XCTAssertThrowsError(try rx.open(held)) { XCTAssertEqual($0 as? ReplayError, .staleTimestamp) }
        // Horodatage dans le futur (> 2 s) aussi rejeté ; dérive ≤ 2 s acceptée.
        XCTAssertThrowsError(try rx.open(try tx.seal(msg, type: .audio, timestampMs: 13_100))) {
            XCTAssertEqual($0 as? ReplayError, .staleTimestamp)
        }
        XCTAssertNoThrow(try rx.open(try tx.seal(msg, type: .audio, timestampMs: 9_000)))
        XCTAssertNoThrow(try rx.open(try tx.seal(msg, type: .audio, timestampMs: 13_000)))
    }

    func testStalePacketDoesNotAdvanceWindow() throws {
        let (tx, rx, clock) = try pair()
        let p0 = try tx.seal(msg, type: .audio, timestampMs: 0)
        let p1 = try tx.seal(msg, type: .audio, timestampMs: 0)
        XCTAssertNoThrow(try rx.open(p0))
        clock.ms += 5_000
        XCTAssertThrowsError(try rx.open(p1))
        clock.ms -= 5_000
        XCTAssertNoThrow(try rx.open(p1)) // non marqué comme vu
    }

    // MARK: Falsification

    func testForgedPacketDoesNotAdvanceWindow() throws {
        let (tx, rx, _) = try pair()
        let ps = try (0..<3).map { _ in try tx.seal(msg, type: .audio, timestampMs: 0) }
        XCTAssertNoThrow(try rx.open(ps[0]))
        // Compteur forgé très en avant (dans la limite de saut), tag invalide.
        var forged = Data(ps[1])
        forged[9] = 0xF0; forged[forged.count - 1] ^= 0xFF
        XCTAssertThrowsError(try rx.open(forged)) { XCTAssertEqual($0 as? CryptoError, .authenticationFailed) }
        var flipped = Data(ps[1]); flipped[20] ^= 0x01
        XCTAssertThrowsError(try rx.open(flipped)) { XCTAssertEqual($0 as? CryptoError, .authenticationFailed) }
        // Les vrais paquets 1 et 2 passent toujours : la fenêtre n'a pas bougé.
        XCTAssertNoThrow(try rx.open(ps[1]))
        XCTAssertNoThrow(try rx.open(ps[2]))
    }

    func testOtherDirectionReplayRejected() throws {
        let (i, r) = try session()
        let ci = PacketCrypter(keys: i), cr = PacketCrypter(keys: r)
        let fromR = try cr.seal(msg, type: .audio, timestampMs: 0)
        XCTAssertNoThrow(try ci.open(fromR))
        XCTAssertThrowsError(try cr.open(fromR)) { XCTAssertEqual($0 as? CryptoError, .authenticationFailed) }
    }

    // MARK: Taille et format

    func testTruncatedPacketsRejected() throws {
        let (tx, rx, _) = try pair()
        let p = try tx.seal(msg, type: .audio, timestampMs: 0)
        for n in [0, 1, 13, 14, 29] {
            XCTAssertThrowsError(try rx.open(p.prefix(n)), "\(n) o") { XCTAssertEqual($0 as? CryptoError, .malformedPacket) }
        }
        // Tronqué mais ≥ 30 o : rejeté par le tag.
        XCTAssertThrowsError(try rx.open(p.prefix(p.count - 1)))
        XCTAssertNoThrow(try rx.open(p)) // la fenêtre n'a pas bougé
    }

    func testOversizedPacketsRejected() throws {
        let (tx, rx, _) = try pair()
        let p = try tx.seal(msg, type: .audio, timestampMs: 0)
        for n in [1_201, 65_536] {
            var big = p; big.append(Data(count: n - p.count))
            XCTAssertThrowsError(try rx.open(big), "\(n) o") { XCTAssertEqual($0 as? CryptoError, .malformedPacket) }
        }
    }

    func testUnknownVersionAndTypeRejected() throws {
        let (tx, rx, _) = try pair()
        let p = try tx.seal(msg, type: .audio, timestampMs: 0)
        for (idx, v) in [(0, UInt8(0x00)), (0, 0x02), (1, 0x01), (1, 0x12), (1, 0xFF)] {
            var bad = p; bad[idx] = v
            XCTAssertThrowsError(try rx.open(bad)) { XCTAssertEqual($0 as? CryptoError, .malformedPacket) }
        }
    }

    func testRandomBytesFuzzNoCrash() throws {
        let (tx, rx, _) = try pair()
        var rng = SystemRandomNumberGenerator()
        for k in 0..<1_000 {
            let n = Int.random(in: 0...1_400, using: &rng)
            var d = Data((0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) })
            if k.isMultiple(of: 2), n >= 2 { d[0] = 0x01; d[1] = 0x10 } // atteint la fenêtre et AES-GCM
            XCTAssertThrowsError(try rx.open(d))
        }
        // Le récepteur fonctionne toujours.
        XCTAssertEqual(try rx.open(try tx.seal(msg, type: .audio, timestampMs: 0)).plaintext, msg)
    }
}
