# M2-07 · Anti-rejeu et intégrité des paquets

Menaces : STRIDE T1, T2, D2, E2. Clés : voir M2-05. Un flux Multipeer **non fiable** (mode `.unreliable`) est utilisé pour l'audio ; l'ordre et la perte sont donc possibles.

## Format du paquet (octets, entiers en grand-boutiste)

```
 0         1         2                    10            14                     N-16        N
 ├─────────┼─────────┼────────────────────┼─────────────┼──────────────────────┼───────────┤
 │ version │  type   │      compteur      │ horodatage  │   texte chiffré      │  tag GCM  │
 │  1 o    │  1 o    │       8 o          │    4 o      │   L octets           │  16 o     │
 └─────────┴─────────┴────────────────────┴─────────────┴──────────────────────┴───────────┘
 └───────── en-tête de 14 octets : AAD (authentifié, non chiffré) ──────────────┘
```

| Champ | Taille | Rôle | Vérification |
|---|---|---|---|
| `version` | 1 | `0x01` | Autre valeur ⇒ rejet |
| `type` | 1 | `0x10` AUDIO, `0x11` CONTROL | Valeur inconnue ⇒ rejet |
| `compteur` | 8 | Numéro de séquence croissant par direction, **commence à 0** à chaque session ; sert aussi de nonce | Fenêtre anti-rejeu (ci-dessous) |
| `horodatage` | 4 | Millisecondes écoulées depuis le début de session côté émetteur (horloge monotone) | Fraîcheur (ci-dessous) |
| `texte chiffré` | L | Trame audio compressée (≈ 20–60 o) ou message de contrôle | Déchiffrement AES-GCM |
| `tag` | 16 | Authentifie en-tête **et** contenu | Échec ⇒ rejet |

**Nonce AES-GCM (12 octets)** = `00 00 00 00 ‖ compteur (8 o)`. Clés distinctes par direction (M2-05) et compteur strictement croissant : un nonce n'est **jamais réutilisé avec une même clé**. Le compteur ne doit jamais dépasser 2⁶⁴ − 1 ; l'émetteur ferme la session bien avant (limite pratique : 2³² paquets ⇒ ≈ 2 ans à 50 paquets/s, mais on borne à 1 h).

**Taille** : 14 + L + 16. Pour L ≈ 40 o ⇒ **≈ 70 o** par paquet, ≈ 50 paquets/s, soit ≈ 28 kbit/s avec l'en-tête.

Le type CONTROL contient dans son clair déchiffré : 1 octet de code (`0x01` SAS_OK, `0x02` HANGUP) ; autre valeur ⇒ rejet. Les messages de poignée de main M2-05 (COMMIT/HELLO/REVEAL) précèdent la clé : leur format est `version ‖ type (0x01/0x02/0x03) ‖ champs à longueurs fixes` et ne passent pas par ce format AEAD ; ils sont protégés par le transcript.

## Règles de réception (dans cet ordre, la plus économique d'abord)

1. **Taille** : `30 ≤ N ≤ 1 200` octets ; sinon rejet (pas de calcul).
2. **Version et type** valides.
3. **Fenêtre de compteur** (type RFC 6479 / IPsec) : on conserve `max_vu` et un masque de 64 bits.
   - `compteur > max_vu` ⇒ plausible (avancer la fenêtre **après** authentification).
   - `max_vu − 64 < compteur ≤ max_vu` et pas encore vu ⇒ plausible (paquet en retard).
   - déjà vu ou `≤ max_vu − 64` ⇒ **rejet** (rejeu).
   - `compteur > max_vu + 1000` ⇒ rejet (saut abusif).
4. **Déchiffrement AES-GCM** avec l'en-tête comme AAD. Échec ⇒ rejet, **et on ne met pas la fenêtre à jour**.
5. **Fraîcheur** : on garde `δ₀ = reçu₀ − horodatage₀` du premier paquet authentifié. Pour les suivants, si `| (reçu − horodatage) − δ₀ | > 2 000 ms` ⇒ rejet (paquet retenu puis rejoué, ou dérive). Les rejeux d'un enregistrement ancien échouent donc deux fois : compteur et fraîcheur.
6. Seulement alors : mise à jour de la fenêtre, remise du contenu à la couche audio.

## Échec en sécurité (cf. M3-10)

- Paquets invalides isolés : ignorés, compteur d'erreurs incrémenté.
- **Plus de 20 rejets en 5 s**, ou un tag invalide pendant la poignée de main : fermeture de la session, effacement des clés, retour à l'écran d'accueil.
- Aucun message d'erreur détaillé envoyé au pair (pas d'oracle).
- Pas de log du contenu ni des clés.

## Tests de validation prévus (M3-08)

| Test | Résultat attendu |
|---|---|
| Rejouer un paquet valide | Rejeté (compteur) |
| Octet modifié dans l'en-tête ou le chiffré | Rejeté (tag) |
| Paquet d'une direction rejoué dans l'autre | Rejeté (clé différente) |
| Paquet trop court / trop long / version inconnue | Rejeté avant déchiffrement |
| Paquet valide mais vieux de 10 s | Rejeté (fraîcheur) |
| Paquets reçus dans le désordre dans la fenêtre | Acceptés une fois chacun |
