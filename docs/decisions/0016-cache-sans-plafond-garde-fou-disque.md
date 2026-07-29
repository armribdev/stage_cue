# 0016 — Cache local sans plafond fixe, garde-fou par espace disque réel

**Statut :** acceptée
**Date :** 2026-07-27

## Contexte

`maxCacheBytes` (2 Go par défaut, non configurable) plafonnait le cache local par une éviction LRU déclenchée dès que le total des tailles trackées dépassait cette valeur fixe. Dès qu'une bibliothèque dépasse ce chiffre arbitraire (constaté : 1128 sons pour ~2.8 Go), le bouton « Tout télécharger » (`downloadAllLibraryAudio`) n'atteint jamais son but : chaque nouveau fichier téléchargé fait évincer un ancien son non épinglé (cf. [0010](0010-epinglage-lru-favoris-et-plateau-actif.md)), donc le nombre de sons disponibles hors-ligne plafonne bien en-dessous du total et semble « repartir de zéro » à chaque relance. Pour un soundboard de live, l'attente réelle est qu'une fois téléchargée, une bibliothèque reste intégralement disponible hors-ligne — un plafond en Go déconnecté de la taille du disque n'a pas de sens fonctionnel ici.

## Décision

`AudioCacheManager` n'a plus de plafond de taille de cache. `_evictIfNeeded` interroge l'espace disque réellement disponible sur le volume contenant la bibliothèque (`AudioCacheManager.minFreeDiskBytes`, garde-fou à 2 Go par défaut) via [`disk_space.availableDiskBytes`](../../lib/core/utils/disk_space.dart) (Win32 `GetDiskFreeSpaceEx` / `df -Pk` POSIX) ; l'éviction (LRU, épinglage favoris/plateau actif inchangés) ne se déclenche que si cet espace passe sous le seuil. Une mesure indisponible (plateforme non supportée, échec de l'appel système) est traitée comme « espace suffisant » — jamais comme disque plein.

## Alternatives écartées

- **Rendre `maxCacheBytes` configurable par l'utilisateur** — répond à la géométrie actuelle mais reporte le problème à la prochaine bibliothèque qui dépasse le nouveau plafond choisi ; demande à l'utilisateur d'estimer une taille au lieu de simplement utiliser l'espace réellement disponible.
- **Contournement ponctuel réservé au bouton « Tout télécharger » (bypass explicite de l'éviction, plafond fixe inchangé pour le reste)** — première version de cette décision. Écartée : elle laisse le plafond arbitraire en place pour le préchargement automatique et ne répond pas à l'attente de fond (« cache = miroir complet, borné par le disque, pas par un chiffre choisi au hasard »). Un plafond fixe redeviendrait de toute façon caduc dès que le disque de l'utilisateur change de taille.
- **Ne jamais évincer, avec un plafond fixe supprimé et aucun garde-fou** — remplirait le disque à 0 octet libre si une bibliothèque Drive dépasse l'espace réellement disponible, avec un risque de casser d'autres écritures de l'application (base SQLite, etc.) ou du système.

## Conséquences

- Toute mesure d'espace disque passe par [`disk_space.availableDiskBytes`](../../lib/core/utils/disk_space.dart), injectable dans `AudioCacheManager` (paramètre `availableDiskBytes`) pour les tests — voir `simulatedDiskProbe` dans `audio_cache_manager_test.dart`, qui simule un disque de taille arbitraire à partir des octets réellement écrits sous la racine de test.
- `downloadAllLibraryAudio` (bouton manuel ET préchargement automatique en arrière-plan) partage désormais le même comportement : aucun des deux ne contourne l'éviction, mais elle ne se déclenche plus qu'en cas de pression disque réelle, pas à cause d'un chiffre arbitraire. Une bibliothèque qui tient sur le disque se télécharge donc entièrement, sans cycle éviction/re-téléchargement.
- Si le disque est réellement trop petit pour la bibliothèque entière, le comportement de cycle (éviction pendant que `downloadAllLibraryAudio` télécharge encore) peut réapparaître — mais cette fois le signal est correct (pas assez de place), contrairement à l'ancien plafond arbitraire.
- `dart:ffi` + `package:win32` (déjà une dépendance, cf. [0015](0015-plein-ecran-windows-manuel.md)) sont utilisés pour la mesure Windows ; `Process.run('df', …)` pour macOS/Linux. Aucune mesure n'existe pour iOS/Android — `availableDiskBytes` y retourne toujours `null`, donc l'éviction n'y est jamais déclenchée par ce garde-fou. À traiter si ces plateformes deviennent prioritaires.
