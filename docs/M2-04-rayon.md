# M2-04 · Estimation du « rayon »

## Constat

L'issue demande une estimation par puissance du signal (RSSI). Or le transport retenu (Multipeer Connectivity, M2-01) **n'expose pas le RSSI** : seul CoreBluetooth le fournit, au prix d'une permission Bluetooth supplémentaire et d'un second canal d'annonce à anonymiser.

## Décision pour le MVP

> **Le « rayon » est la portée du lien Multipeer elle-même** : un pair n'est listé que s'il est atteignable par le lien direct iOS (≈ 10–30 m, selon obstacles). L'app n'affiche **ni distance, ni rang de proximité** : seulement « à portée ».

| Option | Méthode | Verdict |
|---|---|---|
| **A. Portée du lien (retenue)** | Un pair apparaît/disparaît selon `foundPeer` / `lostPeer` | Simple, aucune permission en plus, pas de faux sentiment de précision |
| B. RSSI BLE | Scan BLE, conversion RSSI → distance | **Reportée** (hors MVP) : permission Bluetooth, 2ᵉ canal d'annonce, précision médiocre (voir ci-dessous) |
| C. Temps de trajet (RTT) | Ping authentifié sur le lien | Rejetée : mesure la charge radio, pas la distance |
| D. GPS | Position de chaque appareil | Rejetée : donnée de localisation sensible, contraire à la minimisation (M1-08) |

## Précision attendue et limites (à assumer)

- **Précision** : un seul niveau, « à portée / hors portée ». Marge : la portée réelle varie du simple au triple selon murs, corps, interférences, modèle d'iPhone.
- Si B est ajoutée plus tard : RSSI → distance par modèle log-distance, erreur typique de **plusieurs mètres**, instable (orientation, main qui masque l'antenne, puissance d'émission différente selon l'appareil, multi-trajets). On n'afficherait que 2–3 niveaux (« très proche / proche / lointain ») avec moyenne glissante, jamais une valeur en mètres.
- **Falsifiable** : un attaquant avec une antenne plus puissante paraît plus proche qu'il n'est ; un attaquant discret avec une faible puissance semble plus loin. Le rayon est **une aide d'interface, pas une frontière de sécurité** : la sécurité repose sur le chiffrement et la vérification du pair, jamais sur « il est proche donc il est de confiance ».
- Aucune position n'est calculée ni stockée (RGPD, M1-08).

## Impact sur les issues

- M3-03 : liste des pairs = pairs Multipeer vus, avec retrait à `lostPeer`.
- À valider avec le développeur iOS (rôle partagé de l'issue) : si l'équipe souhaite tout de même un indicateur de proximité, ouvrir une issue pour l'option B avec mise à jour de M2-01, M2-03 (annonces BLE anonymes) et STRIDE.
