import Foundation

/// Pseudonyme éphémère (M2-03) : 8 octets aléatoires (CSPRNG) encodés en base32 (13 car.).
/// Jamais persisté, jamais dérivé d'un identifiant de l'appareil.
struct Pseudonym: Hashable, Sendable {
    let value: String

    init(value: String) { self.value = value }

    /// Format attendu d'un pseudonyme reçu : exactement 13 caractères de l'alphabet base32 (A-Z, 2-7).
    static func isValid(_ value: String) -> Bool {
        value.utf8.count == 13 && value.utf8.allSatisfy { (65...90).contains($0) || (50...55).contains($0) }
    }

    static func random() -> Pseudonym {
        var rng = SystemRandomNumberGenerator()
        let bytes = (0..<8).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        return Pseudonym(value: Base32.encode(bytes))
    }

    /// Alias lisible, dérivé localement du pseudonyme (ex. « Renard-4F2 »).
    var alias: String {
        let animals = ["Renard", "Loutre", "Hibou", "Lynx", "Castor", "Faucon", "Blaireau", "Héron",
                       "Lièvre", "Martre", "Chouette", "Cerf", "Bouquetin", "Marmotte", "Écureuil", "Mésange"]
        let index = value.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % animals.count
        return "\(animals[index])-\(value.suffix(3))"
    }
}

enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encode(_ bytes: [UInt8]) -> String {
        var out = "", buffer = 0, bits = 0
        for b in bytes {
            buffer = (buffer << 8) | Int(b); bits += 8
            while bits >= 5 {
                out.append(alphabet[(buffer >> (bits - 5)) & 31]); bits -= 5
            }
        }
        if bits > 0 { out.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return out
    }
}
