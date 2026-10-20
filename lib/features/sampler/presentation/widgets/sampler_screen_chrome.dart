import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/skeleton.dart';
import '../../../../core/utils/layout_utils.dart';
import '../../domain/entities/sound_board.dart';
import '../providers/sampler_provider.dart';
import 'audio_vu_meter.dart';
import 'boxed_icon_button.dart';
import 'unprocessed_badge.dart';
import 'waveform_mark_button.dart';

part 'sampler_boards_chrome.dart';

/// Barre d'AppBar mobile/tablette du sampler (hamburger ou sortie live, titre
/// de scène, stop / recherche).
class SamplerAppBar extends StatelessWidget implements PreferredSizeWidget {
  final SoundBoard? selectedBoard;
  final bool isPerformanceMode;
  final VoidCallback onOpenMenu;
  final VoidCallback onTogglePerformanceMode;
  final VoidCallback onQuickSearch;
  final Widget stopAllButton;

  const SamplerAppBar({super.key, 
    required this.selectedBoard,
    required this.isPerformanceMode,
    required this.onOpenMenu,
    required this.onTogglePerformanceMode,
    required this.onQuickSearch,
    required this.stopAllButton,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      automaticallyImplyLeading: false,
      // En session live : la bascule étant la seule action du menu, le hamburger
      // cède la place à un bouton de sortie direct (un clic). Hors session, le
      // hamburger ouvre le tiroir (mode live / bibliothèque / paramètres).
      leading: isPerformanceMode
          ? LiveExitButton(onExit: onTogglePerformanceMode)
          : BoxedIconButton(
              icon: Icons.menu_rounded,
              tooltip: 'Menu',
              onPressed: onOpenMenu,
            ),
      title: BoardTitleLabel(board: selectedBoard),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: AppElevation.border(scheme).color,
          height: 1,
        ),
      ),
      actions: [
        // Vumètre de sortie : uniquement là où la barre a la place (tablette+).
        if (context.deviceClass.isAtLeastTablet)
          const Center(child: AudioVuMeter()),
        stopAllButton,
        BoxedIconButton(
          icon: Icons.search_rounded,
          tooltip: 'Recherche rapide',
          onPressed: onQuickSearch,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// ---------- Bouton « Tout arrêter » (bruitages) ----------

/// Bouton panique : coupe d'un coup tous les pads non-musique en cours, sans
/// toucher au tapis musical. Absent tant qu'aucun bruitage ne joue.
class StopAllButton extends StatelessWidget {
  final SamplerNotifier notifier;

  const StopAllButton({super.key, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) {
        // Rien à arrêter → bouton retiré de la barre (plutôt que grisé).
        if (!notifier.hasNonMusicSoundsPlaying) {
          return const SizedBox.shrink();
        }
        void handleTap() {
          unawaited(HapticFeedback.heavyImpact());
          unawaited(notifier.panicStop());
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Tooltip(
            message: isNativeDesktopPlatform()
                ? 'Tout arrêter (Échap)'
                : 'Tout arrêter',
            child: InkWell(
              borderRadius: AppRadius.radiusMd,
              onTap: handleTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + 2,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.radiusMd,
                  border: Border.all(color: scheme.error.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.stop_rounded, size: 14, color: scheme.error),
                    const SizedBox(width: 4),
                    Text(
                      'Stop',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------- Icône « en direct » (voyant live pulsé) ----------

/// Icône + voyant rouge pulsé — même langage visuel que le badge ON AIR.
/// [baseIcon] permet de réutiliser le voyant sur différentes icônes (menu, masque).
class LiveModeActiveIcon extends StatefulWidget {
  final IconData baseIcon;

  const LiveModeActiveIcon({super.key}) : baseIcon = Icons.theater_comedy_rounded;

  @override
  State<LiveModeActiveIcon> createState() => _LiveModeActiveIconState();
}

class _LiveModeActiveIconState extends State<LiveModeActiveIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _pulse = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 1.0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(widget.baseIcon, color: scheme.error),
          Positioned(
            right: -2,
            top: -2,
            child: FadeTransition(
              opacity: _pulse,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: scheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- AppBar desktop ----------

/// Barre d'AppBar desktop : menu hamburger, sélecteur de scène, stop / recherche.
class SamplerDesktopAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final SoundBoard? selectedBoard;
  final List<SoundBoard> boards;
  final bool isBoardsLoading;
  final Future<void> Function(SoundBoard board) onSelectBoard;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function(SoundBoard board, Offset position)
  onBoardContextMenu;
  final bool isPerformanceMode;
  final VoidCallback onTogglePerformanceMode;
  final Future<void> Function() onOpenLibrary;
  final Future<void> Function() onOpenSettings;
  final VoidCallback onQuickSearch;
  final Widget stopAllButton;
  final bool? isWindowsFullScreen;
  final VoidCallback? onToggleWindowsFullScreen;
  final VoidCallback? onQuitApp;

  /// Sons restant à traiter (badge du menu). `null` = pas de badge.
  final ValueListenable<int>? unprocessedCount;

  const SamplerDesktopAppBar({super.key,
    this.unprocessedCount,
    required this.selectedBoard,
    required this.boards,
    required this.isBoardsLoading,
    required this.onSelectBoard,
    required this.onCreateBoard,
    required this.onBoardContextMenu,
    required this.isPerformanceMode,
    required this.onTogglePerformanceMode,
    required this.onOpenLibrary,
    required this.onOpenSettings,
    required this.onQuickSearch,
    required this.stopAllButton,
    this.isWindowsFullScreen,
    this.onToggleWindowsFullScreen,
    this.onQuitApp,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      automaticallyImplyLeading: false,
      // Largeur resserrée sur celle de la marque (32px + padding 4px de
      // chaque côté) : la valeur par défaut (56) laissait un espace mort
      // avant le sélecteur de scène. `titleSpacing: 0` retire l'espacement
      // minimal que l'AppBar impose sinon entre `leading` et `title`.
      leadingWidth: 40,
      titleSpacing: 0,
      // Menu hamburger : regroupe mode live / bibliothèque / paramètres. Toujours
      // accessible — c'est la seule porte de sortie du Mode Spectacle.
      leading: SamplerDesktopMenuButton(
        unprocessedCount: unprocessedCount,
        isPerformanceMode: isPerformanceMode,
        onTogglePerformanceMode: onTogglePerformanceMode,
        onOpenLibrary: onOpenLibrary,
        onOpenSettings: onOpenSettings,
        isWindowsFullScreen: isWindowsFullScreen,
        onToggleWindowsFullScreen: onToggleWindowsFullScreen,
        onQuitApp: onQuitApp,
      ),
      title: BoardSceneSelector(
        boards: boards,
        selectedBoard: selectedBoard,
        isBoardsLoading: isBoardsLoading,
        onSelectBoard: onSelectBoard,
        onCreateBoard: onCreateBoard,
        onBoardContextMenu: onBoardContextMenu,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: AppElevation.border(scheme).color,
          height: 1,
        ),
      ),
      actions: [
        stopAllButton,
        BoxedIconButton(
          icon: Icons.search_rounded,
          tooltip: 'Recherche rapide (Ctrl+F)',
          onPressed: onQuickSearch,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// ---------- Menu hamburger (desktop) ----------

/// Menu déroulant desktop regroupant, dans l'ordre : bascule du mode live,
/// gestion de bibliothèque, paramètres. En Mode Spectacle, seul « Quitter le
/// mode live » reste proposé (préserve le verrouillage anti-modif du live) et
/// l'icône reprend le voyant rouge pulsé « en direct ».
class SamplerDesktopMenuButton extends StatelessWidget {
  final bool isPerformanceMode;
  final VoidCallback onTogglePerformanceMode;
  final Future<void> Function() onOpenLibrary;
  final Future<void> Function() onOpenSettings;
  final bool? isWindowsFullScreen;
  final VoidCallback? onToggleWindowsFullScreen;
  final VoidCallback? onQuitApp;

  /// Sons restant à traiter : pastille sur « Gérer la bibliothèque » et point
  /// sur le bouton menu. `null` = pas de badge.
  final ValueListenable<int>? unprocessedCount;

  const SamplerDesktopMenuButton({super.key,
    this.unprocessedCount,
    required this.isPerformanceMode,
    required this.onTogglePerformanceMode,
    required this.onOpenLibrary,
    required this.onOpenSettings,
    this.isWindowsFullScreen,
    this.onToggleWindowsFullScreen,
    this.onQuitApp,
  });

  /// Ouvre le menu via `showMenu` positionné sous le bouton, plutôt que de
  /// passer par `PopupMenuButton.child` : ce dernier imbriquerait son propre
  /// `InkWell`/`Tooltip` autour de [BoxedIconButton], qui les fournit déjà —
  /// deux calques de retour visuel superposés pour une seule action.
  Future<void> _openMenu(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    final fullScreen = isWindowsFullScreen;
    final toggleFullScreen = onToggleWindowsFullScreen;
    final quitApp = onQuitApp;

    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(
          Offset(0, button.size.height + 8),
          ancestor: overlay,
        ),
        button.localToGlobal(
          button.size.bottomRight(const Offset(0, 8)),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final value = await showMenu<String>(
      context: context,
      position: position,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      items: [
        PopupMenuItem<String>(
          value: 'live',
          height: AppMenu.itemHeight,
          padding: AppMenu.itemPadding,
          child: Row(
            children: [
              Icon(
                Icons.theater_comedy_rounded,
                size: 18,
                color: scheme.onSurface,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text('Démarrer une session live'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'library',
          height: AppMenu.itemHeight,
          padding: AppMenu.itemPadding,
          child: Row(
            children: [
              Icon(
                Icons.library_books_rounded,
                size: 18,
                color: scheme.onSurface,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text('Gérer la bibliothèque'),
              if (unprocessedCount case final count?) ...[
                const SizedBox(width: AppSpacing.sm),
                UnprocessedCountPill(count: count),
              ],
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'settings',
          height: AppMenu.itemHeight,
          padding: AppMenu.itemPadding,
          child: Row(
            children: [
              Icon(Icons.settings, size: 18, color: scheme.onSurface),
              const SizedBox(width: AppSpacing.sm),
              const Text('Paramètres'),
            ],
          ),
        ),
        if (toggleFullScreen != null)
          PopupMenuItem<String>(
            value: 'fullscreen',
            height: AppMenu.itemHeight,
            padding: AppMenu.itemPadding,
            child: Row(
              children: [
                Icon(
                  fullScreen == true
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  size: 18,
                  color: scheme.onSurface,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  fullScreen == true
                      ? 'Quitter le plein écran'
                      : 'Plein écran',
                ),
              ],
            ),
          ),
        // Uniquement en plein écran : la fenêtre n'a alors plus de barre de
        // titre ni de bouton de fermeture natif pour quitter l'app.
        if (fullScreen == true && quitApp != null)
          PopupMenuItem<String>(
            value: 'quit',
            height: AppMenu.itemHeight,
            padding: AppMenu.itemPadding,
            child: Row(
              children: [
                Icon(
                  Icons.exit_to_app_rounded,
                  size: 18,
                  color: scheme.onSurface,
                ),
                const SizedBox(width: AppSpacing.sm),
                const Text('Quitter'),
              ],
            ),
          ),
      ],
    );

    if (!context.mounted || value == null) return;
    switch (value) {
      case 'live':
        onTogglePerformanceMode();
      case 'library':
        unawaited(onOpenLibrary());
      case 'settings':
        unawaited(onOpenSettings());
      case 'fullscreen':
        toggleFullScreen?.call();
      case 'quit':
        quitApp?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    // En session live : la bascule étant la seule action disponible, on remplace
    // le menu par un bouton de sortie direct (un clic).
    if (isPerformanceMode) {
      return LiveExitButton(onExit: onTogglePerformanceMode);
    }

    return Builder(
      builder: (buttonContext) {
        final button = WaveformMarkButton(
          tooltip: 'Menu',
          onPressed: () => unawaited(_openMenu(buttonContext)),
        );
        final count = unprocessedCount;
        return count == null
            ? button
            : UnprocessedDot(count: count, child: button);
      },
    );
  }
}

/// Bouton de sortie de session live : voyant rouge pulsé « en direct » sur le
/// masque de théâtre, action en un clic. Remplace le menu quand la session est
/// active (la sortie est alors la seule action pertinente).
class LiveExitButton extends StatelessWidget {
  final VoidCallback onExit;

  const LiveExitButton({super.key, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const LiveModeActiveIcon(),
      tooltip: 'Quitter la session live',
      onPressed: onExit,
    );
  }
}

// ---------- Sélecteur de scène (desktop) ----------

/// Menu déroulant desktop pour choisir / créer une scène.
