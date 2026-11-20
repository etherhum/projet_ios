import Foundation

/// Messages de poignée de main M2-05, au format M2-07 :
/// `version (1 o) ‖ type (0x01 COMMIT / 0x02 HELLO / 0x03 REVEAL) ‖ champs à longueurs fixes`.
/// Ils précèdent la clé de session et ne passent pas par le format AEAD ; ils sont protégés
/// par l'engagement et le transcript. Entrée réseau NON fiable : longueur exacte exigée.
enum HandshakeMessage: Equatable {
    /// 1. I → R : { v, C } — C = SHA256(pkI ‖ nonceI), 32 o. Transporté dans le contexte de l'invitation Multipeer.
    case commit(commitment: Data)
    /// 2. R → I : { v, pkR (65 o), nonceR (16 o) }.
    case hello(publicKey: Data, nonce: Data)
    /// 3. I → R : { v, pkI (65 o), nonceI (16 o) }.
    case reveal(publicKey: Data, nonce: Data)

    static let version: UInt8 = 0x01
    static let commitType: UInt8 = 0x01
    static let helloType: UInt8 = 0x02
    static let revealType: UInt8 = 0x03

    static let commitByteCount = 2 + 32
    static let keyNonceByteCount = 2 + CryptoConstants.publicKeyByteCount + CryptoConstants.handshakeNonceByteCount // 83
    static let maxByteCount = keyNonceByteCount

    /// Le 2ᵉ octet distingue poignée de main (0x01–0x03) et paquets AEAD (0x10/0x11, M2-07).
    static func isHandshakeType(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let t = data[data.startIndex + 1]
        return t >= commitType && t <= revealType
    }

    var bytes: Data {
        switch self {
        case .commit(let c): return Data([Self.version, Self.commitType]) + c
        case .hello(let pk, let n): return Data([Self.version, Self.helloType]) + pk + n
        case .reveal(let pk, let n): return Data([Self.version, Self.revealType]) + pk + n
        }
    }

    /// Décodage strict : taille bornée, version, type connu, longueur exacte par type. Sinon `nil`.
    static func decode(_ data: Data) -> HandshakeMessage? {
        guard data.count >= 2, data.count <= maxByteCount else { return nil }
        let d = Data(data) // indices à 0
        guard d[0] == version else { return nil }
        let pkEnd = 2 + CryptoConstants.publicKeyByteCount
        switch d[1] {
        case commitType:
            guard d.count == commitByteCount else { return nil }
            return .commit(commitment: d.subdata(in: 2..<d.count))
        case helloType, revealType:
            guard d.count == keyNonceByteCount else { return nil }
            let pk = d.subdata(in: 2..<pkEnd), n = d.subdata(in: pkEnd..<d.count)
            return d[1] == helloType ? .hello(publicKey: pk, nonce: n) : .reveal(publicKey: pk, nonce: n)
        default:
            return nil
        }
    }
}
