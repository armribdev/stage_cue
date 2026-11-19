import 'package:flutter/services.dart';

import '../providers/sampler_provider.dart' show PadItem;

/// Une touche dessinée dans la vue clavier. [keyId] est un
/// `LogicalKeyboardKey.keyId` — le même identifiant que celui stocké par
/// `AppPreferences.setPadHotkey`, donc la touche « sous » laquelle un pad est
/// déclenché au clavier.
class KeyboardKeySpec {
  final int keyId;

  /// Largeur en unités de touche (1 = une touche de caractère).
  final double width;

  const KeyboardKeySpec(this.keyId, {this.width = 1});

  String get label => hotkeyKeycapLabel(keyId);
}

/// Une rangée du clavier : [indent] unités vides avant la première touche
/// (décalage d'une vraie rangée), puis les touches.
class KeyboardRow {
  final double indent;
  final List<KeyboardKeySpec> keys;

  const KeyboardRow({this.indent = 0, required this.keys});

  double get width => indent + keys.fold<double>(0, (sum, k) => sum + k.width);
}

List<KeyboardKeySpec> _chars(String chars) => [
  for (final rune in chars.runes) KeyboardKeySpec(rune),
];

/// Disposition AZERTY (clavier français), les touches telles que l'OS les
/// livre **sans modificateur** — c'est ce que la capture de raccourci
/// enregistre (`event.logicalKey`), d'où `&é"'(-è_çà)=` en haut et pas `1234…`.
///
/// La disposition suit le clavier de l'OS, pas la position physique : sur un
/// clavier QWERTY, les touches s'afficheraient aux mauvais endroits
/// ([décision 0050](../../../../../docs/decisions/0050-vue-clavier-du-board-azerty.md)).
/// Un pad dont la touche n'est pas dessinée ici (flèches, F1…) reste listé
/// sans touche dessinée dans [KeyboardPadAssignment.loose].
final List<KeyboardRow> kAzertyRows = [
  KeyboardRow(
    keys: [
      ..._chars('&é"\'(-è_çà)='),
      KeyboardKeySpec(LogicalKeyboardKey.backspace.keyId, width: 2),
    ],
  ),
  KeyboardRow(
    keys: [
      KeyboardKeySpec(LogicalKeyboardKey.tab.keyId, width: 1.5),
      ..._chars('azertyuiop'),
    ],
  ),
  KeyboardRow(
    indent: 1.75,
    keys: [
      ..._chars('qsdfghjklmù'),
      KeyboardKeySpec(LogicalKeyboardKey.enter.keyId, width: 1.5),
    ],
  ),
  KeyboardRow(indent: 1.25, keys: _chars('<wxcvbn,;:!')),
  KeyboardRow(
    indent: 3.5,
    keys: [KeyboardKeySpec(LogicalKeyboardKey.space.keyId, width: 6)],
  ),
];

/// Largeur de la plus large rangée, en unités de touche.
final double kAzertyWidthUnits = kAzertyRows.fold<double>(
  0,
  (widest, row) => row.width > widest ? row.width : widest,
);

final Set<int> _drawnKeyIds = {
  for (final row in kAzertyRows)
    for (final key in row.keys) key.keyId,
};

/// Étiquette courte d'une touche (symbole pour les non-imprimables les plus
/// courants, sinon `keyLabel` — un `FittedBox` en aval absorbe le reste, ex.
/// « Page Up »).
String hotkeyKeycapLabel(int keyId) {
  final key = LogicalKeyboardKey(keyId);
  final symbols = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.space: '␣',
    LogicalKeyboardKey.tab: '⇥',
    LogicalKeyboardKey.enter: '⏎',
    LogicalKeyboardKey.numpadEnter: '⏎',
    LogicalKeyboardKey.backspace: '⌫',
    LogicalKeyboardKey.delete: 'Del',
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
  };
  final symbol = symbols[key];
  if (symbol != null) return symbol;
  final raw = key.keyLabel;
  return raw.length <= 3 ? raw.toUpperCase() : raw;
}

/// Répartition des pads d'un board entre les touches dessinées et le reste.
class KeyboardPadAssignment {
  /// Pad posé sur chaque touche dessinée.
  final Map<int, PadItem> onKeys;

  /// Pads qui ne sont sur aucune touche dessinée : sans touche, touche non
  /// dessinée, ou touche déjà prise par un autre pad. La vue ne les montre pas,
  /// elle les propose dans le menu d'une touche vide.
  final List<PadItem> loose;

  const KeyboardPadAssignment({required this.onKeys, required this.loose});
}

/// Pose chaque pad sur sa touche. En cas de collision (deux pads, même
/// touche), le **premier** dans l'ordre de [pads] garde la touche : c'est celui
/// que `_handlePadHotkeyEvent` déclenche, il parcourt les pads dans le même
/// ordre. L'autre tombe dans [KeyboardPadAssignment.loose].
KeyboardPadAssignment assignPadsToKeys(
  Iterable<PadItem> pads,
  int? Function(int padId) hotkeyForPad,
) {
  final onKeys = <int, PadItem>{};
  final loose = <PadItem>[];
  for (final item in pads) {
    final keyId = hotkeyForPad(item.pad.id);
    if (keyId != null && _drawnKeyIds.contains(keyId)) {
      if (!onKeys.containsKey(keyId)) {
        onKeys[keyId] = item;
        continue;
      }
    }
    loose.add(item);
  }
  return KeyboardPadAssignment(onKeys: onKeys, loose: loose);
}

/// Modifications de touches (`padId → keyId`, `null` = retirer) à appliquer
/// quand [dragged] est déposé sur [targetKeyId] (`null` : lâché hors d'une
/// touche, sa touche est retirée). Vide si le dépôt ne change rien.
///
/// Sur une touche occupée, les deux pads **échangent** leurs places : le pad
/// délogé prend l'ancienne touche du pad déposé. Si celui-ci n'était pas sur une
/// touche (sans touche dessinée, ou en collision), le pad délogé perd la sienne — lui
/// donner une touche que le pad déposé ne détenait pas créerait une collision.
Map<int, int?> planPadDrop({
  required PadItem dragged,
  required int? targetKeyId,
  required KeyboardPadAssignment assignment,
  required int? Function(int padId) hotkeyForPad,
}) {
  final padId = dragged.pad.id;
  final currentKey = hotkeyForPad(padId);

  if (targetKeyId == null) {
    return currentKey == null ? const {} : {padId: null};
  }

  final holder = assignment.onKeys[targetKeyId];
  if (holder != null && holder.pad.id == padId) return const {};

  final changes = <int, int?>{padId: targetKeyId};
  if (holder != null) {
    final wasOnKey =
        currentKey != null && assignment.onKeys[currentKey] == dragged;
    changes[holder.pad.id] = wasOnKey ? currentKey : null;
  }
  return changes;
}
