import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/string_utils.dart';
import '../../domain/entities/sound.dart';
import '../providers/sampler_provider.dart';

/// Recherche-éclair : overlay flottant (pas une route plein écran) pour trouver
/// un son et agir en moins d'une seconde pendant un spectacle (refonte UX P1).
///
/// - résultats dès le 1er caractère, fuzzy + normalisé (accents) ;
/// - tri par pertinence puis récence ;
/// - tap sur une ligne = pré-écoute (audition, reste ouvert) ;
/// - `Entrée` = joue le 1er résultat et ferme ; `Ctrl/Cmd+Entrée` = l'ajoute à
///   la scène et ferme ; `Échap` = ferme.
///
/// Renvoie l'id du pad créé si un son a été ajouté à la scène (pour le mettre en
/// évidence), sinon null.
class QuickSearchOverlay extends StatefulWidget {
  final SamplerNotifier notifier;

  const QuickSearchOverlay({super.key, required this.notifier});

  static Future<int?> show(
    BuildContext context, {
    required SamplerNotifier notifier,
  }) {
    return showGeneralDialog<int?>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer la recherche',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, _, _) => QuickSearchOverlay(notifier: notifier),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, -0.03), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<QuickSearchOverlay> createState() => _QuickSearchOverlayState();
}

class _QuickSearchOverlayState extends State<QuickSearchOverlay> {
  final _controller = TextEditingController();
  List<Sound> _all = const [];
  bool _loading = true;
  String _query = '';
  SoundType? _typeFilter;

  Set<int> _tagMatchIds = const {};
  String _tagToken = '';
  Timer? _tagDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sounds = await widget.notifier.getAllSounds();
    if (!mounted) return;
    setState(() {
      _all = sounds;
      _loading = false;
    });
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _tagDebounce?.cancel();
    _tagDebounce = Timer(const Duration(milliseconds: 120), () {
      unawaited(_runTagSearch(value));
    });
  }

  Future<void> _runTagSearch(String value) async {
    final norm = normalizeForSearch(value);
    _tagToken = norm;
    if (norm.isEmpty) {
      if (mounted) setState(() => _tagMatchIds = const {});
      return;
    }
    final ids = await widget.notifier.findSoundIdsByTagQuery(value);
    if (!mounted || _tagToken != norm) return;
    setState(() => _tagMatchIds = ids);
  }

  /// Résultats filtrés et classés (pertinence puis récence).
  List<Sound> get _results {
    final q = normalizeForSearch(_query);
    final scored = <(Sound, int)>[];
    for (final sound in _all) {
      if (_typeFilter != null && sound.type != _typeFilter) continue;
      final name = normalizeForSearch(sound.displayName ?? sound.title);
      var score = fuzzyMatchScore(name, q);
      // Repli sur la correspondance par tag si le nom ne matche pas.
      if (score == null && _tagMatchIds.contains(sound.id)) score = 200;
      if (q.isEmpty) score = 0;
      if (score == null) continue;
      scored.add((sound, score));
    }
    scored.sort((a, b) {
      if (a.$2 != b.$2) return b.$2.compareTo(a.$2);
      return b.$1.createdAt.compareTo(a.$1.createdAt); // récence
    });
    return [for (final e in scored) e.$1];
  }

  Future<void> _play(Sound sound) async {
    final ok = await widget.notifier.previewSound(sound.id);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Son indisponible — vérifiez la connexion'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _playTopAndClose() async {
    final results = _results;
    if (results.isEmpty) return;
    await widget.notifier.previewSound(results.first.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _addAndClose(Sound sound) async {
    final padId = await widget.notifier.addSoundToActiveBoard(sound.id);
    if (mounted) Navigator.of(context).pop(padId);
  }

  Future<void> _addTopAndClose() async {
    final results = _results;
    if (results.isEmpty) return;
    await _addAndClose(results.first);
  }

  @override
  void dispose() {
    _tagDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final topInset = mq.padding.top + 12;
    final results = _results;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_addTopAndClose()),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            unawaited(_addTopAndClose()),
      },
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, topInset, 12, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: mq.size.height * 0.7,
            ),
            child: Material(
              color: scheme.surface,
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSearchField(scheme),
                  _buildTypeFilters(scheme),
                  const Divider(height: 1),
                  Flexible(child: _buildResults(scheme, results)),
                  _buildHints(scheme, results.isNotEmpty),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onChanged: _onQueryChanged,
              onSubmitted: (_) => unawaited(_playTopAndClose()),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Chercher un son…',
                isCollapsed: true,
              ),
              style: const TextStyle(fontSize: 17),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Fermer',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilters(ColorScheme scheme) {
    Widget chip(String label, SoundType? type) {
      final selected = _typeFilter == type;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => setState(() => _typeFilter = type),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          chip('Tous', null),
          chip('SFX', SoundType.soundEffect),
          chip('Musique', SoundType.music),
          chip('Ambiance', SoundType.ambiance),
        ],
      ),
    );
  }

  Widget _buildResults(ColorScheme scheme, List<Sound> results) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            _query.isEmpty ? 'Tapez pour chercher' : 'Aucun son',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final sound = results[index];
        final isTop = index == 0 && _query.isNotEmpty;
        return ListTile(
          dense: true,
          tileColor: isTop ? scheme.primary.withValues(alpha: 0.06) : null,
          leading: Icon(_typeIcon(sound.type), color: scheme.onSurfaceVariant),
          title: Text(
            sound.displayName ?? sound.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(_typeLabel(sound.type)),
          onTap: () => unawaited(_play(sound)),
          trailing: IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Ajouter à la scène',
            onPressed: () => unawaited(_addAndClose(sound)),
          ),
        );
      },
    );
  }

  Widget _buildHints(ColorScheme scheme, bool hasResults) {
    if (!hasResults) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Text(
        '↵ jouer    ⌘/Ctrl+↵ ajouter à la scène    tap audition',
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }

  IconData _typeIcon(SoundType type) => switch (type) {
        SoundType.soundEffect => Icons.graphic_eq_rounded,
        SoundType.music => Icons.music_note_rounded,
        SoundType.ambiance => Icons.waves_rounded,
      };

  String _typeLabel(SoundType type) => switch (type) {
        SoundType.soundEffect => 'Effet',
        SoundType.music => 'Musique',
        SoundType.ambiance => 'Ambiance',
      };
}
