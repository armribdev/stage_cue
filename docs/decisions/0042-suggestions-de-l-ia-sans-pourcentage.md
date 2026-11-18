# 0042 — Suggestions de l'IA : l'ordre par score, sans pourcentage affiché

**Statut :** acceptée (amende [0031](0031-tags-de-l-ia-en-suggestions-avec-score.md))
**Date :** 2026-11-18

## Contexte

[0031](0031-tags-de-l-ia-en-suggestions-avec-score.md) affichait chaque suggestion avec son score (« Triste 38 % »). Ce score est la part d'une ambiance dans un softmax sur 15 ambiances : une confiance relative, qui dépend de la bibliothèque, et que le chiffre fait lire comme « 38 % de chances d'être juste ». Un vrai pourcentage demande une vérité terrain : les modèles zéro-shot (MuLan, CLAP) sortent des similarités cosinus, et même les têtes supervisées (Essentia, AudioSet) se règlent par tag sur un jeu de validation. Aucun jeu étiqueté n'est disponible ici.

## Décision

- **Le pourcentage n'est plus affiché.** La pastille d'une suggestion de l'IA ne montre que le nom du tag, comme celles déduites du titre ([0041](0041-tags-deduits-du-titre-calcules-a-la-volee.md)).
- **L'ordre reste celui du score**, décroissant (`LocalTagDataSource`). Le score est toujours calculé (`MoodTagRule`), stocké dans `sound_auto_tags.score` et synchronisé : il sert au classement et à une future calibration.
- Aucun changement de schéma, de snapshot ni de règle de sélection (z ≥ 1,0, 3 suggestions au plus, rien avant 50 sons analysés).

## Alternatives écartées

- **Un niveau (fort / moyen / faible)** — même fausse précision que le pourcentage, avec des seuils tout aussi arbitraires.
- **Un vrai pourcentage maintenant** — impossible sans étiquettes ; voir la piste de calibration d'après l'usage dans `docs/tags.md`.

## Conséquences

- Si le taux d'acceptation par tranche de score (ligne de `sound_auto_tags` + présence du tag dans `sound_tags`) devient mesurable, on pourra réafficher une valeur qui veut dire quelque chose ; cela demandera un nouvel ADR.
- `TagPill.meta`, devenu inutilisé, est supprimé.
