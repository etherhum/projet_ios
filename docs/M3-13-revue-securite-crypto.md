# M3-13 · Revue de sécurité du code crypto (architecte sécurité)

Périmètre : PR #59 (M3-04), #60 (M3-05), #61 (M3-06), #62 (M3-08), #66 (M3-07), #67 (M3-10), sur `main` au commit `ec585c7`. Référence : M2-05 à M2-08, STRIDE (M1-07).
Méthode : lecture complète de `Proxima/Crypto/*` et de `Proxima/Session/CallSession.swift`, `scripts/check-forbidden-apis.sh`, recherche de dépendances et d'API sensibles.
Limites : les tests unitaires n'ont **pas** été exécutés par l'architecte (Xcode non installé sur son poste) ; les conclusions viennent de la lecture du code.

## Conformité à la spécification

| Exigence | Verdict | Constat |
|---|---|---|
| Suite unique P-256 / HKDF-SHA256 / AES-256-GCM, CryptoKit seul (M2-05) | Conforme | Aucun import crypto hors CryptoKit ; aucune dépendance externe (pas de `Package.resolved`, `Podfile`) |
| Clés éphémères, effacées après dérivation | Conforme | `EphemeralKeyPair.deriveSessionKeys` consomme la clé (`defer destroy`) ; limite connue : CryptoKit n'efface pas la mémoire, on supprime la référence |
| Validation de clé publique (65 o, `0x04`, point valide) | Conforme | `PeerPublicKey.init` |
| Engagement avant révélation, comparaison à temps constant | Conforme | `Handshake.verifyCommitment`, côté appelé avant toute dérivation |
| Transcript dans le sel HKDF, info distinctes par usage et direction | Conforme | `SessionKeys.init` |
| Nonce = compteur 64 bits, clés distinctes par direction, jamais réutilisé | Conforme | `PacketCrypter.seal` : compteur incrémenté même si l'envoi échoue ensuite |
| En-tête en AAD, taille/version/type contrôlés avant déchiffrement | Conforme | `PacketHeader.parse`, `open` |
| Fenêtre anti-rejeu 64, saut max 1 000, fraîcheur 2 s, fenêtre non avancée sur paquet falsifié | Conforme | `ReplayWindow.check/accept` appelés avant/après `AES.GCM.open` |
| Audio refusé avant confirmation des deux codes ; micro non capturé | Conforme (côté session) | `canExchangeAudio` n'est vrai qu'en `.active` ; `SAS_OK` unique, doublon ⇒ fermeture |
| Échec en sécurité : >20 rejets/5 s, tag invalide en vérification, 1 h max, délais 30 s | Conforme | `CallSession.registerRejection`, délais et `teardown()` |
| Logs sans secret (M3-12) | Conforme | `check-forbidden-apis.sh` : aucune occurrence |
| **Face ID à l'ouverture et à l'acceptation d'un appel (M2-08, STRIDE E1)** | **NON CONFORME** | Aucun usage de `LocalAuthentication`/`LAContext` dans le code ni de `NSFaceIDUsageDescription`. `AppState.acceptIncomingCall()` accepte sans authentification. Issue ouverte |

## Constats

| ID | Gravité | Constat | Recommandation |
|---|---|---|---|
| F1 | **Élevée** | Face ID absent (voir ci-dessus) : un iPhone déverrouillé laissé à un tiers permet d'accepter un appel et d'ouvrir le micro | Implémenter `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` à l'ouverture et avant `call.accept()` ; refus par défaut en cas d'échec ; ajouter `NSFaceIDUsageDescription` |
| F2 | Faible | Mode QR : l'appelé (R) valide en scannant l'engagement C, mais C ne lie que la clé de l'appelant. L'authentification de R auprès de I repose uniquement sur la comparaison du code à 6 chiffres | Vérifier dans l'UI que l'appelant doit toujours confirmer « codes identiques » même en mode QR (le bouton de confirmation existe dans `CallView` ; garder ce comportement et le tester) |
| F3 | Information | Code SAS : `UInt24 mod 10⁶` introduit un biais négligeable (valeurs 0–777 215 légèrement plus probables) | Aucune action |
| F4 | Information | Aucune vérification `pkR ≠ pkI` (réflexion) | Sans effet : les clés sont directionnelles et les codes différeraient ; non nécessaire |
| F5 | Information | Mémoire : les `SymmetricKey` ne sont pas effaçables explicitement | Limite CryptoKit déjà documentée ; acceptée |
| F6 | À faire | Tests non exécutés par l'architecte | Exécuter la suite `ProximaTests` sur simulateur/iPhone avant la démo et joindre le résultat |

## Suivi

- F1 : issue dédiée (rôle développeur iOS, revue par l'architecte).
- F2 et F6 : à reprendre en M3-14 (attaque interne) et M5-04 (dossier final).
- Les revues futures de MR crypto suivront cette liste : primitives CryptoKit uniquement, nonce/compteur, validation d'entrées, effacement des clés, échec en sécurité, logs, tests.
