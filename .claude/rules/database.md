# Drift ORM

## Règle absolue — migrations

Toute modification de schéma (ajout de colonne, nouvelle table, renommage) exige :

1. Incrémenter `schemaVersion` dans `lib/core/database/database.dart`
2. Ajouter le cas correspondant dans `MigrationStrategy.onUpgrade`
3. Relancer le codegen : `flutter pub run build_runner build --delete-conflicting-outputs`

Ne jamais sauter d'étape. La DB des utilisateurs existants sera corrompue sinon.

## Codegen

- Les fichiers `*.g.dart` sont générés — ne pas les éditer manuellement
- Après toute modification de table ou de requête `.drift`, relancer build_runner
- En cas de conflit : `--delete-conflicting-outputs` résout la plupart des cas

## Patterns

- Requêtes custom → `LocalSoundDataSource`, pas directement dans le repository
- Opérations multi-étapes → `database.transaction()`
- Les settings par board sont dans `board_sound_settings` (override), pas dans `board_sounds` (join)
- La table `tag_aliases` permet la recherche normalisée (accents supprimés)
- Ouvrir la base via `NativeDatabase(file)` (isolate principal), **jamais** `createInBackground` : ce dernier bloque la 1re requête au cold start Windows et laisse les boards jamais chargés jusqu'à un hot restart ([0013](../../docs/decisions/0013-ouverture-db-isolate-principal.md))
