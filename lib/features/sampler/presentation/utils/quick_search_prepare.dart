import 'dart:math';

import '../../domain/entities/pad.dart';

/// Résultat d'une action « Préparer » depuis la recherche-éclair.
///
/// [highlightPadId] est renseigné uniquement pour les bruitages / ambiances
/// dont le pad dédié est (ou vient d'être placé) sur la scène.
class QuickSearchPrepareResult {
  final int? highlightPadId;

  const QuickSearchPrepareResult({this.highlightPadId});

  const QuickSearchPrepareResult.none() : highlightPadId = null;

  const QuickSearchPrepareResult.highlight(int padId) : highlightPadId = padId;
}

/// Référence minimale d'un pad sur scène (hors couche UI).
typedef OnStagePadRef = ({
  int padId,
  bool isDraft,
  List<int> soundIds,
});

/// Pad dédié = exactement un son, visible sur scène (pas brouillon).
int? findDedicatedOnStagePadId(
  Iterable<OnStagePadRef> pads,
  int soundId,
) {
  for (final pad in pads) {
    if (pad.isDraft) continue;
    if (pad.soundIds.length == 1 && pad.soundIds.first == soundId) {
      return pad.padId;
    }
  }
  return null;
}

/// Emplacement pour ajouter un pad en fin de dernière ligne.
class LastRowPadPlacement {
  final int rowIndex;
  final int insertionPositionInRow;
  final int globalSortOrder;

  const LastRowPadPlacement({
    required this.rowIndex,
    required this.insertionPositionInRow,
    required this.globalSortOrder,
  });
}

/// Calcule où placer un nouveau pad : dernière case de la dernière ligne.
///
/// [forceNewRow] place le pad en début d'une toute nouvelle ligne au lieu de
/// l'ajouter à la suite de la dernière ligne existante — utilisé pour le
/// premier ajout d'une session de recherche-éclair en mode live, afin de ne
/// pas polluer la dernière ligne déjà en place sur scène.
LastRowPadPlacement computeLastRowAppendPlacement(
  Iterable<Pad> pads, {
  bool forceNewRow = false,
}) {
  final onStage = pads.toList(growable: false);
  if (onStage.isEmpty) {
    return const LastRowPadPlacement(
      rowIndex: 0,
      insertionPositionInRow: 0,
      globalSortOrder: 0,
    );
  }

  final byRow = <int, List<Pad>>{};
  for (final pad in onStage) {
    (byRow[pad.rowIndex] ??= []).add(pad);
  }
  for (final rowPads in byRow.values) {
    rowPads.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  final lastRowIndex = byRow.keys.reduce(max);
  final maxSortOrder = onStage.map((p) => p.sortOrder).reduce(max);

  if (forceNewRow) {
    return LastRowPadPlacement(
      rowIndex: lastRowIndex + 1,
      insertionPositionInRow: 0,
      globalSortOrder: maxSortOrder + 1,
    );
  }

  final lastRowPads = byRow[lastRowIndex]!;

  return LastRowPadPlacement(
    rowIndex: lastRowIndex,
    insertionPositionInRow: lastRowPads.length,
    globalSortOrder: maxSortOrder + 1,
  );
}

List<OnStagePadRef> onStagePadRefs({
  required Iterable<({Pad pad, bool isDraft})> items,
}) {
  return [
    for (final item in items)
      (
        padId: item.pad.id,
        isDraft: item.isDraft,
        soundIds: [for (final sound in item.pad.sounds) sound.id],
      ),
  ];
}

/// Prépare un bruitage / une ambiance sur le plateau :
/// surbrillance du pad dédié existant, sinon création en fin de dernière ligne.
Future<QuickSearchPrepareResult> prepareSfxOnBoard({
  required int soundId,
  required Iterable<({Pad pad, bool isDraft})> padsOnBoard,
  required Future<int> Function(LastRowPadPlacement placement) createPad,
  required Future<Iterable<({Pad pad, bool isDraft})>> Function() reloadPads,
  bool forceNewRow = false,
}) async {
  final refs = onStagePadRefs(items: padsOnBoard);

  final existing = findDedicatedOnStagePadId(refs, soundId);
  if (existing != null) {
    return QuickSearchPrepareResult.highlight(existing);
  }

  final stagePads = [
    for (final item in padsOnBoard)
      if (!item.isDraft) item.pad,
  ];
  final placement =
      computeLastRowAppendPlacement(stagePads, forceNewRow: forceNewRow);
  final padId = await createPad(placement);

  final reloaded = await reloadPads();
  final reloadedRefs = onStagePadRefs(items: reloaded);

  final verified = findDedicatedOnStagePadId(reloadedRefs, soundId);
  if (verified != null) {
    return QuickSearchPrepareResult.highlight(verified);
  }

  // Pad créé mais pas encore indexé comme dédié : on valide par id + son.
  final createdVisible = reloadedRefs.any(
    (p) => !p.isDraft && p.padId == padId && p.soundIds.contains(soundId),
  );
  if (createdVisible) {
    return QuickSearchPrepareResult.highlight(padId);
  }

  return const QuickSearchPrepareResult.none();
}
