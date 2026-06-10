import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart' show OrderingTerm;
import '../../../../core/database/database.dart' as db;
import '../../../../core/settings/app_preferences.dart';
import '../../../../core/platform/saf_directory_bridge.dart';
import '../../../../core/sync/drive_account_profile.dart';
import '../../../../core/sync/google_oauth_config.dart';
import '../../../../core/sync/google_oauth_setup_dialog.dart';
import '../../../../core/utils/copyable_snackbar.dart';
import '../../../../core/utils/indexed_folder_labels.dart';
import '../../../../core/utils/layout_utils.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/app_modal.dart';
import '../widgets/drive_folder_picker.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/sound_repository.dart';
import '../../data/models/indexing_progress.dart';
import '../../domain/entities/library.dart' as domain;
import '../../domain/entities/watched_path.dart' as domain;
import '../providers/sync_controller.dart';
import 'sound_library_screen.dart';

/// Écran des paramètres
class SettingsScreen extends StatefulWidget {
  final db.AppDatabase database;
  final LibraryRepository libraryRepository;
  final SyncController syncController;
  final AppPreferences appPreferences;
  final bool isModal;

  const SettingsScreen({
    super.key,
    required this.database,
    required this.libraryRepository,
    required this.syncController,
    required this.appPreferences,
    this.isModal = false,
  });

  /// Page plein écran sur téléphone, modale sur tablette et desktop.
  static Future<void> open(
    BuildContext context, {
    required db.AppDatabase database,
    required LibraryRepository libraryRepository,
    required SyncController syncController,
    required AppPreferences appPreferences,
  }) {
    return openAdaptiveScreen(
      context: context,
      builder: ({required isModal}) => SettingsScreen(
        database: database,
        libraryRepository: libraryRepository,
        syncController: syncController,
        appPreferences: appPreferences,
        isModal: isModal,
      ),
    );
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<db.WatchedPath> _watchedPaths = [];
  List<domain.Library> _libraries = [];
  List<db.Sound> _sounds = [];
  bool _isLoading = true;
  String _dbPath = '';
  int _dbSize = 0;
  late final SoundRepository _repository;
  // Suivi de la progression d'indexation par chemin (clé normalisée)
  final Map<String, IndexingProgress> _indexingProgress = {};
  // Suivi de la progression de téléchargement audio par bibliothèque
  final Map<int, IndexingProgress> _downloadProgress = {};
  bool _cancelDownloadAll = false;
  final Map<String, SafTreeInfo> _safFolderInfo = {};
  bool _isInitialLoad = true;
  bool _isSyncBusy = false;
  bool _isDriveAuthBusy = false;

  @override
  void initState() {
    super.initState();
    _initializeRepository();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Laisse la transition de navigation se terminer avant de lancer
      // les lectures DB pour éviter les à-coups à l'ouverture.
      unawaited(_startInitialLoad());
    });
  }

  Future<void> _startInitialLoad() async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) {
      return;
    }
    unawaited(_loadDatabaseInfo());
  }

  void _initializeRepository() {
    _repository = SoundRepository.fromDatabase(widget.database);
  }

  Future<void> _reloadWatchedPaths() async {
    final watchedPaths = await widget.database
        .select(widget.database.watchedPaths)
        .get();

    if (mounted) {
      setState(() {
        _watchedPaths = watchedPaths;
      });
    }
  }

  Future<void> _loadDatabaseInfo() async {
    final showSkeleton = _isInitialLoad;
    if (showSkeleton) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      await widget.libraryRepository.reconnectSilently();

      // Charger les dossiers locaux surveillés et les bibliothèques Drive
      final watchedPaths = await widget.database
          .select(widget.database.watchedPaths)
          .get();
      final libraries = await widget.libraryRepository.getLibraries();

      // Charger tous les sons de la base de données
      final sounds = await widget.database.select(widget.database.sounds).get();

      // Obtenir le chemin de la base de données
      final directory = await getApplicationDocumentsDirectory();
      final dbFile = File('${directory.path}/db.sqlite');

      int dbSize = 0;
      if (await dbFile.exists()) {
        dbSize = await dbFile.length();
      }

      setState(() {
        _watchedPaths = watchedPaths;
        _libraries = libraries;
        _sounds = sounds;
        _dbPath = dbFile.path;
        _dbSize = dbSize;
        _isLoading = false;
        _isInitialLoad = false;
      });
      unawaited(_loadSafFolderInfo());
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isInitialLoad = false;
      });
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors du chargement: $e');
      }
    }
  }

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
          content: Text(
            'Déconnecter le compte ${account.email} ?\n\n'
            'Les dossiers Drive indexés restent enregistrés localement, '
            'mais la synchronisation et l\'ajout de dossiers Drive '
            'nécessiteront une nouvelle connexion.',
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compte Google déconnecté'),
            duration: Duration(seconds: 2),
          ),
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

  Widget _buildGoogleAccountAvatar(DriveAccountProfile account, {double radius = 22}) {
    final photoUrl = account.photoUrl;
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

    if (photoUrl == null || photoUrl.isEmpty) {
      return initialsAvatar();
    }

    return ClipOval(
      child: Image.network(
        photoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => initialsAvatar(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }
          return SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAccountMenu(BuildContext context) {
    if (_isDriveAuthBusy) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final account = widget.libraryRepository.connectedAccountProfile;
    final scheme = Theme.of(context).colorScheme;

    if (account == null) {
      return IconButton(
        tooltip: 'Se connecter à Google Drive',
        onPressed: _connectDriveAccount,
        icon: Icon(Icons.account_circle_outlined, color: scheme.primary),
      );
    }

    const avatarRadius = 16.0;
    const avatarSize = avatarRadius * 2;

    return PopupMenuButton<String>(
      tooltip: 'Compte Google',
      offset: const Offset(0, 44),
      padding: EdgeInsets.zero,
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      splashRadius: avatarRadius,
      borderRadius: BorderRadius.circular(avatarRadius),
      itemBuilder: (menuContext) => [
        PopupMenuItem<String>(
          height: 44,
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          onTap: () {},
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      account.label,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.email,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Déconnecter',
                onPressed: () {
                  Navigator.of(menuContext).pop();
                  unawaited(_disconnectDriveAccount());
                },
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                icon: Icon(
                  Icons.logout_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
      child: SizedBox(
        width: avatarSize,
        height: avatarSize,
        child: _buildGoogleAccountAvatar(account, radius: avatarRadius),
      ),
    );
  }

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Connexion Google Drive requise pour indexer un dossier Drive',
            ),
          ),
        );
      }
      return;
    }

    final folderName = pickResult.displayName;
    final relativeDrivePath = pickResult.displayPath.trim().isNotEmpty
        ? pickResult.displayPath.trim()
        : null;

    final driveFolderId = await widget.libraryRepository.resolveSafDriveFolderId(
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

      final isDrive = info?.isGoogleDrive ??
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
    final ownerEmail = await widget.libraryRepository.resolveSafFolderOwnerEmail(
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

  Future<String?> _pickAddFolderSource() async {
    if (widget.isModal || preferModalPresentation(context)) {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AppFormDialog(
            title: 'Ajouter un dossier',
            width: 400,
            onClose: () => Navigator.of(dialogContext).pop(),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppChoiceOption(
                  icon: Icons.folder_outlined,
                  label: 'Dossier local',
                  onTap: () => Navigator.of(dialogContext).pop('local'),
                ),
                const SizedBox(height: 8),
                AppChoiceOption(
                  icon: Icons.cloud_outlined,
                  label: 'Dossier Drive',
                  onTap: () => Navigator.of(dialogContext).pop('drive'),
                ),
              ],
            ),
          );
        },
      );
    }

    return showModalBottomSheet<String>(
      context: context,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppModalStyle.radius),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppModalStyle.padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppChoiceOption(
                  icon: Icons.folder_outlined,
                  label: 'Dossier local',
                  onTap: () => Navigator.of(sheetContext).pop('local'),
                ),
                const SizedBox(height: 8),
                AppChoiceOption(
                  icon: Icons.cloud_outlined,
                  label: 'Dossier Drive',
                  onTap: () => Navigator.of(sheetContext).pop('drive'),
                ),
              ],
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

  Future<void> _indexWatchedDirectory(
    String selectedDirectory, {
    SafTreeInfo? safInfo,
  }) async {
    try {
      final isSafTree = SafDirectoryBridge.isSafTreeUri(selectedDirectory);
      final directoryExists = isSafTree ||
          await Directory(selectedDirectory).exists();

      if (directoryExists) {
        String? accountEmail;
        String? driveFileId;
        final isGoogleDrive = safInfo?.isGoogleDrive ??
            SafDirectoryBridge.isGoogleDriveUri(selectedDirectory);

        if (isSafTree && isGoogleDrive) {
          driveFileId = safInfo?.driveFileId;
          accountEmail =
              await widget.libraryRepository.resolveSafFolderOwnerEmail(
            driveFileId: driveFileId,
            folderName: safInfo?.displayName ?? 'Dossier',
          );
        }
        // Vérifier si le dossier n'est pas déjà surveillé
        final existing = await (widget.database.select(
          widget.database.watchedPaths,
        )..where((w) => w.path.equals(selectedDirectory))).get();

        if (existing.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ce dossier est déjà surveillé')),
            );
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
            }
          },
        );

        if (mounted) {
          final n = result.newSoundCount;
          if (n > 0) {
            await _offerAddNewSoundsToBoard(n);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Dossier ajouté et indexé'),
                duration: Duration(seconds: 2),
              ),
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
    final boards = await (widget.database.select(widget.database.soundBoards)
          ..orderBy([(b) => OrderingTerm(expression: b.createdAt)]))
        .get();

    if (!mounted) return;

    if (boards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$newSoundCount son${newSoundCount > 1 ? 's' : ''} indexé${newSoundCount > 1 ? 's' : ''}'),
          duration: const Duration(seconds: 3),
        ),
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

  Future<void> _linkAndInitializeDriveFolder({
    required String driveFolderId,
    required String folderName,
    String? relativeDrivePath,
    String? sharedDriveId,
  }) async {
    if (_libraries.any(
      (library) => library.driveFolderId == driveFolderId,
    )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ce dossier Drive est déjà indexé')),
        );
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
          await _showSyncConflictDialog(currentLibrary);
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
          message = 'Dossier Drive « $folderName » mis à jour '
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 3),
            ),
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

  Future<void> _confirmRemoveWatchedPath(db.WatchedPath watchedPath) async {
    final label = _labelsForWatchedPath(watchedPath).title;
    final type = SafDirectoryBridge.isSafTreeUri(watchedPath.path)
        ? 'dossier cloud'
        : 'dossier local';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Retirer l\'élément indexé'),
          content: Text(
            'Retirer le $type "$label" ? '
            'Les sons importés depuis cet élément seront supprimés '
            'de la bibliothèque et retirés des scènes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Retirer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _removeWatchedPath(watchedPath);
  }

  Future<void> _pullDriveLibrary(domain.Library library) async {
    setState(() => _isSyncBusy = true);
    try {
      await widget.syncController.pullForLaunch(library);
      await _loadDatabaseInfo();

      if (!mounted) return;

      final progressKey = _driveProgressKey(library.id);
      await widget.libraryRepository.indexDriveFolder(
        library: library,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _indexingProgress[progressKey] = progress;
            });
          }
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('« ${library.name} » est à jour'),
            duration: const Duration(seconds: 2),
          ),
        );
        await _loadDatabaseInfo();
      }
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors de la récupération : $e');
      }
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _syncDriveLibrary(domain.Library library) async {
    setState(() => _isSyncBusy = true);
    try {
      await widget.syncController.syncNow(library);
      await _loadDatabaseInfo();

      if (!mounted) return;

      if (widget.syncController.state.status == SyncStatus.conflict) {
        await _showSyncConflictDialog(library);
        return;
      }

      if (widget.syncController.state.status == SyncStatus.error) {
        showCopyableSnackBar(
          context,
          widget.syncController.state.message ??
              'Erreur lors de la synchronisation',
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('« ${library.name} » synchronisé vers Drive'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(
          context,
          'Erreur lors de la synchronisation : $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _showSyncConflictDialog(domain.Library library) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Conflit de synchronisation'),
          content: const Text(
            'Une version plus récente existe sur Drive. Quelle version garder ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('remote'),
              child: const Text('Prendre Drive'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('local'),
              child: const Text('Garder local'),
            ),
          ],
        );
      },
    );

    if (!mounted || choice == null) return;

    setState(() => _isSyncBusy = true);
    try {
      if (choice == 'local') {
        await widget.syncController.keepLocal(library);
      } else if (choice == 'remote') {
        await widget.syncController.takeRemote(library);
      }
      await _loadDatabaseInfo();
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  String _formatDriveSyncTimestamp(DateTime syncedAt) {
    final local = syncedAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final syncDay = DateTime(local.year, local.month, local.day);
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(local.hour)}:${two(local.minute)}';

    if (syncDay == today) {
      return "aujourd'hui à $time";
    }
    if (syncDay == today.subtract(const Duration(days: 1))) {
      return 'hier à $time';
    }
    return 'le ${two(local.day)}/${two(local.month)} à $time';
  }

  Widget _buildDriveSyncStatus(domain.Library library) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant.withValues(alpha: 0.75);
    final lastSync = library.lastSyncedAt;

    if (lastSync == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 13, color: muted),
          const SizedBox(width: 4),
          Text(
            'Pas encore synchronisé',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_done_outlined,
          size: 13,
          color: scheme.primary.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Synchronisé ${_formatDriveSyncTimestamp(lastSync)}',
            style: TextStyle(fontSize: 11, color: muted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDriveSyncMenu(domain.Library library) {
    if (_isSyncBusy) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: Padding(
          padding: EdgeInsets.all(7),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final iconColor = scheme.onSurfaceVariant.withValues(alpha: 0.55);

    return PopupMenuButton<_DriveSyncAction>(
      tooltip: 'Synchroniser',
      padding: EdgeInsets.zero,
      splashRadius: 16,
      offset: const Offset(0, 36),
      child: Icon(
        Icons.sync,
        size: 20,
        color: iconColor,
      ),
      onSelected: (action) {
        switch (action) {
          case _DriveSyncAction.pull:
            unawaited(_pullDriveLibrary(library));
          case _DriveSyncAction.push:
            unawaited(_syncDriveLibrary(library));
          case _DriveSyncAction.downloadAll:
            unawaited(_downloadAllLibraryAudio(library));
        }
      },
      itemBuilder: (menuContext) => [
        PopupMenuItem<_DriveSyncAction>(
          value: _DriveSyncAction.pull,
          height: 48,
          child: Row(
            children: [
              Icon(
                Icons.cloud_download_outlined,
                size: 20,
                color: scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Récupérer depuis Drive'),
                    Text(
                      'Appliquer la version distante',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<_DriveSyncAction>(
          value: _DriveSyncAction.push,
          height: 48,
          child: Row(
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                size: 20,
                color: scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Envoyer vers Drive'),
                    Text(
                      'Publier les changements locaux',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<_DriveSyncAction>(
          value: _DriveSyncAction.downloadAll,
          height: 48,
          enabled: _downloadProgress[library.id] == null ||
              _downloadProgress[library.id]!.isComplete,
          child: Row(
            children: [
              Icon(
                Icons.download_for_offline_outlined,
                size: 20,
                color: scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Tout télécharger'),
                    Text(
                      'Rendre tous les sons disponibles hors-ligne',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _downloadAllLibraryAudio(domain.Library library) async {
    _cancelDownloadAll = false;
    setState(() {
      _downloadProgress[library.id] = IndexingProgress(
        path: library.name,
        current: 0,
        total: 0,
        isComplete: false,
      );
    });

    try {
      await widget.libraryRepository.downloadAllLibraryAudio(
        library: library,
        isCancelled: () => _cancelDownloadAll,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress[library.id] = progress);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadProgress[library.id] = IndexingProgress(
            path: library.name,
            current: 0,
            total: 0,
            isComplete: true,
            error: e.toString(),
          );
        });
      }
    }
  }

  Future<void> _confirmRemoveDriveLibrary(domain.Library library) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Retirer l\'élément indexé'),
          content: Text(
            'Retirer le dossier Drive « ${library.name} » ? '
            'Les sons importés depuis cet élément seront supprimés '
            'de la bibliothèque et retirés des scènes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Retirer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await widget.libraryRepository.removeLibrary(library);
      _indexingProgress.remove(_driveProgressKey(library.id));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dossier Drive retiré avec succès'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      await _loadDatabaseInfo();
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors de la suppression : $e');
      }
    }
  }

  Future<void> _removeWatchedPath(db.WatchedPath watchedPath) async {
    try {
      final watchedPathEntity = domain.WatchedPath(
        id: watchedPath.id,
        path: watchedPath.path,
        isDirectory: watchedPath.isDirectory,
        addedAt: watchedPath.addedAt,
      );

      await _repository.removeWatchedPath(watchedPathEntity);

      _indexingProgress.remove(_normalizeWatchedPath(watchedPath.path));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chemin retiré avec succès'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      await _loadDatabaseInfo();
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors de la suppression: $e');
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _normalizeWatchedPath(String path) {
    return p.normalize(path).replaceAll('\\', '/');
  }

  int _countSoundsInDirectory(String directoryPath) {
    final prefix = _normalizeWatchedPath(directoryPath);
    final pathPrefix = prefix.endsWith('/') ? prefix : '$prefix/';

    return _sounds.where((sound) {
      final soundPath = _normalizeWatchedPath(sound.filePath);
      return soundPath.startsWith(pathPrefix) || soundPath == prefix;
    }).length;
  }

  int _countSoundsForWatchedPath(db.WatchedPath watchedPath) {
    if (SafDirectoryBridge.isSafTreeUri(watchedPath.path)) {
      final marker = '/saf_watch/${watchedPath.id}/';
      return _sounds
          .where(
            (sound) => sound.filePath.replaceAll('\\', '/').contains(marker),
          )
          .length;
    }
    return _countSoundsInDirectory(watchedPath.path);
  }

  IndexedFolderLabels _labelsForWatchedPath(
    db.WatchedPath watchedPath, [
    SafTreeInfo? safInfo,
  ]) {
    final info = safInfo ?? _safFolderInfo[watchedPath.path];
    return IndexedFolderLabels.forWatchedPath(
      path: watchedPath.path,
      accountEmail: watchedPath.accountEmail,
      safDisplayName: info?.displayName,
      safDisplayPath: info?.displayPath,
    );
  }

  IndexedFolderLabels _labelsForItem(_IndexedFolderItem item) {
    if (item.isLocal) {
      return _labelsForWatchedPath(item.watchedPath!);
    }

    final library = item.library!;
    return IndexedFolderLabels.forLibrary(
      name: library.name,
      drivePath: library.drivePath,
      ownerEmail: library.ownerEmail,
    );
  }

  String _driveProgressKey(int libraryId, [String? pendingName]) {
    if (libraryId < 0 && pendingName != null) {
      return 'drive:pending:$pendingName';
    }
    return 'drive:$libraryId';
  }

  int _countSoundsInLibrary(int libraryId) {
    return _sounds.where((sound) => sound.libraryId == libraryId).length;
  }

  List<_IndexedFolderItem> _indexedFolderItems() {
    final items = <_IndexedFolderItem>[
      for (final watchedPath in _watchedPaths)
        if (watchedPath.isDirectory) _IndexedFolderItem.local(watchedPath),
      for (final library in _libraries)
        _IndexedFolderItem.drive(library),
    ];
    items.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return items;
  }

  IndexingProgress _progressForItem(_IndexedFolderItem item) {
    final key = item.isLocal
        ? _normalizeWatchedPath(item.watchedPath!.path)
        : _driveProgressKey(item.library!.id, item.library!.name);

    final live = _indexingProgress[key] ??
        (item.isLocal
            ? null
            : _indexingProgress[_driveProgressKey(-1, item.library!.name)]);

    if (live != null) {
      return live;
    }

    if (item.isLocal) {
      final soundCount = _countSoundsForWatchedPath(item.watchedPath!);
      return IndexingProgress(
        path: item.watchedPath!.path,
        current: soundCount,
        total: soundCount,
        isComplete: true,
      );
    }

    final soundCount = _countSoundsInLibrary(item.library!.id);
    return IndexingProgress(
      path: item.library!.name,
      current: soundCount,
      total: soundCount,
      isComplete: true,
    );
  }

  double? _indexingBarValue(IndexingProgress progress, bool isIndexing) {
    if (isIndexing) {
      return progress.total > 0 ? progress.progress : null;
    }
    return 1.0;
  }

  String _indexingStatusLabel(IndexingProgress progress, bool isIndexing) {
    if (isIndexing) {
      return 'Indexation de ${progress.current}/${progress.total > 0 ? progress.total : '…'} fichiers';
    }

    final count = progress.total > 0 ? progress.total : progress.current;
    if (count == 1) {
      return '1 fichier indexé';
    }
    return '$count fichiers indexés';
  }

  Widget _buildSettingsSectionCard({
    required Widget title,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const Divider(),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitleRow({
    required IconData icon,
    required String title,
    List<Widget>? trailing,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (trailing != null) ...[
          const Spacer(),
          ...trailing,
        ],
      ],
    );
  }

  Widget _buildDriveSection() {
    return ListenableBuilder(
      listenable: widget.appPreferences,
      builder: (context, _) {
        return _buildSettingsSectionCard(
          title: _buildSectionTitleRow(
            icon: Icons.cloud_outlined,
            title: 'Google Drive',
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Activer le téléchargement automatique par défaut',
            ),
            subtitle: Text(
              'À l\'ajout d\'un dossier Drive, télécharge les fichiers pour '
              'classer correctement chaque son à l\'indexation.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            value: widget.appPreferences.autoDownloadDriveByDefault,
            onChanged: (value) => unawaited(
              widget.appPreferences.setAutoDownloadDriveByDefault(value),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSamplerSection() {
    return ListenableBuilder(
      listenable: widget.appPreferences,
      builder: (context, _) {
        return _buildSettingsSectionCard(
          title: _buildSectionTitleRow(
            icon: Icons.grid_view_rounded,
            title: 'Scène',
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Télécharger les sons ajoutés à un pad'),
            subtitle: Text(
              'Si connecté à Drive, les variantes sont récupérées dès l\'ajout.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            value: widget.appPreferences.autoDownloadPadSounds,
            onChanged: (value) =>
                unawaited(widget.appPreferences.setAutoDownloadPadSounds(value)),
          ),
        );
      },
    );
  }

  Widget _buildAutoDownloadToggle(domain.Library library) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 28,
          height: 20,
          child: Transform.scale(
            scale: 0.65,
            alignment: Alignment.centerLeft,
            child: Switch(
              value: library.autoDownload,
              onChanged: (value) async {
                await widget.libraryRepository.setAutoDownload(
                  library,
                  value: value,
                );
                if (mounted) await _loadDatabaseInfo();
              },
            ),
          ),
        ),
        const SizedBox(width: 2),
        Text(
          'Téléchargement automatique',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget? _buildDownloadProgressSection(domain.Library library) {
    final progress = _downloadProgress[library.id];
    if (progress == null) return null;
    if (progress.isComplete && progress.error == null) return null;

    final isDownloading = !progress.isComplete;
    final barColor =
        progress.error != null ? Colors.red.shade600 : Colors.blue.shade600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: isDownloading
                ? (progress.total > 0 ? progress.progress : null)
                : 1.0,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                progress.error != null
                    ? 'Erreur: ${progress.error}'
                    : isDownloading
                    ? 'Téléchargement ${progress.current}/${progress.total > 0 ? progress.total : '…'} fichiers'
                    : 'Téléchargement terminé',
                style: TextStyle(
                  fontSize: 11,
                  color: progress.error != null
                      ? Colors.red.shade700
                      : Colors.grey.shade600,
                ),
              ),
            ),
            if (isDownloading)
              GestureDetector(
                onTap: () => setState(() => _cancelDownloadAll = true),
                child: Text(
                  'Annuler',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildIndexingProgressSection(
    BuildContext context,
    IndexingProgress progress,
    bool isIndexing,
  ) {
    final barColor = progress.error != null
        ? Colors.red.shade600
        : Colors.green.shade600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _indexingBarValue(progress, isIndexing),
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          progress.error != null
              ? 'Erreur: ${progress.error}'
              : _indexingStatusLabel(progress, isIndexing),
          style: TextStyle(
            fontSize: 11,
            color: progress.error != null
                ? Colors.red.shade700
                : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsBody() {
    return AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            alignment: Alignment.topCenter,
            children: [
              ...previousChildren,
              ?currentChild,
            ],
          );
        },
        child: _isLoading
            ? const _SettingsLoadingView(key: ValueKey('settings-loading'))
            : RefreshIndicator(
                key: const ValueKey('settings-content'),
                onRefresh: _loadDatabaseInfo,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSamplerSection(),
                      const SizedBox(height: 16),
                      _buildDriveSection(),
                      const SizedBox(height: 16),
                      _buildSettingsSectionCard(
                        title: _buildSectionTitleRow(
                          icon: Icons.storage,
                          title: 'État de la base de données',
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow(
                              'Nombre total de sons',
                              '${_sounds.length}',
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              'Taille de la base de données',
                              _formatBytes(_dbSize),
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              'Chemin de la base de données',
                              _dbPath,
                              isPath: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSettingsSectionCard(
                        title: _buildSectionTitleRow(
                          icon: Icons.folder_copy,
                          title: 'Éléments indexés',
                          trailing: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 32,
                                height: 32,
                              ),
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add),
                              tooltip: Platform.isAndroid
                                  ? 'Ajouter un dossier'
                                  : 'Ajouter un dossier local ou Drive',
                              onPressed: _onAddFolderPressed,
                            ),
                          ],
                        ),
                        child: _indexedFolderItems().isEmpty
                            ? SizedBox(
                                width: double.infinity,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.folder_off,
                                      size: 48,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Aucun dossier indexé',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Ajoutez un dossier local ou un dossier Drive',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _indexedFolderItems().length,
                                separatorBuilder: (context, index) => Divider(
                                  height: 17,
                                  thickness: 1,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.45),
                                ),
                                itemBuilder: (context, index) {
                                  final item = _indexedFolderItems()[index];
                                  final labels = _labelsForItem(item);
                                  final progress = _progressForItem(item);
                                  final isIndexing = !progress.isComplete;

                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                        child: Icon(
                                          item.isLocal &&
                                                  SafDirectoryBridge
                                                      .isSafTreeUri(
                                                    item.watchedPath!.path,
                                                  )
                                              ? Icons.cloud
                                              : item.isLocal
                                              ? Icons.folder
                                              : Icons.cloud,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              labels.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              labels.subtitle,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600],
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (!item.isLocal) ...[
                                              const SizedBox(height: 2),
                                              _buildDriveSyncStatus(
                                                item.library!,
                                              ),
                                              const SizedBox(height: 4),
                                              _buildAutoDownloadToggle(
                                                item.library!,
                                              ),
                                            ],
                                            _buildIndexingProgressSection(
                                              context,
                                              progress,
                                              isIndexing,
                                            ),
                                            if (!item.isLocal)
                                              _buildDownloadProgressSection(
                                                item.library!,
                                              ) ??
                                                  const SizedBox.shrink(),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!item.isLocal)
                                            _buildDriveSyncMenu(
                                              item.library!,
                                            ),
                                          SizedBox(width: 8),
                                          IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints.tightFor(
                                              width: 32,
                                              height: 32,
                                            ),
                                            icon: Icon(
                                              Icons.delete_outline,
                                              size: 20,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant
                                                  .withValues(alpha: 0.55),
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () {
                                              if (item.isLocal) {
                                                _confirmRemoveWatchedPath(
                                                  item.watchedPath!,
                                                );
                                              } else {
                                                _confirmRemoveDriveLibrary(
                                                  item.library!,
                                                );
                                              }
                                            },
                                            tooltip: 'Retirer',
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildSettingsBody();

    final accountAction = ListenableBuilder(
      listenable: widget.libraryRepository,
      builder: (context, _) => _buildAccountMenu(context),
    );

    if (widget.isModal) {
      return AppModalShell(
        title: 'Paramètres',
        actions: [accountAction],
        body: body,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: accountAction,
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isPath = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: isPath ? Colors.grey[600] : null,
              fontSize: isPath ? 12 : null,
            ),
          ),
        ),
      ],
    );
  }
}

enum _DriveSyncAction { pull, push, downloadAll }

class _IndexedFolderItem {
  const _IndexedFolderItem.local(this.watchedPath) : library = null;

  const _IndexedFolderItem.drive(this.library) : watchedPath = null;

  final db.WatchedPath? watchedPath;
  final domain.Library? library;

  bool get isLocal => watchedPath != null;

  DateTime get addedAt =>
      isLocal ? watchedPath!.addedAt : library!.createdAt;
}

class _SettingsLoadingView extends StatefulWidget {
  const _SettingsLoadingView({super.key});

  @override
  State<_SettingsLoadingView> createState() => _SettingsLoadingViewState();
}

class _SettingsLoadingViewState extends State<_SettingsLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _bar(
    Color color, {
    double width = double.infinity,
    double height = 12,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _sectionCardSkeleton({
    required Widget title,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const Divider(),
            child,
          ],
        ),
      ),
    );
  }

  Widget _databaseCard(Color color) {
    return _sectionCardSkeleton(
      title: Row(
        children: [
          _bar(color, width: 20, height: 20),
          const SizedBox(width: 8),
          _bar(color, width: 210, height: 18),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _bar(color, width: 180),
              const SizedBox(width: 12),
              Expanded(child: _bar(color)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _bar(color, width: 180),
              const SizedBox(width: 12),
              Expanded(child: _bar(color, width: 120)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _bar(color, width: 180),
              const SizedBox(width: 12),
              Expanded(child: _bar(color)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _indexedCard(Color color) {
    return _sectionCardSkeleton(
      title: Row(
        children: [
          _bar(color, width: 20, height: 20),
          const SizedBox(width: 8),
          _bar(color, width: 150, height: 18),
          const Spacer(),
          _bar(color, width: 28, height: 28),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _indexedItemRow(color),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _bar(
              color.withValues(alpha: 0.35),
              height: 1,
            ),
          ),
          _indexedItemRow(color),
        ],
      ),
    );
  }

  Widget _indexedItemRow(Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: color,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(color, width: 150, height: 14),
              const SizedBox(height: 4),
              _bar(color, height: 10),
              const SizedBox(height: 8),
              _bar(color, height: 4),
              const SizedBox(height: 4),
              _bar(color, width: 72, height: 10),
            ],
          ),
        ),
        _bar(color, width: 20, height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final alpha = 0.12 + (_controller.value * 0.08);
        final color = scheme.onSurface.withValues(alpha: alpha);
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _databaseCard(color),
              const SizedBox(height: 16),
              _indexedCard(color),
            ],
          ),
        );
      },
    );
  }
}
