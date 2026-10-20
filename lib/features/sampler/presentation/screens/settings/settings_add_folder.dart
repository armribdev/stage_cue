// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../settings_screen.dart';

/// Ajout d'un dossier indexé : sélecteurs local, SAF et Drive.
/// Méthodes de [_SettingsScreenState] extraites via extension dans le même `part`.
extension _SettingsAddFolder on _SettingsScreenState {
  Future<void> _onAddFolderPressed() async {
    if (Platform.isAndroid) {
      await _addDirectoryFromIntegratedPicker();
      return;
    }
    await _showAddFolderMenu();
  }

  /// Sur Android, le sélecteur SAF propose stockage local et Drive (URI persistée).
  Future<void> _addDirectoryFromIntegratedPicker() async {
    try {
      final pickResult = await SafDirectoryBridge.pickDirectory();
      if (pickResult != null) {
        setState(() {
          _safFolderInfo[pickResult.uri] = pickResult.treeInfo;
        });

        if (pickResult.isGoogleDrive) {
          await _addDriveDirectoryFromSafPick(pickResult);
          return;
        }

        await _indexWatchedDirectory(
          pickResult.uri,
          safInfo: pickResult.treeInfo,
        );
      }
    } on SafDirectoryUnavailableException catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, e.message);
      }
    }
  }

  /// Lie un dossier Drive choisi via le sélecteur système Android (SAF).
  Future<void> _addDriveDirectoryFromSafPick(SafPickResult pickResult) async {
    if (!await ensureGoogleOAuthConfigured(context)) {
      return;
    }
    if (!mounted) {
      return;
    }

    if (!await widget.libraryRepository.ensureDriveConnected()) {
      if (mounted) {
        AppSnackBar.show(
          context,
          'Connexion Google Drive requise pour indexer un dossier Drive',
        );
      }
      return;
    }

    final folderName = pickResult.displayName;
    final relativeDrivePath = pickResult.displayPath.trim().isNotEmpty
        ? pickResult.displayPath.trim()
        : null;

    final driveFolderId = await widget.libraryRepository
        .resolveSafDriveFolderId(
          driveFileId: pickResult.driveFileId,
          folderName: folderName,
          relativeDrivePath: relativeDrivePath,
        );

    if (driveFolderId == null) {
      if (mounted) {
        showCopyableSnackBar(
          context,
          'Impossible d\'identifier le dossier Drive. '
          'Vérifiez votre connexion Google puis réessayez.',
        );
      }
      return;
    }

    await _linkAndInitializeDriveFolder(
      driveFolderId: driveFolderId,
      folderName: folderName,
      relativeDrivePath: relativeDrivePath,
    );
  }

  Future<void> _loadSafFolderInfo() async {
    if (!SafDirectoryBridge.isSupported) {
      return;
    }

    final infoByUri = <String, SafTreeInfo>{};
    for (final watchedPath in _watchedPaths) {
      if (!SafDirectoryBridge.isSafTreeUri(watchedPath.path)) {
        continue;
      }
      final info = await SafDirectoryBridge.getTreeInfo(watchedPath.path);
      if (info != null) {
        infoByUri[watchedPath.path] = info;
      }

      final isDrive =
          info?.isGoogleDrive ??
          SafDirectoryBridge.isGoogleDriveUri(watchedPath.path);
      if (isDrive && watchedPath.accountEmail == null) {
        unawaited(_resolveAndStoreOwnerEmail(watchedPath, info));
      }
    }

    if (!mounted || infoByUri.isEmpty) {
      return;
    }

    setState(() {
      _safFolderInfo.addAll(infoByUri);
    });
  }

  Future<void> _resolveAndStoreOwnerEmail(
    db.WatchedPath watchedPath,
    SafTreeInfo? info,
  ) async {
    final folderName = _labelsForWatchedPath(watchedPath, info).title;
    final ownerEmail = await widget.libraryRepository
        .resolveSafFolderOwnerEmail(
          driveFileId: watchedPath.driveFileId ?? info?.driveFileId,
          folderName: folderName,
        );
    if (ownerEmail == null || !mounted) {
      return;
    }

    await _repository.updateWatchedPathAccount(
      id: watchedPath.id,
      accountEmail: ownerEmail,
      driveFileId: watchedPath.driveFileId ?? info?.driveFileId,
    );
    await _reloadWatchedPaths();
  }

  /// Charge en arrière-plan le décompte « hors ligne / total » de chaque
  /// bibliothèque Drive (présence des fichiers dans le cache local).
  Future<void> _loadOfflineCounts() async {
    final libraries = _libraries
        .where((library) => library.isConnectedToDrive)
        .toList();
    for (final library in libraries) {
      if (library.id < 0) continue; // Bibliothèque en cours de création.
      await _refreshOfflineCount(library);
    }
  }

  /// Recalcule le décompte hors-ligne d'une seule bibliothèque (best-effort).
  Future<void> _refreshOfflineCount(domain.Library library) async {
    try {
      final counts = await widget.libraryRepository.countDownloadedSounds(
        library,
      );
      if (!mounted) return;
      setState(() => _offlineCounts[library.id] = counts);
    } catch (_) {
      // Indicateur best-effort : on ignore les erreurs (dossier illisible…).
    }
  }

  Future<String?> _pickAddFolderSource() async {
    if (widget.isModal || preferModalPresentation(context)) {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AppFormDialog(
            title: 'Ajouter un dossier',
            width: 400,
            onClose: () => Navigator.of(dialogContext).pop(),
            content: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: AppChoiceOption(
                      vertical: true,
                      icon: Icons.folder_outlined,
                      label: 'Dossier local',
                      onTap: () => Navigator.of(dialogContext).pop('local'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppChoiceOption(
                      vertical: true,
                      icon: Icons.cloud_outlined,
                      label: 'Dossier Drive',
                      onTap: () => Navigator.of(dialogContext).pop('drive'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppModalStyle.padding),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: AppChoiceOption(
                      vertical: true,
                      icon: Icons.folder_outlined,
                      label: 'Dossier local',
                      onTap: () => Navigator.of(sheetContext).pop('local'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppChoiceOption(
                      vertical: true,
                      icon: Icons.cloud_outlined,
                      label: 'Dossier Drive',
                      onTap: () => Navigator.of(sheetContext).pop('drive'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddFolderMenu() async {
    final choice = await _pickAddFolderSource();

    if (!mounted || choice == null) {
      return;
    }

    if (choice == 'local') {
      await _addLocalDirectory();
    } else if (choice == 'drive') {
      await _addDriveDirectory();
    }
  }

  Future<void> _addLocalDirectory() async {
    final selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir un dossier local',
    );
    if (selectedDirectory != null) {
      await _indexWatchedDirectory(selectedDirectory);
    }
  }

  Future<void> _addDriveDirectory() async {
    if (!await ensureGoogleOAuthConfigured(context)) {
      return;
    }
    if (!mounted) {
      return;
    }

    final selection = await DriveFolderPicker.show(
      context,
      repository: widget.libraryRepository,
    );
    if (!mounted || selection == null) {
      return;
    }

    await _linkAndInitializeDriveFolder(
      driveFolderId: selection.folderId,
      folderName: selection.name,
      relativeDrivePath: selection.relativeDrivePath,
      sharedDriveId: selection.sharedDriveId,
    );
  }
}
