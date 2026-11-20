import CryptoKit
import Foundation

/// Rôle dans la poignée de main M2-05 : initiateur = appelant (I), répondeur = appelé (R).
enum HandshakeRole: Equatable {
    case initiator
    case responder
}

/// Primitives de poignée de main M2-05 (engagement, transcript). Pas de machine à états
/// ni de format de message réseau ici (M3-05).
enum Handshake {
    /// Nonce de poignée de main de 16 o, tiré du CSPRNG système (M2-05).
    static func randomNonce() -> Data {
        var rng = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: CryptoConstants.handshakeNonceByteCount)
        for i in bytes.indices { bytes[i] = rng.next() }
        return Data(bytes)
    }

    /// C = SHA256(pkI ‖ nonceI).
    static func commitment(publicKeyX963: Data, nonce: Data) throws -> Data {
        guard publicKeyX963.count == CryptoConstants.publicKeyByteCount else { throw CryptoError.invalidPublicKey }
        guard nonce.count == CryptoConstants.handshakeNonceByteCount else { throw CryptoError.invalidHandshakeNonce }
        return Data(SHA256.hash(data: publicKeyX963 + nonce))
    }

    /// Côté R : vérifie SHA256(pkI ‖ nonceI) == C (comparaison à temps constant), sinon ABANDON.
    static func verifyCommitment(_ commitment: Data, publicKeyX963: Data, nonce: Data) throws {
        let expected = try Self.commitment(publicKeyX963: publicKeyX963, nonce: nonce)
        guard commitment.count == expected.count, constantTimeEquals(commitment, expected) else {
            throw CryptoError.commitmentMismatch
        }
    }

    /// T = SHA256("proxcall/v1" ‖ C ‖ pkR ‖ nonceR ‖ pkI ‖ nonceI). Champs à longueurs fixes.
    static func transcript(commitment: Data,
                           responderPublicKeyX963: Data, responderNonce: Data,
                           initiatorPublicKeyX963: Data, initiatorNonce: Data) throws -> Data {
        guard commitment.count == SHA256.byteCount else { throw CryptoError.commitmentMismatch }
        for pk in [responderPublicKeyX963, initiatorPublicKeyX963] where pk.count != CryptoConstants.publicKeyByteCount {
            throw CryptoError.invalidPublicKey
        }
        for n in [responderNonce, initiatorNonce] where n.count != CryptoConstants.handshakeNonceByteCount {
            throw CryptoError.invalidHandshakeNonce
        }
        var input = CryptoConstants.transcriptLabel
        input += commitment
        input += responderPublicKeyX963
        input += responderNonce
        input += initiatorPublicKeyX963
        input += initiatorNonce
        return Data(SHA256.hash(data: input))
    }

    static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }
}
