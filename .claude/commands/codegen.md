# codegen

Régénère les fichiers Drift après un changement de schéma ou de requête.

## Quand l'utiliser

- Après modification de tables dans `lib/core/database/database.dart` ou `lib/core/database/sounds.dart`
- Après ajout ou modification d'une requête `.drift`
- Quand les `*.g.dart` sont désynchronisés (erreurs de type inattendues)

## Commande

```sh
flutter pub run build_runner build --delete-conflicting-outputs
```

## Vérification post-codegen

```sh
dart analyze
```

S'il reste des erreurs dans les `*.g.dart`, vérifier que `schemaVersion` a bien été incrémentée et que `onUpgrade` couvre le nouveau cas.
