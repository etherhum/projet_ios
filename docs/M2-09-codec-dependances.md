# M2-09 · Codec audio et dépendances

## Codec

| Élément | Choix | Justification |
|---|---|---|
| Capture / lecture | `AVAudioEngine` (input node + player node) | API native, faible latence |
| Session audio | `AVAudioSession` catégorie `.playAndRecord`, mode `.voiceChat` | Annulation d'écho et contrôle de gain intégrés à iOS |
| Format de capture | PCM mono 16 kHz | Suffisant pour la voix |
| Compression | **Opus** natif Apple (`kAudioFormatOpus`) via `AVAudioConverter`, trames de 20 ms, ~24 kbit/s | Codec voix moderne, supporté nativement depuis iOS 11, aucune bibliothèque externe |
| Repli | AAC-ELD (`kAudioFormatMPEG4AAC_ELD`) | Natif aussi ; utilisé si l'encodeur Opus pose problème sur un appareil |

Chaque trame compressée (~60 octets) est ensuite chiffrée (AES-GCM, cf. M3-04) et envoyée dans un paquet au format M2-07.

Débit total estimé : ~50 paquets/s × ~100 octets ≈ 5 ko/s, très en dessous des capacités de Multipeer.

## Dépendances

**Aucune dépendance externe.**

Frameworks Apple utilisés : SwiftUI, MultipeerConnectivity, AVFoundation, CryptoKit, os (Logger).

Toute dépendance future devra être justifiée dans ce document (existence, mainteneur, version figée, licence) avant toute PR.
