# M3-07 · Vérification que l'audio circule chiffré sur le réseau

Objectif (critère de l'issue #26) : montrer que les paquets audio émis par Proxima sont chiffrés (AES-256-GCM, format M2-07) et qu'un paquet modifié est rejeté. Trois preuves complémentaires.

## Chaîne implémentée

Micro → `AVAudioEngine` (tap sur `inputNode`, traitement voix : annulation d'écho) → conversion 16 kHz mono → trames de 20 ms (320 échantillons) → **Opus** (`kAudioFormatOpus`, `AVAudioConverter`, ≈ 20 kbit/s, ≈ 50 o/trame) → `PacketCrypter.seal(type: AUDIO 0x10)` → `MCSession.send(… with: .unreliable)`.
Réception → `PacketCrypter.open` (taille, version, type, **tag GCM** : authentification d'abord) → taille de trame ≤ 400 o → tampon de gigue (3 trames ≈ 60 ms, réordonnancement par compteur, doublons ignorés, trou ⇒ silence) → décodage Opus → `AVAudioPlayerNode`.

Codec : Opus est disponible nativement (iOS 17+) ; repli automatique AAC-ELD puis PCM 16 bits si l'encodeur échoue à l'init (`VoiceCodecKind.resolved`, affiché dans le compteur DEBUG).

## Preuve 1 — capture réseau (rvictl + Wireshark)

Prérequis : Mac avec Xcode, iPhone branché en USB et approuvé, Wireshark ou `tcpdump`.

```sh
xcrun xctrace list devices          # relever l'UDID de l'iPhone
rvictl -s <UDID>                    # crée l'interface virtuelle rvi0
sudo tcpdump -i rvi0 -w proxima.pcap   # (ou Wireshark sur rvi0)
# … passer un appel Proxima de 30 s en parlant, raccrocher …
rvictl -x <UDID>
```

Analyse dans Wireshark :
1. Filtrer le trafic de l'appel (`udp` / `tcp` hors ports connus ; Multipeer utilise des ports dynamiques en UDP pour `.unreliable`).
2. Le flux doit montrer ≈ 50 paquets/s de petite taille constante (≈ 100 o charge utile Multipeer comprise) pendant tout l'appel, **micro coupé compris** (débit constant, voir plus bas).
3. Rechercher le motif de l'en-tête M2-07 n'est pas possible tel quel : Multipeer chiffre déjà le lien (`encryptionPreference: .required`, DTLS). On vérifie donc l'absence de toute structure Opus/PCM : `Statistics › Conversations` + export de la charge utile, puis `ent` (ou le script Python ci-dessous) ⇒ entropie ≈ 8 bits/octet.

```sh
python3 -c "import sys,math,collections;d=open(sys.argv[1],'rb').read();c=collections.Counter(d);print(-sum(v/len(d)*math.log2(v/len(d)) for v in c.values()))" payload.bin
```

**Limites** : `rvi0` ne voit que le trafic passant par la pile réseau de l'iPhone visible par le Mac. Multipeer peut utiliser **AWDL** (Wi-Fi pair à pair) ou Bluetooth ; selon iOS, ces paquets peuvent ne pas apparaître sur `rvi0`. Dans ce cas : mettre les deux iPhones sur le même Wi-Fi d'infrastructure (Multipeer passe alors par le Wi-Fi) et capturer sur `rvi0`, ou capturer l'air en mode moniteur depuis un Mac (`Diagnostic sans fil › Renifleur`, canal AWDL 6/44/149) — le trafic AWDL apparaît alors chiffré au niveau Multipeer. Dans tous les cas, la capture ne montre que le chiffrement **de transport** de Multipeer ; la preuve de notre chiffrement **applicatif** (bout en bout, indépendant de Multipeer) repose sur les preuves 2 et 3.

## Preuve 2 — tests unitaires (`ProximaTests/AudioTests.swift`)

| Test | Ce qu'il montre |
|---|---|
| `testWireStreamLooksRandomAndHidesPlaintext` | 200 trames PCM (sinus) scellées : seul l'en-tête de 14 o est en clair (type `0x10`) ; aucun fragment de 16 o du clair n'apparaît dans le paquet ; entropie du flux émis > 7,99 bits/octet contre < 7,9 pour le PCM en clair |
| `testTamperedAudioPacketRejectedAndNeverDecoded` | Deux `CallSession` actives : un octet modifié (type, compteur, chiffré, tag) ⇒ paquet rejeté, compté, **jamais remis au décodeur** ; l'appel continue |
| `testEncodeSealOpenDecodeRoundTripKeepsDuration` | Opus → seal → open → decode : même durée (à une trame d'amorçage près), signal non nul |
| `testOversizedFrameRejectedBeforeDecoding` | Trame > 400 o ou vide refusée avant décodage |

## Preuve 3 — compteur DEBUG dans l'écran d'appel

En build DEBUG, l'écran d'appel actif affiche `Envoyés N · reçus N · rejetés N · opus` (nombres uniquement, aucun contenu). Démo : les compteurs « envoyés » et « reçus » progressent d'≈ 50/s des deux côtés ; « rejetés » reste à 0 en conditions normales (il compte les tags invalides, trames surdimensionnées et erreurs de décodage).

## Micro coupé : choix

Micro coupé ⇒ on **continue d'envoyer** des trames encodées de silence. M2-09 fixe un **débit constant** ≈ 20 kbit/s : ne rien envoyer révélerait à un observateur radio (T1) les moments où l'utilisateur coupe son micro. Coût : ≈ 50 paquets/s de ≈ 80 o, négligeable.

## Données sensibles

Aucun log (contenu audio, clé, pseudonyme) ; `scripts/check-forbidden-apis.sh` sort 0. À la fin d'appel, le moteur est arrêté, l'accumulateur PCM et le tampon de gigue sont écrasés à zéro puis vidés, encodeur/décodeur libérés ; les clés sont détruites par `CallSession`.
