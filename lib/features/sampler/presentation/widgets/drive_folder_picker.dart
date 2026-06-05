import 'package:flutter/material.dart';

import '../../../../core/sync/drive_models.dart';
import '../../../../core/utils/indexed_folder_labels.dart';
import '../../data/repositories/library_repository.dart';
import 'app_form_dialog.dart';

/// Dossier Drive choisi par l'utilisateur dans le navigateur.
class DriveFolderSelection {
  final String folderId;
  final String name;
  final String displayPath;
  final String? sharedDriveId;

  const DriveFolderSelection({
    required this.folderId,
    required this.name,
    required this.displayPath,
    this.sharedDriveId,
  });

  /// Chemin relatif dans Drive (sans racine « Drive »).
  String get relativeDrivePath => relativeDrivePathFromBreadcrumb(displayPath);
}

enum _PickerEntryKind { myDrive, sharedDrive, folder }

class _PickerEntry {
  final _PickerEntryKind kind;
  final String id;
  final String name;
  final String? sharedDriveId;

  const _PickerEntry({
    required this.kind,
    required this.id,
    required this.name,
    this.sharedDriveId,
  });

  factory _PickerEntry.myDrive() {
    return const _PickerEntry(
      kind: _PickerEntryKind.myDrive,
      id: 'root',
      name: 'Mon Drive',
    );
  }

  factory _PickerEntry.sharedDrive(DriveSharedDrive drive) {
    return _PickerEntry(
      kind: _PickerEntryKind.sharedDrive,
      id: drive.id,
      name: drive.name,
      sharedDriveId: drive.id,
    );
  }

  factory _PickerEntry.folder(
    DriveFile folder, {
    String? sharedDriveId,
  }) {
    return _PickerEntry(
      kind: _PickerEntryKind.folder,
      id: folder.id,
      name: folder.name,
      sharedDriveId: sharedDriveId,
    );
  }
}

class _BreadcrumbEntry {
  final String id;
  final String name;
  final String? sharedDriveId;
  final bool isHome;

  const _BreadcrumbEntry({
    required this.id,
    required this.name,
    this.sharedDriveId,
    this.isHome = false,
  });
}

/// Navigateur de dossiers Google Drive (Mon Drive, drives partagés, partagés avec moi).
class DriveFolderPicker extends StatefulWidget {
  const DriveFolderPicker({
    super.key,
    required this.repository,
  });

  final LibraryRepository repository;

  static Future<DriveFolderSelection?> show(
    BuildContext context, {
    required LibraryRepository repository,
  }) {
    return showDialog<DriveFolderSelection>(
      context: context,
      builder: (dialogContext) {
        return DriveFolderPicker(repository: repository);
      },
    );
  }

  @override
  State<DriveFolderPicker> createState() => _DriveFolderPickerState();
}

class _DriveFolderPickerState extends State<DriveFolderPicker> {
  static const _homeId = '__home__';

  final List<_BreadcrumbEntry> _breadcrumb = [
    const _BreadcrumbEntry(id: _homeId, name: 'Drive', isHome: true),
  ];

  List<_PickerEntry> _homeEntries = [];
  List<DriveFile> _folders = [];
  bool _isLoading = true;
  String? _error;

  bool get _isHome => _breadcrumb.last.isHome;

  _BreadcrumbEntry get _current => _breadcrumb.last;

  String? get _currentSharedDriveId => _current.sharedDriveId;

  String get _displayPath => _breadcrumb
      .where((entry) => !entry.isHome)
      .map((entry) => entry.name)
      .join(' / ');

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final connected = await widget.repository.ensureDriveConnected();
    if (!mounted) {
      return;
    }
    if (!connected) {
      Navigator.of(context).pop();
      return;
    }
    await _loadContent();
  }

  Future<void> _loadContent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_isHome) {
        final sharedDrives = await widget.repository.listDriveSharedDrives();
        final sharedWithMe =
            await widget.repository.listDriveSharedWithMeFolders();
        if (!mounted) {
          return;
        }
        setState(() {
          _homeEntries = [
            _PickerEntry.myDrive(),
            ...sharedDrives.map(_PickerEntry.sharedDrive),
            ...sharedWithMe.map((folder) => _PickerEntry.folder(folder)),
          ];
          _folders = [];
          _isLoading = false;
        });
        return;
      }

      final folders = await widget.repository.listDriveChildFolders(
        _current.id,
        sharedDriveId: _currentSharedDriveId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _homeEntries = [];
        _folders = folders;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _enterLocation({
    required String id,
    required String name,
    String? sharedDriveId,
  }) {
    setState(() {
      _breadcrumb.add(
        _BreadcrumbEntry(
          id: id,
          name: name,
          sharedDriveId: sharedDriveId,
        ),
      );
    });
    _loadContent();
  }

  void _openEntry(_PickerEntry entry) {
    switch (entry.kind) {
      case _PickerEntryKind.myDrive:
        _enterLocation(id: entry.id, name: entry.name);
      case _PickerEntryKind.sharedDrive:
        _enterLocation(
          id: entry.id,
          name: entry.name,
          sharedDriveId: entry.sharedDriveId,
        );
      case _PickerEntryKind.folder:
        _enterLocation(
          id: entry.id,
          name: entry.name,
          sharedDriveId: entry.sharedDriveId,
        );
    }
  }

  void _openFolder(DriveFile folder) {
    _enterLocation(
      id: folder.id,
      name: folder.name,
      sharedDriveId: _currentSharedDriveId,
    );
  }

  void _goUp() {
    if (_breadcrumb.length <= 1) {
      return;
    }
    setState(() {
      _breadcrumb.removeLast();
    });
    _loadContent();
  }

  void _selectCurrentFolder() {
    if (_isHome) {
      return;
    }

    final current = _current;
    Navigator.of(context).pop(
      DriveFolderSelection(
        folderId: current.id,
        name: current.name,
        displayPath: _displayPath,
        sharedDriveId: current.sharedDriveId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGoUp = _breadcrumb.length > 1;
    final canSelect = !_isHome && !_isLoading && _error == null;

    return AppFormDialog(
      title: 'Choisir un dossier Drive',
      width: 520,
      onClose: () => Navigator.of(context).pop(),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Dossier parent',
                onPressed: canGoUp ? _goUp : null,
                icon: const Icon(Icons.arrow_upward),
              ),
              Expanded(
                child: Text(
                  _isHome ? 'Drive' : _displayPath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: _buildList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: canSelect ? _selectCurrentFolder : null,
          icon: const Icon(Icons.check),
          label: const Text('Sélectionner ce dossier'),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Impossible de lister Drive :\n$_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_isHome) {
      return _buildHomeList();
    }

    if (_folders.isEmpty) {
      return Center(
        child: Text(
          'Aucun sous-dossier.\n'
          'Utilisez « Sélectionner ce dossier » pour indexer « ${_current.name} ».',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return ListView.separated(
      itemCount: _folders.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final folder = _folders[index];
        return ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(folder.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openFolder(folder),
        );
      },
    );
  }

  Widget _buildHomeList() {
    if (_homeEntries.isEmpty) {
      return Center(
        child: Text(
          'Aucun emplacement Drive accessible.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    final children = <Widget>[];
    var sharedDriveHeaderShown = false;
    var sharedWithMeHeaderShown = false;

    for (final entry in _homeEntries) {
      if (entry.kind == _PickerEntryKind.sharedDrive && !sharedDriveHeaderShown) {
        sharedDriveHeaderShown = true;
        children.add(_sectionHeader('Drives partagés'));
      }
      if (entry.kind == _PickerEntryKind.folder && !sharedWithMeHeaderShown) {
        sharedWithMeHeaderShown = true;
        children.add(_sectionHeader('Partagés avec moi'));
      }

      children.add(
        ListTile(
          leading: Icon(_iconForEntry(entry)),
          title: Text(entry.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openEntry(entry),
        ),
      );
    }

    return ListView.separated(
      itemCount: children.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => children[index],
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  IconData _iconForEntry(_PickerEntry entry) {
    return switch (entry.kind) {
      _PickerEntryKind.myDrive => Icons.person_outline,
      _PickerEntryKind.sharedDrive => Icons.groups_outlined,
      _PickerEntryKind.folder => Icons.folder_shared_outlined,
    };
  }
}
