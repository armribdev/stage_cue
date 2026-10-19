// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../settings_screen.dart';

/// Indexation d'un dossier surveillé et liaison d'un dossier Drive.
/// Méthodes de [_SettingsScreenState] extraites via extension dans le même `part`.
extension _SettingsIndexing on _SettingsScreenState {

  Future<void> _indexWatchedDirectory(
    String selectedDirectory, {
    SafTreeInfo? safInfo,
  }) async {
    try {
      final isSafTree = SafDirectoryBridge.isSafTreeUri(selectedDirectory);
      final directoryExists =
          isSafTree || await Directory(selectedDirectory).exists();

      if (directoryExists) {
        // Invariant de routage : un dossier Google Drive est dirigé vers le
        // système de bibliothèques (`_addDriveDirectoryFromSafPick` /
        // `_addDriveDirectory`), jamais ici. `_indexWatchedDirectory` ne gère
        // donc QUE des dossiers locaux → aucune métadonnée Drive (owner/id).
        const String? accountEmail = null;
        const String? driveFileId = null;

        // Vérifier si le dossier n'est pas déjà surveillé
        final existing = await (widget.database.select(
          widget.database.watchedPaths,
        )..where((w) => w.path.equals(selectedDirectory))).get();

        if (existing.isNotEmpty) {
          if (mounted) {
            AppSnackBar.show(context, 'Ce dossier est déjà surveillé');
          }
          return;
        }

        // Ajouter le chemin surveillé
        final watchedPath = domain.WatchedPath(
          id: 0, // Sera généré par la base de données
          path: selectedDirectory,
          isDirectory: true,
          accountEmail: accountEmail,
          driveFileId: driveFileId,
          addedAt: DateTime.now(),
        );

        final normalizedPath = _normalizeWatchedPath(selectedDirectory);
        setState(() {
          _watchedPaths = [
            ..._watchedPaths,
            db.WatchedPath(
              id: -1,
              path: selectedDirectory,
              isDirectory: true,
              accountEmail: accountEmail,
              driveFileId: driveFileId,
              addedAt: DateTime.now(),
            ),
          ];
          _indexingProgress[normalizedPath] = IndexingProgress(
            path: selectedDirectory,
            current: 0,
            total: 0,
            isComplete: false,
          );
        });

        // Ajouter le dossier avec suivi de progression
        final result = await _repository.addWatchedPath(
          watchedPath,
          onInserted: () {
            if (mounted) {
              unawaited(_reloadWatchedPaths());
            }
          },
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _indexingProgress[_normalizeWatchedPath(progress.path)] =
                    progress;
              });
              _maybeRefreshDatabaseSummaryLive(progress);
            }
          },
        );

        if (mounted) {
          final n = result.newSoundCount;
          if (n > 0) {
            await _offerAddNewSoundsToBoard(n);
          } else {
            AppSnackBar.show(
              context,
              'Dossier ajouté et indexé',
              duration: const Duration(seconds: 2),
            );
          }
        }

        if (isSafTree && safInfo == null) {
          final info = await SafDirectoryBridge.getTreeInfo(selectedDirectory);
          if (info != null && mounted) {
            setState(() {
              _safFolderInfo[selectedDirectory] = info;
            });
          }
        }

        await _loadDatabaseInfo();
      } else if (mounted) {
        showCopyableSnackBar(
          context,
          'Dossier inaccessible. Réessayez ou choisissez un autre emplacement.',
        );
      }
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors de l\'ajout du dossier: $e');
      }
    }
  }

  Future<void> _offerAddNewSoundsToBoard(int newSoundCount) async {
    final boards = await (widget.database.select(
      widget.database.soundBoards,
    )..orderBy([(b) => OrderingTerm(expression: b.createdAt)])).get();

    if (!mounted) return;

    if (boards.isEmpty) {
      AppSnackBar.show(
        context,
        '$newSoundCount son${newSoundCount > 1 ? 's' : ''} indexé${newSoundCount > 1 ? 's' : ''}',
        duration: const Duration(seconds: 3),
      );
      return;
    }

    int? targetBoardId;

    if (boards.length == 1) {
      targetBoardId = boards.first.id;
    } else {
      targetBoardId = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Ajouter au plateau'),
          children: [
            for (final board in boards)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, board.id),
                child: Text(board.name),
              ),
          ],
        ),
      );
    }

    if (!mounted || targetBoardId == null) return;

    await SoundLibraryScreen.open(
      context,
      database: widget.database,
      boardId: targetBoardId,
      libraryRepository: widget.libraryRepository,
    );
  }

  Future<void> _linkAndInitializeDriveFolder({
    required String driveFolderId,
    required String folderName,
    String? relativeDrivePath,
    String? sharedDriveId,
  }) async {
    if (_libraries.any((library) => library.driveFolderId == driveFolderId)) {
      if (mounted) {
        AppSnackBar.show(context, 'Ce dossier Drive est déjà indexé');
      }
      return;
    }

    final pendingKey = _driveProgressKey(-1, folderName);
    final now = DateTime.now();
    setState(() {
      _libraries = [
        ..._libraries,
        domain.Library(
          id: -1,
          name: folderName,
          localRootPath: '',
          drivePath: relativeDrivePath,
          sharedDriveId: sharedDriveId,
          createdAt: now,
        ),
      ];
      _indexingProgress[pendingKey] = IndexingProgress(
        path: folderName,
        current: 0,
        total: 0,
        isComplete: false,
      );
    });

    try {
      if (!await widget.libraryRepository.ensureDriveConnected()) {
        if (mounted) {
          setState(() {
            _libraries = _libraries
                .where((item) => item.name != folderName || item.id != -1)
                .toList();
            _indexingProgress.remove(pendingKey);
          });
        }
        return;
      }

      final library = await widget.libraryRepository.linkDriveFolder(
        driveFolderId: driveFolderId,
        name: folderName,
        drivePath: relativeDrivePath,
        sharedDriveId: sharedDriveId,
        autoDownload: widget.appPreferences.autoDownloadDriveByDefault,
      );

      if (!mounted) {
        return;
      }

      final progressKey = _driveProgressKey(library.id);
      setState(() {
        _libraries = [
          for (final item in _libraries)
            if (item.id == -1 && item.name == folderName) library else item,
        ];
        final pending = _indexingProgress.remove(pendingKey);
        if (pending != null) {
          _indexingProgress[progressKey] = pending;
        }
      });

      final init = await widget.libraryRepository.initializeLinkedDriveFolder(
        library: library,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _indexingProgress[progressKey] = progress;
            });
          }
        },
      );

      var uploadSucceeded = false;
      if (init.shouldUpload && mounted) {
        final currentLibrary =
            await widget.libraryRepository.getLibraryById(library.id) ??
            library;
        await widget.syncController.syncNow(currentLibrary);

        if (!mounted) return;

        final syncStatus = widget.syncController.state.status;
        uploadSucceeded = syncStatus == SyncStatus.synced;

        if (syncStatus == SyncStatus.conflict) {
          await _resolveSyncConflict(currentLibrary);
          uploadSucceeded =
              widget.syncController.state.status == SyncStatus.synced;
        } else if (syncStatus == SyncStatus.offline) {
          showCopyableSnackBar(
            context,
            'Impossible d\'envoyer vers Drive : session Google expirée',
          );
        } else if (syncStatus == SyncStatus.error) {
          showCopyableSnackBar(
            context,
            widget.syncController.state.message ??
                'Erreur lors de l\'envoi vers Drive',
          );
        }
      }

      if (mounted) {
        final String message;
        if (init.shouldUpload && !uploadSucceeded) {
          message = init.indexedNewFiles > 0
              ? 'Dossier Drive « $folderName » indexé localement, '
                    'mais l\'envoi vers Drive a échoué'
              : 'Dossier Drive « $folderName » lié, '
                    'mais la BDD n\'a pas pu être créée sur Drive';
        } else if (!init.hadRemoteSnapshot && uploadSucceeded) {
          message = 'Dossier Drive « $folderName » configuré et synchronisé';
        } else if (init.indexedNewFiles > 0) {
          message =
              'Dossier Drive « $folderName » mis à jour '
              '(${init.indexedNewFiles} nouveau(x) fichier(s))';
        } else {
          message = 'Dossier Drive « $folderName » lié';
        }
        if (init.shouldUpload && !uploadSucceeded) {
          showCopyableSnackBar(
            context,
            message,
            duration: const Duration(seconds: 3),
          );
        } else {
          AppSnackBar.show(
            context,
            message,
            duration: const Duration(seconds: 3),
          );
        }
      }

      await _loadDatabaseInfo();
    } on GoogleOAuthNotConfiguredException catch (e) {
      if (mounted) {
        setState(() {
          _libraries = _libraries
              .where((item) => item.name != folderName || item.id != -1)
              .toList();
          _indexingProgress.remove(pendingKey);
        });
        showCopyableSnackBar(
          context,
          e.message,
          duration: const Duration(seconds: 8),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _libraries = _libraries
              .where((item) => item.name != folderName || item.id != -1)
              .toList();
          _indexingProgress.remove(pendingKey);
        });
        showCopyableSnackBar(context, 'Erreur lors de l\'ajout Drive : $e');
      }
    }
  }
}
