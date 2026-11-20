import Foundation

/// Paramètres de la suite unique v1 (M2-05, M2-07, M2-10 §3). Pas de négociation.
enum CryptoConstants {
    /// Préfixe du transcript T (M2-05).
    static let transcriptLabel = Data("proxcall/v1".utf8)
    /// `info` HKDF (M2-05).
    static let infoKeyInitiatorToResponder = Data("proxcall/v1/key I→R".utf8)
    static let infoKeyResponderToInitiator = Data("proxcall/v1/key R→I".utf8)
    static let infoSAS = Data("proxcall/v1/sas".utf8)

    /// Clé AES-256 (32 o) et SAS (3 o) (M2-05).
    static let sessionKeyByteCount = 32
    static let sasByteCount = 3
    /// Clé publique X9.63 non compressée : 65 o (M2-05).
    static let publicKeyByteCount = 65
    /// nonceI / nonceR de poignée de main : 16 o (M2-05).
    static let handshakeNonceByteCount = 16

    /// Format de paquet (M2-07).
    static let packetVersion: UInt8 = 0x01
    static let headerByteCount = 14
    static let tagByteCount = 16
    static let minPacketByteCount = 30
    static let maxPacketByteCount = 1_200
    static var maxPlaintextByteCount: Int { maxPacketByteCount - headerByteCount - tagByteCount }

    /// Borne pratique du compteur (M2-07 : « limite pratique 2³² paquets »).
    /// L'émetteur refuse de chiffrer au-delà ; la durée max de session (1 h) relève de M3-10.
    static let maxPacketCounter: UInt64 = 1 << 32
}
