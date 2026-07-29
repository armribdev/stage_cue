import 'dart:async';

import '../../../../core/sync/local_availability_probe.dart' as probe;
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';

/// Instantané de la bibliothèque tel que consommé par le sélecteur de sons.
class SoundSearchSnapshot {
  final List<Sound> sounds;
  final Map<int, List<TagItem>> tagsBySound;
  final List<TagCategoryWithTags> tagCatalog;

  /// Sons dont le fichier est présent localement (filtre hors-ligne).
  final Set<int> locallyAvailableSoundIds;

  /// Instant de la dernière sonde disque — gouverne la fréquence de re-sondage.
  final DateTime probedAt;

  const SoundSearchSnapshot({
    required this.sounds,
    required this.tagsBySound,
    required this.tagCatalog,
    required this.locallyAvailableSoundIds,
    required this.probedAt,
  });

  List<TagItem> tagsFor(int soundId) => tagsBySound[soundId] ?? const [];

  SoundSearchSnapshot withSounds(List<Sound> next) => SoundSearchSnapshot(
        sounds: next,
        tagsBySound: tagsBySound,
        tagCatalog: tagCatalog,
        locallyAvailableSoundIds: locallyAvailableSoundIds,
        probedAt: probedAt,
      );
}

/// Cache mémoire de la bibliothèque pour la recherche de sons.
///
/// Ouvrir la recherche en plein spectacle ne doit jamais attendre la base ni le
/// disque. L'index sert donc l'instantané courant tel quel ([current]) et
/// rafraîchit en tâche de fond (*stale-while-revalidate*) : sur une
/// bibliothèque d'un millier de sons, la liste s'affiche immédiatement et se
/// corrige silencieusement si quelque chose a changé.
///
/// La sonde de disponibilité locale, elle, parcourt le disque : elle n'est
/// refaite qu'au-delà de [_localProbeTtl], sinon le résultat précédent est
/// repris. Une lecture ou un ajout de son n'invalide donc pas le disque.
class SoundSearchIndex {
  final SoundRepository _repository;
  final LibraryRepository? _libraryRepository;

  SoundSearchIndex(this._repository, this._libraryRepository);

  /// Au-delà de ce délai, la prochaine reconstruction re-parcourt le cache
  /// disque. En deçà, la disponibilité locale connue est reconduite : les
  /// téléchargements en cours se reflètent avec au plus ce retard.
  static const Duration _localProbeTtl = Duration(seconds: 30);

  SoundSearchSnapshot? _current;
  Future<SoundSearchSnapshot>? _inFlight;

  /// Instantané disponible sans attente, `null` avant le premier chargement.
  SoundSearchSnapshot? get current => _current;

  /// Instantané courant s'il existe, sinon premier chargement.
  Future<SoundSearchSnapshot> ensureLoaded() {
    final snapshot = _current;
    if (snapshot != null) return Future.value(snapshot);
    return refresh();
  }

  /// Reconstruit l'instantané. Les appels concurrents partagent le même travail
  /// plutôt que de lancer plusieurs balayages de la bibliothèque en parallèle.
  Future<SoundSearchSnapshot> refresh({bool forceLocalProbe = false}) {
    final pending = _inFlight;
    if (pending != null) return pending;
    final task = _build(forceLocalProbe: forceLocalProbe);
    _inFlight = task;
    return task.whenComplete(() {
      if (identical(_inFlight, task)) _inFlight = null;
    });
  }

  /// Remplace un son de l'instantané sans toucher à la base ni au disque —
  /// pour les mutations locales connues (favori, dernière lecture, type), dont
  /// le seul effet visible en recherche est le tri et l'étiquette.
  void patchSound(int soundId, Sound Function(Sound sound) update) {
    final snapshot = _current;
    if (snapshot == null) return;
    final index = snapshot.sounds.indexWhere((sound) => sound.id == soundId);
    if (index < 0) return;
    final next = List<Sound>.from(snapshot.sounds);
    next[index] = update(next[index]);
    _current = snapshot.withSounds(next);
  }

  /// Jette l'instantané : le prochain accès repart de la base (changement de
  /// bibliothèque, indexation, fusion d'un pull Drive).
  void invalidate() => _current = null;

  Future<SoundSearchSnapshot> _build({required bool forceLocalProbe}) async {
    final previous = _current;
    final results = await Future.wait([
      _repository.getAllSounds(),
      _repository.getTagsForAllSounds(),
      _repository.getTagCatalog(),
    ]);
    final sounds = results[0] as List<Sound>;

    final now = DateTime.now();
    final probeIsFresh = previous != null &&
        !forceLocalProbe &&
        now.difference(previous.probedAt) < _localProbeTtl;

    final snapshot = SoundSearchSnapshot(
      sounds: sounds,
      tagsBySound: results[1] as Map<int, List<TagItem>>,
      tagCatalog: results[2] as List<TagCategoryWithTags>,
      locallyAvailableSoundIds: probeIsFresh
          ? previous.locallyAvailableSoundIds
          : await _probeLocalAvailability(sounds),
      probedAt: probeIsFresh ? previous.probedAt : now,
    );
    _current = snapshot;
    return snapshot;
  }

  Future<Set<int>> _probeLocalAvailability(List<Sound> sounds) async {
    final libraryRepository = _libraryRepository;
    if (libraryRepository != null) {
      return libraryRepository.probeLocallyAvailableSoundIds(sounds);
    }
    // Sans bibliothèque Drive, aucune racine de cache à parcourir : la sonde
    // retombe sur l'existence du fichier de chaque son legacy.
    return probe.probeLocallyAvailableSoundIds(
      sounds: sounds,
      libraryRootPaths: const {},
    );
  }
}
