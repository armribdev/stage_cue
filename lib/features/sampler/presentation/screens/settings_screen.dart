import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../../core/database/database.dart' as db;
import '../../../../core/platform/saf_directory_bridge.dart';
import '../../../../core/sync/google_oauth_config.dart';
import '../../../../core/sync/google_oauth_setup_dialog.dart';
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
import 'library_sync_screen.dart';

/// Écran des paramètres
class SettingsScreen extends StatefulWidget {
  final db.AppDatabase database;
  final LibraryRepository libraryRepository;
  final SyncController syncController;
  final bool isModal;

  const SettingsScreen({
    super.key,
    required this.database,
    required this.libraryRepository,
    required this.syncController,
    this.isModal = false,
  });

  /// Page plein écran sur téléphone, modale sur tablette et desktop.
  static Future<void> open(
    BuildContext context, {
    required db.AppDatabase database,
    required LibraryRepository libraryRepository,
    required SyncController syncController,
  }) {
    return openAdaptiveScreen(
      context: context,
      builder: ({required isModal}) => SettingsScreen(
        database: database,
        libraryRepository: libraryRepository,
        syncController: syncController,
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
  final Map<String, SafTreeInfo> _safFolderInfo = {};
  bool _isInitialLoad = true;

  @override
  void initState() {
    super.initState();
    _initializeRepository();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Laisse la transition de navigation se terminer avant de lancer
      // les lectures DB pour éviter les à-coups à l'ouverture.
      unawaited(_startInitialLoad());
      unawaited(widget.libraryRepository.reconnectSilently());
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du chargement: $e')),
        );
      }
    }
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
        await _indexWatchedDirectory(
          pickResult.uri,
          safInfo: pickResult.treeInfo,
        );
      }
    } on SafDirectoryUnavailableException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
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
          if (accountEmail == null &&
              mounted &&
              !widget.libraryRepository.isConnected) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Connectez-vous via « Bibliothèque Drive » pour afficher '
                  'l\'e-mail du propriétaire du dossier.',
                ),
                duration: Duration(seconds: 4),
              ),
            );
          }
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
        await _repository.addWatchedPath(
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Dossier ajouté et indexé'),
              duration: Duration(seconds: 2),
            ),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Dossier inaccessible. Réessayez ou choisissez un autre emplacement.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'ajout du dossier: $e')),
        );
      }
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

    final folderName = selection.name;
    if (_libraries.any(
      (library) => library.driveFolderId == selection.folderId,
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
          drivePath: selection.relativeDrivePath,
          sharedDriveId: selection.sharedDriveId,
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
      final library = await widget.libraryRepository.linkDriveFolder(
        driveFolderId: selection.folderId,
        name: folderName,
        drivePath: selection.relativeDrivePath,
        ownerEmail: widget.libraryRepository.connectedAccountEmail,
        sharedDriveId: selection.sharedDriveId,
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
            content: Text('Dossier Drive « $folderName » indexé'),
            duration: const Duration(seconds: 2),
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            duration: const Duration(seconds: 8),
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'ajout Drive : $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la suppression : $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la suppression: $e')),
        );
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
      sessionOwnerEmail: widget.libraryRepository.connectedAccountEmail,
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
            alignment: widget.isModal
                ? Alignment.topCenter
                : Alignment.center,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
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
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.storage,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'État de la base de données',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                ],
                              ),
                              const Divider(),
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
                      ),
                      const SizedBox(height: 16),
                      AppNavigationCard(
                        icon: Icons.cloud_sync,
                        title: 'Bibliothèque Drive',
                        subtitle:
                            'Synchroniser les sons et métadonnées entre appareils',
                        onTap: () {
                          LibrarySyncScreen.open(
                            context,
                            libraryRepository: widget.libraryRepository,
                            syncController: widget.syncController,
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Éléments indexés',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.add),
                                tooltip: Platform.isAndroid
                                    ? 'Ajouter un dossier'
                                    : 'Ajouter un dossier local ou Drive',
                                onPressed: _onAddFolderPressed,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _indexedFolderItems().isEmpty
                          ? Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.folder_off,
                                      size: 48,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Aucun dossier indexé',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Ajoutez un dossier local ou un dossier Drive',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _indexedFolderItems().length,
                              itemBuilder: (context, index) {
                                final item = _indexedFolderItems()[index];
                                final labels = _labelsForItem(item);
                                final progress = _progressForItem(item);
                                final isIndexing = !progress.isComplete;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Stack(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          12,
                                          44,
                                          12,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            CircleAvatar(
                                              backgroundColor: Theme.of(
                                                context,
                                              ).colorScheme.primaryContainer,
                                              child: Icon(
                                                item.isLocal &&
                                                        SafDirectoryBridge
                                                            .isSafTreeUri(
                                                          item
                                                              .watchedPath!
                                                              .path,
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
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    labels.subtitle,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey[600],
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  _buildIndexingProgressSection(
                                                    context,
                                                    progress,
                                                    isIndexing,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Positioned(
                                        top: 10,
                                        right: 10,
                                        child: IconButton(
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
                                      ),
                                    ],
                                  ),
                                );
                              },
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

    if (widget.isModal) {
      return AppModalShell(title: 'Paramètres', body: body);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
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

  Widget _databaseCard(Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _bar(color, width: 20, height: 20),
                const SizedBox(width: 8),
                _bar(color, width: 210, height: 18),
              ],
            ),
            const SizedBox(height: 12),
            _bar(color, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                _bar(color, width: 180),
                const SizedBox(width: 12),
                Expanded(child: _bar(color)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _bar(color, width: 180),
                const SizedBox(width: 12),
                Expanded(child: _bar(color, width: 120)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _bar(color, width: 180),
                const SizedBox(width: 12),
                Expanded(child: _bar(color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _driveLibraryCard(Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _bar(color, width: 24, height: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(color, width: 140, height: 14),
                  const SizedBox(height: 8),
                  _bar(color, height: 10),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _bar(color, width: 16, height: 16),
          ],
        ),
      ),
    );
  }

  Widget _indexedHeader(Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _bar(color, width: 150, height: 20),
        _bar(color, width: 28, height: 28),
      ],
    );
  }

  Widget _indexedItemCard(Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 44, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(height: 8),
                      _bar(color, height: 10),
                      const SizedBox(height: 8),
                      _bar(color, height: 4),
                      const SizedBox(height: 4),
                      _bar(color, width: 72, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: _bar(color, width: 20, height: 20),
          ),
        ],
      ),
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
              _driveLibraryCard(color),
              const SizedBox(height: 16),
              _indexedHeader(color),
              const SizedBox(height: 8),
              _indexedItemCard(color),
              _indexedItemCard(color),
            ],
          ),
        );
      },
    );
  }
}
