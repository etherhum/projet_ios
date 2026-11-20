# M2-05 · Échange de clés

Objectif : une clé de session partagée, éphémère, dont la compromission ne déchiffre pas les appels passés (**confidentialité persistante**). Primitives : **uniquement CryptoKit**, aucune cryptographie maison.

## Primitives et justification

| Primitive | Usage | Pourquoi |
|---|---|---|
| `P256.KeyAgreement.PrivateKey` (ECDH P-256), **éphémère** | Un couple de clés neuf par appel | Confidentialité persistante ; clés publiques courtes (X9.63 : 65 octets) ; standard, matériel Apple optimisé |
| `SharedSecret` (sortie ECDH) | Matériau brut, **jamais utilisé directement** comme clé | La sortie ECDH n'est pas uniforme |
| `HKDF<SHA256>` | Dérive les clés à partir du secret, avec sel et contexte | Séparation des usages et des directions ; lie les clés à la poignée de main (transcript) |
| `AES.GCM` (clé 256 bits) | Chiffrement authentifié des paquets | Confidentialité + intégrité en une opération ; nonce de 12 octets |
| `SHA256` | Engagement (commit) et transcript | Standard, résistant aux collisions |
| `SystemRandomNumberGenerator` | Nonces de poignée de main | CSPRNG du système |

Écartés : RSA (clés lourdes, pas de FS native), Curve25519 (valable, mais P-256 est aligné sur le cours et sur la Secure Enclave ; pas de gain justifiant le changement), ECB/CBC, clé pré-partagée statique (pas de FS), mot de passe/PIN partagé.

## Protocole (initiateur = appelant I, répondeur = appelé R)

L'engagement préalable (inspiré de ZRTP) empêche un attaquant de **choisir sa clé après avoir vu celle de l'autre** pour obtenir un même code de vérification des deux côtés (M2-06).

```
         I (appelant)                                       R (appelé)
 génère (skI, pkI), nonceI(16 o)
 C = SHA256(pkI ‖ nonceI)
              ── 1. COMMIT { v, C } ──────────────────────────►
                                                      (Face ID, acceptation – M2-08)
                                                      génère (skR, pkR), nonceR(16 o)
              ◄── 2. HELLO { v, pkR, nonceR } ─────────────────
              ── 3. REVEAL { pkI, nonceI } ────────────────────►
                                                      vérifie SHA256(pkI ‖ nonceI) == C, sinon ABANDON
 secret = ECDH(skI, pkR)                              secret = ECDH(skR, pkI)
 T = SHA256( "proxcall/v1" ‖ C ‖ pkR ‖ nonceR ‖ pkI ‖ nonceI )     (transcript)

 HKDF-SHA256(secret, salt = T) avec info distinctes :
     k_IR  = expand("proxcall/v1/key I→R", 32 o)   clé AES-256 appelant → appelé
     k_RI  = expand("proxcall/v1/key R→I", 32 o)   clé AES-256 appelé → appelant
     sas   = expand("proxcall/v1/sas", 3 o)        → code à 6 chiffres (M2-06)

 effacement immédiat de skI/skR et du secret ECDH après dérivation

              ◄── 4. paquets CONTROL « SAS_OK » chiffrés, après comparaison humaine (M2-06) ──►
              ──── 5. audio chiffré (M2-07) ────────────────────
```

Détails :

- Deux clés, une par direction : un paquet renvoyé dans l'autre sens est rejeté (réflexion) et le compteur de nonce de chaque direction est indépendant.
- `salt = T` : toute modification de la poignée de main (clé publique remplacée, version rétrogradée) change les clés **et** le code ⇒ échec de l'appel, pas de dégradation silencieuse.
- Clé publique reçue : validée par `P256.KeyAgreement.PublicKey(x963Representation:)` (rejette les points invalides) ; longueur exacte 65 octets, sinon abandon.
- Version `v` incluse dans le transcript : pas de négociation d'algorithme (un seul suite : P-256 / HKDF-SHA256 / AES-256-GCM) donc pas d'attaque par rétrogradation.
- Délai maximal de poignée de main (ex. 30 s) puis abandon et effacement.
- Aucune clé n'est écrite sur disque, en Keychain ni dans les logs (STRIDE I2, I4).

## Propriétés obtenues

| Propriété | Comment |
|---|---|
| Confidentialité | AES-256-GCM avec clé issue d'ECDH |
| Confidentialité persistante | Clés privées éphémères détruites ; voler un appareil après l'appel ne déchiffre pas une capture |
| Intégrité de la poignée de main | Transcript dans HKDF et dans le code |
| Protection MitM | Code de vérification comparé par les humains (M2-06) ; sans cela, l'échange seul **ne protège pas** d'un MitM actif |
| Pas de rétrogradation | Suite unique, version dans le transcript |

## Menaces STRIDE couvertes

S1, T2, I4 (cf. M1-07).
