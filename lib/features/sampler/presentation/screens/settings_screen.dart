import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart' show OrderingTerm;
import '../../../../core/database/database.dart' as db;
import '../../../../core/settings/app_preferences.dart';
import '../../../../core/platform/saf_directory_bridge.dart';
import '../../../../core/sync/drive_account_profile.dart';
import '../../../../core/sync/google_oauth_config.dart';
import '../../../../core/sync/google_oauth_setup_dialog.dart';
import '../../../../core/sync/drive_client.dart';
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
import '../widgets/compact_switch.dart';
import '../widgets/drive_sync_ui.dart';
import 'sound_library_screen.dart';

/// Écran des paramètres
class SettingsScreen extends StatefulWidget {
  final db.AppDatabase database;
  final LibraryRepository libraryRepository;
  final SyncController syncController;
  final AppPreferences appPreferences;
  final bool isModal;
  final bool scrollToDriveSection;

  const SettingsScreen({
    super.key,
    required this.database,
    required this.libraryRepository,
    required this.syncController,
    required this.appPreferences,
    this.isModal = false,
    this.scrollToDriveSection = false,
  });

  /// Page plein écran sur téléphone, modale sur tablette et desktop.
  static Future<void> open(
    BuildContext context, {
    required db.AppDatabase database,
    required LibraryRepository libraryRepository,
    required SyncController syncController,
    required AppPreferences appPreferences,
    bool scrollToDriveSection = false,
  }) {
    return openAdaptiveScreen(
      context: context,
      builder: ({required isModal}) => SettingsScreen(
        database: database,
        libraryRepository: libraryRepository,
        syncController: syncController,
        appPreferences: appPreferences,
        isModal: isModal,
        scrollToDriveSection: scrollToDriveSection,
      ),
    );
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Hauteur réservée pour la zone statut d'un élément indexé : elle contient
  /// soit la ligne méta (repos), soit le bloc barre + libellé (activité), sans
  /// que le passage de l'un à l'autre ne change la hauteur de l'élément.
  static const double _statusSlotHeight = 30;

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
  // Décompte « disponible hors ligne / total » par bibliothèque Drive.
  final Map<int, ({int available, int total})> _offlineCounts = {};
  bool _cancelDownloadAll = false;
  final Map<String, SafTreeInfo> _safFolderInfo = {};
  bool _isInitialLoad = true;
  bool _isSyncBusy = false;
  bool _isDriveAuthBusy = false;
  bool _shouldScrollToDriveSection = false;
  final GlobalKey _driveSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _shouldScrollToDriveSection = widget.scrollToDriveSection;
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

  void _scrollToDriveSectionIfNeeded() {
    if (!_shouldScrollToDriveSection) return;
    _shouldScrollToDriveSection = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sectionContext = _driveSectionKey.currentContext;
      if (sectionContext == null) return;
      Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
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
      if (isDriveAuthExpired(widget.syncController.state) ||
          widget.libraryRepository.requiresInteractiveReconnect) {
        await widget.libraryRepository.invalidateAuthSession();
      } else {
        await widget.libraryRepository.reconnectSilently();
      }

      // Charger les dossiers locaux surveillés et les bibliothèques Drive
      final watchedPaths = await widget.database
          .select(widget.database.watchedPaths)
          .get();
      final libraries = await widget.libraryRepository.getLibraries();

      // Charger tous les sons de la base de données
      final sounds = await widget.database.select(widget.database.sounds).get();

      // Obtenir le chemin de la base de données (source de vérité unique)
      final dbFile = await db.resolveDatabaseFile();

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
      _scrollToDriveSectionIfNeeded();
      unawaited(_loadSafFolderInfo());
      unawaited(_loadOfflineCounts());
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
    final photoUrl = account.photoUrlForDisplay(
      sizePx: (radius * 2).round(),
    );
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
        key: ValueKey(photoUrl),
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
      return const Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          SizedBox(width: 12),
          Text('Connexion Google…'),
        ],
      );
    }

    if (!signedIn) {
      return Row(
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
                Text(
                  'Compte Google',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildGoogleAccountAvatar(account, radius: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Compte Google',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (authExpired) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Reconnectez-vous pour synchroniser vos bibliothèques.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!sessionActive)
                  TextButton(
                    onPressed: _connectDriveAccount,
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
      ],
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

  /// Charge en arrière-plan le décompte « hors ligne / total » de chaque
  /// bibliothèque Drive (présence des fichiers dans le cache local).
  Future<void> _loadOfflineCounts() async {
    final libraries =
        _libraries.where((library) => library.isConnectedToDrive).toList();
    for (final library in libraries) {
      if (library.id < 0) continue; // Bibliothèque en cours de création.
      await _refreshOfflineCount(library);
    }
  }

  /// Recalcule le décompte hors-ligne d'une seule bibliothèque (best-effort).
  Future<void> _refreshOfflineCount(domain.Library library) async {
    try {
      final counts =
          await widget.libraryRepository.countDownloadedSounds(library);
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

  Future<void> _indexWatchedDirectory(
    String selectedDirectory, {
    SafTreeInfo? safInfo,
  }) async {
    try {
      final isSafTree = SafDirectoryBridge.isSafTreeUri(selectedDirectory);
      final directoryExists = isSafTree ||
          await Directory(selectedDirectory).exists();

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

  Future<void> _refreshAllFromDrive() async {
    final connected =
        _libraries.where((library) => library.isConnectedToDrive).toList();
    if (connected.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun dossier Drive indexé')),
        );
      }
      return;
    }

    setState(() => _isSyncBusy = true);
    try {
      for (final library in connected) {
        await widget.syncController.pullForLaunch(library);
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
      }

      await _loadDatabaseInfo();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bibliothèque(s) Drive actualisée(s)'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on DriveAuthException {
      await widget.syncController.handleAuthFailure();
      if (mounted) {
        showCopyableSnackBar(
          context,
          'Session Google expirée — reconnectez-vous via l\'icône compte.',
        );
      }
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Erreur lors de l\'actualisation : $e');
      }
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _resolveSyncConflict(domain.Library library) async {
    setState(() => _isSyncBusy = true);
    try {
      await showSyncConflictDialog(
        context: context,
        syncController: widget.syncController,
        library: library,
        onResolved: _loadDatabaseInfo,
      );
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

  /// Zone d'actions d'un élément indexé. Pour un dossier Drive, toutes les
  /// actions secondaires (tout télécharger, téléchargement auto, retirer) sont
  /// regroupées dans un unique menu ⋮ ; un dossier local n'a que « Retirer ».
  Widget _buildItemTrailing(_IndexedFolderItem item) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant.withValues(alpha: 0.7);

    if (item.isLocal) {
      // Même geste (menu ⋮) que pour un dossier Drive, avec ici une seule
      // entrée, pour homogénéiser l'action « Retirer » entre les deux types.
      return PopupMenuButton<_LibraryAction>(
        tooltip: 'Options',
        icon: Icon(Icons.more_vert, color: muted),
        onSelected: (action) {
          if (action == _LibraryAction.remove) {
            unawaited(_confirmRemoveWatchedPath(item.watchedPath!));
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<_LibraryAction>(
            value: _LibraryAction.remove,
            child: _menuRow(
              Icons.delete_outline,
              'Retirer',
              iconColor: scheme.error,
              textColor: scheme.error,
            ),
          ),
        ],
      );
    }

    final library = item.library!;
    final downloadProgress = _downloadProgress[library.id];
    final isDownloading =
        downloadProgress != null && !downloadProgress.isComplete;
    final offline = _offlineCounts[library.id];
    final fullyOffline =
        offline != null && offline.total > 0 && offline.available >= offline.total;

    final String downloadLabel;
    if (isDownloading) {
      downloadLabel = 'Téléchargement en cours…';
    } else if (fullyOffline) {
      downloadLabel = 'Déjà tout téléchargé';
    } else {
      downloadLabel = 'Tout télécharger';
    }

    return PopupMenuButton<_LibraryAction>(
      tooltip: 'Options',
      icon: Icon(Icons.more_vert, color: muted),
      onSelected: (action) {
        switch (action) {
          case _LibraryAction.downloadAll:
            unawaited(_downloadAllLibraryAudio(library));
          case _LibraryAction.toggleAutoDownload:
            unawaited(_toggleAutoDownload(library));
          case _LibraryAction.remove:
            unawaited(_confirmRemoveDriveLibrary(library));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_LibraryAction>(
          value: _LibraryAction.downloadAll,
          enabled: !isDownloading && !fullyOffline,
          child: _menuRow(
            fullyOffline
                ? Icons.download_done_outlined
                : Icons.download_outlined,
            downloadLabel,
          ),
        ),
        PopupMenuItem<_LibraryAction>(
          value: _LibraryAction.toggleAutoDownload,
          child: _menuRow(
            library.autoDownload
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            'Téléchargement auto',
            iconColor: library.autoDownload ? scheme.primary : null,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_LibraryAction>(
          value: _LibraryAction.remove,
          child: _menuRow(
            Icons.delete_outline,
            'Retirer',
            iconColor: scheme.error,
            textColor: scheme.error,
          ),
        ),
      ],
    );
  }

  /// Ligne icône + libellé pour une entrée du menu ⋮ (mise en page homogène).
  Widget _menuRow(
    IconData icon,
    String label, {
    Color? iconColor,
    Color? textColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: textColor)),
      ],
    );
  }

  Future<void> _toggleAutoDownload(domain.Library library) async {
    await widget.libraryRepository.setAutoDownload(
      library,
      value: !library.autoDownload,
    );
    if (mounted) await _loadDatabaseInfo();
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
    } finally {
      // Rafraîchit l'indicateur hors-ligne (téléchargement complet ou annulé).
      await _refreshOfflineCount(library);
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

  /// Détail complet de l'état de la base, dont le chemin copiable — ouvert au
  /// tap sur l'icône « i » des éléments indexés.
  Future<void> _showDatabaseStateDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AppFormDialog(
          title: 'État de la base de données',
          width: 460,
          onClose: () => Navigator.of(dialogContext).pop(),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Nombre total de sons', '${_sounds.length}'),
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
        );
      },
    );
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

  /// Libellé compact du nombre de fichiers indexés (état au repos).
  String _fileCountLabel(IndexingProgress progress) {
    final count = progress.total > 0 ? progress.total : progress.current;
    return count <= 1 ? '$count fichier' : '$count fichiers';
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

  /// Sélecteur du mode réseau : boutons segmentés (3 choix) + description du
  /// mode courant. Plus léger qu'un dropdown pour un réglage à faible cardinalité.
  Widget _buildConnectivityModeSelector() {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.appPreferences.connectivityMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mode réseau',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ConnectivityMode>(
            // Ordre d'affichage : « Live » (mode par défaut, cas d'usage
            // principal en scène) en premier, puis Connecté et Hors ligne.
            segments: const [
              ConnectivityMode.liveOffline,
              ConnectivityMode.connected,
              ConnectivityMode.offline,
            ]
                .map(
                  (mode) => ButtonSegment<ConnectivityMode>(
                    value: mode,
                    label: Text(mode.label),
                  ),
                )
                .toList(),
            selected: {selected},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
            onSelectionChanged: (selection) => unawaited(
              widget.appPreferences.setConnectivityMode(selection.first),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          selected.description,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildDriveSection() {
    return KeyedSubtree(
      key: _driveSectionKey,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          widget.libraryRepository,
          widget.syncController,
          widget.appPreferences,
        ]),
        builder: (context, _) {
          final scheme = Theme.of(context).colorScheme;
          final syncState = widget.syncController.state;
          final authExpired = isDriveAuthExpired(syncState);
          return _buildSettingsSectionCard(
            title: _buildSectionTitleRow(
              icon: Icons.cloud_outlined,
              title: 'Drive',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDriveAccountHeader(
                  syncState: syncState,
                  authExpired: authExpired,
                ),
                // La bannière n'affiche QUE l'activité de synchro (syncing /
                // synced / conflit / erreur). L'état de connexion — dont
                // « hors-ligne » — est déjà porté par l'en-tête de compte
                // ci-dessus ; le dupliquer ici créait deux nuages
                // contradictoires (« Connecté » + « Hors-ligne »).
                if (syncState.status != SyncStatus.idle &&
                    syncState.status != SyncStatus.offline) ...[
                  const SizedBox(height: 12),
                  SyncStatusBanner(state: syncState),
                ],
                const SizedBox(height: 12),
                Text(
                  'Téléchargement automatique',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                CompactSwitchListTile(
                  title: const Text('Sons ajoutés à un pad'),
                  subtitle: Text(
                    'Si connecté à Drive, les variantes sont récupérées dès l\'ajout.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  value: widget.appPreferences.autoDownloadPadSounds,
                  onChanged: (value) => unawaited(
                    widget.appPreferences.setAutoDownloadPadSounds(value),
                  ),
                ),
                CompactSwitchListTile(
                  title: const Text('Nouveaux dossiers Drive (tout le contenu)'),
                  subtitle: Text(
                    'À l\'ajout d\'un dossier Drive, télécharge les fichiers pour '
                    'classer correctement chaque son à l\'indexation.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  value: widget.appPreferences.autoDownloadDriveByDefault,
                  onChanged: (value) => unawaited(
                    widget.appPreferences.setAutoDownloadDriveByDefault(value),
                  ),
                ),
                const Divider(height: 24),
                _buildConnectivityModeSelector(),
                const Divider(height: 24),
                // Pull + ré-indexation de toutes les bibliothèques Drive
                // connectées, en un tap. Désactivé pendant une synchro en cours
                // (_isSyncBusy) ou si la session Drive a expiré (le pull
                // échouerait). La méthode gère elle-même le cas « aucun dossier ».
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: (_isSyncBusy || authExpired)
                        ? null
                        : () => unawaited(_refreshAllFromDrive()),
                    icon: _isSyncBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(
                      _isSyncBusy
                          ? 'Actualisation…'
                          : 'Tout actualiser depuis Drive',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Ligne d'information au repos : statut de synchro Drive + nombre de
  /// fichiers indexés, sur une seule ligne compacte (pas de barre pleine).
  Widget _buildItemMetaRow(_IndexedFolderItem item, IndexingProgress indexing) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant.withValues(alpha: 0.75);

    Widget chip(IconData icon, String label, {Color? color}) {
      final c = color ?? muted;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: c)),
        ],
      );
    }

    final fileCount = chip(Icons.audiotrack_outlined, _fileCountLabel(indexing));

    if (item.isLocal) {
      return fileCount;
    }

    // Indicateur de téléchargement : on affiche TOUJOURS « dispo/total » — le
    // total donne le nombre de fichiers, et « 13/13 » signale aussi que tout
    // est téléchargé.
    final offline = _offlineCounts[item.library!.id];
    final Widget availability;
    if (offline == null || offline.total == 0) {
      // Décompte pas encore calculé (ou dossier vide) : nombre de fichiers seul.
      availability = fileCount;
    } else {
      final complete = offline.available >= offline.total;
      availability = chip(
        complete
            ? Icons.download_done_outlined
            : Icons.download_outlined,
        '${offline.available}/${offline.total} téléchargés',
        color: complete ? scheme.primary.withValues(alpha: 0.85) : null,
      );
    }

    return Row(
      children: [
        Flexible(child: _buildDriveSyncStatus(item.library!)),
        const SizedBox(width: 12),
        availability,
      ],
    );
  }

  /// Zone d'activité unifiée : **une seule** barre de progression à la fois.
  /// Priorité à l'indexation, puis au téléchargement ; au repos, aucune barre
  /// (le décompte de fichiers vit dans [_buildItemMetaRow]).
  Widget? _buildItemActivity(
    _IndexedFolderItem item,
    IndexingProgress indexing,
  ) {
    final scheme = Theme.of(context).colorScheme;

    // 1. Indexation en cours (local ou Drive) — prioritaire.
    if (!indexing.isComplete || indexing.error != null) {
      final hasError = indexing.error != null;
      return _buildActivityBlock(
        value: hasError
            ? 1.0
            : (indexing.total > 0 ? indexing.progress : null),
        color: hasError ? scheme.error : scheme.primary,
        label: hasError
            ? 'Erreur : ${indexing.error}'
            : 'Indexation ${indexing.current}/'
                '${indexing.total > 0 ? indexing.total : '…'}',
        isError: hasError,
      );
    }

    // 2. Téléchargement des variantes audio (Drive uniquement).
    if (!item.isLocal) {
      final download = _downloadProgress[item.library!.id];
      if (download != null && !download.isComplete) {
        return _buildActivityBlock(
          value: download.total > 0 ? download.progress : null,
          color: scheme.tertiary,
          label: 'Téléchargement ${download.current}/'
              '${download.total > 0 ? download.total : '…'}',
          onCancel: () => setState(() => _cancelDownloadAll = true),
        );
      }
      if (download?.error != null) {
        return _buildActivityBlock(
          value: 1.0,
          color: scheme.error,
          label: 'Erreur : ${download!.error}',
          isError: true,
        );
      }
    }

    // 3. Au repos : rien à afficher ici.
    return null;
  }

  /// Bloc d'activité empilé : barre de progression **puis libellé en dessous**.
  /// Rendu dans le même emplacement de hauteur fixe ([_statusSlotHeight]) que la
  /// ligne méta, pour que le passage repos ↔ activité ne bouge pas la hauteur.
  /// Erreur : libellé seul (avec ellipsis).
  Widget _buildActivityBlock({
    required double? value,
    required Color color,
    required String label,
    VoidCallback? onCancel,
    bool isError = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      fontSize: 11,
      color: isError ? scheme.error : scheme.onSurfaceVariant,
    );

    if (isError) {
      return Text(
        label,
        style: labelStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 5,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: Text(label, style: labelStyle)),
            if (onCancel != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCancel,
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
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
                      _buildDriveSection(),
                      const SizedBox(height: 16),
                      _buildIndexedFoldersCard(),
                    ],
                  ),
                ),
              ),
    );
  }

  /// Carte « Éléments indexés » : liste des dossiers locaux/Drive, plus un pied
  /// de carte résumant l'état de la base (cliquable pour le détail complet).
  Widget _buildIndexedFoldersCard() {
    // Calculé une seule fois par build (au lieu de quatre appels + tris).
    final items = _indexedFolderItems();

    return _buildSettingsSectionCard(
      title: _buildSectionTitleRow(
        icon: Icons.folder_copy,
        title: 'Éléments indexés',
        trailing: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            visualDensity: VisualDensity.compact,
            tooltip: 'Ajouter un dossier',
            icon: const Icon(Icons.add),
            onPressed: _onAddFolderPressed,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isEmpty)
            _buildEmptyIndexedState()
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (context, index) => Divider(
                height: 17,
                thickness: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.45),
              ),
              itemBuilder: (context, index) => _buildIndexedItemRow(items[index]),
            ),
          _buildDatabaseSummaryFooter(),
        ],
      ),
    );
  }

  Widget _buildEmptyIndexedState() {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.folder_off, size: 48, color: muted),
          const SizedBox(height: 8),
          Text(
            'Aucun dossier indexé',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: muted),
          ),
          const SizedBox(height: 8),
          Text(
            'Ajoutez un dossier local ou un dossier Drive',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: muted.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexedItemRow(_IndexedFolderItem item) {
    final labels = _labelsForItem(item);
    final progress = _progressForItem(item);
    // Même emplacement, même hauteur : activité en cours OU ligne méta au
    // repos, jamais les deux.
    final statusLine =
        _buildItemActivity(item, progress) ?? _buildItemMetaRow(item, progress);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            item.isLocal &&
                    SafDirectoryBridge.isSafTreeUri(item.watchedPath!.path)
                ? Icons.cloud
                : item.isLocal
                ? Icons.folder
                : Icons.cloud,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labels.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                labels.subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: _statusSlotHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: statusLine,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildItemTrailing(item),
      ],
    );
  }

  /// Pied de carte résumant l'état de la base — remplace l'ancienne icône « i »
  /// peu découvrable : le décompte est désormais visible, et le tap ouvre le
  /// détail complet (taille, chemin copiable).
  Widget _buildDatabaseSummaryFooter() {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final soundLabel =
        '${_sounds.length} son${_sounds.length > 1 ? 's' : ''}';
    return Column(
      children: [
        Divider(
          height: 24,
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.45),
        ),
        InkWell(
          onTap: _showDatabaseStateDialog,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.storage_outlined, size: 16, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$soundLabel · ${_formatBytes(_dbSize)}',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                Icon(Icons.info_outline, size: 16, color: muted),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildSettingsBody();

    if (widget.isModal) {
      return AppModalShell(
        title: 'Paramètres',
        body: body,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: body,
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isPath = false}) {
    final valueStyle = TextStyle(
      color: isPath ? Theme.of(context).colorScheme.onSurfaceVariant : null,
      fontSize: isPath ? 12 : null,
    );

    Widget valueWidget = Text(value, style: valueStyle);
    if (isPath && value.isNotEmpty) {
      valueWidget = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Chemin copié'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          child: Text(value, style: valueStyle),
        ),
      );
    }

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
        Expanded(child: valueWidget),
      ],
    );
  }
}

/// Actions du menu ⋮ d'une bibliothèque Drive indexée.
enum _LibraryAction { downloadAll, toggleAutoDownload, remove }

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
              _indexedCard(color),
            ],
          ),
        );
      },
    );
  }
}
