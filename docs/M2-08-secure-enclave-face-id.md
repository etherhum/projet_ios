# M2-08 · Rôle de la Secure Enclave et de Face ID

## Décision

1. **Pas de clé d'identité en Secure Enclave.** Les clés de session sont éphémères et vivent en mémoire (CryptoKit `P256.KeyAgreement`).
2. **Face ID (ou code de l'appareil) est exigé à deux endroits** : (a) à l'ouverture de l'app, (b) à l'acceptation d'un appel entrant. Via `LocalAuthentication` (`LAContext`, politique `.deviceOwnerAuthentication`, avec repli sur le code).

## Pourquoi pas de clé d'identité persistante

La Secure Enclave sert à garder des clés **durables** non exportables (identité, passkeys). Ici, l'objectif est l'inverse :

- Une clé publique persistante, même protégée, est **un identifiant stable** : toute personne qui la voit (signature, annonce, échange) peut relier deux appels, voire pister l'appareil (contraire à M2-03, STRIDE I1, A3).
- Pas de compte, pas d'annuaire, pas de serveur : aucune partie ne peut vérifier que « cette clé est celle de Marie ». On l'authentifie quand même par comparaison de code (M2-06), à chaque appel.
- La confidentialité persistante exige des clés **qui disparaissent** ; une clé Secure Enclave est faite pour durer.
- Placer aussi les clés éphémères en Secure Enclave n'apporterait presque rien : elles n'existent que quelques minutes en mémoire de l'app et sont effacées ; l'enjeu de la Secure Enclave (rendre une clé durable non exportable) ne s'applique pas.
- Conséquence assumée : pas de non-répudiation (STRIDE R1/R2), choix cohérent avec l'anonymat.

## Où placer Face ID

| Moment | Décision | Justification |
|---|---|---|
| **Ouverture de l'app** | Oui | iPhone déverrouillé prêté à un tiers : l'app ne s'ouvre pas, pas d'appel possible (STRIDE E1, T4) |
| **Acceptation d'un appel** | **Oui, obligatoire** | Un appel ouvre le micro : l'acceptation doit venir du propriétaire (E1) ; aussi un frein au harcèlement automatisé |
| Émission d'un appel | Non (déjà authentifié à l'ouverture) | Évite la fatigue d'authentification ; l'appel est sortant et explicite |
| Pendant l'appel (revalidation périodique) | Non | Coupure en cours de conversation = nuisance ; l'app se verrouille au passage en arrière-plan (M3-11) |
| Chaque paquet / dérivation de clé | Non | Face ID n'est pas un secret cryptographique ici |

Limite à documenter : `LAContext` est une **porte logique** de l'app, pas une liaison cryptographique des clés de session (elles ne sont pas stockées). C'est acceptable car la session n'existe pas hors de l'app ; mais un attaquant qui contrôle l'app contourne cette porte (appareil compromis, hors périmètre).

## Échec en sécurité

- Biométrie non disponible / non configurée : repli sur le code de l'appareil ; si aucun code n'est défini, **l'app refuse de démarrer les appels** (message explicite).
- Échec, annulation ou délai de Face ID : l'appel est **refusé** (jamais accepté par défaut).
- `NSFaceIDUsageDescription` est requis dans `Info.plist`. Compatible avec un compte Apple gratuit.

## Alternatives rejetées

| Alternative | Motif du rejet |
|---|---|
| Clé d'identité P-256 en Secure Enclave, signée à chaque appel | Identifiant stable → traçabilité, contraire à l'anonymat |
| Clé en Keychain `.biometryCurrentSet` / `ThisDeviceOnly` | Même problème de persistance ; sans serveur aucune utilité de vérification |
| Aucun Face ID (le déverrouillage de l'iPhone suffit) | Un iPhone déverrouillé laissé sans surveillance permettrait d'accepter un appel |
| Face ID à chaque émission et chaque minute d'appel | Gêne importante, bénéfice marginal |
| Dériver la clé de session d'une clé protégée par Face ID | Complexité sans gain : la clé n'est pas stockée |

## Évolution possible

Si un jour des contacts persistants sont ajoutés (hors MVP), une clé de signature en Secure Enclave deviendrait pertinente pour authentifier un contact connu ; c'est un changement d'architecture et de modèle de menaces, à traiter séparément.
