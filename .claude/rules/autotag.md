# Analyse automatique des tags

Cadre : [0029](../../docs/decisions/0029-analyse-automatique-des-tags-sur-l-appareil.md). Code : `lib/core/autotag/`.

- L'analyse ne touche **jamais** un son traité, déjà tagué, ou qui n'est pas de type musique, et ne marque **jamais** un son traité : le son reste « à valider ». L'éligibilité se revérifie au moment de poser les tags (`LocalAutoTagDataSource.applyDecisions`), pas seulement au moment de l'analyse
- Elle ne s'orchestre que depuis `AutoSyncCoordinator` (après le pull, jamais dans un écran) et s'arrête en Mode Spectacle, en arrière-plan ou pendant une passe de synchro. Ne rien ajouter qui s'exécute sur le chemin d'un déclenchement de pad
- Inférence : **uniquement** via `OnnxSession`/`MuqAnalyzer` (isolate de travail). L'API Dart de `flutter_onnxruntime` gèle le thread de l'interface pendant l'inférence (≈ 410 ms/clip mesurés) — le paquet ne sert qu'à embarquer la bibliothèque native
- Décodage : uniquement via `decodeAnalysisClips` (symbole natif appelé directement, tampons libérés, file ADR 0001 tenue ≈ 100 ms par clip). `test/core/autotag/pcm_decoder_test.dart` échoue si le comportement détourné de flutter_soloud change : ne pas l'ignorer, ne pas élargir le décodeur sans lui ajouter un cas
- Un tag posé automatiquement doit déjà exister (catalogue EMOTION_STYLE) : l'analyse ne crée aucun tag. `kMoods` suit l'ordre des lignes de `assets/autotag/text_latents.f32`
- Les statistiques de recentrage portent sur **toutes** les empreintes (`sounds.auto_embedding`), pas seulement les sons éligibles ; `auto_tagged_at` signifie « décision prise (tags posés ou non) », pas « tags posés »
- Le pack (`AutoTagPackRelease`) porte en dur adresse, taille et SHA-256 : changer de modèle = nouveau pack publié + nouvelle version de l'app. Un fichier au nom final dans le dossier du pack est toujours complet (`.part` puis renommage)
- Journaliser via `AppLog` (une ligne par événement : démarrage, bilan, raison d'arrêt) et `AudioLoadLog.trace` pour le détail par fichier. Licence : modèles CC BY-NC → usage non commercial, attribution affichée dans Paramètres
