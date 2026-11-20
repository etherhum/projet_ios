# M2-06 · Authentification du pair sans compte

Sans compte ni serveur, rien ne prouve *a priori* qui est le pair. Le seul canal de confiance est **humain et hors bande** : les deux utilisateurs sont physiquement proches. On y ancre l'authentification par la **vérification d'une empreinte de la session** (M2-05).

## Mécanisme : code court de vérification (SAS)

Après la poignée de main, chaque appareil calcule le même code :

```
sas_bytes = HKDF-expand("proxcall/v1/sas", 3 octets)   (dérivé du secret ET du transcript T)
code      = (UInt24(sas_bytes) mod 1 000 000), affiché sur 6 chiffres  ex. « 482 915 »
```

Si un attaquant s'est interposé, il a établi **deux sessions distinctes** (une avec chaque victime) : les deux codes affichés sont **différents**. Les utilisateurs se lisent leur code ; s'ils diffèrent, l'appel est refusé.

Sécurité : l'engagement de l'étape 1 (M2-05) force l'attaquant à fixer sa clé avant de connaître celle de la victime ; il ne peut donc pas « fabriquer » deux clés qui donnent le même code. Probabilité de réussite par tentative ≈ 1 / 10⁶ (≈ 20 bits). Les clés étant éphémères, chaque tentative impose une **nouvelle session visible** (les victimes voient l'appel échouer) : pas de recherche hors ligne.

## Variante QR (recommandée en face à face)

L'appelant affiche un QR, l'appelé le scanne avec la caméra de l'app :

- Contenu du QR : `v ‖ SHA256(pkI ‖ nonceI)` = l'engagement C de l'étape 1, transmis **hors bande par la lumière**.
- L'appelé compare C reçu par radio avec C scanné. Un MitM ne peut pas modifier C sans que ça se voie.

Le QR nécessite la permission caméra (moindre privilège : **demandée seulement si l'utilisateur choisit le QR**). Le code à 6 chiffres reste le mode par défaut et suffisant.

| Mode | Avantage | Inconvénient |
|---|---|---|
| **Code 6 chiffres (défaut)** | Aucune permission, fonctionne à voix haute ou en regardant les deux écrans | Dépend de l'attention humaine |
| QR | Automatique, moins d'erreurs | Permission caméra, les deux doivent se voir |

## Flux

```
 Appelant I                                 Appelé R
   │ appel accepté (Face ID chez R), poignée de main M2-05 terminée
   ├─ affiche « 482 915 » ───────── comparaison orale / visuelle ───────── affiche « 482 915 »
   │   [Identiques]  [Différents]                          [Identiques]  [Différents]
   │        │               │                                   │              │
   │   « Identiques » des 2 côtés ⇒ chacun envoie CONTROL SAS_OK (chiffré)
   │   audio ouvert seulement quand SAS_OK local envoyé ET SAS_OK distant reçu
   │   « Différents » ou délai dépassé (30 s) ⇒ fermeture de session, clés effacées
```

Règles d'échec en sécurité : le micro n'est **pas capturé** et aucun audio n'est joué avant confirmation des deux côtés ; défaut de réponse = refus.

## Ce que la vérification prouve (et ne prouve pas)

- Prouve : « la personne en face de moi partage la même session que moi » (pas de MitM sur cet appel).
- Ne prouve pas l'**identité civile** : l'app est anonyme. Pas de persistance : on revérifie à chaque appel (pas de « contact de confiance »).
- Le code est spécifique à la session : inutilisable ensuite, non rejouable.

## Menace STRIDE couverte

**S1 Usurpation / MitM** et S2 (pseudonyme usurpé), T2 (poignée de main altérée) : cf. M1-07.

Test de validation prévu (M3-06) : simuler un MitM local (deux sessions) et vérifier que les deux codes diffèrent.
