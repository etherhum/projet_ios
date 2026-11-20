## Issue liée

Refs #<!-- numéro de l’issue -->

## Changements

<!-- Décrire les changements et leur objectif. -->

## Vérification

<!-- Indiquer les commandes ou scénarios exécutés et leurs résultats. Si non applicable, expliquer pourquoi. -->

## Checklist

- [ ] Relu : j’ai relu le diff avant de demander une revue.
- [ ] Testé : j’ai vérifié le comportement modifié et renseigné les résultats ci-dessus.
- [ ] Sans secret : le diff ne contient aucun mot de passe, token, clé privée ou autre secret.
- [ ] Prompt journalisé : les prompts utilisés sont consignés dans `PROMPT_LOG.md` ; si aucun outil d’IA n’a été utilisé, je l’ai indiqué ci-dessus.

## Règles de fusion vers `main`

- Toute modification passe par une pull request (PR, équivalent GitHub d’une MR).
- Une approbation d’un autre membre disposant du droit d’écriture est obligatoire, y compris pour l’administrateur. L’auteur ne peut pas approuver sa propre PR.
- Un nouveau commit annule les approbations précédentes : une nouvelle revue est nécessaire.
- Les pushs forcés et la suppression de `main` sont interdits.
