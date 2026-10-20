# Journalisation

- Tout log passe par `SyncLog` / `AudioLoadLog` / `UpdateLog` / `AppLog` (canaux `Sync`, `Audio`, `Update`, `App`), jamais `debugPrint` brut : seul le journal fichier (`lib/core/logging/log_sink.dart`) est lisible en release ([0025](../../docs/decisions/0025-journal-fichier-persistant.md))
- `LogSink.log` est synchrone, sans E/S, et ne lève jamais : ne jamais y ajouter d'`await`, d'écriture synchrone ni de dépendance bloquante sur le chemin d'un déclenchement de pad
- Une ligne par **événement**, jamais par fichier / frame / pad en boucle ; le détail haute fréquence va dans `trace` (muet sauf `--dart-define=STAGE_CUE_*_TRACE=true`). Une cause qui se répète : `AudioLoadLog.warnOnce` / `_once`, ou une fenêtre de déduplication
- Ne jamais logguer de jeton, de contenu de credentials ni d'adresse e-mail : `LogRedactor` est un filet de sécurité, pas une autorisation. Pour l'auth Drive on journalise l'événement (connexion, déconnexion, rejet), pas l'identité
- Un déclenchement de pad qui ne joue rien doit passer par `reportPadTriggerFailure` (raison explicite) — ne pas laisser un `return` silencieux
- Ne pas déplacer l'incrément `_markPlayedAt` (cf. `audio.md`) en ajoutant un log de lecture
