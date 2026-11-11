# 0037 — Mode réseau binaire : c'est le Mode Spectacle qui masque les pads injouables

**Statut :** acceptée
**Date :** 2026-11-12

## Contexte

Le réglage « Mode réseau » avait trois valeurs : Connecté, Hors ligne et Live. Elles fusionnaient deux questions indépendantes — « le réseau est-il autorisé ? » (seul Connecté disait oui) et « masque-t-on les pads sans fichier local ? » (seul Live disait oui). Live faisait double emploi avec le Mode Spectacle, qui verrouille déjà l'édition, suspend la synchro auto, démarre la session live ([0014](0014-priorite-au-son-le-moins-joue-en-mode-live.md)) et propose un bilan de préparation avant d'entrer. Le masquage s'appliquait aussi en édition (grille et détail d'un pad), là où il n'a pas de sens, et le défaut d'une installation neuve était Live, donc sans synchro.

## Décision

`ConnectivityMode` n'a plus que deux valeurs, `connected` et `offline`, et ne commande que le réseau (`allowsNetworkSync`, `allowsSoundDownload`). Le masquage des pads sans son en cache, l'arrêt de leur lecture et la coupure des téléchargements suivent **le Mode Spectacle** (`SamplerNotifier.isLiveSessionActive`), quel que soit le mode réseau.

## Alternatives écartées

- **Garder trois états en renommant « Live »** — le recouvrement avec le Mode Spectacle reste : deux notions de « scène » à régler avant de jouer, et le masquage continue de gêner l'édition.
- **Deux réglages indépendants (réseau + « masquer les pads injouables »)** — expose la quatrième combinaison (réseau actif, pads masqués hors spectacle) sans cas d'usage, et ajoute un réglage à penser avant chaque soirée. Le Mode Spectacle est déjà le geste qui dit « je suis en scène ».
- **Laisser les téléchargements possibles en Mode Spectacle quand on est connecté** — un fichier tiré de Drive au déclenchement d'un pad ajoute une latence réseau imprévisible en scène. Le bilan d'entrée existe précisément pour télécharger **avant** de verrouiller l'écran.

## Conséquences

- **`live_offline` est lu comme `offline`** (`ConnectivityModeUi.fromStorageKey`) : un utilisateur qui était en Live garde un réseau coupé, et retrouve le masquage en entrant en Mode Spectacle. Le fichier `app_preferences.json` n'est pas réécrit tant qu'il ne change pas le réglage, et un ancien exécutable relit `offline` sans problème.
- **Le défaut reste « réseau coupé »** (`offline`) : aucune bibliothèque n'est tirée tant que l'utilisateur n'a pas choisi Connecté. Changer ce défaut est une décision produit à part.
- **`allowsSoundDownload` du notifier combine réseau et session** : ne pas lire `AppPreferences.allowsSoundDownload` directement dans l'UI, on contournerait la coupure du Mode Spectacle.
- **`startLiveSession` applique les contraintes de scène** (file de téléchargement annulée, musique/ambiance/file dont le pad est masqué arrêtées, numéros de multipads recalculés) et `endLiveSession` rend les numéros. Toute nouvelle règle « pas jouable en scène » s'y rattache, pas à un réglage réseau.
- L'écran de détail d'un pad n'est plus filtré : il est inaccessible en Mode Spectacle (édition verrouillée), donc le filtre ne faisait que cacher des sons pendant l'édition.
