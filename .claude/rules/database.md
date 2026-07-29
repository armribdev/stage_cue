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
- Ne pas retirer les `PRAGMA journal_mode = WAL` / `synchronous = NORMAL` du `beforeOpen` : sans eux la base retombe silencieusement aux défauts SQLite (rollback journal + double fsync par transaction), ce que `test/core/database/journal_mode_test.dart` détecte — il doit tourner sur une base **fichier**, une base mémoire ignore WAL sans erreur ([0018](../../docs/decisions/0018-journalisation-wal-et-synchronous-normal.md))
- `ensureFolder`, `ensureMembership` et `syncLibrarySoundFromDriveIndex` ne sont plus que des **façades à une entrée** sur leurs variantes en masse (`ensureFolders`, `ensureMemberships`, `syncLibrarySoundsFromDriveIndex`), qui préchargent l'existant. Les appeler en boucle sur un scan est quadratique — pour traiter un lot, passer par la variante en masse. Ne pas réintroduire d'implémentation unitaire séparée : deux jeux de règles de rapprochement finiraient par diverger
