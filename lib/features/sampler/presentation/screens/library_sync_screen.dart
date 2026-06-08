import 'package:flutter/material.dart';

import '../../../../core/settings/app_preferences.dart';
import '../../../../core/sync/google_oauth_config.dart';
import '../../../../core/utils/copyable_snackbar.dart';
import '../../../../core/sync/google_oauth_setup_dialog.dart';
import '../../data/repositories/library_repository.dart';
import '../../domain/entities/library.dart';
import '../providers/sync_controller.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/app_modal.dart';

/// Écran de gestion de la synchronisation Drive : connexion d'une bibliothèque
/// portable, état de synchro, push/pull manuels et résolution de conflit.
///
/// Reçoit le [LibraryRepository] partagé d'AppServices : la session Drive
/// connectée ici est donc la même que celle utilisée par la lecture (download
/// à la demande des sons).
class LibrarySyncScreen extends StatefulWidget {
  final LibraryRepository libraryRepository;
  final SyncController syncController;
  final AppPreferences? appPreferences;
  final bool isModal;

  const LibrarySyncScreen({
    super.key,
    required this.libraryRepository,
    required this.syncController,
    this.appPreferences,
    this.isModal = false,
  });

  /// Page plein écran sur téléphone, modale sur tablette et desktop.
  static Future<void> open(
    BuildContext context, {
    required LibraryRepository libraryRepository,
    required SyncController syncController,
    AppPreferences? appPreferences,
  }) {
    return openAdaptiveScreen(
      context: context,
      builder: ({required isModal}) => LibrarySyncScreen(
        libraryRepository: libraryRepository,
        syncController: syncController,
        appPreferences: appPreferences,
        isModal: isModal,
      ),
    );
  }

  @override
  State<LibrarySyncScreen> createState() => _LibrarySyncScreenState();
}

class _LibrarySyncScreenState extends State<LibrarySyncScreen> {
  late final LibraryRepository _repository;
  late final SyncController _syncController;

  List<Library> _libraries = const [];
  bool _isLoading = true;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.libraryRepository;
    // Contrôleur partagé (AppServices) : l'état de sync reste cohérent avec la
    // synchro automatique. On ne le crée ni ne le dispose ici.
    _syncController = widget.syncController;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Reconnexion silencieuse pour restaurer une session Drive existante.
    await _repository.reconnectSilently();
    await _loadLibraries();
  }

  Future<void> _loadLibraries() async {
    final libraries = await _repository.getLibraries();
    if (!mounted) return;
    setState(() {
      _libraries = libraries;
      _isLoading = false;
    });
  }

  Future<void> _connect() async {
    if (!await ensureGoogleOAuthConfigured(context)) {
      return;
    }
    if (!mounted) {
      return;
    }

    final name = await _promptLibraryName();
    if (name == null || name.trim().isEmpty) return;

    setState(() => _isBusy = true);
    try {
      final library = await _repository.connectAndCreateLibrary(
        name: name.trim(),
        autoDownload: widget.appPreferences?.autoDownloadDriveByDefault ?? false,
      );
      if (!mounted) return;
      if (library == null) {
        _snack('Connexion annulée');
      } else {
        _snack('Bibliothèque « ${library.name} » connectée');
        await _loadLibraries();
      }
    } on GoogleOAuthNotConfiguredException catch (e) {
      if (mounted) _snack(e.message, copyable: true);
    } catch (e) {
      if (mounted) _snack('Erreur de connexion : $e', copyable: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _syncNow(Library library) async {
    await _syncController.syncNow(library);
    await _loadLibraries();
    if (_syncController.state.status == SyncStatus.conflict && mounted) {
      await _showConflictDialog(library);
    }
  }

  Future<void> _pull(Library library) async {
    await _syncController.pullForLaunch(library);
    await _loadLibraries();
  }

  Future<void> _disconnect() async {
    setState(() => _isBusy = true);
    try {
      await _repository.disconnect();
      if (mounted) _snack('Déconnecté de Drive');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _showConflictDialog(Library library) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conflit de synchronisation'),
        content: const Text(
          'Une version plus récente existe sur Drive. Quelle version garder ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'remote'),
            child: const Text('Prendre Drive'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'local'),
            child: const Text('Garder local'),
          ),
        ],
      ),
    );

    if (choice == 'local') {
      await _syncController.keepLocal(library);
    } else if (choice == 'remote') {
      await _syncController.takeRemote(library);
    }
    if (mounted) await _loadLibraries();
  }

  Future<String?> _promptLibraryName() {
    final controller = TextEditingController(text: 'Stage Cue');
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AppFormDialog(
        title: 'Nouvelle bibliothèque Drive',
        width: 400,
        onClose: () => Navigator.of(dialogContext).pop(),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom de la bibliothèque',
            hintText: 'Ex. Spectacle 2026',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Connecter'),
          ),
        ],
      ),
    );
  }

  void _snack(String message, {bool copyable = false}) {
    if (copyable) {
      showCopyableSnackBar(context, message);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ConnectionCard(
          email: _repository.connectedAccountEmail,
          isBusy: _isBusy,
          onConnect: _connect,
          onDisconnect: _repository.isConnected ? _disconnect : null,
        ),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: _syncController,
          builder: (context, _) =>
              _SyncStatusBanner(state: _syncController.state),
        ),
        const SizedBox(height: 8),
        if (_libraries.isEmpty)
          const _EmptyLibrariesHint()
        else
          ..._libraries.map(
            (library) => _LibraryTile(
              library: library,
              enabled: !_isBusy,
              onSync: () => _syncNow(library),
              onPull: () => _pull(library),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (widget.isModal) {
      return AppModalShell(title: 'Bibliothèque Drive', body: body);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Bibliothèque Drive')),
      body: body,
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final String? email;
  final bool isBusy;
  final VoidCallback onConnect;
  final VoidCallback? onDisconnect;

  const _ConnectionCard({
    required this.email,
    required this.isBusy,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final connected = email != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connected ? Icons.cloud_done : Icons.cloud_off,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    connected ? 'Connecté : $email' : 'Non connecté à Drive',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: isBusy ? null : onConnect,
                  icon: const Icon(Icons.add_to_drive),
                  label: const Text('Connecter une bibliothèque'),
                ),
                if (onDisconnect != null)
                  OutlinedButton(
                    onPressed: isBusy ? null : onDisconnect,
                    child: const Text('Déconnecter'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncStatusBanner extends StatelessWidget {
  final SyncState state;

  const _SyncStatusBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (state.status) {
      SyncStatus.idle => (Icons.cloud_queue, 'Prêt', Colors.grey),
      SyncStatus.syncing => (Icons.sync, 'Synchronisation…', Colors.blue),
      SyncStatus.synced => (Icons.check_circle, 'Synchronisé', Colors.green),
      SyncStatus.offline => (Icons.cloud_off, 'Hors-ligne', Colors.orange),
      SyncStatus.conflict => (Icons.warning, 'Conflit', Colors.deepOrange),
      SyncStatus.error => (Icons.error, 'Erreur', Colors.red),
    };

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color)),
        if (state.message != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.message!,
              style: const TextStyle(fontSize: 12, color: Colors.red),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _LibraryTile extends StatelessWidget {
  final Library library;
  final bool enabled;
  final VoidCallback onSync;
  final VoidCallback onPull;

  const _LibraryTile({
    required this.library,
    required this.enabled,
    required this.onSync,
    required this.onPull,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lastSync = library.lastSyncedAt;
    final subtitle = lastSync != null
        ? 'Révision ${library.lastSyncedRevision} · ${_formatDate(lastSync)}'
        : 'Jamais synchronisé';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.library_music, color: scheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    library.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.cloud_download),
              tooltip: 'Récupérer depuis Drive',
              onPressed: enabled ? onPull : null,
            ),
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              tooltip: 'Synchroniser maintenant',
              onPressed: enabled ? onSync : null,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _EmptyLibrariesHint extends StatelessWidget {
  const _EmptyLibrariesHint();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.cloud_outlined, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 12),
            Text(
              'Aucune bibliothèque Drive',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              'Connecte une bibliothèque pour synchroniser tes sons entre appareils. '
              'Ajoute des dossiers Drive depuis Paramètres → Éléments indexés.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
