# test

## Commandes

```sh
# Tous les tests
flutter test

# Fichier spécifique
flutter test test/features/sampler/domain/usecases/play_sound_usecase_test.dart

# Avec couverture
flutter test --coverage
```

## Structure des tests

```
test/
  features/sampler/
    domain/usecases/        # Tests use cases avec mock repository (mocktail)
    presentation/widgets/   # Tests widgets (PadButton, interactions UI)
```

## Patterns mocktail

- Déclarer les fakes : `class FakeAudioPlayerService extends Fake implements AudioPlayerService`
- Enregistrer les fallback values dans `setUpAll` pour les types custom
- Utiliser `when(() => mock.method()).thenAnswer(...)` pour les futures

## Notes

- Les tests audio utilisent `FakeAudioPlayerService` — pas de vrai moteur audio en test
- Peu de tests widget actuellement — priorité aux tests domain/use cases
