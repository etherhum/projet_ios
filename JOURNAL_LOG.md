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

## 2026-11-20 — Issue #10 (M2-02) : prototype de faisabilité du transport

- Demande reformulée : « Créer le projet Xcode de l'app et un prototype Multipeer Connectivity permettant à deux iPhones réels, sans Wi-Fi commun, de se découvrir et d'échanger un message de test. Compiler et tester en local, et attendre la validation humaine sur appareils avant tout push. »
- Livrable : projet `Proxima.xcodeproj` (SwiftUI, iOS 17, aucune dépendance externe), `TransportPrototype` (pseudonyme aléatoire par lancement, chiffrement Multipeer `.required`, message borné à 256 octets), écran de test, 2 tests unitaires.
- Vérification locale : `xcodebuild build-for-testing` OK. Simulateur indisponible sur le Mac (runtime iOS non installé) : tests unitaires à lancer depuis Xcode sur iPhone.
- Résultat sur 2 appareils réels : _à compléter par le développeur après l'essai._
