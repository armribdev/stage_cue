import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart' show OrderingTerm;
import '../../../../core/audio/cue_audio_service.dart';
import '../../../../core/audio/waveform_extractor.dart';
import '../../../../core/database/database.dart' as db;
import '../../../../core/logging/app_log.dart';
import '../../../../core/logging/log_export.dart';
import '../../../../core/logging/log_sink.dart';
import '../../../../core/settings/app_preferences.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/skeleton.dart';
import '../../../../core/platform/saf_directory_bridge.dart';
import '../../../../core/sync/auto_sync_coordinator.dart';
import '../../../../core/sync/drive_account_profile.dart';
import '../../../../core/sync/drive_profile_cache.dart';
import '../../../../core/sync/google_oauth_config.dart';
import '../../../../core/sync/google_oauth_setup_dialog.dart';
import '../../../../core/update/app_update_checker.dart';
import '../../../../core/update/update_flow.dart';
import '../../../../core/update/update_log.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/indexed_folder_labels.dart';
import '../../../../core/utils/layout_utils.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/app_modal.dart';
import '../widgets/boxed_icon_button.dart';
import '../widgets/drive_folder_picker.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/sound_repository.dart';
import '../../data/models/indexing_progress.dart';
import '../../domain/entities/library.dart' as domain;
import '../../domain/entities/watched_path.dart' as domain;
import '../providers/sync_controller.dart';
import '../widgets/compact_switch.dart';
import '../widgets/drive_sync_ui.dart';
import '../widgets/section_context_anchor.dart';
import '../widgets/settings_indexed_folders_section.dart';
import '../widgets/settings_loading_view.dart';
import 'sound_library_screen.dart';

part 'settings/settings_data.dart';
part 'settings/settings_diagnostic.dart';
part 'settings/settings_drive_account.dart';
part 'settings/settings_add_folder.dart';
part 'settings/settings_indexing.dart';
part 'settings/settings_library_actions.dart';
part 'settings/settings_labels.dart';
part 'settings/settings_sections.dart';

/// Écran des paramètres
class SettingsScreen extends StatefulWidget {
  final db.AppDatabase database;
  final LibraryRepository libraryRepository;
  final SyncController syncController;
  final AutoSyncCoordinator autoSyncCoordinator;
  final AppPreferences appPreferences;
  final bool isModal;
  final bool scrollToDriveSection;

  const SettingsScreen({
    super.key,
    required this.database,
    required this.libraryRepository,
    required this.syncController,
    required this.autoSyncCoordinator,
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
    required AutoSyncCoordinator autoSyncCoordinator,
    required AppPreferences appPreferences,
    bool scrollToDriveSection = false,
  }) {
    return openAdaptiveScreen(
      context: context,
      builder: ({required isModal}) => SettingsScreen(
        database: database,
        libraryRepository: libraryRepository,
        syncController: syncController,
        autoSyncCoordinator: autoSyncCoordinator,
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
  List<db.WatchedPath> _watchedPaths = [];
  List<domain.Library> _libraries = [];
  List<db.Sound> _sounds = [];
  bool _isLoading = true;
  String _dbPath = '';
  int _dbSize = 0;
  late final SoundRepository _repository;
  // Suivi de la progression d'indexation par chemin (clé normalisée)
  final Map<String, IndexingProgress> _indexingProgress = {};
  // La progression de téléchargement audio vit dans le repository (durée de vie
  // longue) : fermer/rouvrir l'écran ré-attache l'UI à la passe réelle en cours.
  // Décompte « disponible hors ligne / total » par bibliothèque Drive.
  final Map<int, ({int available, int total})> _offlineCounts = {};
  final Map<String, SafTreeInfo> _safFolderInfo = {};
  bool _isInitialLoad = true;
  bool _isSyncBusy = false;
  bool _isDriveAuthBusy = false;
  bool _isRegeneratingWaveforms = false;
  int _waveformRegenDone = 0;
  int _waveformRegenTotal = 0;
  String? _appVersion;
  bool _isCheckingForUpdate = false;
  bool _isDiagnosticBusy = false;

  /// Périphériques de sortie de pré-écoute (cue) — Windows uniquement.
  List<CueDevice> _cueDevices = const [];
  bool _isLoadingCueDevices = false;
  bool _shouldScrollToDriveSection = false;

  /// Contexte de la section Drive pour le défilement ([Scrollable.ensureVisible]).
  /// Ancre sans [GlobalKey] : la section vit sous un [AnimatedSwitcher] qui
  /// empile brièvement l'ancien enfant (`previousChildren`) — une GlobalKey
  /// partagée pourrait alors apparaître deux fois dans l'arbre.
  BuildContext? _driveSectionContext;

  /// Cache disque de la photo de profil Google (affichage hors-ligne + pas de
  /// re-téléchargement à chaque ouverture des réglages).
  final DriveAvatarCache _avatarCache = DriveAvatarCache();

  /// Taille canonique de l'avatar mis en cache : découplée du `radius` des
  /// widgets pour qu'un seul fichier serve tous les affichages (Image.file
  /// redimensionne via `BoxFit.cover`), sans re-télécharger par taille.
  static const int _kAvatarCacheSizePx = 128;

  /// Futures d'avatar mémorisés par identité (e-mail) : évite de relancer un
  /// `resolve` (et de faire clignoter l'avatar) à chaque reconstruction du
  /// header.
  final Map<String, Future<File?>> _avatarFutures = {};

  /// Fichiers déjà résolus, conservés de façon synchrone : sert d'`initialData`
  /// au `FutureBuilder` pour un affichage immédiat aux reconstructions
  /// suivantes, sans repasser par l'état `waiting` (donc sans re-clignotement).
  final Map<String, File> _resolvedAvatars = {};

  DateTime? _lastLiveSummaryRefresh;

  Future<File?> _resolveAvatar(DriveAccountProfile account) {
    final url = account.photoUrlForDisplay(sizePx: _kAvatarCacheSizePx);
    if (url == null) return Future.value(null);
    return _avatarFutures.putIfAbsent(account.email, () async {
      final file = await _avatarCache.resolve(identity: account.email, url: url);
      if (file != null) {
        _resolvedAvatars[account.email] = file;
      }
      return file;
    });
  }

  @override
  void initState() {
    super.initState();
    _shouldScrollToDriveSection = widget.scrollToDriveSection;
    _initializeRepository();
    // Le repository publie la progression de téléchargement (durée de vie longue) :
    // on s'y abonne pour refléter une passe en cours dès l'ouverture de l'écran.
    widget.libraryRepository.addListener(_onLibraryRepositoryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Laisse la transition de navigation se terminer avant de lancer
      // les lectures DB pour éviter les à-coups à l'ouverture.
      unawaited(_startInitialLoad());
    });
    if (CueAudioService.isSupported) {
      unawaited(_loadCueDevices());
    }
    if (Platform.isWindows) {
      unawaited(_loadAppVersion());
    }
  }

  @override
  void dispose() {
    widget.libraryRepository.removeListener(_onLibraryRepositoryChanged);
    _avatarCache.dispose();
    super.dispose();
  }

  /// Le repository a notifié un changement (progression de téléchargement, session
  /// Drive…) : on reconstruit pour refléter la passe en cours. Le téléchargement
  /// lui-même vit dans le repository et continue indépendamment de cet écran.
  void _onLibraryRepositoryChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildSettingsBody();
    final syncPill = SyncStatusPill(
      syncController: widget.syncController,
      onTap: _onSyncPillTap,
    );
    final actions = <Widget>[
      ?_buildDriveRefreshAction(),
      syncPill,
    ];

    if (widget.isModal) {
      return AppModalShell(
        title: 'Paramètres',
        actions: actions,
        body: body,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres'), actions: actions),
      body: body,
    );
  }

}
