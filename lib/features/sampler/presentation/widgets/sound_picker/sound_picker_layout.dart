// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../sound_picker_overlay.dart';

/// Mise en page : volet scindé, champ de recherche, filtres de type.
/// Méthodes de [_SoundPickerOverlayState] extraites via extension dans le même `part`.
extension _SoundPickerLayout on _SoundPickerOverlayState {
  /// Gestion en volet scindé : sons à gauche, infos du son sélectionné à droite.
  ///
  /// Le bloc entier est borné en largeur et centré : sur un grand écran, la
  /// liste et le formulaire ne s'étirent pas aux deux bords de la fenêtre.
  Widget _buildSplit(ColorScheme scheme, Widget listPane, List<Sound> shown) {
    final border = AppElevation.border(scheme);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0.0, _splitMaxWidth);
        final isCapped = constraints.maxWidth > _splitMaxWidth;
        return Center(
          child: Container(
            width: width,
            height: constraints.maxHeight,
            decoration: BoxDecoration(
              // Filets latéraux seulement quand le bloc flotte au centre.
              border: isCapped ? Border.symmetric(vertical: border) : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: (width * 0.4).clamp(320.0, 460.0),
                  child: listPane,
                ),
                Container(width: 1, color: border.color),
                Expanded(child: _buildEditPane(scheme, shown)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditPane(ColorScheme scheme, List<Sound> shown) {
    final sound = _editingSound;
    final mode = _manageMode;
    if (sound == null || mode == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 32,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              _unprocessedOnly && _unprocessedCount == 0
                  ? 'Tous les sons sont traités'
                  : 'Sélectionnez un son pour le modifier',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return SoundEditForm(
      // isProcessed dans la clé : la validation en masse doit recréer le
      // formulaire ouvert, mais un enregistrement normal (l'état local passe
      // à « traité » sans toucher à `sound`) ne doit pas le réinitialiser.
      key: ValueKey('${sound.id}-${sound.isProcessed}'),
      sound: sound,
      tagCatalog: _tagCatalog,
      repository: mode.repository,
      notifier: widget.notifier,
      controller: _editController,
      isQueueMode: _unprocessedOnly,
      queueRemaining: _unprocessedOnly ? _unprocessedCount : null,
      onSkip: _unprocessedOnly && shown.length > 1
          ? () => _skipToNext(shown)
          : null,
      onDirtyChanged: (dirty) => setState(() => _editDirty = dirty),
      // Nom, type ou tags ont pu changer : on reconstruit l'index plutôt que
      // de recharger la seule liste des sons. En file de traitement, on
      // enchaîne ensuite sur le son suivant.
      onSaved: () => unawaited(_afterPaneSave(sound)),
    );
  }

  /// Sans champ de recherche (variante de pad), on rattache [_focusNode] ici
  /// pour garder la navigation clavier (↑↓, Entrée).
  Widget _buildResultsFocusable(
    ColorScheme scheme,
    List<Sound> shown,
    int selectedIndex,
  ) {
    final results = _buildResults(scheme, shown, selectedIndex);
    if (!_isPadVariant) return results;
    return Focus(focusNode: _focusNode, autofocus: true, child: results);
  }

  Widget _buildSearchField(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      child: Row(
        children: [
          // Page pleine (mobile) : flèche retour, seul moyen de fermer
          // l'overlay puisqu'il n'y a pas de fond à taper.
          if (widget._isFullPage) ...[
            ExcludeFocus(
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => unawaited(Navigator.of(context).maybePop()),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onChanged: _onQueryChanged,
              onSubmitted: (_) => unawaited(_onSubmit()),
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: _hintText,
                isCollapsed: true,
                suffixIcon: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => _controller.text.isEmpty
                      ? const SizedBox.shrink()
                      : ExcludeFocus(
                          child: IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: _clearQuery,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                ),
                suffixIconConstraints: const BoxConstraints(
                  maxHeight: 24,
                  maxWidth: 24,
                ),
              ),
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilters(ColorScheme scheme) {
    // Musique : type verrouillé → pas de barre de filtres.
    if (_lockedTypeFilter != null) return const SizedBox.shrink();

    // "Tous" uniquement pour QuickSearch, Library et Manage
    final segments = <(String, SoundType?, IconData)>[
      if (_isQuickSearch || _isLibrary || _isManage)
        ('Tous', null, Icons.apps_rounded),
      (
        SoundType.soundEffect.label,
        SoundType.soundEffect,
        SoundType.soundEffect.icon,
      ),
      (SoundType.music.label, SoundType.music, SoundType.music.icon),
      (SoundType.ambiance.label, SoundType.ambiance, SoundType.ambiance.icon),
    ];

    Widget segment(String label, SoundType? type, IconData icon, bool isLast) {
      final selected = _effectiveTypeFilter == type;
      final colors =
          type?.avatarColors(scheme) ??
          (
            background: scheme.primaryContainer,
            foreground: scheme.onPrimaryContainer,
          );
      return InkWell(
        canRequestFocus: false,
        onTap: () {
          setState(() {
            _typeFilter = type;
            _selectedIndex = 0;
          });
        },
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.background : Colors.transparent,
            border: isLast
                ? null
                : Border(
                    right: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? colors.foreground : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? colors.foreground : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final segmentedControl = Material(
      color: Colors.transparent,
      child: Container(
        height: 32,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: AppRadius.radiusMd,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < segments.length; i++)
              segment(
                segments[i].$1,
                segments[i].$2,
                segments[i].$3,
                i == segments.length - 1,
              ),
          ],
        ),
      ),
    );

    final trailingActions = <Widget>[
      if (_isQuickSearch) ...[
        Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
        _roundIconButton(
          scheme: scheme,
          icon: _favoritesOnly ? Icons.star_rounded : Icons.star_border_rounded,
          iconColor: _favoritesOnly ? scheme.primary : scheme.onSurfaceVariant,
          active: _favoritesOnly,
          flat: true,
          onPressed: () {
            setState(() {
              _favoritesOnly = !_favoritesOnly;
              _selectedIndex = 0;
            });
          },
        ),
        _roundIconButton(
          scheme: scheme,
          icon: Icons.offline_bolt_rounded,
          iconColor: _effectiveLocalOnly
              ? scheme.primary
              : scheme.onSurfaceVariant,
          active: _effectiveLocalOnly,
          flat: true,
          onPressed: () {
            setState(() {
              _localOnly = !_localOnly;
              _selectedIndex = 0;
            });
          },
        ),
      ],
    ];

    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
        // Groupe pilule + actions centré comme un seul bloc ; passe en scroll
        // horizontal (démarrant à gauche) si la largeur manque. Le
        // ConstrainedBox(minWidth) force le Row à occuper toute la largeur
        // disponible quand le contenu est plus étroit, pour que le
        // MainAxisAlignment.center ait un effet visible.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [segmentedControl, ...trailingActions],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ligne de séparation fine et atténuée sous la barre de filtres — un
  /// `Divider` plein-largeur par défaut tranche trop avec les chips arrondis.
  Widget _buildFilterDivider(ColorScheme scheme) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: scheme.outlineVariant.withValues(alpha: 0.4),
    );
  }
}
