# flutter_soloud

- Toujours preloader les sons avec `LoadMode.memory` avant la lecture (réduit la latence)
- Ne jamais appeler `SoLoud.instance.loadMem` directement — passer par `loadAudioSourceFromFile` / `enqueueSoLoudFileTask`, qui sérialisent tout décodage natif sur une file unique globale (deux accès natifs concurrents plantent sous Windows) ([décision 0001](../../docs/decisions/0001-chargement-audio-soloud.md))
- Les octets sont copiés en mémoire avant lecture : supprimer un fichier du cache disque ne coupe pas une lecture en cours — l'éviction LRU affecte la disponibilité future, pas le son en train de jouer ([décision 0001](../../docs/decisions/0001-chargement-audio-soloud.md))
- Classifier le type **uniquement à l'insertion** via SoLoud (`getLength`) sur le fichier local ; sans fichier téléchargé → `type = null` (colonne nullable depuis v23) ; le type en base ne change jamais sauf via `updateSoundType`
- Valider `soundHandle.isValid()` avant toute opération sur un handle (volume, stop)
- Appeler `soloud.disposeSource(audioSource)` quand un son est supprimé — éviter les fuites
- Le volume master et le volume par son sont indépendants — ne pas les confondre
- Les changements d'état audio arrivent via le stream `onPlayerStateChanged` — ne pas polluer
- Buffer size = 1024 (optimisé low-latency) — ne pas augmenter sans profiling
- En Mode Spectacle (mode live), `_pickSoundIndex` ignore `playMode` et priorise le son le moins joué de la session (`SamplerNotifier.isLiveSessionActive` / `sessionPlayCountFor`) — voir [décision 0014](../../docs/decisions/0014-priorite-au-son-le-moins-joue-en-mode-live.md). Le compteur n'est incrémenté que par `_markPlayedAt` (lecture réelle), jamais par `_markPlayed` seul (pré-écoute) — ne pas déplacer l'incrément
