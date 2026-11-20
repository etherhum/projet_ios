import Foundation

/// Variante QR de M2-06 : contenu = `v ‖ C` (C = engagement SHA256(pkI ‖ nonceI) de l'étape 1, M2-05),
/// transmis hors bande par la lumière. Encodé en hexadécimal majuscule (mode alphanumérique du QR,
/// lisible par `AVMetadataMachineReadableCodeObject.stringValue`) : 1 + 32 octets → 66 caractères.
enum VerificationQR {
    static let version: UInt8 = 0x01
    static let byteCount = 1 + 32

    static func payload(commitment: Data) -> String? {
        guard commitment.count == byteCount - 1 else { return nil }
        return (Data([version]) + commitment).map { String(format: "%02X", $0) }.joined()
    }

    /// Décodage strict (longueur exacte, hexadécimal, version connue). Renvoie C, ou nil.
    static func commitment(fromPayload s: String) -> Data? {
        let chars = Array(s.utf8)
        guard chars.count == byteCount * 2 else { return nil }
        var bytes = Data(capacity: byteCount)
        var i = 0
        while i < chars.count {
            guard let hi = hexValue(chars[i]), let lo = hexValue(chars[i + 1]) else { return nil }
            bytes.append(hi << 4 | lo)
            i += 2
        }
        guard bytes.first == version else { return nil }
        return bytes.dropFirst()
    }

    private static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
        default: return nil
        }
    }
}

#if DEBUG
/// Démonstration (DEBUG uniquement, absent du binaire Release) : l'argument de lancement
/// `-ProximaFakeFingerprint` altère localement le code affiché et le QR, pour montrer qu'une
/// empreinte fausse ne passe pas (les utilisateurs voient deux codes différents → « Ne correspondent pas »).
/// Les clés et le SAS réels ne sont pas modifiés. Jamais persisté, jamais journalisé.
enum FingerprintDemo {
    static let launchArgument = "-ProximaFakeFingerprint"

    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    /// Chaque chiffre + 1 (mod 10) : le code affiché diffère toujours du code réel, à chaque position.
    static func alter(code: String) -> String {
        String(code.map { c in
            guard let d = c.wholeNumberValue else { return c }
            return Character(String((d + 1) % 10))
        })
    }

    /// Engagement altéré (premier octet inversé) : le QR affiché / attendu ne correspond plus.
    static func alter(commitment: Data) -> Data {
        var c = Data(commitment)
        if !c.isEmpty { c[0] ^= 0xFF }
        return c
    }
}
#endif
