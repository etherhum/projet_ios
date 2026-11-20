# Journal des prompts 

Chaque demande utilisateur est consignée dans `JOURNAL_LOG.md` avec une formulation développée et fidèle à son intention, sans inventer de consignes supplémentaires.

- Analyse ce document contenant les consignes présices du projet. Détermine un ensemble de règle et de tâches adaptés au brief du projet présent dans BRIEF.md

## 2026-11-20 — Issue #1 : initialisation et règles de merge

- Demande reformulée : « Prendre en charge l’issue #1 du projet : vérifier l’initialisation du dépôt Git, protéger la branche `main`, imposer le passage par une PR et l’approbation d’un autre membre, puis fournir un template couvrant la relecture, les tests, l’absence de secrets et la journalisation des prompts. Vérifier par une tentative réelle qu’une PR sans approbation ne peut pas être fusionnée. »
- Périmètre : dépôt Git existant, protection de `main`, PR obligatoire avec une approbation d’un autre membre et template de PR (relu / testé / sans secret / prompt journalisé).
- Choix : règles appliquées aussi aux administrateurs, approbations invalidées par les nouveaux commits, pushs forcés et suppression de `main` interdits.
- Vérification : tentative réelle de fusion de la [PR #49](https://github.com/etherhum/projet_ios/pull/49), sans revue, refusée par GitHub avec HTTP `405` : « At least 1 approving review is required by reviewers with write access. »
- État : protection active sur `main` ; template proposé dans la PR #49. Le seul collaborateur est actuellement l’auteur : ajouter un second membre avec droit d’écriture pour obtenir l’approbation et fusionner sans contourner la règle.

## 2026-11-20 — Journalisation systématique et validation de l’issue #1

- Demande reformulée : « Consigner chaque demande dans `JOURNAL_LOG.md` en développant sa formulation pour rendre l’objectif et le contexte explicites, plutôt que de conserver une instruction trop succincte comme “faire l’issue 1”. Mettre à jour la journalisation de la demande précédente et de cette précision, puis traiter la validation de l’issue #1. »
- Mise en œuvre : migration du journal vers `JOURNAL_LOG.md`, reformulation de la demande liée à l’issue #1 et mise à jour du template de PR. La convention est également inscrite dans `AGENTS.md` pour les prochaines interventions.

## 2026-11-20 — Approbation, fusion et clôture demandées

- Demande reformulée : « Finaliser le traitement de l’issue #1 de bout en bout : approuver la PR #49, la fusionner dans `main`, puis clôturer l’issue correspondante, en conservant la journalisation de cette demande. »
- Tentative d’approbation : `gh pr review 49 --approve` refusé par GitHub avec « Review Can not approve your own pull request ». Le compte disponible, `etherhum`, est l’auteur de la PR.
- Tentative de fusion : `PUT /repos/etherhum/projet_ios/pulls/49/merge` sur le commit `29ed85c`, refusé avec HTTP `405` : « At least 1 approving review is required by reviewers with write access. »
- Blocage : un autre membre avec droit d’écriture doit approuver la PR. La fusion n’a pas eu lieu et l’issue reste ouverte ; `Closes #1` assurera sa clôture lors de la fusion.

## 2026-11-20 — Rôle architecte sécurité : issues M1 et M2

- Demande reformulée : « En tant qu'architecte sécurité du groupe, lire `Projet M2.pdf` puis traiter les issues portant le label “rôle: Architecte sécurité” du dépôt GitHub `etherhum/projet_ios`. »
- Périmètre traité (livrables rédactionnels, sans code) : M1-05 (#4), M1-06 (#5), M1-07 (#6), M1-08 (#7), M2-03 (#11), M2-04 (#12), M2-05 (#13), M2-06 (#14), M2-07 (#15), M2-08 (#16), M2-09 (#17), M2-10 (#18), dans `docs/`. M2-01 (#9) est déjà en PR #50.
- Non traité : issues M3 à M5 (#23, #29, #32, #39, #41, #46), qui dépendent du code, d'un audit ou de jalons ultérieurs.
- Choix signalés : le rayon (M2-04) n'utilise pas le RSSI car Multipeer ne l'expose pas ; aucune clé d'identité Secure Enclave (M2-08) pour préserver l'anonymat ; code de vérification à 6 chiffres avec engagement préalable (M2-05/06).
- Relecture : contenu généré par IA, à relire par l'équipe (et le point codec Opus à confirmer par prototype).

## 2026-11-20 — Issue #9 (M2-01) : choix du transport pair-à-pair

- Demande reformulée : « En tant que développeur iOS, traiter dans l'ordre les issues du rôle iOS à partir du sujet du projet (`Projet M2.pdf`). Pour M2-01, comparer Multipeer Connectivity, CoreBluetooth et Network framework, et choisir un transport qui fonctionne avec un compte Apple gratuit et **sans que les iPhones soient sur le même Wi-Fi**. Évaluer l'intérêt du Bluetooth seul. »
- Échanges : le BLE seul est écarté (débit insuffisant pour l'audio) ; Multipeer est retenu, sans BLE complémentaire.
- Livrable : `docs/M2-01-transport.md` (tableau comparatif + justification).
- Relecture : contenu relu par le développeur humain avant PR.
## 2026-11-20 — Issue #10 (M2-02) : prototype de faisabilité du transport

- Demande reformulée : « Créer le projet Xcode de l'app et un prototype Multipeer Connectivity permettant à deux iPhones réels, sans Wi-Fi commun, de se découvrir et d'échanger un message de test. Compiler et tester en local, et attendre la validation humaine sur appareils avant tout push. »
- Livrable : projet `Proxima.xcodeproj` (SwiftUI, iOS 17, aucune dépendance externe), `TransportPrototype` (pseudonyme aléatoire par lancement, chiffrement Multipeer `.required`, message borné à 256 octets), écran de test, 2 tests unitaires.
- Vérification locale : `xcodebuild build-for-testing` OK. Simulateur indisponible sur le Mac (runtime iOS non installé) : tests unitaires à lancer depuis Xcode sur iPhone.
- Bug trouvé lors de l'essai : `NSBonjourServices` absent de l'Info.plist généré (clé non supportée en build setting), découverte bloquée silencieusement par iOS. Corrigé via `Proxima-Info.plist`.
- Résultat sur 2 appareils réels (iPhone 17 Pro Max + iPhone 16 Pro Max) : découverte, connexion et message de test reçus — validé par le développeur le 2026-11-20.

## 2026-11-20 — Issues #12 (M2-04) et #17 (M2-09) : rayon, codec et dépendances

- Demande reformulée : « Poursuivre les issues du rôle iOS dans l'ordre. Documenter l'estimation du rayon de proximité compatible avec Multipeer seul (méthode, précision, limites assumées) et choisir le codec audio en privilégiant les API natives Apple, avec la liste justifiée des dépendances. Regrouper ces deux documents dans une seule PR. »
- Résultat : l'architecte sécurité avait rédigé en parallèle ces deux documents (PR #53), avec les mêmes décisions (rayon = portée Multipeer, pas une frontière de sécurité ; Opus natif, repli AAC-ELD, aucune dépendance). Leur version, plus complète, est conservée ; relue et validée côté iOS.
## 2026-11-20 — Issue #20 (M3-01) : squelette de l'app SwiftUI

- Demande reformulée : « Créer le squelette SwiftUI (liste des proches, appel en cours) qui servira de base aux issues M3, le lancer sur les deux iPhones réels ; utiliser un agent pour économiser le contexte. »
- Architecture : `App/` (`ProximaApp`, `AppState` état racine, `RootView`), `Features/NearbyList/NearbyListView`, `Features/Call/CallView` (alias du pair, durée, micro coupé, raccrocher), `Models/` (`Pseudonym`, `NearbyPeerList`), `Services/` (protocole `PeerDiscovering`, `NearbyService` Multipeer). Prototype M2-02 supprimé.
- Conformité M2-03 : pseudonyme = 8 octets CSPRNG en base32 (13 car.), régénéré à chaque démarrage de la découverte, jamais persisté ; `discoveryInfo = ["v": "1"]` ; alias lisible dérivé localement (« Renard-XYZ »). Écart : `serviceType` reste `proxima` (déjà déclaré dans l'Info.plist) au lieu de l'exemple `proxcall`. Rotation 10 min laissée en TODO M3-03.
- Comportement : découverte au premier plan seulement (arrêt en arrière-plan), liste mise à jour via foundPeer/lostPeer, aucune connexion automatique, invitations entrantes refusées. Taper un pair ouvre l'écran d'appel en maquette (aucun audio, aucune crypto ; TODO M3-05/M3-07). Aucun log de pseudonyme.
- Permission : aucune demande explicite, mais le démarrage de la découverte Multipeer au lancement déclenche la popup système « Réseau local » (M3-02 prévoira un écran d'explication avant).
- Vérification : `build-for-testing` OK ; 8 tests unitaires OK sur iPhone 17 Pro Max. App installée et lancée sur l'iPhone 17 Pro Max ; le second iPhone était « unavailable » (verrouillé/déconnecté) au moment de l'installation, à refaire.

## 2026-11-20 — Issue #21 (M3-02) : permissions au moment du besoin

- Demande reformulée : « Faire demander chaque permission (réseau local, micro) au moment de son premier usage et non au lancement, avec des textes clairs, sans permission superflue (pas de Bluetooth), en gérant le refus ; partir de la branche M3-01 ; utiliser un agent pour économiser le contexte. »
- Réseau local : écran d'accueil expliquant le besoin (Wi-Fi pair-à-pair, sans Internet ni serveur, pseudonyme éphémère) avec le bouton « Rechercher les personnes proches » ; la découverte Multipeer (donc la popup iOS) ne démarre qu'au tap. Choix mémorisé pour la session uniquement (`AppState.searchRequested`, aucun UserDefaults : minimisation M1-08, et iOS mémorise déjà la réponse). Refus : iOS n'expose pas l'état de cette permission, donc après 10 s sans pair une aide discrète propose « Réglages > Proxima > Réseau local » avec lien vers les Réglages.
- Micro : `Services/MicrophonePermission.swift` (protocole + `AVAudioApplication.requestRecordPermission`, iOS 17). Demandé au tap sur un pair, avant d'ouvrir l'écran d'appel. Refus ou refus antérieur → aucun appel, alerte avec bouton « Ouvrir les Réglages », sans nouvelle demande. `NSMicrophoneUsageDescription` ajoutée (Debug/Release).
- Permissions déclarées : réseau local (+ NSBonjourServices) et micro uniquement ; ni Bluetooth, ni caméra, ni localisation. Aucun log de pseudonyme.
- Tests : injection `PeerDiscovering` + `MicrophonePermission` dans `AppState` ; nouveaux tests (rien demandé au lancement, découverte après action utilisateur, micro refusé/déjà refusé → pas d'appel, accordé → appel).
- Vérification : `build-for-testing` OK ; 12 tests unitaires OK sur iPhone 16 Pro Max (l'iPhone 17 Pro Max était « unavailable »). `plutil -p` : Info.plist avec NSLocalNetworkUsageDescription, NSMicrophoneUsageDescription, NSBonjourServices, aucune clé Bluetooth/caméra/localisation. App réinstallée sur l'iPhone 16 Pro Max (lancement bloqué tant que le profil développeur n'est pas de nouveau approuvé après désinstallation) ; installation sur l'iPhone 17 Pro Max à refaire. Tests manuels des popups à faire par l'équipe.
- Validation manuelle sur 2 iPhones réels (17 Pro Max + 16 Pro Max) : aucune popup au lancement, popup réseau local au tap « Rechercher », popup micro au premier appel uniquement, reprise après arrière-plan — validé par le développeur le 2026-11-20.

## 2026-11-20 — Issue #22 (M3-03) : découverte des utilisateurs proches

- Demande reformulée : « Finaliser la découverte des utilisateurs proches conformément à M2-03 : liste à jour avec pseudonymes éphémères en rotation, retrait des pairs disparus, validation des annonces reçues, sans identifiant stable ni log sensible ; partir de la branche M3-02 ; utiliser un agent pour économiser le contexte. »
- Rotation (M2-03) : toutes les 10 min (`RotationPolicy.defaultInterval = 600`) via une minuterie injectable (`Services/RotationTimer.swift`). Chaque rotation : arrêt, nouveau pseudonyme CSPRNG jamais utilisé pendant ce lancement (ensemble en mémoire seulement), nouveau `MCPeerID`, nouvelle `MCSession` (`.required`), nouvel advertiser et nouveau browser ; la liste est vidée puis se remplit à nouveau. Nouveau pseudonyme aussi au retour au premier plan et à la fin d'appel. Pas de rotation pendant un appel : l'échéance est reportée à la fin de l'appel (`AppState.isInCall`, hook pour M3-05, aujourd'hui basé sur l'écran d'appel en maquette). En DEBUG uniquement, l'argument de lancement `-ProximaRotationSeconds <n>` (n ≥ 10) raccourcit l'intervalle pour les essais.
- Validation des annonces (`Models/DiscoveryValidator.swift`) : displayName = exactement 13 caractères base32 (A-Z, 2-7), sinon ignoré ; `discoveryInfo` requis, `v == "1"`, au plus 4 clés et 64 octets au total, clés inconnues ignorées dans ces bornes ; son propre pseudonyme ignoré (aussi dans `AppState`, défense en profondeur).
- Liste : pas de doublon, retrait sur `lostPeer`, tri stable (alias puis pseudonyme), borne de 64 pairs contre l'inondation (limitation fine en M3-09).
- Aucun log ; un test vérifie l'absence de `UIDevice`, `identifierForVendor`, `hostName`, `UserDefaults`, `print`/`NSLog`/`Logger` dans les sources (ignoré sur appareil si les sources ne sont pas accessibles).
- Vérification : `build-for-testing` OK ; 23 tests unitaires OK sur iPhone 16 Pro Max (1 ignoré : scan des sources inaccessible sur appareil ; l'iPhone 17 Pro Max a bloqué le lancement des tests) ; app installée et lancée sur les 2 iPhones. Validation manuelle « les 2 appareils se voient » à faire par l'équipe.
- Tests : validation displayName/discoveryInfo (invalide, surdimensionné, version), propre pair, doublons, pair perdu, tri stable et borne, rotation (50 pseudonymes différents), pas de rotation pendant un appel puis rotation au raccrochage, pas de rotation à l'arrêt.
- Écarts / choix : pas de purge par ancienneté (« non revu depuis N s ») car Multipeer n'émet `foundPeer` qu'une fois par pair : une purge retirerait des pairs encore présents ; les entrées périmées sont couvertes par `lostPeer` et par la remise à zéro de la liste à chaque rotation (au plus 10 min). Clés inconnues de `discoveryInfo` tolérées (bornées) plutôt que rejetées, pour la compatibilité de version ; la spec ne tranche pas. `serviceType` reste `proxima` (cf. M3-01). La capture `dns-sd` (preuve 2 de M2-03) reste à faire par l'équipe.
