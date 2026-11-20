import CryptoKit
import XCTest
@testable import Proxima

/// Tests M3-04 : module crypto (M2-05, M2-06, M2-07).
final class CryptoTests: XCTestCase {

    /// Poignée de main complète M2-05 entre I et R, sans réseau.
    private func handshake() throws -> (i: SessionKeys, r: SessionKeys) {
        let kpI = EphemeralKeyPair(), nI = Handshake.randomNonce()
        let c = try Handshake.commitment(publicKeyX963: kpI.publicKeyX963, nonce: nI)
        let kpR = EphemeralKeyPair(), nR = Handshake.randomNonce()
        try Handshake.verifyCommitment(c, publicKeyX963: kpI.publicKeyX963, nonce: nI)
        let t = try Handshake.transcript(commitment: c, responderPublicKeyX963: kpR.publicKeyX963, responderNonce: nR,
                                         initiatorPublicKeyX963: kpI.publicKeyX963, initiatorNonce: nI)
        let i = try kpI.deriveSessionKeys(role: .initiator, peerPublicKey: PeerPublicKey(x963Representation: kpR.publicKeyX963), transcript: t)
        let r = try kpR.deriveSessionKeys(role: .responder, peerPublicKey: PeerPublicKey(x963Representation: kpI.publicKeyX963), transcript: t)
        return (i, r)
    }

    private func raw(_ k: SymmetricKey) -> Data { k.withUnsafeBytes { Data($0) } }
    private let msg = Data("trame audio de test".utf8)

    // MARK: Accord de clés

    func testBothPeersDeriveSameDirectionalKeysAndSAS() throws {
        let (i, r) = try handshake()
        XCTAssertEqual(raw(try i.currentSendKey()), raw(try r.currentReceiveKey()))
        XCTAssertEqual(raw(try r.currentSendKey()), raw(try i.currentReceiveKey()))
        XCTAssertNotEqual(raw(try i.currentSendKey()), raw(try i.currentReceiveKey()))
        XCTAssertEqual(raw(try i.currentSendKey()).count, 32)
        XCTAssertEqual(try i.verificationCode(), try r.verificationCode())
        XCTAssertNotNil(try i.verificationCode().range(of: "^[0-9]{3} [0-9]{3}$", options: .regularExpression))
    }

    func testTwoSessionsHaveDifferentKeys() throws {
        let a = try handshake(), b = try handshake()
        XCTAssertNotEqual(raw(try a.i.currentSendKey()), raw(try b.i.currentSendKey()))
        XCTAssertNotEqual(raw(try a.i.currentReceiveKey()), raw(try b.i.currentReceiveKey()))
    }

    func testEphemeralKeysAreFreshAndConsumed() throws {
        let a = EphemeralKeyPair(), b = EphemeralKeyPair()
        XCTAssertNotEqual(a.publicKeyX963, b.publicKeyX963)
        XCTAssertEqual(a.publicKeyX963.count, 65)
        _ = try a.deriveSessionKeys(role: .initiator, peerPublicKey: PeerPublicKey(x963Representation: b.publicKeyX963), transcript: Data(count: 32))
        XCTAssertTrue(a.isDestroyed)
        XCTAssertThrowsError(try a.deriveSessionKeys(role: .initiator, peerPublicKey: PeerPublicKey(x963Representation: b.publicKeyX963), transcript: Data(count: 32))) {
            XCTAssertEqual($0 as? CryptoError, .keyDestroyed)
        }
    }

    func testInvalidPublicKeysRejected() {
        let valid = EphemeralKeyPair().publicKeyX963
        var offCurve = valid; offCurve[64] ^= 0x01
        var badPrefix = valid; badPrefix[0] = 0x02
        let compressed = P256.KeyAgreement.PrivateKey().publicKey.compressedRepresentation
        for bad in [Data(), valid.prefix(64), valid + Data([0]), offCurve, badPrefix, Data(count: 65), compressed] {
            XCTAssertThrowsError(try PeerPublicKey(x963Representation: bad)) {
                XCTAssertEqual($0 as? CryptoError, .invalidPublicKey)
            }
        }
        XCTAssertNoThrow(try PeerPublicKey(x963Representation: valid))
    }

    func testCommitmentMismatchAborts() throws {
        let kp = EphemeralKeyPair(), n = Handshake.randomNonce()
        let c = try Handshake.commitment(publicKeyX963: kp.publicKeyX963, nonce: n)
        XCTAssertThrowsError(try Handshake.verifyCommitment(c, publicKeyX963: EphemeralKeyPair().publicKeyX963, nonce: n)) {
            XCTAssertEqual($0 as? CryptoError, .commitmentMismatch)
        }
        XCTAssertThrowsError(try Handshake.verifyCommitment(c, publicKeyX963: kp.publicKeyX963, nonce: Handshake.randomNonce()))
        XCTAssertThrowsError(try Handshake.commitment(publicKeyX963: kp.publicKeyX963, nonce: Data(count: 15))) {
            XCTAssertEqual($0 as? CryptoError, .invalidHandshakeNonce)
        }
    }

    func testTranscriptChangeChangesKeysAndSAS() throws {
        let b = EphemeralKeyPair(), pkB = try PeerPublicKey(x963Representation: b.publicKeyX963)
        let priv = P256.KeyAgreement.PrivateKey()
        let secret = try priv.sharedSecretFromKeyAgreement(with: pkB.key)
        let k1 = SessionKeys(role: .initiator, sharedSecret: secret, transcript: Data(count: 32))
        let k2 = SessionKeys(role: .initiator, sharedSecret: secret, transcript: Data(repeating: 1, count: 32))
        XCTAssertNotEqual(raw(try k1.currentSendKey()), raw(try k2.currentSendKey()))
    }

    // MARK: Paquets

    func testSealOpenRoundTripBothDirections() throws {
        let (i, r) = try handshake()
        let ci = PacketCrypter(keys: i), cr = PacketCrypter(keys: r)
        let p = try ci.seal(msg, type: .audio, timestampMs: 1234)
        XCTAssertEqual(p.count, 14 + msg.count + 16)
        let o = try cr.open(p)
        XCTAssertEqual(o.plaintext, msg)
        XCTAssertEqual(o.header, PacketHeader(type: .audio, counter: 0, timestampMs: 1234))
        let back = try cr.seal(Data([ControlCode.sasOK.rawValue]), type: .control, timestampMs: 5)
        XCTAssertEqual(try ci.open(back).plaintext, Data([0x01]))
        XCTAssertEqual(try cr.open(try ci.seal(Data([0x7F]), type: .audio, timestampMs: 0)).plaintext, Data([0x7F])) // 1 o minimum
    }

    func testTamperedPacketRejected() throws {
        let (i, r) = try handshake()
        let p = try PacketCrypter(keys: i).seal(msg, type: .audio, timestampMs: 42)
        let cr = PacketCrypter(keys: r)
        // 1 = type (AAD, reste valide 0x11 -> rejet tag), 2..9 compteur (AAD + nonce), 10..13 horodatage, chiffré, tag.
        for index in [1, 5, 9, 12, 14, 14 + msg.count - 1, p.count - 16, p.count - 1] {
            var t = p
            t[index] ^= (index == 1 ? 0x01 : 0x80)
            XCTAssertThrowsError(try cr.open(t), "octet \(index)") {
                XCTAssertEqual($0 as? CryptoError, .authenticationFailed)
            }
        }
        XCTAssertNoThrow(try cr.open(p))
    }

    func testWrongNonceRejected() throws {
        let (i, _) = try handshake()
        let key = try i.currentSendKey()
        let aad = PacketHeader(type: .audio, counter: 7, timestampMs: 0).bytes
        let box = try AES.GCM.seal(msg, using: key, nonce: AES.GCM.Nonce(data: PacketHeader.nonce(counter: 7)), authenticating: aad)
        let wrong = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: PacketHeader.nonce(counter: 8)), ciphertext: box.ciphertext, tag: box.tag)
        XCTAssertThrowsError(try AES.GCM.open(wrong, using: key, authenticating: aad))
    }

    func testWrongKeyRejected() throws {
        let (i, _) = try handshake()
        let (_, otherR) = try handshake()
        let p = try PacketCrypter(keys: i).seal(msg, type: .audio, timestampMs: 0)
        XCTAssertThrowsError(try PacketCrypter(keys: otherR).open(p)) {
            XCTAssertEqual($0 as? CryptoError, .authenticationFailed)
        }
    }

    func testReflectedPacketRejected() throws {
        let (i, _) = try handshake()
        let ci = PacketCrypter(keys: i)
        let p = try ci.seal(msg, type: .audio, timestampMs: 0)
        XCTAssertThrowsError(try ci.open(p)) { XCTAssertEqual($0 as? CryptoError, .authenticationFailed) }
    }

    func testNonceNeverRepeats() throws {
        let (i, _) = try handshake()
        let ci = PacketCrypter(keys: i)
        var counters = Set<UInt64>()
        for n in 0..<5_000 {
            let h = try PacketHeader.parse(try ci.seal(msg, type: .audio, timestampMs: 0))
            XCTAssertEqual(h.counter, UInt64(n))
            counters.insert(h.counter)
        }
        XCTAssertEqual(counters.count, 5_000)
        XCTAssertEqual(PacketHeader.nonce(counter: 0x0102030405060708),
                       Data([0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8]))
    }

    func testMalformedPacketsRejectedBeforeDecryption() throws {
        let (i, r) = try handshake()
        let p = try PacketCrypter(keys: i).seal(msg, type: .audio, timestampMs: 0)
        let cr = PacketCrypter(keys: r)
        var badVersion = p; badVersion[0] = 0x02
        var badType = p; badType[1] = 0x12
        for bad in [Data(count: 29), p.prefix(29), Data(count: 1_201), badVersion, badType] {
            XCTAssertThrowsError(try cr.open(bad)) { XCTAssertEqual($0 as? CryptoError, .malformedPacket) }
        }
        let ci = PacketCrypter(keys: i)
        XCTAssertThrowsError(try ci.seal(Data(count: 1_171), type: .audio, timestampMs: 0)) {
            XCTAssertEqual($0 as? CryptoError, .plaintextTooLarge)
        }
        XCTAssertNoThrow(try cr.open(try ci.seal(Data(count: 1_170), type: .audio, timestampMs: 0)))
        XCTAssertThrowsError(try ci.seal(Data([0x03]), type: .control, timestampMs: 0)) {
            XCTAssertEqual($0 as? CryptoError, .invalidControlCode)
        }
    }

    func testDestroyedKeysThrow() throws {
        let (i, r) = try handshake()
        let ci = PacketCrypter(keys: i), cr = PacketCrypter(keys: r)
        let p = try ci.seal(msg, type: .audio, timestampMs: 0)
        ci.destroy(); r.destroy()
        XCTAssertTrue(i.isDestroyed)
        XCTAssertThrowsError(try ci.seal(msg, type: .audio, timestampMs: 0)) { XCTAssertEqual($0 as? CryptoError, .keyDestroyed) }
        XCTAssertThrowsError(try cr.open(p)) { XCTAssertEqual($0 as? CryptoError, .keyDestroyed) }
        XCTAssertThrowsError(try r.verificationCode()) { XCTAssertEqual($0 as? CryptoError, .keyDestroyed) }
        let kp = EphemeralKeyPair(); kp.destroy()
        XCTAssertThrowsError(try kp.deriveSessionKeys(role: .responder, peerPublicKey: PeerPublicKey(x963Representation: EphemeralKeyPair().publicKeyX963), transcript: Data())) {
            XCTAssertEqual($0 as? CryptoError, .keyDestroyed)
        }
    }

    func testEmptyAudioPayloadRejected() throws {
        let (i, r) = try handshake()
        let ci = PacketCrypter(keys: i), cr = PacketCrypter(keys: r)
        XCTAssertThrowsError(try ci.seal(Data(), type: .audio, timestampMs: 0)) {
            XCTAssertEqual($0 as? CryptoError, .emptyPayload)
        }
        XCTAssertEqual(ci.nextSendCounter, 0) // aucun nonce consommé
        // Paquet AUDIO vide mais authentique (forgé avec la vraie clé) : rejeté à la réception.
        let header = PacketHeader(type: .audio, counter: 0, timestampMs: 0)
        let box = try AES.GCM.seal(Data(), using: try i.currentSendKey(),
                                   nonce: try AES.GCM.Nonce(data: PacketHeader.nonce(counter: 0)),
                                   authenticating: header.bytes)
        XCTAssertThrowsError(try cr.open(header.bytes + box.ciphertext + box.tag)) {
            XCTAssertEqual($0 as? CryptoError, .malformedPacket)
        }
        // CONTROL reste conforme à M2-07 : exactement 1 octet de code.
        XCTAssertThrowsError(try ci.seal(Data(), type: .control, timestampMs: 0)) {
            XCTAssertEqual($0 as? CryptoError, .invalidControlCode)
        }
        let ok = try cr.open(try ci.seal(Data([ControlCode.hangUp.rawValue]), type: .control, timestampMs: 0))
        XCTAssertEqual(ok.plaintext, Data([0x02]))
    }

    func testEveryOperationFailsAfterDestroy() throws {
        let (i, r) = try handshake()
        let ci = PacketCrypter(keys: i), cr = PacketCrypter(keys: r)
        let p = try ci.seal(msg, type: .audio, timestampMs: 0)
        ci.destroy(); cr.destroy()
        for keys in [i, r] {
            XCTAssertTrue(keys.isDestroyed)
            XCTAssertThrowsError(try keys.currentSendKey()) { XCTAssertEqual($0 as? CryptoError, .keyDestroyed) }
            XCTAssertThrowsError(try keys.currentReceiveKey()) { XCTAssertEqual($0 as? CryptoError, .keyDestroyed) }
            XCTAssertThrowsError(try keys.verificationCode()) { XCTAssertEqual($0 as? CryptoError, .keyDestroyed) }
        }
        XCTAssertThrowsError(try ci.seal(Data([1]), type: .control, timestampMs: 0)) { XCTAssertEqual($0 as? CryptoError, .keyDestroyed) }
        XCTAssertThrowsError(try cr.open(p)) { XCTAssertEqual($0 as? CryptoError, .keyDestroyed) }
        // Clé éphémère : consommée par la dérivation, puis plus utilisable ; l'objet est libéré.
        weak var weakPair: EphemeralKeyPair?
        try {
            let kp = EphemeralKeyPair(); weakPair = kp
            let peer = try PeerPublicKey(x963Representation: EphemeralKeyPair().publicKeyX963)
            _ = try kp.deriveSessionKeys(role: .initiator, peerPublicKey: peer, transcript: Data(count: 32))
            XCTAssertTrue(kp.isDestroyed)
            XCTAssertThrowsError(try kp.deriveSessionKeys(role: .initiator, peerPublicKey: peer, transcript: Data(count: 32))) {
                XCTAssertEqual($0 as? CryptoError, .keyDestroyed)
            }
        }()
        XCTAssertNil(weakPair, "aucune référence ne doit retenir la paire éphémère")
    }

    // MARK: Vecteur fixe (format, pas de vecteur fourni par la spec)

    func testHeaderVector() {
        let h = PacketHeader(type: .control, counter: 0x0A0B, timestampMs: 0x01020304)
        XCTAssertEqual(h.bytes, Data([0x01, 0x11, 0, 0, 0, 0, 0, 0, 0x0A, 0x0B, 1, 2, 3, 4]))
    }
}
