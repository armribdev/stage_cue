# 0051 — Multipads enregistrés dans la bibliothèque, par copie

**Statut :** acceptée
**Date :** 2026-11-20

## Contexte

Un multipad (plusieurs sons, tirage aléatoire sans répétition) donne déjà la variété voulue pour un bruitage comme « porte qui grince ». Mais il faut le reconstituer à la main sur chaque plateau, son par son. L'opérateur veut le ranger dans la bibliothèque, le retrouver par son nom en cherchant un bruitage, et le gérer à un endroit dédié.

## Décision

Un multipad se **sauvegarde dans la bibliothèque comme un modèle** (`saved_multipads` + `saved_multipad_sounds`, v52) : nom, couleur, mode de lecture, sons dans l'ordre. Le poser sur un plateau crée un **pad ordinaire, copie du modèle** ; modifier ce pad ne change pas le modèle, modifier le modèle ne change pas les pads déjà posés.

- Les sons ne sont jamais dupliqués : le modèle ne référence que leurs ids, donc gain, waveform et fichier restent ceux de la bibliothèque.
- Le sélecteur de sons les propose en tête de liste (recherche-éclair avec une requête, mode bibliothèque), filtrés comme les sons (périmètre du plateau, type, hors-ligne) sur l'ensemble de leurs sons. Entrée, un clic (sauf en Mode Spectacle) ou le bouton de fin de ligne posent une copie ; jamais de lecture directe depuis la recherche.
- Création : « Enregistrer dans la bibliothèque » dans les détails d'un multipad. Gestion (renommer, couleur, mode, sons et ordre, suppression) : écran « Multipads enregistrés », ouvert depuis la gestion de la bibliothèque. L'édition est explicite (Enregistrer / Annuler), pas à la volée.
- Supprimer un son retire ce son des modèles (déclencheur de cascade, ADR 0032) ; un modèle devenu vide reste listé en gestion pour être complété ou supprimé, jamais proposé à la pose.
- **Synchro Drive (v53).** Un modèle prend la bibliothèque du plateau d'où il est enregistré (`saved_multipads.library_id` ; plateau local = modèle local, jamais publié). Il voyage dans le snapshot **racine** avec les boards : sons par `driveFileId` puis `relativePath`, résolus après les snapshots de dossiers ; fusion par `multipad_key` (UUID), dernier écrivain gagnant (`updated_at`), sans purge ; un modèle local sans propriétaire est rattaché à la bibliothèque qui publie sa clé ; un modèle dont aucun son n'est résolu n'est pas écrit (le prochain pull réessaie) et un modèle distant plus récent mais sans son résolu ne remplace pas le local.
- **Suppression : pierre tombale.** Supprimer un modèle rattaché à une bibliothèque écrit une trace (`saved_multipad_tombstones`, clé + date), publiée avec le snapshot et conservée par chaque appareil qui la reçoit (pour la republier). Sans elle, l'union ferait revenir un modèle supprimé depuis un appareil en retard. Une trace supprime le modèle visé s'il n'a pas été modifié depuis ; un modèle modifié **après** la suppression survit, et le modèle republié plus récent que la trace la fait tomber.

## Alternatives écartées

- **Groupe vivant référencé par les pads** (`pads.group_id`, sons résolus au chargement) — un seul endroit où corriger, mais un pad ne porterait plus ses propres sons, la fusion de synchro devrait arbitrer des liens entre appareils, et modifier un modèle changerait des plateaux sans qu'on y touche. Écarté : l'opérateur veut qu'un pad modifié sur le plateau n'altère pas le modèle.
- **Réutiliser les tags** — le catalogue de tags fait foi (ADR 0046) et n'est pas créé par l'utilisateur ; un tag désignerait un ensemble de sons sans ordre ni mode de lecture.

## Conséquences

- Le sélecteur de sons ne manipule plus seulement des `Sound` : les lignes de modèles précèdent celles des sons, et un indice de ligne `< _multipadResults.length` désigne un modèle. Tout nouveau mode qui affiche des résultats doit décider s'il les propose.
- L'index de recherche (ADR 0017) porte les modèles : toute écriture sur eux passe par `SamplerNotifier` (`saveMultipadToLibrary`, `updateSavedMultipad`, `deleteSavedMultipad`), qui invalide l'instantané.
- Le périmètre **d'affichage** d'un modèle (sélecteur) se déduit de ses sons, pas de `library_id`, qui ne sert qu'à la publication. Les traces de suppression ne sont jamais purgées (quelques dizaines d'octets) ; elles disparaissent avec la bibliothèque.
- Un appareil antérieur à la v53 ignore ces tables et republie un snapshot racine sans elles : les autres appareils gardent leurs modèles (la fusion ne supprime jamais sur absence). Le seul angle mort est une suppression faite pendant qu'un tel appareil publie en dernier ; elle est rejouée au prochain push d'un appareil à jour.
