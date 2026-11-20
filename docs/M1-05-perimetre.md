# M1-05 · Périmètre fonctionnel (MVP vs hors périmètre)

App iOS d'appel vocal **de proximité, anonyme et chiffré de bout en bout**, entre deux iPhones proches, sans compte, sans serveur, sans Wi-Fi commun (transport : Multipeer Connectivity, cf. M2-01).

## Dans le MVP

| # | Fonction | Exigence de sécurité associée |
|---|---|---|
| 1 | **Découverte** des utilisateurs proches sous un pseudonyme éphémère | Aucun identifiant stable diffusé (M2-03) |
| 2 | **Demande d'appel** et acceptation par le destinataire | Face ID à l'acceptation (M2-08), limitation du spam (M3-09) |
| 3 | **Établissement de session chiffrée** | ECDH P-256 éphémère + HKDF + AES-GCM (M2-05) |
| 4 | **Vérification d'empreinte** entre les deux utilisateurs | Contre l'homme du milieu (M2-06) |
| 5 | **Appel audio** chiffré, un à un | Anti-rejeu, intégrité, format de paquet (M2-07) |
| 6 | **Fin d'appel** et effacement des clés | Échouer en sécurité (M3-10) |

## Hors périmètre (« plus tard »)

- Appels de groupe, vidéo, messagerie texte, envoi de fichiers.
- Comptes, annuaire, contacts persistants, liste d'amis, historique d'appels.
- Appels hors proximité (Internet, relais, serveur), notifications push (compte payant).
- Identité persistante / clé d'identité en Secure Enclave (rejeté, cf. M2-08).
- Mesure précise de distance, géolocalisation (cf. M2-04).
- Enregistrement ou transcription de l'audio (exclu par principe, cf. M1-08).
- Android, iPad, Mac.

## Hypothèses

- Un iPhone par utilisateur, iOS récent, compte Apple gratuit (app à réinstaller tous les 7 jours).
- Wi-Fi et Bluetooth activés sur les deux appareils ; pas de Wi-Fi commun requis.
- Les deux utilisateurs peuvent se parler ou se voir pour comparer le code de vérification.

## Validation

À valider par l'équipe (chef de projet + architecte sécurité) en revue de la PR ; l'approbation GitHub fait foi.
