# M4-05 · Triage des failles reçues (gabarit)

À remplir à la réception du rapport de l'autre groupe (M4-04). Une ligne par faille. Tableau à faire valider par l'équipe.

## Échelle

- **Gravité** : Critique (compromet audio ou clés), Haute (contourne une authentification ou la vie privée), Moyenne (déni de service, fuite limitée), Faible (durcissement).
- **Priorité de correction** : P1 avant la démo, P2 si le temps le permet, P3 documentée et acceptée.
- **Lien STRIDE** : S, T, R, I, D ou E avec l'identifiant de M1-07 (ex. I2).
- **Domaine MASVS** : STORAGE, CRYPTO, AUTH, NETWORK, PLATFORM, CODE, RESILIENCE ou PRIVACY.

## Tableau

| # | Faille (rapport) | Reproductible ? | Gravité | STRIDE | MASVS | Cause | Priorité | Correctif / décision | Issue |
|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | |

## Règles

1. Une faille n'est classée « non reproductible » qu'après une tentative par l'architecte et le développeur iOS.
2. Toute faille sur la cryptographie ou l'authentification est au minimum P1.
3. Un risque accepté (P3) est justifié par écrit et reporté dans le dossier (M4-07).
4. Chaque correctif repasse par la boucle du sujet : spécifier, générer, relire, tester, attaquer.
