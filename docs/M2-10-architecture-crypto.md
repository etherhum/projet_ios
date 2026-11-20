# M2-10 · Architecture globale et dossier de choix crypto (livrable M2)

Document d'assemblage : renvoie aux décisions détaillées M2-01 à M2-09. **À valider par toute l'équipe** (approbation de la PR).

## 1. Schéma d'architecture

```
              iPhone A (appelant)                               iPhone B (appelé)
   ┌────────────────────────────────────┐          ┌────────────────────────────────────┐
   │ UI SwiftUI : découverte, appel,    │          │ UI SwiftUI                         │
   │   code de vérification             │          │                                    │
   │ Face ID (LAContext) ─ ouverture    │          │ Face ID ─ ouverture + acceptation  │
   │ Session : machine à états (échoue  │          │ Session : machine à états          │
   │   en sécurité, efface les clés)    │          │                                    │
   │ Crypto : CryptoKit (ECDH/HKDF/GCM) │          │ Crypto : CryptoKit                 │
   │ Audio : AVAudioEngine + Opus       │          │ Audio : AVAudioEngine + Opus       │
   │ Transport : Multipeer Connectivity │          │ Transport : Multipeer Connectivity │
   └──────────────────┬─────────────────┘          └──────────────────┬─────────────────┘
                      │   lien direct iOS (AWDL / Bluetooth),         │
                      └───  sans Wi-Fi commun, NON DE CONFIANCE ──────┘
                            1. annonces : pseudonyme éphémère (M2-03)
                            2. invitation, acceptation Face ID (M2-08)
                            3. COMMIT / HELLO / REVEAL (M2-05)
                            4. code de vérification comparé par les humains (M2-06)
                            5. paquets AES-GCM : compteur + horodatage (M2-07)
```

Principes (cours) : réseau non fiable (**Zero Trust**), défense en profondeur (utilisateur → appareil → réseau → app → données), moindre privilège, **échouer en sécurité**, jamais de cryptographie maison. Pas de serveur ni de compte ⇒ rien à héberger, aucune donnée centralisée.

## 2. Flux d'un appel (vue d'ensemble)

| # | Étape | Qui | Sécurité | Réf. |
|---|---|---|---|---|
| 1 | Ouverture de l'app | A, B | Face ID / code | M2-08 |
| 2 | Découverte | A, B | Pseudonyme éphémère, pas d'identifiant fixe | M2-03 |
| 3 | Demande d'appel | A → B | Limitation de débit chez B | M3-09 |
| 4 | Acceptation | B | Face ID ; refus par défaut | M2-08 |
| 5 | Échange de clés | A ↔ B | ECDH P-256 éphémère, HKDF, engagement | M2-05 |
| 6 | Vérification | humains | Code 6 chiffres / QR | M2-06 |
| 7 | Audio | A ↔ B | AES-256-GCM, anti-rejeu | M2-07 |
| 8 | Fin ou erreur | A, B | Clés effacées, session fermée | M3-10 |

## 3. Dossier de choix cryptographiques

| Choix | Valeur | Alternative écartée | Pourquoi |
|---|---|---|---|
| Accord de clé | ECDH **P-256 éphémère** (CryptoKit) | Clé statique, RSA, Curve25519 | Confidentialité persistante ; standard du cours ; matériel Apple |
| Dérivation | **HKDF-SHA256**, sel = transcript, info distinctes | Utiliser le secret ECDH tel quel, SHA-256 simple | Séparation des clés/directions, liaison à la poignée de main |
| Chiffrement | **AES-256-GCM** (CryptoKit) | AES-CBC/ECB, ChaCha20-Poly1305 (acceptable) | Authentifié (intégrité incluse), accéléré matériellement |
| Nonce | Compteur 64 bits par direction (clé par direction) | Nonce aléatoire 96 bits | Unicité garantie, sert aussi à l'anti-rejeu |
| Intégrité de poignée de main | Hash du transcript + **engagement** | Aucun | Empêche de choisir une clé pour égaliser les codes |
| Authentification du pair | **Code court (SAS) / QR** hors bande | Clé d'identité, mot de passe partagé | Pas de compte ; adapté à la proximité (M2-06) |
| Identité longue durée | **Aucune** | Clé Secure Enclave | Anonymat, non-traçabilité (M2-08) |
| Secure Enclave | Non utilisée | Clé d'identité | Voir M2-08 |
| Face ID | Ouverture + acceptation d'appel | À chaque paquet, jamais | Voir M2-08 |
| Aléa | `SystemRandomNumberGenerator` | PRNG maison | CSPRNG système |
| Dépendances | **Aucune** | libopus, WebRTC | Voir M2-09 |

Suite cryptographique **unique** (pas de négociation) : P-256 + HKDF-SHA256 + AES-256-GCM ; version `v1` dans le transcript.

## 4. Couverture du modèle de menaces

| STRIDE | Couvert par |
|---|---|
| S1, S2 | M2-05 (engagement), M2-06 (code), M2-03 |
| T1, T2 | M2-05 (transcript), M2-07 (tag GCM, AAD) |
| R1, R2 | Choix assumé (M2-08) : pas de non-répudiation |
| I1 | M2-03 |
| I2, I3, I4 | M3-12, M3-11, M2-05 (effacement) |
| D1, D2 | M3-09, M2-07 (rejet précoce, limites) |
| E1, E2, E3 | M2-08, M2-07 + parseur strict, M3-02 |

## 5. Points ouverts avant M3

1. Prototype du transport et du codec Opus (M2-02, M2-09) : confirmer faisabilité sur l'iPhone de l'équipe.
2. Rayon : décision MVP « portée du lien » (M2-04), à confirmer avec le développeur iOS.
3. Valeurs de réglage (fenêtres, seuils, délais) à ajuster en test ; elles ne changent pas l'architecture.
4. Revue de cette architecture par la red team (M2-11).
