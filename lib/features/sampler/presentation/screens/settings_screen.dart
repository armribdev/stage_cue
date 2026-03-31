import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../../core/database/database.dart' as db;
import '../../../../core/database/sounds.dart' as db_sounds;
import '../../data/repositories/sound_repository.dart';
import '../../data/datasources/local_sound_datasource.dart';
import '../../data/datasources/local_tag_datasource.dart';
import '../../data/models/indexing_progress.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../../domain/entities/watched_path.dart' as domain;

/// Écran des paramètres
class SettingsScreen extends StatefulWidget {
  final db.AppDatabase database;

  const SettingsScreen({super.key, required this.database});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<db.WatchedPath> _watchedPaths = [];
  List<db.Sound> _sounds = [];
  bool _isLoading = true;
  String _dbPath = '';
  int _dbSize = 0;
  late final SoundRepository _repository;
  // Suivi de la progression d'indexation par chemin
  final Map<String, IndexingProgress> _indexingProgress = {};
  List<TagCategoryWithTags> _tagCatalog = [];
  bool _isTagCatalogLoading = true;
  final Map<int, List<TagItem>> _soundTags = {};

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
    unawaited(_loadTagCatalog());
    unawaited(_loadDatabaseInfo());
  }

  void _initializeRepository() {
    final soundDataSource = LocalSoundDataSource(widget.database);
    final watchedPathDataSource = LocalWatchedPathDataSource(widget.database);
    final soundBoardDataSource = LocalSoundBoardDataSource(widget.database);
    final tagDataSource = LocalTagDataSource(widget.database);
    _repository = SoundRepository(
      soundDataSource,
      watchedPathDataSource,
      soundBoardDataSource,
      tagDataSource,
    );
  }

  Future<void> _loadDatabaseInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Charger tous les dossiers/fichiers surveillés
      final watchedPaths = await widget.database
          .select(widget.database.watchedPaths)
          .get();

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
        _sounds = sounds;
        _dbPath = dbFile.path;
        _dbSize = dbSize;
        _isLoading = false;
      });
      unawaited(_loadSoundTags());
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du chargement: $e')),
        );
      }
    }
  }

  Future<void> _loadTagCatalog() async {
    setState(() {
      _isTagCatalogLoading = true;
    });
    final catalog = await _repository.getTagCatalog();
    if (!mounted) {
      return;
    }
    setState(() {
      _tagCatalog = catalog;
      _isTagCatalogLoading = false;
    });
  }

  Future<void> _loadSoundTags() async {
    if (_sounds.isEmpty) {
      setState(() {
        _soundTags.clear();
      });
      return;
    }
    final entries = await Future.wait(
      _sounds.map((sound) async {
        final tags = await _repository.getTagsForSound(sound.id);
        return MapEntry(sound.id, tags);
      }),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _soundTags
        ..clear()
        ..addEntries(entries);
    });
  }

  Future<void> _editSoundTags(db.Sound sound) async {
    if (_isTagCatalogLoading) {
      return;
    }
    final initialTags = _soundTags[sound.id] ?? [];
    final selected = initialTags.map((t) => t.id).toSet();
    final updated = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (dialogContext) {
        return DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          initialChildSize: 0.6,
          builder: (context, scrollController) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: StatefulBuilder(
                        builder: (context, setDialogState) {
                          if (_tagCatalog.isEmpty) {
                            return const Center(
                              child: Text('Aucun tag disponible'),
                            );
                          }
                          return SingleChildScrollView(
                            controller: scrollController,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final category in _tagCatalog) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8.0,
                                      bottom: 4,
                                    ),
                                    child: Text(
                                      category.category.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 0,
                                    children: [
                                      for (final tag in category.tags)
                                        FilterChip(
                                          label: Text(tag.name),
                                          selected: selected.contains(tag.id),
                                          backgroundColor: Color(
                                            category.category.color,
                                          ).withAlpha(24),
                                          selectedColor: Color(
                                            category.category.color,
                                          ).withAlpha(64),
                                          checkmarkColor: Color(
                                            category.category.color,
                                          ),
                                          side: BorderSide(
                                            color: Color(
                                              category.category.color,
                                            ),
                                          ),
                                          onSelected: (value) {
                                            setDialogState(() {
                                              if (value) {
                                                selected.add(tag.id);
                                              } else {
                                                selected.remove(tag.id);
                                              }
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Annuler'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(selected),
                          child: const Text('Enregistrer'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (updated == null) {
      return;
    }
    await _repository.setTagsForSound(sound.id, updated.toList());
    await _loadSoundTags();
  }

  Color? _getCategoryColor(int categoryId) {
    for (final category in _tagCatalog) {
      if (category.category.id == categoryId) {
        return Color(category.category.color);
      }
    }
    return null;
  }

  Widget _buildTagChip(TagItem tag) {
    final color = _getCategoryColor(tag.categoryId);
    return Chip(
      label: Text(tag.name, style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      backgroundColor: color?.withAlpha(24),
      side: color == null ? null : BorderSide(color: color),
    );
  }

  Future<void> _addDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      try {
        final directory = Directory(selectedDirectory);
        if (await directory.exists()) {
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
            addedAt: DateTime.now(),
          );

          // Ajouter le dossier avec suivi de progression
          await _repository.addWatchedPath(
            watchedPath,
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _indexingProgress[selectedDirectory] = progress;
                });
              }
            },
          );

          // Nettoyer la progression après un court délai
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                _indexingProgress.remove(selectedDirectory);
              });
            }
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Dossier ajouté et indexé'),
                duration: Duration(seconds: 2),
              ),
            );
          }

          await _loadDatabaseInfo();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur lors de l\'ajout du dossier: $e')),
          );
        }
      }
    }
  }

  Future<void> _addFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3',
        'wav',
        'm4a',
        'aac',
        'ogg',
        'flac',
        'wma',
        'opus',
      ],
      allowMultiple: true, // Permettre la sélection multiple
    );

    if (result != null && result.files.isNotEmpty) {
      try {
        int addedCount = 0;
        int skippedCount = 0;

        for (final pickedFile in result.files) {
          if (pickedFile.path == null) continue;

          final filePath = pickedFile.path!;
          final file = File(filePath);

          if (await file.exists()) {
            // Vérifier si le fichier n'est pas déjà surveillé
            final existing = await (widget.database.select(
              widget.database.watchedPaths,
            )..where((w) => w.path.equals(filePath))).get();

            if (existing.isNotEmpty) {
              skippedCount++;
              continue;
            }

            // Ajouter le chemin surveillé
            final watchedPath = domain.WatchedPath(
              id: 0, // Sera généré par la base de données
              path: filePath,
              isDirectory: false,
              addedAt: DateTime.now(),
            );

            await _repository.addWatchedPath(watchedPath);
            addedCount++;
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                addedCount > 0
                    ? '$addedCount fichier(s) indexé(s)${skippedCount > 0 ? ", $skippedCount déjà présent(s)" : ""}'
                    : 'Aucun nouveau fichier ajouté',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }

        await _loadDatabaseInfo();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur lors de l\'ajout des fichiers: $e')),
          );
        }
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

  String _getSoundTypeName(db_sounds.SoundType type) {
    switch (type) {
      case db_sounds.SoundType.soundEffect:
        return 'Bruitage';
      case db_sounds.SoundType.music:
        return 'Musique';
      case db_sounds.SoundType.ambiance:
        return 'Son d\'ambiance';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
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
                                icon: const Icon(Icons.folder),
                                tooltip: 'Ajouter un dossier',
                                onPressed: _addDirectory,
                              ),
                              IconButton(
                                icon: const Icon(Icons.audio_file),
                                tooltip:
                                    'Ajouter des fichiers audio (sélection multiple)',
                                onPressed: _addFile,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _watchedPaths.isEmpty
                          ? Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.folder_off,
                                        size: 48,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Aucun dossier ou fichier surveillé',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Ajoutez un dossier ou un fichier pour commencer',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _watchedPaths.length,
                              itemBuilder: (context, index) {
                                final watchedPath = _watchedPaths[index];
                                final progress =
                                    _indexingProgress[watchedPath.path];
                                final isIndexing =
                                    progress != null && !progress.isComplete;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Column(
                                    children: [
                                      ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer,
                                          child: Icon(
                                            watchedPath.isDirectory
                                                ? Icons.folder
                                                : Icons.audio_file,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                        title: Text(
                                          p.basename(watchedPath.path),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 4),
                                            Text(
                                              watchedPath.path,
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              watchedPath.isDirectory
                                                  ? 'Dossier'
                                                  : 'Fichier',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () =>
                                              _removeWatchedPath(watchedPath),
                                          tooltip: 'Retirer',
                                        ),
                                        isThreeLine: true,
                                      ),
                                      // Barre de progression pour les dossiers en cours d'indexation
                                      if (watchedPath.isDirectory &&
                                          progress != null)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            0,
                                            16,
                                            16,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (isIndexing)
                                                LinearProgressIndicator(
                                                  value: progress.progress,
                                                  backgroundColor:
                                                      Colors.grey[300],
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.primary,
                                                      ),
                                                )
                                              else if (progress.error != null)
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red[50],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.error_outline,
                                                        color: Colors.red[700],
                                                        size: 16,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          'Erreur: ${progress.error}',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color:
                                                                Colors.red[700],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              else
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: progress.total == 0
                                                        ? Colors.orange[50]
                                                        : Colors.green[50],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        progress.total == 0
                                                            ? Icons
                                                                  .warning_amber_rounded
                                                            : Icons
                                                                  .check_circle,
                                                        color:
                                                            progress.total == 0
                                                            ? Colors.orange[700]
                                                            : Colors.green[700],
                                                        size: 16,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          progress.total == 0
                                                              ? 'Aucun fichier audio trouvé dans ce dossier'
                                                              : 'Indexation terminée: ${progress.current}/${progress.total} fichier(s)',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color:
                                                                progress.total ==
                                                                    0
                                                                ? Colors
                                                                      .orange[700]
                                                                : Colors
                                                                      .green[700],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (isIndexing &&
                                                  progress.total > 0)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4,
                                                      ),
                                                  child: Text(
                                                    'Indexation en cours: ${progress.current}/${progress.total} fichier(s)',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                      const SizedBox(height: 16),
                      Text(
                        'Sons indexés (${_sounds.length})',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      _sounds.isEmpty
                          ? Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.music_off,
                                        size: 48,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Aucun son enregistré',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _sounds.length,
                              itemBuilder: (context, index) {
                                final sound = _sounds[index];
                                final tags = _soundTags[sound.id] ?? [];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer,
                                      child: Icon(
                                        Icons.music_note,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                    title: Text(sound.title),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text(
                                          'Chemin: ${sound.filePath}',
                                          style: const TextStyle(fontSize: 11),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (tags.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: -6,
                                            children: [
                                              for (final tag in tags)
                                                _buildTagChip(tag),
                                            ],
                                          ),
                                        ],
                                        const SizedBox(height: 2),
                                        Text(
                                          'Type: ${_getSoundTypeName(sound.type)}',
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Créé le: ${sound.createdAt.toString().substring(0, 19)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.label),
                                      tooltip: 'Gérer les tags',
                                      onPressed: _isTagCatalogLoading
                                          ? null
                                          : () => _editSoundTags(sound),
                                    ),
                                    isThreeLine: true,
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ),
      ),
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

  Widget _listHeader(Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _bar(color, width: 170, height: 20),
        Row(
          children: [
            _bar(color, width: 28, height: 28),
            const SizedBox(width: 8),
            _bar(color, width: 28, height: 28),
          ],
        ),
      ],
    );
  }

  Widget _itemCard(Color color) {
    return Card(
      child: ListTile(
        isThreeLine: true,
        leading: CircleAvatar(backgroundColor: color),
        title: _bar(color, width: 180),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(color),
              const SizedBox(height: 6),
              _bar(color, width: 120),
            ],
          ),
        ),
        trailing: _bar(color, width: 20, height: 20),
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
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _databaseCard(color),
            const SizedBox(height: 16),
            _listHeader(color),
            const SizedBox(height: 8),
            _itemCard(color),
            const SizedBox(height: 8),
            _itemCard(color),
            const SizedBox(height: 16),
            _bar(color, width: 160, height: 20),
            const SizedBox(height: 8),
            _itemCard(color),
          ],
        );
      },
    );
  }
}
