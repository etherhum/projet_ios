# M1-08 · Cadrage RGPD

## Synthèse : données collectées

**Aucune donnée n'est collectée, aucune n'est conservée.** Tout ce qui est traité est **éphémère**, reste sur les deux iPhones et disparaît à la fin de l'appel ou à la fermeture de l'app. Pas de serveur, pas de compte, pas d'analytics, pas de SDK tiers (M2-09).

| Donnée | Collectée ? | Où | Durée | Justification |
|---|---|---|---|---|
| Audio du micro | Traité, **jamais enregistré** | Mémoire, envoyé chiffré au pair | Le temps de la trame (≈ 20 ms) | Finalité unique : l'appel |
| Pseudonyme aléatoire | Éphémère | Mémoire, visible des appareils à portée | Une session de découverte | Nécessaire pour être trouvé ; non lié à une personne |
| Clés de session | Éphémères | Mémoire | Une session | Chiffrement ; effacées en fin d'appel |
| Code de vérification | Éphémère | Écran | Le temps de la comparaison | Authentification du pair |
| Présence à portée (proximité) | Éphémère | Radio locale | Tant que l'app découvre | Découverte. **Pas de GPS**, aucune position stockée |
| Identité réelle, contacts, téléphone, e-mail, identifiant publicitaire | **Non** | n/a | n/a | Inutile |
| Journal d'appels, historique | **Non** | n/a | n/a | Pas de persistance |
| Logs techniques | Sans donnée personnelle | Console | Session | Aucun secret, pseudonyme ni contenu (M3-12) |

## Principes appliqués

- **Consentement** : le micro n'est demandé qu'au premier appel (permission iOS avec texte explicite). Un appel n'est jamais accepté automatiquement ; le destinataire accepte par Face ID/code. Le pair sait qu'un appel est en cours (indicateur iOS du micro + écran d'appel).
- **Minimisation** : ne rien collecter qui ne sert pas l'appel. Pas de localisation, pas de contacts, pas de nom d'appareil.
- **Limitation de la finalité** : l'audio ne sert qu'à l'appel ; aucune transcription, aucun enregistrement, aucune analyse.
- **Limitation de la conservation** : rien n'est écrit sur disque ni en Keychain ; les clés vivent en mémoire et sont effacées.
- **Sécurité (art. 32)** : chiffrement de bout en bout, authentification du pair, défense en profondeur (cf. STRIDE).
- **Transparence** : écran d'information court au premier lancement (« aucune donnée collectée, rien n'est enregistré »).
- **Droits des personnes** : sans donnée personnelle conservée, accès / effacement / portabilité n'ont pas d'objet ; à indiquer dans l'écran d'information.

## Points de vigilance

- **Tiers non-utilisateur** : une voix captée par le micro peut être celle d'une personne qui n'a pas utilisé l'app. Rappeler à l'utilisateur dans l'écran d'information qu'il doit informer ses interlocuteurs.
- **Voix = donnée personnelle** en contexte d'appel, même éphémère : d'où le chiffrement et l'absence d'enregistrement.
- **Pseudonyme** : s'il est stable et diffusé, il devient une donnée personnelle (traçage). D'où sa rotation à chaque session (M2-03).
- **Démo en groupe** : n'utiliser que des comptes/appareils de l'équipe, aucune donnée réelle de tiers (règle du sujet : pas de données réelles).
- Hors sujet : base légale précise et AIPD relèveraient d'un déploiement réel ; non traitées ici car projet pédagogique, à mentionner à l'oral.
