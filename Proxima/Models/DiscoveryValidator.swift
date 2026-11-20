import Foundation

/// Validation des annonces reçues (entrée réseau NON fiable, M2-03 / STRIDE D2).
/// Rejet immédiat, sans opération coûteuse ni log.
enum DiscoveryValidator {
    /// Version de protocole attendue dans `discoveryInfo["v"]`.
    static let protocolVersion = "1"
    /// Bornes sur `discoveryInfo` : au plus 4 clés, 64 octets UTF-8 au total (clés + valeurs).
    static let maxInfoKeys = 4
    static let maxInfoBytes = 64

    /// Retourne le pair si l'annonce est valide, `nil` sinon (annonce ignorée).
    /// - Clés inconnues : ignorées (compatibilité ascendante), dans la limite des bornes de taille.
    /// - Son propre pseudonyme : ignoré.
    static func peer(displayName: String, info: [String: String]?, local: Pseudonym?) -> NearbyPeer? {
        guard let info, isValidInfo(info), Pseudonym.isValid(displayName) else { return nil }
        if let local, local.value == displayName { return nil }
        return NearbyPeer(pseudonym: Pseudonym(value: displayName))
    }

    static func isValidInfo(_ info: [String: String]) -> Bool {
        guard info.count <= maxInfoKeys else { return false }
        let size = info.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
        guard size <= maxInfoBytes else { return false }
        return info["v"] == protocolVersion
    }
}
