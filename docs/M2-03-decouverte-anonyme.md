# M2-03 · Découverte anonyme

Transport : Multipeer Connectivity (M2-01). Menace couverte : STRIDE I1, S2.

## Principe

Un utilisateur n'est visible que sous un **pseudonyme aléatoire éphémère**. Rien de stable (nom d'appareil, prénom, identifiant fournisseur, UUID persistant) n'est dans `MCPeerID.displayName`, dans `discoveryInfo` ou dans le nom de service.

## Ce qui est diffusé

| Champ | Valeur | Stable ? |
|---|---|---|
| `serviceType` Bonjour | constante de l'app, ex. `proxcall` (≤ 15 car.) | Oui, identique pour tous les utilisateurs : révèle « utilise l'app », pas qui |
| `MCPeerID.displayName` | pseudonyme : 8 octets aléatoires encodés en base32 (13 car.) | **Non** : régénéré |
| `discoveryInfo` | `["v": "1"]` (version de protocole), identique pour tous | Oui, mais non identifiant |
| Alias lisible à l'écran | dérivé du pseudonyme (ex. « Renard-4F2 ») | Non, local |

Jamais : `UIDevice.current.name`, `identifierForVendor`, clés publiques longues durée, position.

## Cycle de vie du pseudonyme

```
lancement de la découverte ──► pseudo = random(8 octets) ──► new MCPeerID(displayName: pseudo)
        │                                                          │
        │   toutes les 10 min si aucun appel en cours              │ annonce + navigation
        ├──────────────────► rotation : stop, nouveau pseudo, restart
        │
fin d'appel / retour au premier plan ──► nouveau pseudo
app tuée ──► le pseudo n'existe plus (jamais écrit sur disque)
```

Règles :

1. Aléa via `SystemRandomNumberGenerator` (CSPRNG d'Apple) ou `SecRandomCopyBytes`. Pas de `Int.random` seedé, pas de dérivation à partir d'un identifiant de l'appareil.
2. **Ne jamais archiver/persister un `MCPeerID`** (usage courant des tutoriels avec `UserDefaults`) : un `MCPeerID` réutilisé est un identifiant stable.
3. Rotation : nouvelle session Multipeer (`MCSession`, advertiser, browser) à chaque nouveau pseudonyme. Pas de rotation pendant un appel.
4. Le pseudonyme n'authentifie personne (M2-06) : deux utilisateurs peuvent entrer en collision, l'UI doit alors se fier au code de vérification.

## Schéma

```
 iPhone A (pseudo a1)                              iPhone B (pseudo b7)
   Advertiser(a1, {v:1}) ─── annonce Bonjour ───►  Browser : voit « a1 »
   Browser : voit « b7 » ◄─── annonce Bonjour ───  Advertiser(b7, {v:1})
                                   │
                      invitation de A vers B (contexte vide)
                      → B : Face ID, accepte (M2-08) → poignée de main (M2-05)
```

L'invitation ne porte aucune donnée dans `context` (pas d'identité, pas de clé) : la poignée de main applicative est la seule source de vérité.

## Preuve qu'aucun identifiant fixe n'est diffusé

Critère d'acceptation de l'issue. À fournir en M3-03 (preuve produite avec l'implémentation) :

1. **Test unitaire** : le générateur de pseudonymes appelé 10 000 fois ne produit pas de doublon et aucun préfixe constant ; aucune dépendance à des API d'identité de l'appareil (revue de code : `grep` interdisant `UIDevice`, `identifierForVendor`, `ProcessInfo.hostName`).
2. **Capture de ce qui est annoncé** sur le Mac de l'équipe : `dns-sd -B _proxcall._tcp` puis `dns-sd -L <nom> _proxcall._tcp local` (ou Wireshark sur l'interface AWDL `awdl0`), sur **deux lancements successifs** de l'app, iPhone fixe : les valeurs annoncées diffèrent à 100 %, et aucune ne contient le nom de l'appareil.
3. **Revue red team** (M3-14) : tentative de relier deux sessions du même iPhone.

## Risques résiduels

- Les identifiants de couche liaison (adresse MAC AWDL/Wi-Fi, adresse Bluetooth) sont gérés par iOS (adresses privées/aléatoires). Non contrôlés par l'app : à observer pendant la capture, pas à promettre.
- Le type de service constant permet de savoir que l'app est utilisée à proximité.
- Un attaquant peut inventer autant de pseudonymes qu'il veut (spam, M3-09).

## Validation : moment de la rotation du pseudonyme (2026-11-20)

Le développeur iOS a restreint la rotation « fin d'appel » : le pseudonyme change à la fin d'un appel **réellement établi** (clés dérivées), ou si une rotation périodique a été reportée pendant l'appel. Il ne change **pas** après un appel refusé, sans réponse, bloqué ou expiré. Raison : sinon un appelant bloqué réapparaîtrait aussitôt sous un nouveau pseudonyme et contournerait le blocage (M3-09, STRIDE D1).

Décision de l'architecte sécurité : **validé, avec cette règle écrite dans la spécification.**

| Règle | Valeur |
|---|---|
| Nouveau pseudonyme | À chaque démarrage ou retour au premier plan, toutes les 10 min hors appel, à la fin d'un appel établi |
| Pas de nouveau pseudonyme | Après refus, absence de réponse, blocage ou délai de demande |
| Fenêtre maximale de corrélation d'un pseudonyme | 10 min (inchangée) |

Impact sur STRIDE I1 (traçage) : **faible**. La durée maximale pendant laquelle un même pseudonyme est visible reste 10 min ; une demande refusée n'expose rien de plus que ce que tout appareil à portée voit déjà pendant cette fenêtre. Le gain est sur D1 (blocage efficace).

Limites assumées : un attaquant qui relance l'app obtient un nouveau pseudonyme (le blocage reste un frein, pas une garantie : la limite globale de M3-09 contient le reste). Un appelant refusé garde son pseudonyme jusqu'à 10 min.
