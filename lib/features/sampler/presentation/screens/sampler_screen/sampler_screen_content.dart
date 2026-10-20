// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sampler_screen.dart';

/// Contenu central : bandeau de préparation, régie musique et ambiance.
/// Méthodes de [_SamplerScreenState] extraites via extension dans le même `part`.
extension _SamplerScreenContent on _SamplerScreenState {
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
        // Inclut l'id du board : sinon le switcher ne remonte pas la grille
        // au changement de scène (et une GlobalKey partagée plantait ici).
        key: ValueKey<String>(
          selectedBoard == null
              ? (isBoardsLoading ? 'boards_loading' : 'boards_empty')
              : state.isLoading && state.pads.isEmpty
              ? 'sounds_loading_${selectedBoard.id}'
              : state.error != null && state.pads.isEmpty
              ? 'sounds_error_${selectedBoard.id}'
              : 'sounds_grid_${selectedBoard.id}',
        ),
        builder: (context) {
          if (selectedBoard == null) {
            if (isBoardsLoading) {
              return const SizedBox.shrink();
            }
            return const Center(child: Text('Aucune scène disponible'));
          }
          if (state.isLoading && state.pads.isEmpty) {
            return const SizedBox.shrink();
          }
          if (state.error != null && state.pads.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 40,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Erreur: ${state.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final downloadableCount = state.pads
              .where(_notifier.isPadPreparable)
              .length;
          final showPrepareBanner =
              _notifier.allowsSoundDownload &&
              (downloadableCount > 0 || state.isBoardPreparing);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.error != null)
                Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.error!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOutCubic,
                child: showPrepareBanner
                    ? _buildPrepareBanner(context, state, downloadableCount)
                    : const SizedBox.shrink(),
              ),
              Expanded(child: _buildPadsGrid(context, state, selectedBoard)),
            ],
          );
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

    if (state.isBoardPreparing) {
      final total = state.boardPrepareTotal;
      final done = state.boardPrepareDone;
      final progress = total > 0 ? done / total : 0.0;
      return ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$done/$total son${total > 1 ? 's' : ''} téléchargé${done != 1 ? 's' : ''}',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                builder: (ctx, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(scheme.primary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => _notifier.prepareBoardForOffline(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.cloud_download_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$count son${count > 1 ? 's' : ''} '
                  'non téléchargé${count > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
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

  /// Bouton lecture de la régie sans rien de chargé : la musique choisie
  /// part immédiatement au lieu d'aller en file.
  Future<void> _openMusicPickerToPlay() async {
    await SoundPickerOverlay.showForMusic(
      context,
      notifier: _notifier,
      playNow: true,
    );
  }

  /// Voie ambiance de la régie : l'ambiance choisie part tout de suite.
  Future<void> _openAmbiancePicker() async {
    await SoundPickerOverlay.showForAmbiance(context, notifier: _notifier);
  }

  Widget _buildMusicPreviewPanel(BuildContext context, SamplerState state) {
    return MusicPreviewPanel(
      state: state,
      musicVolume: _notifier.musicVolume,
      resolveMusicPad: _notifier.resolveMusicPad,
      ambianceVolume: _notifier.ambianceVolume,
      onChooseAmbiance: () => unawaited(_openAmbiancePicker()),
      onStopAmbiance: (fade) => unawaited(
        _notifier.stopCurrentAmbiance(
          fade: fade ?? AmbianceController.stopFadeDuration,
        ),
      ),
      onAmbianceVolumeChanged: (value) =>
          unawaited(_notifier.setAmbianceVolume(value, smooth: true)),
      isAdvanced: _isMusicRegieAdvanced,
      isDesktop: context.prefersDesktopUi,
      onAdvancedChanged: (isAdvanced) =>
          setState(() => _isMusicRegieAdvanced = isAdvanced),
      onChooseMusic: () => unawaited(_openMusicPicker()),
      onChooseMusicToPlay: () => unawaited(_openMusicPickerToPlay()),
      onTogglePlayPause: () =>
          unawaited(_notifier.toggleCurrentMusicPlayback()),
      onSkipNext: () => unawaited(_notifier.skipToNextMusic()),
      onEjectMusic: () => unawaited(_notifier.stopCurrentMusic()),
      onRemoveFromQueue: (padId) =>
          unawaited(_notifier.removeFromMusicQueue(padId)),
      onReorderMusicQueue: _notifier.reorderMusicQueue,
      onMusicVolumeChanged: (value) =>
          unawaited(_notifier.setMusicVolume(value, smooth: true)),
      onFadeOut: (duration) =>
          unawaited(_notifier.fadeOutCurrentMusic(duration)),
      onTransitionToNext: (duration) =>
          unawaited(_notifier.crossfadeToNextMusic(duration)),
      onSeekMusic: (position) => unawaited(_notifier.seekPausedMusic(position)),
      onOccupiedHeightChanged: context.prefersDesktopUi
          ? null
          : (height) {
              if ((height - _musicRegieOccupiedHeight).abs() < 0.5) return;
              setState(() => _musicRegieOccupiedHeight = height);
            },
    );
  }
}
