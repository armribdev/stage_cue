# Stage Cue

Stage Cue est une application Flutter de type **soundboard** pour charger, organiser et déclencher rapidement des sons pendant une performance (scène, stream, jeu de rôle, podcast, etc.).

L'application est pensée pour une latence faible, une manipulation rapide, et une organisation claire via des boards et des tags.

## Fonctionnalités

- **Boards multiples** : crée, renomme, supprime et sélectionne des soundboards.
- **Pads audio réactifs** : déclenche/stoppe des sons avec un feedback visuel immédiat.
- **Réorganisation** : réordonne les pads par glisser-déposer.
- **Personnalisation** : nom d'affichage, couleur et volume par son.
- **Volume global** : contrôle du volume master de la board active.
- **Suppression avec annulation** : retire un pad puis annule la dernière suppression.
- **Bibliothèque locale** : persistance avec SQLite via Drift.

## Stack technique

- **Flutter / Dart**
- **Audio** : `flutter_soloud`
- **Base locale** : `drift` + `sqlite3_flutter_libs`
- **Fichiers** : `file_picker`, `path_provider`
- **Permissions** : `permission_handler`

## Prérequis

- Flutter SDK (version compatible avec le `pubspec.yaml`)
- Un device ou un émulateur configuré (`flutter doctor` doit être OK)

## Installation

```bash
flutter pub get
flutter run
```

## Lancer les tests

```bash
flutter test
```

## Structure du projet

```text
lib/
  core/
    app/
    audio/
    database/
    theme/
    utils/
  features/
    sampler/
      data/
      domain/
      presentation/
```

- `core/` contient les briques transverses (app, thème, audio, base locale, utilitaires).
- `features/sampler/` contient le domaine fonctionnel principal de l'app.

## Notes de développement

- La persistance est locale (SQLite), sans backend distant.
- Les fichiers audio sont chargés depuis le système local de l'appareil.
- Le moteur audio privilégie la réactivité au déclenchement.

## Idées d'amélioration

- Sauvegarde/import-export de boards.
- Recherche et filtres avancés dans la bibliothèque sonore.
- Raccourcis clavier et support desktop plus poussé.
- Plus de tests d'intégration UI (chargement, undo, reorder, erreurs).

## Ressources Flutter

- [Documentation Flutter](https://docs.flutter.dev/)
- [Cookbook Flutter](https://docs.flutter.dev/cookbook)
