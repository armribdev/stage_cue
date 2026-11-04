import 'tag_item.dart';

/// Tag trouvé par l'analyse automatique pour un son (décision 0030).
///
/// [hidden] : l'utilisateur l'a masqué. Il reste en base — l'IA ne le repose
/// pas — mais n'est ni affiché ni cherché.
class SoundAutoTag {
  final TagItem tag;
  final bool hidden;

  const SoundAutoTag({required this.tag, required this.hidden});
}
