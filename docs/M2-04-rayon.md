# M2-04 · Estimation du « rayon »

## Méthode retenue

Le transport est Multipeer Connectivity seul (cf. M2-01). Multipeer **n'expose pas** la puissance du signal (RSSI) ni la distance.

Le « rayon » est donc **défini par la portée radio** :

> Un utilisateur apparaît dans la liste ⇔ son iPhone est joignable directement (Wi-Fi pair-à-pair AWDL ou Bluetooth), sans relais ni Internet.

L'app affiche « à proximité » sans distance chiffrée.

## Précision attendue

| Environnement | Portée typique observée |
|---|---|
| Extérieur dégagé | ~30 m, parfois plus |
| Intérieur, même pièce / pièces voisines | ~10–20 m |
| À travers murs porteurs / étages | quelques mètres, ou rien |

Valeurs indicatives : à mesurer sur nos 2 iPhones et à reporter dans le journal.

## Limites assumées

- **Pas de distance** : on ne sait pas distinguer 2 m de 25 m.
- **Rayon non réglable** par l'utilisateur.
- **Variabilité** : corps humain, murs, interférences 2,4/5 GHz changent fortement la portée.
- **Asymétrie** : A peut voir B un instant avant que B voie A.
- **Pas de garantie de présence physique** : un attaquant avec une antenne plus puissante peut paraître « proche ». Le rayon n'est **pas** un mécanisme de sécurité ; l'authentification repose sur la vérification d'empreinte (M3-06).

## Alternative écartée

Une annonce BLE complémentaire donnerait le RSSI (estimation grossière, ±plusieurs mètres), au prix de la permission Bluetooth et d'un deuxième canal à anonymiser. Écartée au nom du moindre privilège ; réévaluable si le besoin d'un rayon chiffré apparaît.

## Vie privée

Aucune estimation de distance ou de position n'est calculée, stockée ou journalisée (cf. M3-12).
