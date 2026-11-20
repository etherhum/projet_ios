# M2-09 · Codec audio et dépendances

Règle du sujet : toute dépendance externe doit être **vérifiée** (existence, mainteneur, version) ; on préfère les API Apple.

## Dépendances : **aucune**

| Besoin | API Apple retenue | Dépendance externe |
|---|---|---|
| Transport | `MultipeerConnectivity` (M2-01) | Non |
| Cryptographie | `CryptoKit` (M2-05) | Non |
| Authentification locale | `LocalAuthentication` (M2-08) | Non |
| Capture et lecture audio | `AVFoundation` / `AVAudioEngine`, `AVAudioSession` | Non |
| Compression audio | `AudioToolbox` / `AVAudioConverter` (voir ci-dessous) | Non |
| Scan QR (optionnel) | `AVFoundation` (`AVCaptureMetadataOutput`) | Non |
| Interface | `SwiftUI` | Non |
| Journalisation | `os.Logger` | Non |

**Aucune dépendance Swift Package / CocoaPods / Carthage.** Cela supprime le risque de dépendance fantôme ou compromise (menace A7). Toute proposition d'ajout passe par une issue, avec : nom exact, dépôt officiel, mainteneur, version épinglée, licence, date de dernière publication, et revue de l'architecte sécurité.

## Choix du codec

Contraintes : voix, faible latence (≤ 100 ms de bout en bout), faible débit (le flux doit tenir dans les paquets de M2-07 : ~ 40–60 octets par trame de 20 ms), disponible nativement.

| Option | Native Apple | Débit voix | Remarque |
|---|---|---|---|
| **Opus** via `AudioToolbox` (`kAudioFormatOpus`) | Oui (encodage/décodage) | 16–24 kbit/s en 16 kHz mono | Conçu pour la voix et la perte de paquets. **Préféré**, à confirmer par prototype (M2-02) |
| AAC-ELD (`kAudioFormatMPEG4AAC_ELD`) | Oui | 24–32 kbit/s | Faible latence, repli prévu si Opus n'est pas utilisable dans nos conditions |
| PCM 16 bits non compressé | Oui | 256 kbit/s à 16 kHz | Possible sur AWDL (Mbit/s), mais 10× plus gros ; repli de dernier recours |
| libopus embarqué / WebRTC | Non | | **Rejeté** : dépendance externe lourde |

Paramètres cibles : 16 kHz, mono, trames de 20 ms (320 échantillons), débit constant ≈ 20 kbit/s. Une trame compressée = un paquet M2-07 (ou plusieurs si besoin, jamais de fragmentation d'une trame).

**Point à vérifier en prototype avant de figer** (cf. M2-02) : l'encodeur Opus d'`AudioToolbox` est utilisable sur l'iPhone de l'équipe avec les paramètres ci-dessus et sans latence excessive. Si ce n'est pas le cas, basculer sur AAC-ELD (même format de paquet ; le codec est fixé par la version du protocole, sans négociation).

## Sécurité du décodage

- Le décodeur traite des données **issues du réseau** : il n'est appelé qu'**après** authentification AES-GCM (M2-07), donc jamais sur des données non authentifiées (réduit fortement le risque E2).
- Taille maximale de trame vérifiée avant décodage.
- Une erreur de décodage compte comme un paquet invalide (échec en sécurité).

## Vérification périodique

À chaque PR : `Package.resolved` / `Podfile` absents ou inchangés ; la revue vérifie qu'aucun import hors frameworks Apple n'a été ajouté.
