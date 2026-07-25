# Stage Cue

Stage Cue est une application Flutter de type **soundboard** pour charger, organiser et déclencher rapidement des sons pendant une performance (scène, stream, jeu de rôle, podcast, etc.).

L'application est pensée pour une latence faible, une manipulation rapide, et une organisation claire via des boards et des tags.

## Fonctionnalités

- **Boards multiples** : crée, renomme, supprime et sélectionne des soundboards.
- **Pads audio réactifs** : déclenche/stoppe des sons avec un feedback visuel immédiat, y compris des multipads (plusieurs sons par pad, alternance aléatoire/séquentielle).
- **Réorganisation** : réordonne les pads par glisser-déposer.
- **Personnalisation** : nom d'affichage, couleur et volume par son.
- **Volume global** : contrôle du volume master de la board active.
- **Suppression avec annulation** : retire un pad puis annule la dernière suppression.
- **Bibliothèque locale** : persistance avec SQLite via Drift.
- **Synchronisation Google Drive** : bibliothèque de sons et boards synchronisés entre appareils, cache local avec éviction LRU (favoris et plateau actif épinglés).
- **Mode Spectacle** : mode live qui priorise le son le moins joué de la session sur les multipads, pour éviter la répétition pendant une représentation.
- **Sortie cue séparée (desktop)** : pré-écoute sur un device audio distinct de la sortie « salle », pour préparer le prochain son sans le diffuser au public.
- **Recherche rapide** : recherche-éclair dans la bibliothèque avec placement automatique sur le plateau.

## Stack technique

- **Flutter / Dart**
- **Audio** : `flutter_soloud` (moteur principal), `media_kit` (routage cue desktop uniquement)
- **Base locale** : `drift` + `sqlite3_flutter_libs`
- **Synchronisation** : Google Drive (`googleapis`, `google_sign_in`)
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

- La persistance est locale (SQLite), avec synchronisation optionnelle via Google Drive.
- Les fichiers audio sont mis en cache localement (éviction LRU) et chargés depuis ce cache.
- Le moteur audio privilégie la réactivité au déclenchement.

## Idées d'amélioration

- Sauvegarde/import-export de boards (indépendant de la sync Drive).
- Filtres avancés dans la bibliothèque sonore (au-delà de la recherche rapide existante).
- Raccourcis clavier.
- Plus de tests d'intégration UI (chargement, undo, reorder, erreurs).

## Ressources Flutter

- [Documentation Flutter](https://docs.flutter.dev/)
- [Cookbook Flutter](https://docs.flutter.dev/cookbook)
