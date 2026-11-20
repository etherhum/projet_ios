# M2-01 · Choix du transport pair-à-pair

## Besoin

- Découvrir les iPhones proches et passer un appel audio entre eux.
- **Fonctionner sans Wi-Fi commun** (ni box, ni Internet).
- Ne diffuser aucun identifiant stable dans les annonces (anonymat, cf. M2-03).
- Compatible avec un compte Apple **gratuit**.

## Comparatif

| Critère | Multipeer Connectivity | CoreBluetooth (BLE seul) | Network framework |
|---|---|---|---|
| Compte gratuit | Oui | Oui | Oui |
| Sans Wi-Fi commun | Oui : Wi-Fi pair-à-pair (AWDL) + Bluetooth, gérés par iOS | Oui | Uniquement avec `includePeerToPeer` (AWDL), API plus bas niveau |
| Portée typique | ~10–30 m (selon obstacles) | ~10–30 m | ~10–30 m en AWDL |
| Débit utile | Plusieurs Mbit/s en AWDL, largement suffisant pour l'audio | Quelques dizaines de ko/s ; latence élevée, audio dégradé | Plusieurs Mbit/s |
| Effort de développement | Faible : découverte, invitation, session et flux fournis | Élevé : fragmentation, file d'envoi, reconnexions à coder | Moyen : découverte Bonjour + gestion des connexions à coder |
| Contenu des annonces | `displayName` + `discoveryInfo` choisis par l'app | Contenu de l'annonce choisi par l'app | Nom de service Bonjour choisi par l'app |
| Puissance du signal (RSSI) | Non exposée | Exposée | Non exposée |
| Permissions iOS | Réseau local | Bluetooth | Réseau local |
| Chiffrement intégré | Option `.required` (TLS/DTLS) | Appairage BLE optionnel | TLS possible |

## Choix : Multipeer Connectivity seul

Justification :

1. **Sans Wi-Fi commun** : iOS établit lui-même le lien direct (AWDL, comme AirDrop) ; il suffit que Wi-Fi et Bluetooth soient activés.
2. **Débit audio** : suffisant pour un flux voix compressé (cf. M2-09), contrairement au BLE seul.
3. **Anonymat** : l'app maîtrise `MCPeerID.displayName` et `discoveryInfo`. On y met un pseudonyme aléatoire régénéré à chaque session, et on ne réutilise jamais un `MCPeerID` entre deux sessions.
4. **Moindre privilège** : seule la permission « réseau local » est requise ; pas de permission Bluetooth.
5. **Simplicité** : moins de code réseau à écrire, donc moins de surface d'erreur.

BLE est écarté : seul, il n'a pas le débit nécessaire ; en complément, il n'apporterait que le RSSI pour estimer une distance, au prix d'une permission supplémentaire (cf. M2-04).

## Points de vigilance (sécurité)

- **Le transport n'est pas de confiance.** Le chiffrement `.required` de Multipeer est activé mais ne remplace pas notre chiffrement de bout en bout applicatif (CryptoKit, cf. M2-05 / M3-04) : pas d'authentification du pair au niveau Multipeer.
- `displayName` est visible par tout appareil à portée : jamais de nom d'appareil, de prénom ou d'identifiant fixe.
- Invitations entrantes : n'importe qui à portée peut en envoyer → limitation de débit et blocage (M3-09).
- Clés `Info.plist` requises : `NSLocalNetworkUsageDescription` et `NSBonjourServices` (`_<service>._tcp`, `_<service>._udp`).
