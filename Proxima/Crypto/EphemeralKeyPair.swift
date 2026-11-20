import CryptoKit
import Foundation

/// Clé publique P-256 reçue du pair, validée (M2-05).
struct PeerPublicKey: Equatable {
    let key: P256.KeyAgreement.PublicKey
    /// Représentation X9.63 (65 o), utilisée dans l'engagement et le transcript.
    let x963: Data

    /// Longueur exacte 65 o puis validation du point par CryptoKit, sinon `invalidPublicKey`.
    init(x963Representation data: Data) throws {
        guard data.count == CryptoConstants.publicKeyByteCount, data.first == 0x04 else {
            throw CryptoError.invalidPublicKey
        }
        do {
            key = try P256.KeyAgreement.PublicKey(x963Representation: data)
        } catch {
            throw CryptoError.invalidPublicKey
        }
        x963 = Data(data)
    }

    static func == (a: PeerPublicKey, b: PeerPublicKey) -> Bool { a.x963 == b.x963 }
}

/// Couple de clés ECDH P-256 **éphémère** : un neuf par appel (M2-05).
/// La clé privée ne sort jamais de l'objet ; elle est oubliée après `deriveSessionKeys`
/// ou `destroy()`. Toute utilisation ultérieure lève `keyDestroyed`.
final class EphemeralKeyPair {
    private var privateKey: P256.KeyAgreement.PrivateKey?
    /// Clé publique X9.63 (65 o) à envoyer au pair.
    let publicKeyX963: Data

    init() {
        let key = P256.KeyAgreement.PrivateKey()
        privateKey = key
        publicKeyX963 = key.publicKey.x963Representation
    }

    var isDestroyed: Bool { privateKey == nil }

    /// Oublie la clé privée. CryptoKit ne permet pas d'effacer explicitement sa mémoire :
    /// on supprime la seule référence (la zone est libérée par CryptoKit).
    func destroy() { privateKey = nil }

    /// ECDH puis HKDF (M2-05). Consomme la clé privée : appelable une seule fois.
    func deriveSessionKeys(role: HandshakeRole,
                           peerPublicKey: PeerPublicKey,
                           transcript: Data) throws -> SessionKeys {
        guard let key = privateKey else { throw CryptoError.keyDestroyed }
        defer { destroy() }
        let secret: SharedSecret
        do {
            secret = try key.sharedSecretFromKeyAgreement(with: peerPublicKey.key)
        } catch {
            throw CryptoError.invalidPublicKey
        }
        return SessionKeys(role: role, sharedSecret: secret, transcript: transcript)
        // `secret` sort de portée ici : plus aucune référence au secret ECDH.
    }
}
