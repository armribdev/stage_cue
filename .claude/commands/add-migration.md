# add-migration

Checklist pour ajouter une migration de schéma Drift sans casser les bases existantes.

## Étapes

**1. Modifier le schéma** dans `lib/core/database/database.dart` ou `lib/core/database/sounds.dart`

**2. Incrémenter la version** dans `AppDatabase` :
```dart
@override
int get schemaVersion => 10; // était 9
```

**3. Ajouter le cas de migration** dans `MigrationStrategy.onUpgrade` :
```dart
onUpgrade: (m, from, to) async {
  if (from < 10) {
    await m.addColumn(sounds, sounds.newColumn);
    // ou : await m.createTable(newTable);
  }
},
```

**4. Régénérer le code** :
```sh
flutter pub run build_runner build --delete-conflicting-outputs
```

**5. Vérifier** :
```sh
dart analyze
flutter test
```

## Checklist avant commit

- [ ] `schemaVersion` incrémentée
- [ ] Cas `onUpgrade` ajouté pour la nouvelle version
- [ ] `onCreate` toujours cohérent avec le schéma final
- [ ] build_runner relancé, `*.g.dart` à jour
- [ ] `dart analyze` sans erreurs
- [ ] Tests passent

## Pattern pour nouvelles tables

```dart
if (from < 10) {
  await m.createTable(newTable);
}
```

Les nouvelles tables doivent aussi être dans le callback `onCreate` pour les installations fraîches.
