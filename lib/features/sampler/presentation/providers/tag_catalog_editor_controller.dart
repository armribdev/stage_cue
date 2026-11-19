import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_log.dart';
import '../../data/datasources/local_tag_editing_datasource.dart';
import '../../domain/entities/tag_catalog_change.dart';
import '../utils/tag_catalog_snippet.dart';

/// État de l'éditeur de catalogue de tags de développement (décision 0047) : le
/// catalogue lu en base, et les modifications faites depuis l'ouverture, dont
/// on tire la déclaration à ajouter au code.
///
/// Les modifications ne vivent qu'en mémoire (et dans le journal, une ligne par
/// événement) : fermer l'éditeur sans avoir copié le code les perd de vue, d'où
/// [hasUncopiedChanges].
class TagCatalogEditorController extends ChangeNotifier {
  final LocalTagEditingDataSource _editor;

  TagCatalogEditorController(this._editor);

  List<TagEditorCategory> _categories = const [];
  final List<TagCatalogChange> _changes = [];
  int _copiedCount = 0;
  bool _isLoading = true;
  Object? _loadError;

  List<TagEditorCategory> get categories => _categories;
  bool get isLoading => _isLoading;
  Object? get loadError => _loadError;

  List<TagCatalogChange> get changes => List.unmodifiable(_changes);

  /// Déclaration Dart des modifications ; vide s'il n'y a rien à déclarer.
  String get snippet => renderTagCatalogSnippet(_changes);

  bool get hasUncopiedChanges => _changes.length > _copiedCount;

  /// Le code vient d'être copié : les modifications faites jusqu'ici sont
  /// couvertes.
  void markSnippetCopied() {
    _copiedCount = _changes.length;
    notifyListeners();
  }

  /// Le tag [tagId] avec sa catégorie, ou `null` s'il n'existe plus.
  ({String category, TagEditorEntry entry})? find(int tagId) {
    for (final category in _categories) {
      for (final entry in category.entries) {
        if (entry.tag.id == tagId) {
          return (category: category.category.name, entry: entry);
        }
      }
    }
    return null;
  }

  Future<void> load() async {
    try {
      _categories = await _editor.load();
      _loadError = null;
    } catch (e) {
      AppLog.warn('Éditeur de catalogue de tags : lecture impossible : $e');
      _loadError = e;
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> createTag({
    required int categoryId,
    required String name,
    List<String> aliases = const [],
  }) => _apply(
    () =>
        _editor.createTag(categoryId: categoryId, name: name, aliases: aliases),
  );

  Future<void> renameTag(int tagId, String name) =>
      _apply(() => _editor.renameTag(tagId: tagId, name: name));

  Future<void> mergeTag({required int fromId, required int intoId}) =>
      _apply(() => _editor.mergeTag(fromId: fromId, intoId: intoId));

  Future<void> deleteTag(int tagId) => _apply(() => _editor.deleteTag(tagId));

  Future<void> addAlias(int tagId, String alias) =>
      _apply(() => _editor.addAlias(tagId: tagId, alias: alias));

  Future<void> removeAlias(int aliasId) =>
      _apply(() => _editor.removeAlias(aliasId));

  /// Exécute une écriture, la retient, puis relit le catalogue. Un refus
  /// ([TagEditException]) remonte à l'appelant, qui l'affiche : rien n'a été
  /// écrit ni retenu.
  Future<void> _apply(Future<TagCatalogChange> Function() write) async {
    final change = await write();
    _changes.add(change);
    AppLog.info(
      'Éditeur de catalogue de tags, à déclarer dans le code :\n'
      '${renderTagCatalogSnippet([change])}',
    );
    await load();
  }
}
