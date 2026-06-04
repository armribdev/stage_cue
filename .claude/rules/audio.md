# flutter_soloud

- Toujours preloader les sons avec `LoadMode.memory` avant la lecture (réduit la latence)
- Valider `soundHandle.isValid()` avant toute opération sur un handle (volume, stop)
- Appeler `soloud.disposeSource(audioSource)` quand un son est supprimé — éviter les fuites
- Le volume master et le volume par son sont indépendants — ne pas les confondre
- Les changements d'état audio arrivent via le stream `onPlayerStateChanged` — ne pas polluer
- Buffer size = 1024 (optimisé low-latency) — ne pas augmenter sans profiling
