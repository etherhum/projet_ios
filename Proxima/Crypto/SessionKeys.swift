import CryptoKit
import Foundation

/// Clés de session dérivées par HKDF-SHA256 (M2-05) :
/// `salt = T`, IKM = secret ECDH, `info` distincte par usage.
/// k_IR (I→R), k_RI (R→I), sas (3 o). Destructibles : après `destroy()`, toute utilisation
/// lève `keyDestroyed`.
final class SessionKeys {
    let role: HandshakeRole
    private var sendKey: SymmetricKey?
    private var receiveKey: SymmetricKey?
    private var sasValue: UInt32?

    init(role: HandshakeRole, sharedSecret: SharedSecret, transcript: Data) {
        self.role = role
        func expand(_ info: Data, _ count: Int) -> SymmetricKey {
            sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: transcript,
                                                 sharedInfo: info, outputByteCount: count)
        }
        let kIR = expand(CryptoConstants.infoKeyInitiatorToResponder, CryptoConstants.sessionKeyByteCount)
        let kRI = expand(CryptoConstants.infoKeyResponderToInitiator, CryptoConstants.sessionKeyByteCount)
        let sas = expand(CryptoConstants.infoSAS, CryptoConstants.sasByteCount)
        switch role {
        case .initiator: sendKey = kIR; receiveKey = kRI
        case .responder: sendKey = kRI; receiveKey = kIR
        }
        sasValue = sas.withUnsafeBytes { b in
            (UInt32(b[0]) << 16 | UInt32(b[1]) << 8 | UInt32(b[2])) % 1_000_000
        }
    }

    var isDestroyed: Bool { sendKey == nil && receiveKey == nil && sasValue == nil }

    /// Oublie les clés et le code (fin d'appel, erreur, M3-10). Seules références : ces trois
    /// propriétés (le secret ECDH et le transcript ne sont pas conservés : ils ne vivent que
    /// pendant `init`, la fonction locale `expand` n'est pas stockée).
    func destroy() {
        sendKey = nil
        receiveKey = nil
        sasValue = nil
    }

    /// Code de vérification à 6 chiffres (M2-06) : UInt24 grand-boutiste mod 10⁶, ex. « 482 915 ».
    func verificationCode() throws -> String {
        guard let v = sasValue else { throw CryptoError.keyDestroyed }
        let s = String(format: "%06u", v)
        return "\(s.prefix(3)) \(s.suffix(3))"
    }

    func currentSendKey() throws -> SymmetricKey {
        guard let k = sendKey else { throw CryptoError.keyDestroyed }
        return k
    }

    func currentReceiveKey() throws -> SymmetricKey {
        guard let k = receiveKey else { throw CryptoError.keyDestroyed }
        return k
    }
}
