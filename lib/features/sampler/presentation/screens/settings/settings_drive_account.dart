// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../settings_screen.dart';

/// Compte Google : connexion, renouvellement, déconnexion et en-tête.
/// Méthodes de [_SettingsScreenState] extraites via extension dans le même `part`.
extension _SettingsDriveAccount on _SettingsScreenState {
  Future<void> _connectDriveAccount() async {
    if (!await ensureGoogleOAuthConfigured(context)) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() => _isDriveAuthBusy = true);
    try {
      final connected = await widget.libraryRepository.ensureDriveConnected();
      if (!mounted) {
        return;
      }

      if (!connected) return;
      widget.syncController.clearAuthOfflineState();
      await widget.libraryRepository.refreshConnectedAccountProfile();
      await _loadDatabaseInfo();
    } on GoogleOAuthNotConfiguredException catch (e) {
      if (mounted) {
        showCopyableSnackBar(
          context,
          e.message,
          duration: const Duration(seconds: 8),
        );
      }
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur de connexion Google : $e');
      }
    } finally {
      if (mounted) setState(() => _isDriveAuthBusy = false);
    }
  }

  /// Renouvelle la session Drive. Tente d'abord une reconnexion silencieuse
  /// (refresh token) pour éviter un aller-retour navigateur/Google ; ne bascule
  /// sur l'OAuth interactif que si le silencieux échoue réellement.
  Future<void> _renewDriveSession() async {
    if (!await ensureGoogleOAuthConfigured(context)) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() => _isDriveAuthBusy = true);
    var reconnected = false;
    try {
      reconnected = await widget.libraryRepository.reconnectSilently();
      if (reconnected && mounted) {
        widget.syncController.clearAuthOfflineState();
        await widget.libraryRepository.refreshConnectedAccountProfile();
        await _loadDatabaseInfo();
      }
    } catch (_) {
      // Le silencieux a échoué : on retombe sur l'interactif ci-dessous.
      reconnected = false;
    } finally {
      if (mounted) setState(() => _isDriveAuthBusy = false);
    }

    if (!reconnected && mounted) {
      await _connectDriveAccount();
    }
  }

  Future<void> _disconnectDriveAccount() async {
    final account = widget.libraryRepository.connectedAccountProfile;
    if (account == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Déconnecter Google Drive'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(
              'Déconnecter le compte ${account.email} ?\n\n'
              'Les dossiers Drive indexés restent enregistrés localement, '
              'mais la synchronisation et l\'ajout de dossiers Drive '
              'nécessiteront une nouvelle connexion.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Déconnecter'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isDriveAuthBusy = true);
    try {
      await widget.libraryRepository.disconnect();
      if (mounted) {
        AppSnackBar.show(
          context,
          'Compte Google déconnecté',
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors de la déconnexion : $e');
      }
    } finally {
      if (mounted) setState(() => _isDriveAuthBusy = false);
    }
  }

  Widget _buildGoogleAccountAvatar(
    DriveAccountProfile account, {
    double radius = 22,
  }) {
    final size = radius * 2;

    Widget initialsAvatar() {
      return CircleAvatar(
        radius: radius,
        child: Text(
          account.initials,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
    }

    if (account.photoUrl == null || account.photoUrl!.isEmpty) {
      return initialsAvatar();
    }

    // La photo est servie depuis un cache disque : affichage immédiat aux
    // lancements suivants et hors-ligne. Pendant la 1re résolution (lecture
    // disque / téléchargement) on affiche un skeleton pulsé plutôt que les
    // initiales, pour éviter le clignotement « initiales → photo ». On ne
    // retombe sur les initiales qu'une fois la résolution terminée sans photo
    // (échec réseau sans cache).
    return FutureBuilder<File?>(
      initialData: _resolvedAvatars[account.email],
      future: _resolveAvatar(account),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file != null) {
          return ClipOval(
            child: Image.file(
              file,
              key: ValueKey(file.path),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => initialsAvatar(),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return initialsAvatar();
        }
        return Skeleton(
          child: SkeletonBox(width: size, height: size, shape: BoxShape.circle),
        );
      },
    );
  }

  /// Hauteur constante réservée à l'en-tête « Compte Google » : garantit que
  /// les changements d'état (connecté / déconnecté / à renouveler / expiré) ne
  /// décalent pas le reste de la section Drive. `minHeight` (et non une hauteur
  /// fixe) évite tout débordement si le contenu grandit (mise à l'échelle du
  /// texte).
  static const double _kDriveHeaderMinHeight = 80;

  Widget _driveHeaderFrame(Widget child) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _kDriveHeaderMinHeight),
      child: child,
    );
  }

  Widget _buildDriveAccountHeader({
    required SyncState syncState,
    required bool authExpired,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final account = widget.libraryRepository.connectedAccountProfile;
    final sessionActive =
        widget.libraryRepository.hasUsableDriveSession && !authExpired;
    final signedIn = account != null;

    if (_isDriveAuthBusy) {
      return _driveHeaderFrame(
        const Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            SizedBox(width: 12),
            Text('Connexion Google…'),
          ],
        ),
      );
    }

    if (!signedIn) {
      return _driveHeaderFrame(
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.account_circle_outlined, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Compte Google',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Connectez-vous pour synchroniser vos bibliothèques Drive.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: _connectDriveAccount,
              child: const Text('Se connecter'),
            ),
          ],
        ),
      );
    }

    final statusLabel = authExpired
        ? 'Session expirée'
        : sessionActive
        ? 'Connecté'
        : 'Session à renouveler';
    final statusColor = authExpired
        ? scheme.error
        : sessionActive
        ? scheme.primary
        : scheme.tertiary;
    final statusIcon = authExpired
        ? Icons.cloud_off_outlined
        : sessionActive
        ? Icons.cloud_done_outlined
        : Icons.cloud_queue;

    return _driveHeaderFrame(
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildGoogleAccountAvatar(account, radius: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Compte Google',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  account.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  account.email,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        statusLabel,
                        style: TextStyle(fontSize: 12, color: statusColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!sessionActive)
                TextButton(
                  onPressed: _renewDriveSession,
                  child: const Text('Renouveler'),
                )
              else
                TextButton.icon(
                  onPressed: _disconnectDriveAccount,
                  icon: Icon(
                    Icons.logout_outlined,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  label: const Text('Déconnecter'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
