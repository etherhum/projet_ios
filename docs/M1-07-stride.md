# M1-07 · Modèle de menaces STRIDE

Actifs A1–A7 et attaquants T1–T4 : voir M1-06. Références de conception : M2-03 à M2-09. Statut des contre-mesures : **prévue** (conception) ; elle passe à « implémentée / testée » en M3.

## S · Usurpation (Spoofing)

| ID | Menace | Impact | Contre-mesure prévue |
|---|---|---|---|
| S1 | Un attaquant s'interpose entre deux iPhones (homme du milieu) pendant l'échange de clés et se fait passer pour le pair | Écoute et altération de l'appel (A1) | Engagement (hash des clés) puis **code de vérification à comparer** entre les deux humains (M2-05, M2-06). Audio refusé tant que les deux n'ont pas confirmé |
| S2 | Un utilisateur adopte le pseudonyme d'un autre dans la liste de découverte | Appel destiné à X reçu par un imposteur | Le pseudonyme n'est **pas une identité** : il n'authentifie rien. L'authentification se fait par le code de vérification, hors bande (M2-06) |

## T · Altération (Tampering)

| ID | Menace | Impact | Contre-mesure prévue |
|---|---|---|---|
| T1 | Modification d'un paquet audio en transit | Audio falsifié (A1) | AES-GCM : tag d'authentification de 16 octets, en-tête en données authentifiées (AAD) ; paquet invalide ⇒ rejet (M2-07) |
| T2 | Modification des messages de poignée de main (clé publique remplacée) | Clé de session contrôlée par l'attaquant | Transcript de la poignée de main dans la dérivation HKDF et dans le code de vérification ; toute altération ⇒ codes différents ⇒ appel refusé (M2-05) |

## R · Répudiation

| ID | Menace | Impact | Contre-mesure prévue |
|---|---|---|---|
| R1 | « Ce n'est pas moi qui ai appelé / accepté l'appel » | Litige, absence de preuve | **Choix assumé : répudiation possible**. Pas de journal signé, pas d'identité persistante : l'anonymat prime sur la non-répudiation (M2-08). Documenté comme compromis |
| R2 | Un pair prétend ne jamais avoir envoyé un paquet, ou un attaquant prétend l'avoir fait au nom d'un pair | Contestation du contenu | Authentification **symétrique** (AES-GCM, clé partagée) : chaque pair peut forger les messages de l'autre, donc rien n'est opposable à un tiers. Voulu : déni plausible. Aucun enregistrement conservé |

## I · Divulgation d'information (Information disclosure)

| ID | Menace | Impact | Contre-mesure prévue |
|---|---|---|---|
| I1 | Annonce BLE / Bonjour contenant un identifiant stable ou le nom de l'appareil | Traçage d'une personne entre deux sessions (A3, A4) | Pseudonyme aléatoire régénéré à chaque session, `MCPeerID` jamais réutilisé, `discoveryInfo` constant (M2-03) |
| I2 | Secrets, clés, pseudonymes ou contenu dans les logs et la console | Fuite (A1, A2, A5) | Logs sans donnée sensible, niveau `private` d'`os.Logger` (M3-12) |
| I3 | Aperçu multitâche ou capture d'écran montrant l'écran d'appel | Fuite visuelle (A5) | Masquage au passage en arrière-plan (M3-11) |
| I4 | Clés de session récupérables en mémoire ou sur disque après l'appel | Déchiffrement d'une capture passée (A1) | Clés éphémères par session (confidentialité persistante), aucun stockage, effacement en fin d'appel (M3-10, M3-11) |

## D · Déni de service (Denial of service)

| ID | Menace | Impact | Contre-mesure prévue |
|---|---|---|---|
| D1 | Inondation de demandes d'appel / d'invitations par un utilisateur à proximité | App inutilisable, harcèlement (A6) | Limitation de débit par pseudonyme et globale, blocage temporaire, refus silencieux (M3-09) |
| D2 | Flot de paquets invalides ou de poignées de main incomplètes | Saturation CPU, appel coupé | Rejet immédiat avant toute opération coûteuse (taille, version, fenêtre de compteur), délai maximal de poignée de main, une seule session active (M2-07) |

## E · Élévation de privilèges (Elevation of privilege)

| ID | Menace | Impact | Contre-mesure prévue |
|---|---|---|---|
| E1 | Appel accepté, micro ouvert, sans passer par Face ID (iPhone déverrouillé laissé à un tiers, contournement du flux) | Écoute non voulue (A6) | Face ID / code exigé à l'acceptation de l'appel (M2-08) ; micro et audio activés seulement après confirmation du code des deux côtés |
| E2 | Paquet malformé exploitant le parseur pour exécuter du code ou forcer un état « session ouverte » | Prise de contrôle | Parseur strict à longueurs fixes, aucune désérialisation d'objets (pas de `NSKeyedUnarchiver` sur des données reçues), machine à états qui échoue en sécurité (M3-08, M3-10) |
| E3 | Permissions iOS excessives (Bluetooth, localisation, contacts) | Surface d'attaque, atteinte à la vie privée | Moindre privilège : micro (au premier appel) et réseau local uniquement (M3-02) |

## Menaces résiduelles acceptées

- Un attaquant qui obtient du même utilisateur **une comparaison de code faite sans attention** gagne la partie sur S1 : facteur humain, atténué par un code court, lisible, et un message explicite.
- Analyse de trafic : un observateur radio voit qu'un flux chiffré existe et sa durée.
- Les identifiants de couche liaison (MAC AWDL) sont gérés par iOS : non maîtrisés, à auditer par la red team.
