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
