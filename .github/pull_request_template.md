## Issue liée

Closes #<!-- numéro de l’issue résolue ; utiliser Refs #… pour une simple référence -->

## Changements

<!-- Décrire les changements et leur objectif. -->

## Vérification

<!-- Indiquer les commandes ou scénarios exécutés et leurs résultats. Si non applicable, expliquer pourquoi. -->

## Checklist

- [ ] Relu : j’ai relu le diff avant de demander une revue.
- [ ] Testé : j’ai vérifié le comportement modifié et renseigné les résultats ci-dessus.
- [ ] Sans secret : le diff ne contient aucun mot de passe, token, clé privée ou autre secret.
- [ ] Prompt journalisé : chaque demande utilisateur est consignée dans `JOURNAL_LOG.md` avec une formulation développée et fidèle à son intention ; si aucun outil d’IA n’a été utilisé, je l’ai indiqué ci-dessus.

## Règles de fusion vers `main`

- Toute modification passe par une pull request (PR, équivalent GitHub d’une MR).
- Une approbation indépendante de l’auteur est obligatoire, y compris pour l’administrateur. Elle peut être fournie par `github-actions[bot]` : l’auteur ne peut toujours pas approuver sa propre PR avec son compte.
- Le workflow `Trusted PR auto-merge` approuve puis active le squash auto-merge des PR non brouillon, internes au dépôt, visant `main`, dont l’auteur possède le droit `write`, `maintain` ou `admin`. Une IA utilisant le compte d’un de ces membres suit le même circuit.
- Un nouveau commit annule les approbations précédentes : le workflow réapprouve le nouveau commit et réactive l’auto-merge.
- Les pushs forcés et la suppression de `main` sont interdits.
- Le bot n’exécute pas le code de la PR et ne réalise pas de revue sémantique du code. L’approbation automatique remplace donc une validation humaine obligatoire : relire et tester avant de quitter le mode brouillon.
- L’auto-merge ne contourne pas les protections et attend les contrôles requis. Aucun contrôle CI obligatoire n’est actuellement configuré : ne pas considérer le statut du workflow comme une validation des tests iOS.
- `Closes #N` clôture automatiquement l’issue à la fusion dans `main` ; `Refs #N` ne la clôture pas. Une issue seule ne s’approuve ni ne se fusionne.

### PR déjà ouverte ou relance manuelle

Pour une PR existante, utiliser **Actions → Trusted PR auto-merge → Run workflow**, depuis `main`, en renseignant son numéro, ou lancer avec un compte disposant de l’écriture :

```sh
gh workflow run trusted-auto-merge.yml --repo etherhum/projet_ios --ref main -f pull_request=NUMERO
```

Les mêmes restrictions s’appliquent en relance manuelle : les brouillons, forks, autres branches cibles et auteurs sans écriture sont ignorés. Pour suspendre l’automatisation avant une nouvelle modification, remettre la PR en brouillon.

### Paramètres GitHub nécessaires

- **Settings → General → Pull Requests → Allow auto-merge** : activé.
- **Settings → Actions → General → Workflow permissions → Allow GitHub Actions to create and approve pull requests** : activé. Les permissions par défaut restent en lecture ; seul ce workflow demande `contents: write` et `pull-requests: write`.
- La protection de `main` conserve une approbation obligatoire, l’invalidation après nouveau commit et l’application aux administrateurs, sans autoriser les pushs forcés ni la suppression de la branche.
