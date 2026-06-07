import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import '../providers/sampler_provider.dart';
import '../widgets/pad_item.dart' show PadCard;
import '../widgets/music_preview_panel.dart';
import '../widgets/music_picker_sheet.dart';
import '../widgets/app_form_dialog.dart';
import '../../domain/entities/sound_board.dart';
import '../../../../core/app/app_services.dart';
import '../../../../core/utils/copyable_snackbar.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/layout_utils.dart';
import 'settings_screen.dart';
import 'pad_details_screen.dart';
import 'sound_library_screen.dart';
import 'sound_library_manage_screen.dart';

/// Marqueur pour le bouton d'ajout dans la grille
const _addButtonMarker = _AddButtonMarker();

class _AddButtonMarker {
  const _AddButtonMarker();
}

class _UndoPadIntent extends Intent {
  const _UndoPadIntent();
}

/// Écran principal du sampler
class SamplerScreen extends StatefulWidget {
  final AppServices services;

  const SamplerScreen({super.key, required this.services});

  @override
  State<SamplerScreen> createState() => _SamplerScreenState();
}

class _SamplerScreenState extends State<SamplerScreen> {
  late final SamplerNotifier _notifier;
  late final db.AppDatabase _database;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _normalGridScrollController = ScrollController();
  final ScrollController _editGridScrollController = ScrollController();

  ScrollController get _activeGridScrollController =>
      _isEditMode ? _editGridScrollController : _normalGridScrollController;
  int _gridCrossAxisCount = 2;
  double _gridViewportWidth = 0;
  bool _isEditMode = false;
  int? _recentlyRestoredSoundId;
  int? _highlightedPadId;
  bool _didAutoOpenCreateForCurrentEmptyState = false;
  bool _isMusicRegieAdvanced = false;
  bool _isMusicRegieLocked = false;

  static const _musicRegieTapGroup = 'music-regie-dismiss';

  bool get _isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    _database = widget.services.database;
    _initializeNotifier();
    _notifier.loadBoards();
  }

  void _initializeNotifier() {
    _notifier = SamplerNotifier(
      widget.services.soundRepository,
      widget.services.loadSoundsUseCase,
      widget.services.removeSoundFromBoardUseCase,
      widget.services.libraryRepository,
    );

    _notifier.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {
        if (_isEditMode && _notifier.state.pads.isEmpty) {
          _isEditMode = false;
        }
      });
    }
  }

  /// Sélectionne un board et ferme le drawer (mobile).
  Future<void> _selectBoard(SoundBoard board) async {
    Navigator.pop(context);
    await _notifier.selectBoard(board);
  }

  /// Sélectionne un board sans fermer de drawer (sidebar desktop).
  Future<void> _selectBoardDirect(SoundBoard board) async {
    await _notifier.selectBoard(board);
  }

  Future<void> _createBoard() async {
    if (!mounted) return;

    final suggestedName = _buildSuggestedBoardName(_notifier.state.boards);
    final result = await AppBoardCreationDialog.show(
      context,
      suggestedName: suggestedName,
    );

    if (result == null || !mounted) return;
    // Ferme le drawer s'il est ouvert (mobile — no-op si pas de drawer).
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    final newBoard = await _notifier.createBoard(
      result.name,
      color: result.color,
    );
    if (!mounted) return;
    if (newBoard == null) {
      showCopyableSnackBar(context, 'Erreur lors de la création de la scène');
    }
  }

  String _buildSuggestedBoardName(List<SoundBoard> boards) {
    final existingNames = boards
        .map((b) => b.name.trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();
    var index = 1;
    while (existingNames.contains('scène $index')) {
      index++;
    }
    return 'Scène $index';
  }

  String _buildSuggestedDuplicateBoardName(
    String sourceName,
    List<SoundBoard> boards,
  ) {
    final existingNames = boards
        .map((b) => b.name.trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();
    final baseName = '$sourceName (copie)';
    if (!existingNames.contains(baseName.toLowerCase())) {
      return baseName;
    }
    var index = 2;
    while (existingNames.contains('$baseName $index'.toLowerCase())) {
      index++;
    }
    return '$baseName $index';
  }

  /// Actions sur une scène via bottom sheet — pattern tactile (mobile/tablette).
  Future<void> _showBoardActions(SoundBoard board) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Renommer'),
                onTap: () {
                  Navigator.pop(context);
                  _renameBoard(board);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Dupliquer'),
                onTap: () {
                  Navigator.pop(context);
                  _duplicateBoard(board);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Supprimer'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteBoard(board);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Actions sur une scène via menu contextuel — clic droit sur le titre (desktop).
  Future<void> _showBoardContextMenu(
    SoundBoard board,
    Offset globalPosition,
  ) async {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final position = RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      screenSize.width - globalPosition.dx,
      screenSize.height - globalPosition.dy,
    );

    final value = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 18, color: scheme.onSurface),
              const SizedBox(width: AppSpacing.sm),
              const Text('Renommer'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 18, color: scheme.onSurface),
              const SizedBox(width: AppSpacing.sm),
              const Text('Dupliquer'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error),
              const SizedBox(width: AppSpacing.sm),
              Text('Supprimer', style: TextStyle(color: scheme.error)),
            ],
          ),
        ),
      ],
    );

    if (!mounted) return;
    if (value == 'rename') {
      await _renameBoard(board);
    } else if (value == 'duplicate') {
      await _duplicateBoard(board);
    } else if (value == 'delete') {
      await _deleteBoard(board);
    }
  }

  Future<void> _renameBoard(SoundBoard board) async {
    final name = await AppTextInputDialog.show(
      context,
      title: 'Renommer la scène',
      confirmLabel: 'Renommer',
      initialValue: board.name,
      hint: board.name,
      icon: Icons.text_fields_rounded,
    );

    final trimmedName = name?.trim();
    if (trimmedName == null ||
        trimmedName.isEmpty ||
        trimmedName == board.name) {
      return;
    }

    final ok = await _notifier.renameBoard(board, trimmedName);
    if (!mounted) return;
    if (!ok) {
      showCopyableSnackBar(context, 'Erreur lors du renommage de la scène');
    }
  }

  Future<void> _duplicateBoard(SoundBoard board) async {
    final suggestedName = _buildSuggestedDuplicateBoardName(
      board.name,
      _notifier.state.boards,
    );
    final name = await AppTextInputDialog.show(
      context,
      title: 'Dupliquer la scène',
      confirmLabel: 'Dupliquer',
      initialValue: suggestedName,
      hint: suggestedName,
      icon: Icons.copy_rounded,
    );

    final trimmedName = name?.trim();
    if (trimmedName == null || trimmedName.isEmpty) return;

    final duplicated = await _notifier.duplicateBoard(board, trimmedName);
    if (!mounted) return;
    if (duplicated == null) {
      showCopyableSnackBar(
        context,
        'Erreur lors de la duplication de la scène',
      );
    }
  }

  Future<void> _deleteBoard(SoundBoard board) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Supprimer la scène',
      message: 'Supprimer "${board.name}" ? Cette action est irréversible.',
      confirmLabel: 'Supprimer',
      isDestructive: true,
    );

    if (!confirmed) return;

    final ok = await _notifier.deleteBoard(board);
    if (!mounted) return;
    if (!ok) {
      showCopyableSnackBar(
        context,
        'Erreur lors de la suppression de la scène',
      );
    }
  }

  /// Ouvre la bibliothèque sans fermer de drawer (base method).
  Future<void> _openLibrary() async {
    await SoundLibraryManageScreen.open(context, database: _database);
    if (!mounted) return;
    await _notifier.loadSounds();
  }

  /// Ouvre les paramètres sans fermer de drawer (base method).
  Future<void> _openSettings() async {
    if (!mounted) return;
    await SettingsScreen.open(
      context,
      database: _database,
      libraryRepository: widget.services.libraryRepository,
      syncController: widget.services.syncController,
    );
    if (!mounted) return;
    await _notifier.loadSounds();
  }

  Future<void> _handleUndoShortcut() async {
    if (!_isDesktopPlatform || !mounted) return;
    final restoredSoundId = await _notifier.undoLastRemoval();
    if (!mounted || restoredSoundId == null) return;
    setState(() {
      _recentlyRestoredSoundId = restoredSoundId;
    });
    _scrollPadIntoView(restoredSoundId);
    unawaited(
      Future<void>.delayed(_padEmphasisDuration, () {
        if (!mounted || _recentlyRestoredSoundId != restoredSoundId) return;
        setState(() {
          _recentlyRestoredSoundId = null;
        });
      }),
    );
  }

  static const double _itemWidth = 180;
  static const Duration _padEmphasisDuration = Duration(milliseconds: 2200);

  Future<void> _openSoundLibrary(SoundBoard board) async {
    final result = await Navigator.push<SoundLibraryScreenResult>(
      context,
      MaterialPageRoute(
        builder: (context) => SoundLibraryScreen(
          database: _database,
          boardId: board.id,
          libraryRepository: widget.services.libraryRepository,
        ),
      ),
    );
    await _notifier.loadSounds();
    if (!mounted || result == null) return;
    _emphasizePad(result.highlightPadId);
  }

  void _scrollPadIntoView(int padId) {
    void tryScroll() {
      if (!mounted) return;
      final controller = _activeGridScrollController;
      if (!controller.hasClients || controller.positions.length != 1) return;
      final index = _notifier.state.pads.indexWhere((p) => p.pad.id == padId);
      if (index < 0 || _gridViewportWidth <= 0) return;

      const padding = 16.0;
      const crossSpacing = 14.0;
      const mainSpacing = 14.0;
      const aspectRatio = 1.4;

      final contentWidth = _gridViewportWidth - (padding * 2);
      final cellWidth =
          (contentWidth - crossSpacing * (_gridCrossAxisCount - 1)) /
          _gridCrossAxisCount;
      final cellHeight = cellWidth / aspectRatio;
      final row = index ~/ _gridCrossAxisCount;
      final targetTop = padding + row * (cellHeight + mainSpacing);
      final viewport = controller.position.viewportDimension;
      final offset = (targetTop - viewport * 0.25).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );

      controller.animateTo(
        offset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      tryScroll();
      WidgetsBinding.instance.addPostFrameCallback((_) => tryScroll());
    });
  }

  void _toggleEditMode() {
    final outgoing = _activeGridScrollController;
    final savedOffset = outgoing.hasClients && outgoing.positions.length == 1
        ? outgoing.offset
        : 0.0;
    setState(() {
      _isEditMode = !_isEditMode;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final incoming = _activeGridScrollController;
      if (!incoming.hasClients || incoming.positions.length != 1) return;
      incoming.jumpTo(
        savedOffset.clamp(0.0, incoming.position.maxScrollExtent),
      );
    });
  }

  void _emphasizePad(int padId) {
    setState(() {
      _highlightedPadId = padId;
    });
    _scrollPadIntoView(padId);
    unawaited(
      Future<void>.delayed(_padEmphasisDuration, () {
        if (!mounted || _highlightedPadId != padId) return;
        setState(() {
          _highlightedPadId = null;
        });
      }),
    );
  }

  Widget _buildAddButtonCard(BuildContext context, SoundBoard selectedBoard) {
    final scheme = Theme.of(context).colorScheme;
    return _wrapMusicRegieTapTarget(
      Card(
        key: const ValueKey('add_button'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
            style: BorderStyle.solid,
            width: 1.0,
          ),
        ),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.22),
        child: InkWell(
          onTap: () => _openSoundLibrary(selectedBoard),
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_circle_outline_rounded,
                  size: 28,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.82),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ajouter un son',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPadsGrid(
    BuildContext context,
    SamplerState state,
    SoundBoard selectedBoard,
  ) {
    return LayoutBuilder(
      key: ValueKey<bool>(_isEditMode),
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        int crossAxisCount = (screenWidth / _itemWidth).floor();
        crossAxisCount = max(2, crossAxisCount);
        _gridCrossAxisCount = crossAxisCount;
        _gridViewportWidth = screenWidth;
        final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.4,
        );

        if (_isEditMode) {
          return ReorderableGridView.builder(
            key: const ValueKey('pads_reorder_grid'),
            controller: _editGridScrollController,
            padding: const EdgeInsets.all(16),
            gridDelegate: gridDelegate,
            itemCount: state.pads.length,
            dragEnabled: true,
            dragStartDelay: Duration.zero,
            dragWidgetBuilder: (index, child) {
              return Material(
                type: MaterialType.transparency,
                child: Opacity(opacity: 0.95, child: child),
              );
            },
            onDragStart: (index) {
              HapticFeedback.selectionClick();
            },
            onReorder: (oldIndex, newIndex) {
              if (oldIndex == newIndex) return;
              final reordered = List<PadItem>.from(state.pads);
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              _notifier.reorderSoundsFromList(reordered);
            },
            itemBuilder: (context, index) {
              return _buildPadWidget(context, state, state.pads[index]);
            },
          );
        }

        final gridItems = <Object>[...state.pads, _addButtonMarker];
        return GridView.builder(
          key: const ValueKey('pads_normal_grid'),
          controller: _normalGridScrollController,
          padding: const EdgeInsets.all(16),
          gridDelegate: gridDelegate,
          itemCount: gridItems.length,
          itemBuilder: (context, index) {
            final item = gridItems[index];
            if (item == _addButtonMarker) {
              return _buildAddButtonCard(context, selectedBoard);
            }
            return _buildPadWidget(context, state, item as PadItem);
          },
        );
      },
    );
  }

  Widget _wrapMusicRegieTapTarget(Widget child) {
    if (!_isMusicRegieAdvanced) return child;
    return TapRegion(
      groupId: _musicRegieTapGroup,
      child: child,
    );
  }

  void _showPadUnavailableSheet(BuildContext context, PadItem padItem) {
    final reason = padItem.unavailabilityReason!;
    final (title, body) = switch (reason) {
      PadUnavailabilityReason.needsDownload => (
          'Son non téléchargé',
          'Ce pad n\'est pas disponible localement. Synchronisez la bibliothèque pour télécharger les fichiers audio.',
        ),
      PadUnavailabilityReason.offline => (
          'Hors-ligne',
          'Ce pad n\'est pas disponible sans connexion. Reconnectez-vous pour accéder aux fichiers audio.',
        ),
      PadUnavailabilityReason.missingFile => (
          'Fichier introuvable',
          'Le fichier audio de ce pad est introuvable. Re-synchronisez la bibliothèque.',
        ),
    };

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        if (reason != PadUnavailabilityReason.needsDownload) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(body, style: Theme.of(ctx).textTheme.bodyMedium),
              ],
            ),
          );
        }

        // needsDownload : proposer le téléchargement.
        return _PadDownloadSheet(padItem: padItem, notifier: _notifier);
      },
    );
  }

  Widget _buildPadWidget(
    BuildContext context,
    SamplerState state,
    PadItem padItem,
  ) {
    // ValueKey sur la racine : requis par ReorderableGridView (ne pas utiliser GlobalKey ici).
    return _wrapMusicRegieTapTarget(
      PadCard(
        key: ValueKey<int>(padItem.pad.id),
        padItem: padItem,
        isEditMode: _isEditMode,
        animateOnRestore: _recentlyRestoredSoundId == padItem.pad.id,
        isHighlighted: _highlightedPadId == padItem.pad.id,
        onTap: _isEditMode
            ? null
            : padItem.unavailabilityReason != null
                ? () => _showPadUnavailableSheet(context, padItem)
                : () => _notifier.toggleSound(padItem),
        onLongPress: _isEditMode
            ? null
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PadDetailsScreen(
                      padItem: padItem,
                      notifier: _notifier,
                    ),
                  ),
                );
              },
        onRemove: _isEditMode
            ? () async {
                final removed = await _notifier.removeSound(padItem);
                if (!mounted || !removed) return;
              }
            : null,
      ),
    );
  }

  Widget _buildSamplerContent(BuildContext context, SamplerState state) {
    final selectedBoard = state.selectedBoard;
    final isBoardsLoading = state.isBoardsLoading;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Builder(
        key: ValueKey<String>(
          selectedBoard == null
              ? (isBoardsLoading ? 'boards_loading' : 'boards_empty')
              : state.isLoading
              ? 'sounds_loading'
              : state.error != null
              ? 'sounds_error'
              : 'sounds_grid',
        ),
        builder: (context) {
          if (selectedBoard == null) {
            return Center(
              child: isBoardsLoading
                  ? const CircularProgressIndicator()
                  : const Text('Aucune scène disponible'),
            );
          }
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null) {
            return Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Erreur: ${state.error}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          final downloadableCount = state.pads
              .where(
                (p) =>
                    p.unavailabilityReason ==
                    PadUnavailabilityReason.needsDownload,
              )
              .length;
          if (downloadableCount > 0 || state.isBoardPreparing) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPrepareBanner(context, state, downloadableCount),
                Expanded(
                  child: _buildPadsGrid(context, state, selectedBoard),
                ),
              ],
            );
          }
          return _buildPadsGrid(context, state, selectedBoard);
        },
      ),
    );
  }

  Widget _buildPrepareBanner(
    BuildContext context,
    SamplerState state,
    int count,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: state.isBoardPreparing
            ? null
            : () => _notifier.prepareBoardForOffline(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (state.isBoardPreparing)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else
                Icon(
                  Icons.cloud_download_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.isBoardPreparing
                      ? 'Téléchargement en cours…'
                      : '$count son${count > 1 ? 's' : ''} '
                          'non téléchargé${count > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!state.isBoardPreparing)
                Text(
                  'Préparer',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMusicPicker() async {
    await MusicPickerSheet.show(
      context,
      repository: widget.services.soundRepository,
      notifier: _notifier,
    );
  }

  Widget _buildMusicPreviewPanel(BuildContext context, SamplerState state) {
    return TapRegion(
      groupId: _musicRegieTapGroup,
      onTapOutside: _isMusicRegieAdvanced && !_isMusicRegieLocked
          ? (_) => setState(() => _isMusicRegieAdvanced = false)
          : null,
      child: MusicPreviewPanel(
        state: state,
        musicVolume: _notifier.musicVolume,
        resolveMusicPad: _notifier.resolveMusicPad,
        isAdvanced: _isMusicRegieAdvanced,
        isDesktop: _isDesktopPlatform,
        isLocked: _isMusicRegieLocked,
        onLockedChanged: _isDesktopPlatform
            ? (locked) => setState(() => _isMusicRegieLocked = locked)
            : null,
        onAdvancedChanged: (isAdvanced) => setState(() {
          _isMusicRegieAdvanced = isAdvanced;
          if (!isAdvanced) _isMusicRegieLocked = false;
        }),
        onChooseMusic: () => unawaited(_openMusicPicker()),
        onTogglePlayPause: () =>
            unawaited(_notifier.toggleCurrentMusicPlayback()),
        onSkipNext: () => unawaited(_notifier.skipToNextMusic()),
        onRemoveFromQueue: (padId) =>
            unawaited(_notifier.removeFromMusicQueue(padId)),
        onReorderMusicQueue: _notifier.reorderMusicQueue,
        onMusicVolumeChanged: (value) =>
            unawaited(_notifier.setMusicVolume(value, smooth: true)),
        onFadeOut: (duration) =>
            unawaited(_notifier.fadeOutCurrentMusic(duration)),
        onTransitionToNext: (duration) =>
            unawaited(_notifier.crossfadeToNextMusic(duration)),
      ),
    );
  }

  @override
  void dispose() {
    _normalGridScrollController.dispose();
    _editGridScrollController.dispose();
    _notifier.removeListener(_onStateChanged);
    _notifier.dispose();
    super.dispose();
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final state = _notifier.state;
    final selectedBoard = state.selectedBoard;
    final boards = state.boards;
    final isBoardsLoading = state.isBoardsLoading;
    final isDesktop = context.deviceClass.isDesktop;

    if (!isBoardsLoading &&
        boards.isEmpty &&
        !_didAutoOpenCreateForCurrentEmptyState) {
      _didAutoOpenCreateForCurrentEmptyState = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_createBoard());
      });
    } else if (boards.isNotEmpty && _didAutoOpenCreateForCurrentEmptyState) {
      _didAutoOpenCreateForCurrentEmptyState = false;
    }

    return Shortcuts(
      shortcuts: _isDesktopPlatform
          ? const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                  _UndoPadIntent(),
            }
          : const <ShortcutActivator, Intent>{},
      child: Actions(
        actions: <Type, Action<Intent>>{
          _UndoPadIntent: CallbackAction<_UndoPadIntent>(
            onInvoke: (intent) {
              unawaited(_handleUndoShortcut());
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            key: isDesktop ? null : _scaffoldKey,
            appBar: isDesktop
                ? _SamplerDesktopAppBar(
                    selectedBoard: selectedBoard,
                    boards: boards,
                    isBoardsLoading: isBoardsLoading,
                    isEditMode: _isEditMode,
                    canToggleEditMode: state.pads.isNotEmpty,
                    onSelectBoard: _selectBoardDirect,
                    onCreateBoard: _createBoard,
                    onBoardContextMenu: _showBoardContextMenu,
                    onToggleEditMode: _toggleEditMode,
                    onOpenLibrary: _openLibrary,
                    onOpenSettings: _openSettings,
                  )
                : _SamplerAppBar(
                    selectedBoard: selectedBoard,
                    isEditMode: _isEditMode,
                    canToggleEditMode: state.pads.isNotEmpty,
                    onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
                    onToggleEditMode: _toggleEditMode,
                  ),
            drawer: isDesktop
                ? null
                : _BoardsDrawer(
                    boards: boards,
                    selectedBoard: selectedBoard,
                    isBoardsLoading: isBoardsLoading,
                    onSelectBoard: _selectBoard,
                    onCreateBoard: _createBoard,
                    onBoardLongPress: _showBoardActions,
                    onOpenLibrary: () async {
                      Navigator.pop(context);
                      await _openLibrary();
                    },
                    onOpenSettings: () async {
                      Navigator.pop(context);
                      await _openSettings();
                    },
                  ),
            body: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildSamplerContent(context, state),
                  ),
                  _buildMusicPreviewPanel(context, state),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}

// ---------- AppBar (mobile/tablette) ----------

class _SamplerAppBar extends StatelessWidget implements PreferredSizeWidget {
  final SoundBoard? selectedBoard;
  final bool isEditMode;
  final bool canToggleEditMode;
  final VoidCallback onOpenMenu;
  final VoidCallback onToggleEditMode;

  const _SamplerAppBar({
    required this.selectedBoard,
    required this.isEditMode,
    required this.canToggleEditMode,
    required this.onOpenMenu,
    required this.onToggleEditMode,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded),
        tooltip: 'Menu',
        onPressed: onOpenMenu,
      ),
      title: _BoardTitleLabel(board: selectedBoard),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
          height: 1,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            isEditMode ? Icons.done_rounded : Icons.grid_view_rounded,
            color: isEditMode ? scheme.primary : null,
          ),
          tooltip: isEditMode ? 'Terminer l\'édition' : 'Modifier la grille',
          onPressed: canToggleEditMode ? onToggleEditMode : null,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// ---------- Liste des scènes (drawer mobile/tablette) ----------

class _BoardsList extends StatelessWidget {
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board)? onBoardLongPress;
  final Future<void> Function()? onOpenLibrary;
  final Future<void> Function() onOpenSettings;

  const _BoardsList({
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.onSelectBoard,
    required this.onCreateBoard,
    this.onBoardLongPress,
    required this.onOpenLibrary,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(Icons.theater_comedy_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Scènes',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (isBoardsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (boards.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Aucune scène',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                )
              else
                ...boards.map(
                  (board) => ListTile(
                    leading: board.color != null
                        ? _BoardTileIcon(color: board.color!)
                        : null,
                    title: Text(board.name),
                    onTap: () => onSelectBoard(board),
                    onLongPress: onBoardLongPress == null
                        ? null
                        : () => onBoardLongPress!(board),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Nouvelle scène'),
                onTap: () => onCreateBoard(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.library_books_rounded),
          title: const Text('Gérer la bibliothèque'),
          onTap: onOpenLibrary == null ? null : () => onOpenLibrary!(),
        ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: const Text('Paramètres'),
          onTap: () => onOpenSettings(),
        ),
      ],
    );
  }
}

// ---------- Drawer (mobile/tablette) ----------

class _BoardsDrawer extends StatelessWidget {
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board) onBoardLongPress;
  final Future<void> Function()? onOpenLibrary;
  final Future<void> Function() onOpenSettings;

  const _BoardsDrawer({
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.onSelectBoard,
    required this.onCreateBoard,
    required this.onBoardLongPress,
    required this.onOpenLibrary,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: _BoardsList(
          boards: boards,
          selectedBoard: selectedBoard,
          isBoardsLoading: isBoardsLoading,
          onSelectBoard: onSelectBoard,
          onCreateBoard: onCreateBoard,
          onBoardLongPress: onBoardLongPress,
          onOpenLibrary: onOpenLibrary,
          onOpenSettings: onOpenSettings,
        ),
      ),
    );
  }
}

// ---------- AppBar desktop ----------

class _SamplerDesktopAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final SoundBoard? selectedBoard;
  final List<SoundBoard> boards;
  final bool isBoardsLoading;
  final bool isEditMode;
  final bool canToggleEditMode;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board, Offset position)
      onBoardContextMenu;
  final VoidCallback onToggleEditMode;
  final Future<void> Function() onOpenLibrary;
  final Future<void> Function() onOpenSettings;

  const _SamplerDesktopAppBar({
    required this.selectedBoard,
    required this.boards,
    required this.isBoardsLoading,
    required this.isEditMode,
    required this.canToggleEditMode,
    required this.onSelectBoard,
    required this.onCreateBoard,
    required this.onBoardContextMenu,
    required this.onToggleEditMode,
    required this.onOpenLibrary,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      leading: _BoardsMenuButton(
        boards: boards,
        selectedBoard: selectedBoard,
        isBoardsLoading: isBoardsLoading,
        onSelectBoard: onSelectBoard,
        onCreateBoard: onCreateBoard,
        onOpenLibrary: onOpenLibrary,
        onOpenSettings: onOpenSettings,
      ),
      title: GestureDetector(
        onSecondaryTapDown: selectedBoard != null
            ? (details) =>
                onBoardContextMenu(selectedBoard!, details.globalPosition)
            : null,
        child: Tooltip(
          message: selectedBoard != null
              ? 'Clic droit pour les actions…'
              : '',
          child: _BoardTitleLabel(board: selectedBoard),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
          height: 1,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            isEditMode ? Icons.done_rounded : Icons.grid_view_rounded,
            color: isEditMode ? scheme.primary : null,
          ),
          tooltip: isEditMode ? 'Terminer l\'édition' : 'Modifier la grille',
          onPressed: canToggleEditMode ? onToggleEditMode : null,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// ---------- Menu popup scènes (desktop) ----------

class _BoardsMenuButton extends StatelessWidget {
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function() onOpenLibrary;
  final Future<void> Function() onOpenSettings;

  const _BoardsMenuButton({
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.onSelectBoard,
    required this.onCreateBoard,
    required this.onOpenLibrary,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: 'Scènes',
      icon: const Icon(Icons.menu_rounded),
      itemBuilder: (context) => [
        if (isBoardsLoading)
          const PopupMenuItem<Object>(
            enabled: false,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (boards.isEmpty)
          const PopupMenuItem<Object>(
            enabled: false,
            child: Text('Aucune scène'),
          )
        else
          ...boards.map(
            (board) => PopupMenuItem<Object>(
              value: board,
              child: Row(
                children: [
                  if (board.color != null) ...[
                    _BoardTileIcon(color: board.color!),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Text(board.name),
                ],
              ),
            ),
          ),
        const PopupMenuItem<Object>(
          value: 'create',
          child: Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: AppSpacing.sm),
              Text('Nouvelle scène'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          value: 'library',
          child: Row(
            children: [
              Icon(Icons.library_books_rounded, size: 18),
              SizedBox(width: AppSpacing.sm),
              Text('Gérer la bibliothèque'),
            ],
          ),
        ),
        const PopupMenuItem<Object>(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings, size: 18),
              SizedBox(width: AppSpacing.sm),
              Text('Paramètres'),
            ],
          ),
        ),
      ],
      onSelected: (value) async {
        if (value is SoundBoard) {
          await onSelectBoard(value);
        } else if (value == 'create') {
          await onCreateBoard();
        } else if (value == 'library') {
          await onOpenLibrary();
        } else if (value == 'settings') {
          await onOpenSettings();
        }
      },
    );
  }
}

// ---------- Titre de scène dans l'AppBar (icône + nom) ----------

class _BoardTitleLabel extends StatelessWidget {
  const _BoardTitleLabel({this.board});

  final SoundBoard? board;

  @override
  Widget build(BuildContext context) {
    final showIcon = board != null && board!.color != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showIcon) ...[
          _BoardTileIcon(color: board!.color!),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Text(
            board?.name ?? 'Scène',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ---------- Feuille de téléchargement d'un pad ----------

class _PadDownloadSheet extends StatefulWidget {
  final PadItem padItem;
  final SamplerNotifier notifier;

  const _PadDownloadSheet({required this.padItem, required this.notifier});

  @override
  State<_PadDownloadSheet> createState() => _PadDownloadSheetState();
}

class _PadDownloadSheetState extends State<_PadDownloadSheet> {
  bool _isDownloading = false;
  bool _failed = false;

  Future<void> _download() async {
    setState(() {
      _isDownloading = true;
      _failed = false;
    });
    final ok = await widget.notifier.downloadAndLoadPad(widget.padItem);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isDownloading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Son non téléchargé',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Ce pad n\'est pas encore disponible localement.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_failed) ...[
            const SizedBox(height: 8),
            Text(
              'Téléchargement échoué. Vérifiez la connexion.',
              style: TextStyle(color: scheme.error, fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isDownloading ? null : _download,
              icon: _isDownloading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.cloud_download_outlined, size: 18),
              label: Text(_isDownloading ? 'Téléchargement…' : 'Télécharger'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Icône de scène (couleur + icône) ----------

class _BoardTileIcon extends StatelessWidget {
  const _BoardTileIcon({required this.color});

  final int color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Color(color),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );
  }
}
