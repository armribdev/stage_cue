import '../providers/sampler_provider.dart' show PadItem;
import 'pad_sound_slot.dart';

/// Gravité d'un point du bilan de préparation d'un plateau.
enum ReadinessSeverity {
  /// Le pad (ou la pré-écoute) ne jouera pas, et rien à faire d'ici.
  blocking,

  /// Le pad ne jouera pas encore, mais un téléchargement le règle.
  fixable,

  /// Pas un échec : une chose à savoir avant d'entrer en scène.
  warning,
}

enum ReadinessIssueKind {
  missingFile(ReadinessSeverity.blocking),
  unsupportedFormat(ReadinessSeverity.blocking),
  offline(ReadinessSeverity.blocking),
  needsDownload(ReadinessSeverity.fixable),
  emptyPad(ReadinessSeverity.warning),

  /// Une sortie casque est possible sur la plateforme mais aucune n'est choisie.
  cueNotChosen(ReadinessSeverity.warning),

  /// Un casque est choisi mais n'est plus vu par le système.
  cueUnavailable(ReadinessSeverity.blocking);

  const ReadinessIssueKind(this.severity);

  final ReadinessSeverity severity;
}

/// Un point du bilan. [padLabel] est `null` pour un point qui ne concerne pas
/// un pad (casque). [affectedSounds] / [totalSounds] ne valent que pour un pad.
class BoardReadinessIssue {
  const BoardReadinessIssue({
    required this.kind,
    this.padLabel,
    this.affectedSounds = 0,
    this.totalSounds = 0,
  });

  final ReadinessIssueKind kind;
  final String? padLabel;
  final int affectedSounds;
  final int totalSounds;

  ReadinessSeverity get severity => kind.severity;
}

/// État du casque de pré-écoute, tel que l'a vu l'appelant.
class CueReadinessInput {
  const CueReadinessInput({
    required this.isSupported,
    this.selectedDeviceId,
    this.visibleDeviceIds = const {},
  });

  /// Pas de sortie séparée sur cette plateforme : le bilan n'en dit rien.
  static const unsupported = CueReadinessInput(isSupported: false);

  final bool isSupported;
  final String? selectedDeviceId;
  final Set<String> visibleDeviceIds;
}

/// Bilan « le plateau jouera-t-il au moment voulu ? », calculé à partir de
/// l'état de disponibilité déjà en mémoire (aucune E/S) : il peut donc être
/// recalculé à chaque changement de l'état sans coût.
class BoardReadinessReport {
  const BoardReadinessReport({required this.padCount, required this.issues});

  /// Pads réels du plateau (hors brouillons).
  final int padCount;
  final List<BoardReadinessIssue> issues;

  factory BoardReadinessReport.build({
    required Iterable<PadItem> pads,
    required CueReadinessInput cue,
  }) {
    final issues = <BoardReadinessIssue>[];
    var padCount = 0;
    for (final item in pads) {
      if (item.isDraft) continue;
      padCount++;
      final issue = _padIssue(item);
      if (issue != null) issues.add(issue);
    }
    final cueIssue = _cueIssue(cue);
    if (cueIssue != null) issues.add(cueIssue);
    return BoardReadinessReport(padCount: padCount, issues: issues);
  }

  static BoardReadinessIssue? _padIssue(PadItem item) {
    final total = item.totalSoundCount;
    final label = item.displayName;
    if (total == 0) {
      return BoardReadinessIssue(
        kind: ReadinessIssueKind.emptyPad,
        padLabel: label,
      );
    }
    ReadinessIssueKind? worst;
    var affected = 0;
    for (final slot in item.slots) {
      final kind = _kindOf(slot.availability);
      if (kind == null) continue;
      affected++;
      if (worst == null || _rank(kind) < _rank(worst)) worst = kind;
    }
    if (worst == null) return null;
    return BoardReadinessIssue(
      kind: worst,
      padLabel: label,
      affectedSounds: affected,
      totalSounds: total,
    );
  }

  static ReadinessIssueKind? _kindOf(PadSoundAvailability availability) =>
      switch (availability) {
        PadSoundAvailability.ready || PadSoundAvailability.cached => null,
        PadSoundAvailability.needsDownload => ReadinessIssueKind.needsDownload,
        PadSoundAvailability.offline => ReadinessIssueKind.offline,
        PadSoundAvailability.missingFile => ReadinessIssueKind.missingFile,
        PadSoundAvailability.unsupportedFormat =>
          ReadinessIssueKind.unsupportedFormat,
      };

  /// Plus petit = plus grave : un pad qui cumule un fichier perdu et un son à
  /// télécharger se présente comme perdu, pas comme « à télécharger ».
  static int _rank(ReadinessIssueKind kind) => switch (kind) {
    ReadinessIssueKind.missingFile => 0,
    ReadinessIssueKind.unsupportedFormat => 1,
    ReadinessIssueKind.offline => 2,
    _ => 3,
  };

  static BoardReadinessIssue? _cueIssue(CueReadinessInput cue) {
    if (!cue.isSupported) return null;
    final selected = cue.selectedDeviceId;
    if (selected == null) {
      return const BoardReadinessIssue(kind: ReadinessIssueKind.cueNotChosen);
    }
    if (!cue.visibleDeviceIds.contains(selected)) {
      return const BoardReadinessIssue(kind: ReadinessIssueKind.cueUnavailable);
    }
    return null;
  }

  Iterable<BoardReadinessIssue> _with(ReadinessSeverity severity) =>
      issues.where((i) => i.severity == severity);

  List<BoardReadinessIssue> get blocking =>
      _with(ReadinessSeverity.blocking).toList(growable: false);

  List<BoardReadinessIssue> get fixable =>
      _with(ReadinessSeverity.fixable).toList(growable: false);

  List<BoardReadinessIssue> get warnings =>
      _with(ReadinessSeverity.warning).toList(growable: false);

  /// Rien qui empêche ou retarde un son. Les avertissements ne comptent pas.
  bool get isReady => blocking.isEmpty && fixable.isEmpty;

  /// Pads qui jouent tels quels : ni bloqués, ni à télécharger.
  int get playablePadCount {
    final problem = issues
        .where(
          (i) =>
              i.padLabel != null &&
              (i.severity == ReadinessSeverity.blocking ||
                  i.severity == ReadinessSeverity.fixable),
        )
        .length;
    return padCount - problem;
  }
}
