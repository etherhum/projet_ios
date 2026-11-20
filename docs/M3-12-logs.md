# M3-12 · Logs propres

Objectif : aucun secret, clé, pseudonyme ou donnée de proximité en clair dans les logs, y compris en mode debug.

## Règles

**Une seule porte : `AppLog` (`Proxima/Services/AppLog.swift`)**, basée sur `os.Logger`,
subsystem `fr.epita.projetios.proxima`, catégories `discovery`, `session`, `crypto`, `audio`, `ui`.

| On journalise | On ne journalise JAMAIS |
|---|---|
| Événements typés `AppLog.Event` (enum sans valeur associée) | Pseudonyme, alias, `MCPeerID`/`displayName` |
| Messages `StaticString` écrits dans le code | Clés (privées, publiques, de session), `Data`, nonces, sels, engagements |
| Changements d'état : découverte démarrée/arrêtée, rotation, invitation refusée, micro refusé ; session (sortant, entrant, accepté, refusé, clés établies, actif, terminé, échec par catégorie) ; anti-spam (limitée, bloquée) ; anti-rejeu (paquet rejeté, debug) ; secrets effacés | Code de vérification (SAS), compteurs/numéros de séquence liés à un pair |
| Éventuellement un identifiant de corrélation **opaque**, toujours `.private(mask: .hash)` | Horodatages ou durées liés à un pair, nombre/présence de pairs proches, `discoveryInfo` |
| | Descriptions d'erreurs système contenant des données (`error.localizedDescription`, `"\(error)"`) |

- `print`, `NSLog`, `debugPrint`, `dump`, `os_log` et toute construction de `Logger` hors `AppLog` sont
  **interdits** (contrôlés par `scripts/check-forbidden-apis.sh`, qui n'autorise `Logger(` que dans
  `Proxima/Services/AppLog.swift` via une liste blanche explicite).
- Le niveau `.debug` n'est émis qu'en build DEBUG (`AppLog.isDebugEnabled`) ; rien en Release.
- Ajouter un log = ajouter un cas à `AppLog.Event` avec un message statique, relu en revue de code.
- Les erreurs du module crypto (`CryptoError`) sont des cas sans contenu : si on les journalise, on
  journalise un événement statique (ex. « échec d'authentification ») et jamais le paquet.

## Mapping des données sensibles

| Donnée | Sensibilité | Traitement dans les logs |
|---|---|---|
| Pseudonyme (13 car. base32) | Identifiant éphémère, traçable pendant 10 min | Interdit (aucune API ne l'accepte) |
| Alias (« Renard-4F2 ») | Dérivé du pseudonyme | Interdit |
| Clés éphémères / de session, `Data` | Secret | Interdit |
| Code SAS (M2-06) | Secret d'authentification | Interdit |
| Horodatages d'événements liés à un pair | Corrélation / présence | Seul l'horodatage système de la ligne existe ; aucun horodatage applicatif de pair |
| RSSI / distance | Proximité | Inexistant : Multipeer ne l'expose pas, et l'app ne le calcule pas |
| Présence / nombre de pairs (`found`/`lost`) | Donnée de proximité | Interdit (pas d'événement `found`/`lost`) |
| Compteurs de paquets par pair | Corrélation | Interdit |

## Procédure de revue des logs (équipe / red team)

1. Brancher l'iPhone, installer une build **Debug** (pire cas).
2. Capturer :
   - Terminal (Mac) : `log stream --predicate 'subsystem == "fr.epita.projetios.proxima"' --level debug`
     (pour l'iPhone : Console.app → sélectionner l'iPhone → Démarrer, filtre `subsystem:fr.epita.projetios.proxima`,
     menu Action → « Inclure les messages d'information » et « … de débogage »).
   - En complément, sans filtre, chercher `process:Proxima` pour attraper un `print`/`NSLog` oublié.
3. Scénario à dérouler sur 2 iPhones :
   1. Lancer l'app, taper « Rechercher » (attendu : « Découverte démarrée »).
   2. Attendre que l'autre appareil apparaisse ; noter son alias affiché à l'écran.
   3. Passer en arrière-plan puis revenir (arrêt / démarrage).
   4. Forcer une rotation (attendre l'échéance ou raccrocher un appel) : « Rotation du pseudonyme effectuée ».
   5. Lancer un appel (accepter puis, sur un autre essai, refuser le micro : « Permission micro refusée »).
   6. Appeler l'autre appareil, accepter, confirmer les codes, raccrocher (« Appel sortant », « Appel entrant »,
      « accepté », « Clés de session établies », « appel actif », « terminé », « Secrets de session effacés ») ;
      refaire avec « Ne correspondent pas » (« codes de vérification différents »).
   7. Bloquer l'autre appareil puis l'appeler depuis celui-ci (« Demande d'appel d'un pair bloqué ignorée »).
4. Vérifier dans la capture :
   - aucune chaîne de 13 caractères `[A-Z2-7]{13}`, aucun alias vu à l'écran (nom d'animal + 3 caractères) ;
   - aucun hexadécimal/base64 long (clé, nonce, `Data`), aucun code SAS ;
   - aucune ligne mentionnant l'arrivée/le départ d'un pair ni un nombre de pairs ;
   - toute valeur dynamique apparaît `<private>` ou `<mask.hash: …>` ;
   - aucune ligne de catégorie hors `discovery|session|crypto|audio|ui`.
   Aide : `log show --last 15m --predicate 'process == "Proxima"' | grep -E '[A-Z2-7]{13}|Renard|Loutre|Hibou'` doit être vide.
5. Consigner le résultat (date, build, appareils, OK/KO) dans la PR ou le journal.

Note : sur Mac connecté, Xcode/Console peuvent afficher les valeurs `.private` en clair si un profil de
journalisation « private data » est installé ; la revue se fait **sans** ce profil.
