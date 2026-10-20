// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sound_picker_overlay.dart';

/// Liste des résultats : lignes, sous-titres, actions de fin de ligne.
/// Méthodes de [_SoundPickerOverlayState] extraites via extension dans le même `part`.
extension _SoundPickerResults on _SoundPickerOverlayState {
  Widget _buildResults(
    ColorScheme scheme,
    List<Sound> shown,
    int selectedIndex,
  ) {
    if (_loading || _awaitingLocalIds) {
      return _buildLoadingSkeleton();
    }

    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            _emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isBrowseMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'FAVORIS & RÉCENTS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: ClipRect(
            child: ListView.builder(
              controller: _scrollController,
              itemExtent: _itemExtent,
              padding: EdgeInsets.zero,
              itemCount: shown.length,
              itemBuilder: (context, index) => _buildItem(
                shown[index],
                index,
                index == selectedIndex,
                scheme,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Placeholders animés qui épousent la forme des items de résultat
  /// (icône + titre + sous-titre + bouton d'action) le temps du chargement.
  Widget _buildLoadingSkeleton() {
    return Skeleton(
      child: ListView.builder(
        itemExtent: _itemExtent,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 7,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const SkeletonBox(width: 24, height: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(widthFactor: index.isEven ? 0.7 : 0.5),
                    const SizedBox(height: 7),
                    SkeletonLine(
                      widthFactor: index.isEven ? 0.3 : 0.4,
                      height: 10,
                      intensity: 0.75,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const SkeletonBox(
                width: _actionButtonSize,
                height: _actionButtonSize,
                shape: BoxShape.circle,
                intensity: 0.8,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    Sound sound,
    int index,
    bool isSelected,
    ColorScheme scheme,
  ) {
    final onAir =
        (_isMusicPicker && _isMusicOnAir(sound)) ||
        (_isAmbiancePicker && _isAmbianceOnAir(sound));
    final queued = _isMusicPicker && _isMusicQueued(sound);
    final onPad = _isPadPicker && _padSoundIds.contains(sound.id);
    final inBoard = _isLibrary && _isMusicOnBoard(sound);
    final variantMode = _padVariantMode;
    // Polyphonie : plusieurs variantes du pad peuvent jouer en même temps, donc
    // on regarde l'état du lecteur de CE slot plutôt que le seul index le plus
    // récemment déclenché (`currentSoundIndex`, qui ne reflète que le dernier).
    final isCurrentVariant =
        variantMode != null &&
        index < variantMode.padItem.slots.length &&
        (variantMode.padItem.slots[index].player?.isPlaying ?? false);
    final tags = _soundTags[sound.id] ?? const <TagItem>[];

    // Son affiché dans le volet d'édition (mode gestion scindé).
    final isEditing = _isSplitLayout && _editingSound?.id == sound.id;

    Color? bgColor;
    if (onAir || queued || isCurrentVariant || isEditing) {
      bgColor = scheme.primaryContainer.withValues(
        alpha: isSelected ? 0.55 : 0.35,
      );
    } else if (isSelected) {
      bgColor = scheme.primary.withValues(alpha: 0.10);
    }

    return Material(
      key: _itemKey(index),
      color: bgColor ?? Colors.transparent,
      child: InkWell(
        canRequestFocus: false,
        onTap: () {
          setState(() => _selectedIndex = index);
          switch (widget.mode) {
            case QuickSearchMode():
              unawaited(_previewSound(sound));
            case MusicPickerMode(playNow: true):
              unawaited(_playMusicNow(sound));
            case MusicPickerMode():
              unawaited(_enqueueMusic(sound));
            case AmbiancePickerMode():
              unawaited(_playAmbianceNow(sound));
            case PadPickerMode():
              unawaited(_togglePadSound(sound));
            case LibraryMode():
              unawaited(_prepareAndClose(sound));
            case ManageMode():
              unawaited(_handleManageTap(sound));
            case PadVariantMode(padItem: final padItem):
              _playPadVariant(padItem, index);
          }
        },
        child: Container(
          // Accent de 2 px sur les sons à traiter (transparent sinon, pour ne
          // pas décaler les lignes) : se repère d'un coup d'œil en défilant.
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 2,
                color: _isManage && !sound.isProcessed
                    ? scheme.primary
                    : Colors.transparent,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 0, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SoundTypeAvatar(
                type: sound.type,
                colorValue: sound.colorValue,
                radius: 14,
                iconSize: 16,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoveredIndex = index),
                  onExit: (_) {
                    if (_hoveredIndex == index) {
                      setState(() => _hoveredIndex = null);
                    }
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ScrollingTextSpan(
                        animate: isSelected || _hoveredIndex == index,
                        span: buildHighlightedSpan(
                          sound.displayName,
                          _highlightTokens,
                        ),
                      ),
                      _buildSubtitle(
                        sound,
                        scheme,
                        onAir: onAir,
                        queued: queued,
                        inBoard: inBoard,
                        isCurrentVariant: isCurrentVariant,
                      ),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        _buildTagRow(scheme, tags),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildTrailing(
                sound,
                scheme,
                onAir: onAir,
                queued: queued,
                onPad: onPad,
                inBoard: inBoard,
                isCurrentVariant: isCurrentVariant,
                index: index,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitle(
    Sound sound,
    ColorScheme scheme, {
    required bool onAir,
    required bool queued,
    required bool inBoard,
    required bool isCurrentVariant,
  }) {
    if (_isMusicPicker) {
      final onBoard = _isMusicOnBoard(sound);
      final label = onAir
          ? 'À l\'antenne'
          : queued
          ? 'En file de passage'
          : onBoard
          ? 'Pad sur la scène'
          : null;
      if (label == null) return const SizedBox.shrink();
      return Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: onAir || queued ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: onAir || queued ? FontWeight.w600 : FontWeight.normal,
        ),
      );
    }

    if (_isAmbiancePicker) {
      if (!onAir) return const SizedBox.shrink();
      return Text(
        'À l\'antenne',
        style: TextStyle(
          fontSize: 12,
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    if (isCurrentVariant) {
      return Text(
        'En cours de lecture',
        style: TextStyle(
          fontSize: 12,
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Row(
      children: [
        Text(
          _typeLabel(sound.type),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        if (_isLibrary && inBoard) ...[
          const SizedBox(width: 6),
          Text(
            '· sur le plateau',
            style: TextStyle(
              fontSize: 12,
              color: scheme.primary.withValues(alpha: 0.8),
            ),
          ),
        ],
        if (_isQuickSearch && _localIds != null && !_isLocal(sound)) ...[
          const SizedBox(width: 6),
          Icon(
            Icons.cloud_outlined,
            size: 13,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ],
      ],
    );
  }

  Widget _buildTrailing(
    Sound sound,
    ColorScheme scheme, {
    required bool onAir,
    required bool queued,
    required bool onPad,
    required bool inBoard,
    required bool isCurrentVariant,
    required int index,
  }) {
    switch (widget.mode) {
      case QuickSearchMode():
        final fav = sound.isFavorite;
        final playedInSession = widget.notifier.hasPlayedInSession(sound.id);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fav) ...[
              SizedBox(
                width: _actionButtonSize,
                height: _actionButtonSize,
                child: Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (playedInSession) ...[
              Tooltip(
                message:
                    'Joué ${widget.notifier.sessionPlayCountFor(sound.id)} '
                    'fois cette session',
                child: SizedBox(
                  width: _actionButtonSize,
                  height: _actionButtonSize,
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            _roundIconButton(
              scheme: scheme,
              icon: sound.type == SoundType.music
                  ? Icons.playlist_add_rounded
                  : Icons.layers_rounded,
              iconColor: scheme.primary,
              onPressed: () => unawaited(_prepareAndClose(sound)),
            ),
          ],
        );

      case AmbiancePickerMode():
        if (!onAir) return const SizedBox.shrink();
        return SizedBox(
          width: _actionButtonSize,
          height: _actionButtonSize,
          child: Icon(Icons.sensors_rounded, size: 18, color: scheme.primary),
        );

      case MusicPickerMode():
        if (onAir || queued) {
          return SizedBox(
            width: _actionButtonSize,
            height: _actionButtonSize,
            child: Icon(
              onAir ? Icons.sensors_rounded : Icons.check_rounded,
              size: 18,
              color: scheme.primary,
            ),
          );
        }
        return const SizedBox.shrink();

      case PadPickerMode():
        final isAdding = _addingSoundIds.contains(sound.id);
        final isRemoving = _removingSoundIds.contains(sound.id);
        if (isAdding || isRemoving) {
          return SizedBox(
            width: _actionButtonSize,
            height: _actionButtonSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          );
        }
        return SizedBox(
          width: _actionButtonSize,
          height: _actionButtonSize,
          child: Icon(
            onPad ? Icons.check_rounded : Icons.add_rounded,
            color: onPad ? scheme.primary : scheme.onSurfaceVariant,
          ),
        );

      case LibraryMode():
        return _roundIconButton(
          scheme: scheme,
          icon: sound.type == SoundType.music
              ? Icons.playlist_add_rounded
              : Icons.layers_rounded,
          iconColor: inBoard ? scheme.primary : scheme.onSurfaceVariant,
          onPressed: () => unawaited(_prepareAndClose(sound)),
        );

      case ManageMode():
        final isPlaying = widget.notifier.libraryPreviewIsPlaying(sound.id);
        return Tooltip(
          message: isPlaying ? 'Pause' : 'Aperçu depuis le point d\'entrée',
          child: _roundIconButton(
            scheme: scheme,
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            iconColor: scheme.primary,
            onPressed: () => unawaited(_toggleLibraryPreview(sound)),
          ),
        );

      case PadVariantMode():
        if (isCurrentVariant) {
          return SizedBox(
            width: _actionButtonSize,
            height: _actionButtonSize,
            child: Icon(Icons.graphic_eq_rounded, color: scheme.primary),
          );
        }
        if (widget.notifier.hasPlayedInSession(sound.id)) {
          return Tooltip(
            message: 'Déjà joué cette session',
            child: SizedBox(
              width: _actionButtonSize,
              height: _actionButtonSize,
              child: Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
    }
  }
}
