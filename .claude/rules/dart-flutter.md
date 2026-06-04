# Dart / Flutter

- Utiliser `const` pour tous les constructeurs de widgets stateless
- Vérifier `mounted` avant tout `setState`, `showDialog`, ou navigation après un `await`
- Disposer les streams, controllers et sources audio dans `dispose()`
- Préférer `async`/`await` aux chaînes `.then()` brutes
- Éviter le `!` (force-unwrap) — préférer `??`, `if (x != null)`, ou les null checks explicites
- Les `BuildContext` ne doivent pas traverser des gaps asynchrones sans guard `mounted`
- Nommer les paramètres nommés explicitement — pas de positionnels pour plus de 2 arguments
