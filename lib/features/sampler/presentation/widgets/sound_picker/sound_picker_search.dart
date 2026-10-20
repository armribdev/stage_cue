// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sound_picker_overlay.dart';

/// Recherche (débounce, tags) et calcul des résultats affichés.
/// Méthodes de [_SoundPickerOverlayState] extraites via extension dans le même `part`.
extension _SoundPickerSearch on _SoundPickerOverlayState {
  // ── Recherche ─────────────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    // Le champ de texte gère son propre affichage via _controller : retarder
    // la mise à jour de _query ne fait pas lagger la frappe, seulement le
    // recalcul du scoring flou (sur toute la bibliothèque) et la recherche
    // de tags — inutile de les relancer à chaque caractère tapé.
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() {
        _query = value;
        _selectedIndex = 0;
      });
      unawaited(_runTagSearch(value));
    });
  }

  /// Vide le champ de recherche — déclenché par la croix, donc immédiat
  /// (pas de débounce à attendre).
  void _clearQuery() {
    _searchDebounce?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      _selectedIndex = 0;
    });
    unawaited(_runTagSearch(''));
  }

  /// Tokens normalisés (≥ 2 chars) extraits de [_query].
  List<String> get _normalizedTokens {
    if (_query.trim().isEmpty) return const [];
    return _query
        .split(RegExp(r'[\s,]+'))
        .map((t) => normalizeForSearch(t.trim()))
        .where((t) => t.length >= 2)
        .toList();
  }

  /// Tokens à mettre en gras : les tokens normalisés si disponibles,
  /// sinon la requête entière normalisée (pour les mots courts / 1 token).
  List<String> get _highlightTokens {
    final tokens = _normalizedTokens;
    if (tokens.isNotEmpty) return tokens;
    final q = normalizeForSearch(_query);
    return q.isEmpty ? const [] : [q];
  }

  Future<void> _runTagSearch(String value) async {
    final norm = normalizeForSearch(value);
    _tagToken = norm;
    if (norm.isEmpty) {
      if (mounted) setState(() => _tagMatchSetsPerToken = const []);
      return;
    }
    final tokens = value
        .split(RegExp(r'[\s,]+'))
        .map((t) => t.trim())
        .where((t) => t.length >= 2)
        .toList();
    // Si aucun token valide (requête < 2 chars), cherche la requête entière.
    final queries = tokens.isEmpty ? [value] : tokens;
    final sets = await Future.wait(
      queries.map((t) => widget.notifier.findSoundIdsByTagQuery(t)),
    );
    if (!mounted || _tagToken != norm) return;
    setState(() => _tagMatchSetsPerToken = sets);
  }

  // ── Résultats ─────────────────────────────────────────────────────────────

  DateTime _recencyKey(Sound s) => s.lastPlayedAt ?? s.createdAt;

  List<Sound> get _results {
    // Variante d'un multipad : ordre figé sur les slots du pad (l'index doit
    // rester aligné avec `pad.sounds` pour `playPadSoundAtIndex`) — jamais
    // retrié par score/favori/récence.
    if (_isPadVariant) return _all;
    final q = normalizeForSearch(_query);
    final tokens = _normalizedTokens;
    final scored = <(Sound, int)>[];
    for (final sound in _all) {
      if (!_matchesBoardScope(sound)) {
        continue;
      }
      if (_effectiveTypeFilter != null &&
          !sound.matchesSoundType(_effectiveTypeFilter!)) {
        continue;
      }
      if (_favoritesOnly && !sound.isFavorite) {
        continue;
      }
      if (_effectiveLocalOnly && !_isLocal(sound)) {
        continue;
      }
      if (_isManage && _unprocessedOnly && sound.isProcessed) {
        continue;
      }

      int? score;
      if (q.isEmpty) {
        score = 0;
      } else if (tokens.isEmpty) {
        // Requête sans token valide (ex : 1 char) → fuzzy entier + tag fallback.
        final name = normalizeForSearch(sound.displayName);
        score = fuzzyMatchScore(name, q);
        if (score == null &&
            _tagMatchSetsPerToken.isNotEmpty &&
            _tagMatchSetsPerToken[0].contains(sound.id)) {
          score = 200;
        }
      } else {
        // Logique AND par token : chaque token doit matcher titre OU tag.
        final name = normalizeForSearch(sound.displayName);
        var total = 0;
        var allMatch = true;
        for (var i = 0; i < tokens.length; i++) {
          final ts = fuzzyMatchScore(name, tokens[i]);
          if (ts != null) {
            total += ts;
          } else if (i < _tagMatchSetsPerToken.length &&
              _tagMatchSetsPerToken[i].contains(sound.id)) {
            total += 200;
          } else {
            allMatch = false;
            break;
          }
        }
        if (allMatch) score = total;
      }

      if (score == null) continue;
      scored.add((sound, score));
    }
    scored.sort((a, b) {
      if (a.$2 != b.$2) return b.$2.compareTo(a.$2);
      final favA = a.$1.isFavorite, favB = b.$1.isFavorite;
      if (favA != favB) return favA ? -1 : 1;
      return _recencyKey(b.$1).compareTo(_recencyKey(a.$1));
    });
    return [for (final e in scored) e.$1];
  }

  /// Mode parcours : favoris + récents uniquement (QuickSearch, requête vide).
  List<Sound> _shownResults(List<Sound> results) {
    final isBrowse = _isQuickSearch && _query.isEmpty && !_favoritesOnly;
    if (!isBrowse) return results;
    return results
        .where((s) => s.isFavorite || s.lastPlayedAt != null)
        .take(25)
        .toList();
  }

  bool get _isBrowseMode => _isQuickSearch && _query.isEmpty && !_favoritesOnly;
}
