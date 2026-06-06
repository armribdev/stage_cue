import 'dart:async';
import 'dart:math' show max, min;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import '../providers/sampler_provider.dart';
import '../widgets/pad_item.dart' show PadCard;
import '../widgets/music_preview_panel.dart';
import '../widgets/music_picker_sheet.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/sound_board.dart';
import '../../../../core/app/app_services.dart';
import '../../../../core/utils/copyable_snackbar.dart';
import '../../../../core/database/database.dart' as db;
import 'settings_screen.dart';
import 'pad_details_screen.dart';
import 'sound_library_screen.dart';
import 'sound_library_manage_screen.dart';
import '../utils/sound_type_ui.dart';

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

  static const _musicRegieTapGroup = 'music-regie-dismiss';

  bool get _isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool _restartNotified = false;

  @override
  void initState() {
    super.initState();
    _database = widget.services.database;
    _initializeNotifier();
    // Surface l'application différée d'un snapshot tiré (auto-pull au lancement).
    widget.services.syncController.addListener(_onSyncChanged);
    _notifier.loadBoards();
  }

  void _onSyncChanged() {
    if (!mounted || _restartNotified) return;
    if (!widget.services.syncController.state.pendingRestart) return;
    _restartNotified = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Nouvelle version récupérée depuis Drive — redémarre l\'app pour l\'appliquer',
        ),
        duration: Duration(seconds: 6),
      ),
    );
  }

  void _initializeNotifier() {
    // Initialiser les dépendances
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

  Future<void> _selectBoard(SoundBoard board) async {
    Navigator.pop(context);
    await _notifier.selectBoard(board);
  }

  Future<void> _createBoard() async {
    if (!mounted) {
      return;
    }

    final suggestedName = _buildSuggestedBoardName(_notifier.state.boards);
    final nameController = TextEditingController();
    final nameFocusNode = FocusNode();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        final dialogWidth = min(
          560.0,
          MediaQuery.of(dialogContext).size.width - 48,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (nameFocusNode.canRequestFocus && !nameFocusNode.hasFocus) {
            nameFocusNode.requestFocus();
          }
        });
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
          actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          buttonPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: const Text('Nouvelle scène'),
          content: SizedBox(
            width: dialogWidth,
            child: TextField(
              controller: nameController,
              focusNode: nameFocusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) =>
                  Navigator.of(dialogContext).pop(nameController.text.trim()),
              decoration: InputDecoration(
                hintText: suggestedName,
                prefixIcon: Icon(
                  Icons.auto_awesome_rounded,
                  color: scheme.primary.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(nameController.text.trim()),
              child: const Text('Créer'),
            ),
          ],
        );
      },
    );
    nameController.dispose();
    nameFocusNode.dispose();

    final trimmedName = name?.trim();
    if (trimmedName == null || !mounted) {
      return;
    }
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    final finalName = trimmedName.isEmpty ? suggestedName : trimmedName;
    final newBoard = await _notifier.createBoard(finalName);
    if (!mounted) {
      return;
    }
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

  Future<void> _renameBoard(SoundBoard board) async {
    final nameController = TextEditingController(text: board.name);
    final nameFocusNode = FocusNode();
    final dialogWidth = min(560.0, MediaQuery.of(context).size.width - 48);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (nameFocusNode.canRequestFocus && !nameFocusNode.hasFocus) {
            nameFocusNode.requestFocus();
          }
        });
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
          actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          buttonPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: const Text('Renommer la scène'),
          content: SizedBox(
            width: dialogWidth,
            child: TextField(
              controller: nameController,
              focusNode: nameFocusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) =>
                  Navigator.of(dialogContext).pop(nameController.text.trim()),
              decoration: InputDecoration(
                hintText: board.name,
                prefixIcon: Icon(
                  Icons.text_fields_rounded,
                  color: scheme.primary.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(nameController.text.trim()),
              child: const Text('Renommer'),
            ),
          ],
        );
      },
    );
    nameController.dispose();
    nameFocusNode.dispose();

    final trimmedName = name?.trim();
    if (trimmedName == null ||
        trimmedName.isEmpty ||
        trimmedName == board.name) {
      return;
    }

    final ok = await _notifier.renameBoard(board, trimmedName);
    if (!mounted) {
      return;
    }
    if (!ok) {
      showCopyableSnackBar(context, 'Erreur lors du renommage de la scène');
    }
  }

  Future<void> _duplicateBoard(SoundBoard board) async {
    final suggestedName = _buildSuggestedDuplicateBoardName(
      board.name,
      _notifier.state.boards,
    );
    final nameController = TextEditingController(text: suggestedName);
    final nameFocusNode = FocusNode();
    final dialogWidth = min(560.0, MediaQuery.of(context).size.width - 48);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (nameFocusNode.canRequestFocus && !nameFocusNode.hasFocus) {
            nameFocusNode.requestFocus();
          }
        });
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
          actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          buttonPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: const Text('Dupliquer la scène'),
          content: SizedBox(
            width: dialogWidth,
            child: TextField(
              controller: nameController,
              focusNode: nameFocusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) =>
                  Navigator.of(dialogContext).pop(nameController.text.trim()),
              decoration: InputDecoration(
                hintText: suggestedName,
                prefixIcon: Icon(
                  Icons.copy_rounded,
                  color: scheme.primary.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(nameController.text.trim()),
              child: const Text('Dupliquer'),
            ),
          ],
        );
      },
    );
    nameController.dispose();
    nameFocusNode.dispose();

    final trimmedName = name?.trim();
    if (trimmedName == null || trimmedName.isEmpty) {
      return;
    }

    final duplicated = await _notifier.duplicateBoard(board, trimmedName);
    if (!mounted) {
      return;
    }
    if (duplicated == null) {
      showCopyableSnackBar(context, 'Erreur lors de la duplication de la scène');
    }
  }

  Future<void> _deleteBoard(SoundBoard board) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer la scène'),
          content: Text(
            'Supprimer "${board.name}" ? Cette action est irréversible.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final ok = await _notifier.deleteBoard(board);
    if (!mounted) {
      return;
    }
    if (!ok) {
      showCopyableSnackBar(context, 'Erreur lors de la suppression de la scène');
    }
  }

  Future<void> _handleUndoShortcut() async {
    if (!_isDesktopPlatform || !mounted) {
      return;
    }
    final restoredSoundId = await _notifier.undoLastRemoval();
    if (!mounted || restoredSoundId == null) {
      return;
    }
    setState(() {
      _recentlyRestoredSoundId = restoredSoundId;
    });
    _scrollPadIntoView(restoredSoundId);
    unawaited(
      Future<void>.delayed(_padEmphasisDuration, () {
        if (!mounted || _recentlyRestoredSoundId != restoredSoundId) {
          return;
        }
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
    if (!mounted || result == null) {
      return;
    }
    _emphasizePad(result.highlightPadId);
  }

  void _scrollPadIntoView(int padId) {
    void tryScroll() {
      if (!mounted) return;
      final controller = _activeGridScrollController;
      if (!controller.hasClients || controller.positions.length != 1) {
        return;
      }
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
        if (!mounted || _highlightedPadId != padId) {
          return;
        }
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
        onTap: _isEditMode ? null : () => _notifier.toggleSound(padItem),
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
              : state.pads.isEmpty
              ? 'sounds_empty'
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
          if (state.pads.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      SoundType.soundEffect.icon,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Aucun son dans la scène',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ajoutez des sons depuis la bibliothèque',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => _openSoundLibrary(selectedBoard),
                      icon: const Icon(Icons.library_music_rounded),
                      label: const Text('Ouvrir la bibliothèque'),
                    ),
                  ],
                ),
              ),
            );
          }
          return _buildPadsGrid(context, state, selectedBoard);
        },
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
      onTapOutside: _isMusicRegieAdvanced
          ? (_) => setState(() => _isMusicRegieAdvanced = false)
          : null,
      child: MusicPreviewPanel(
        state: state,
        musicVolume: _notifier.musicVolume,
        resolveMusicPad: _notifier.resolveMusicPad,
        isAdvanced: _isMusicRegieAdvanced,
        onAdvancedChanged: (isAdvanced) =>
            setState(() => _isMusicRegieAdvanced = isAdvanced),
        onChooseMusic: () => unawaited(_openMusicPicker()),
      onTogglePlayPause: () =>
          unawaited(_notifier.toggleCurrentMusicPlayback()),
      onRestart: () => unawaited(_notifier.restartCurrentMusic()),
      onSkipNext: () => unawaited(_notifier.skipToNextMusic()),
      onStopCurrent: () => unawaited(_notifier.stopCurrentMusic()),
      onClearQueue: () => unawaited(_notifier.clearMusicQueue()),
      onPlayNextInQueue: () => unawaited(_notifier.playNextInQueueNow()),
      onRemoveFromQueue: (padId) =>
          unawaited(_notifier.removeFromMusicQueue(padId)),
      onMusicVolumeChanged: (value) => unawaited(_notifier.setMusicVolume(value)),
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
    widget.services.syncController.removeListener(_onSyncChanged);
    _notifier.removeListener(_onStateChanged);
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _notifier.state;
    final selectedBoard = state.selectedBoard;
    final boards = state.boards;
    final isBoardsLoading = state.isBoardsLoading;

    if (!isBoardsLoading &&
        boards.isEmpty &&
        !_didAutoOpenCreateForCurrentEmptyState) {
      _didAutoOpenCreateForCurrentEmptyState = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
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
            key: _scaffoldKey,
            appBar: _SamplerAppBar(
              title: selectedBoard == null ? 'Scène' : selectedBoard.name,
              isEditMode: _isEditMode,
              canToggleEditMode: state.pads.isNotEmpty,
              onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
              onToggleEditMode: _toggleEditMode,
            ),
            drawer: _BoardsDrawer(
              boards: boards,
              selectedBoard: selectedBoard,
              isBoardsLoading: isBoardsLoading,
              onCreateBoard: _createBoard,
              onSelectBoard: _selectBoard,
              onBoardLongPress: _showBoardActions,
              onOpenLibrary: () async {
                      Navigator.pop(context);
                      await SoundLibraryManageScreen.open(
                        context,
                        database: _database,
                      );
                      await _notifier.loadSounds();
                    },
              onOpenSettings: () async {
                Navigator.pop(context);
                await SettingsScreen.open(
                  context,
                  database: _database,
                  libraryRepository: widget.services.libraryRepository,
                  syncController: widget.services.syncController,
                );
                await _notifier.loadSounds();
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

class _SamplerAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool isEditMode;
  final bool canToggleEditMode;
  final VoidCallback onOpenMenu;
  final VoidCallback onToggleEditMode;

  const _SamplerAppBar({
    required this.title,
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
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
          tooltip: isEditMode ? 'Terminer l’édition' : 'Modifier la grille',
          onPressed: canToggleEditMode ? onToggleEditMode : null,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _BoardsDrawer extends StatelessWidget {
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function(SoundBoard board) onBoardLongPress;
  final Future<void> Function()? onOpenLibrary;
  final Future<void> Function() onOpenSettings;

  const _BoardsDrawer({
    required this.boards,
    required this.selectedBoard,
    required this.isBoardsLoading,
    required this.onCreateBoard,
    required this.onSelectBoard,
    required this.onBoardLongPress,
    required this.onOpenLibrary,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Column(
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
                    ...boards.map((board) {
                      return ListTile(
                        title: Text(board.name),
                        selected: selectedBoard?.id == board.id,
                        onLongPress: () => onBoardLongPress(board),
                        onTap: () => onSelectBoard(board),
                      );
                    }),
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
              onTap: onOpenLibrary == null
                  ? null
                  : () async {
                      await onOpenLibrary!();
                    },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Paramètres'),
              onTap: () async {
                await onOpenSettings();
              },
            ),
          ],
        ),
      ),
    );
  }
}
