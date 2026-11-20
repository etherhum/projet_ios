import Foundation

/// Erreurs du module crypto. Volontairement peu détaillées (pas d'oracle, M2-07)
/// et sans aucun contenu secret.
enum CryptoError: Error, Equatable {
    /// Clé publique reçue de longueur incorrecte ou point invalide (M2-05).
    case invalidPublicKey
    /// Engagement COMMIT ne correspondant pas au REVEAL (M2-05) : abandon.
    case commitmentMismatch
    /// Nonce de poignée de main de longueur incorrecte.
    case invalidHandshakeNonce
    /// Objet (clé éphémère ou clés de session) déjà détruit ou consommé.
    case keyDestroyed
    /// Compteur d'émission épuisé : la session doit être fermée (M2-07).
    case counterExhausted
    /// Paquet hors bornes de taille, version ou type inconnus (M2-07, règles 1-2).
    case malformedPacket
    /// Texte clair trop grand pour tenir dans un paquet de 1 200 octets.
    case plaintextTooLarge
    /// Échec d'authentification AES-GCM (tag, AAD, nonce, clé).
    case authenticationFailed
    /// Message CONTROL au code inconnu (M2-07).
    case invalidControlCode
}
