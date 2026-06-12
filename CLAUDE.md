# Stage Cue

Soundboard Flutter pour déclenchement audio en live (théâtre, streaming, JDR). Architecture Clean, SQLite via Drift, audio via flutter_soloud.

## Stack

- **Flutter** — multi-plateforme, cibles primaires iOS/Android
- **Audio** — flutter_soloud (low-latency, preloading mémoire)
- **DB** — Drift ORM sur SQLite, schéma v23, migrations incrémentales
- **State** — ChangeNotifier custom (`SamplerNotifier` + `SamplerState.copyWith()`)
- **Codegen** — drift_dev + build_runner (requis après tout changement de schéma)

## Architecture

```
lib/
  core/           # Audio engine, DB, theme, utils — infrastructure partagée
  features/
    sampler/
      domain/     # Entités + use cases — Dart pur, zéro Flutter
      data/       # Modèles Drift, datasources, repository
      presentation/ # Screens, widgets, ChangeNotifier providers
```

## Workflows clés

**Après un changement de schéma Drift :**
```sh
flutter pub run build_runner build --delete-conflicting-outputs
```
Voir `.claude/commands/add-migration.md` pour la checklist complète.

**Tests :**
```sh
flutter test
```

**Analyse statique :**
```sh
dart analyze
```

## Conventions

- Noms de fichiers : `snake_case.dart` — classes : `PascalCase`
- Commentaires en français, identifiants de code en anglais
- `const` partout où possible dans les widgets
- Les overrides de pad (nom, couleur, volume) vivent dans la table `pads` — `board_sound_settings` et `board_sounds` n'existent plus depuis v10
- Les use cases sont intentionnellement minces — la logique reste dans le repository ou le domain

## Ce qu'il ne faut pas faire

- Ne pas introduire Riverpod, Bloc ou un autre gestionnaire d'état
- Ne pas modifier les fichiers `*.g.dart` générés — relancer build_runner
- Ne pas jouer un son sans le preloader au préalable (`LoadMode.memory`)
- Ne pas bypasser les migrations Drift — toujours incrémenter `schemaVersion`
- Ne pas ajouter de dépendances sans vérifier `pubspec.yaml` d'abord
