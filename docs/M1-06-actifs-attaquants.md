# M1-06 · Actifs et attaquants

## Actifs à protéger

| ID | Actif | Pourquoi il compte | Protection visée |
|---|---|---|---|
| A1 | **Contenu audio** de l'appel | Conversation privée | Confidentialité, intégrité |
| A2 | **Clés de session** (privées éphémères, AES) | Donnent accès à A1 | Mémoire seulement, jamais persistées, effacées en fin de session |
| A3 | **Identité éphémère** (pseudonyme) | Ne doit pas relier une personne à son appareil ni deux sessions entre elles | Non-traçabilité |
| A4 | **Position approximative** (présence à portée radio) | Révèle qu'une personne est à tel endroit | Minimisation : jamais de GPS, pas d'estimation précise |
| A5 | **Métadonnées** : qui appelle qui, quand, combien de temps | Sensibles même sans contenu | Aucune persistance ; non visibles au-delà des deux pairs |
| A6 | **Disponibilité** de l'appel et du micro | Un appel non sollicité ou un micro ouvert à l'insu de l'utilisateur est une atteinte | Acceptation explicite (Face ID), spam limité |
| A7 | **Intégrité de l'app** et de ses dépendances | Une dépendance piégée compromet tout le reste | Pas de dépendance externe (M2-09) |

## Profils d'attaquants

| ID | Attaquant | Capacités | Hors capacité |
|---|---|---|---|
| T1 | **Curieux sur le Wi-Fi / à portée radio** (passif) | Capture le trafic Multipeer/AWDL et les annonces Bonjour ; observe les pseudonymes | Casser AES-GCM / P-256 |
| T2 | **Utilisateur malveillant à proximité** (actif) | Lance l'app modifiée ou un outil maison ; envoie des invitations en masse, usurpe un pseudonyme, rejoue ou modifie des paquets, fait de l'homme du milieu au moment de l'appairage | Voir l'écran de la victime ; deviner un code de vérification qui n'est pas comparé |
| T3 | **Groupe red team** (insider, boîte grise) | Connaît l'architecture, le code et la spécification ; audite et attaque l'app | Modifier le code de l'autre groupe en production |
| T4 | **Personne ayant accès physique à l'iPhone déverrouillé / verrouillé** | Voit l'aperçu multitâche, lit la mémoire de l'appareil s'il est jailbreaké ; essaie de répondre à un appel | Contourner Face ID / code (hors périmètre) |

## Hors périmètre de la défense

- Appareil compromis (jailbreak, malware) : on réduit la surface (rien de persistant) mais on ne promet rien.
- Attaque sur iOS ou le matériel (Secure Enclave, radio) elle-même.
- Analyse de trafic fine (présence d'une émission radio, durée d'un flux) : acceptée et documentée.
- Adversaire étatique et attaque par canal auxiliaire.

## Matrice attaquant × actif (principales cibles)

| | A1 | A2 | A3 | A4 | A5 | A6 |
|---|---|---|---|---|---|---|
| T1 | ● | | ● | ● | ● | |
| T2 | ● | ● | ● | | ● | ● |
| T3 | ● | ● | ● | ● | ● | ● |
| T4 | | ● | | | ● | ● |
