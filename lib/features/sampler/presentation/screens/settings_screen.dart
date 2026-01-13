import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../../core/database/database.dart' as db;
import '../../../../core/database/sounds.dart' as db_sounds;
import '../../data/repositories/sound_repository.dart';
import '../../data/datasources/local_sound_datasource.dart';
import '../../data/models/indexing_progress.dart';
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

  @override
  void initState() {
    super.initState();
    _initializeRepository();
    _loadDatabaseInfo();
  }

  void _initializeRepository() {
    final soundDataSource = LocalSoundDataSource(widget.database);
    final watchedPathDataSource = LocalWatchedPathDataSource(widget.database);
    _repository = SoundRepository(soundDataSource, watchedPathDataSource);
  }

  Future<void> _loadDatabaseInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Charger tous les dossiers/fichiers surveillés
      final watchedPaths = await widget.database.select(widget.database.watchedPaths).get();
      
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

  Future<void> _addDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    
    if (selectedDirectory != null) {
      try {
        final directory = Directory(selectedDirectory);
        if (await directory.exists()) {
          // Vérifier si le dossier n'est pas déjà surveillé
          final existing = await (widget.database.select(widget.database.watchedPaths)
            ..where((w) => w.path.equals(selectedDirectory)))
            .get();
          
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
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'wma', 'opus'],
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
            final existing = await (widget.database.select(widget.database.watchedPaths)
              ..where((w) => w.path.equals(filePath)))
              .get();
            
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
      appBar: AppBar(
        title: const Text('Paramètres'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
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
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'État de la base de données',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                            const Divider(),
                            _buildInfoRow('Nombre total de sons', '${_sounds.length}'),
                            const SizedBox(height: 8),
                            _buildInfoRow('Taille de la base de données', _formatBytes(_dbSize)),
                            const SizedBox(height: 8),
                            _buildInfoRow('Chemin de la base de données', _dbPath, isPath: true),
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
                              tooltip: 'Ajouter des fichiers audio (sélection multiple)',
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
                              final progress = _indexingProgress[watchedPath.path];
                              final isIndexing = progress != null && !progress.isComplete;
                              
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  children: [
                                    ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor:
                                            Theme.of(context).colorScheme.primaryContainer,
                                        child: Icon(
                                          watchedPath.isDirectory
                                              ? Icons.folder
                                              : Icons.audio_file,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                      title: Text(
                                        p.basename(watchedPath.path),
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(
                                            watchedPath.path,
                                            style: const TextStyle(fontSize: 11),
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
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () => _removeWatchedPath(watchedPath),
                                        tooltip: 'Retirer',
                                      ),
                                      isThreeLine: true,
                                    ),
                                    // Barre de progression pour les dossiers en cours d'indexation
                                    if (watchedPath.isDirectory && progress != null)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (isIndexing)
                                              LinearProgressIndicator(
                                                value: progress.progress,
                                                backgroundColor: Colors.grey[300],
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  Theme.of(context).colorScheme.primary,
                                                ),
                                              )
                                            else if (progress.error != null)
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.red[50],
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.error_outline, 
                                                      color: Colors.red[700], 
                                                      size: 16,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        'Erreur: ${progress.error}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.red[700],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: progress.total == 0 
                                                      ? Colors.orange[50] 
                                                      : Colors.green[50],
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      progress.total == 0 
                                                          ? Icons.warning_amber_rounded
                                                          : Icons.check_circle, 
                                                      color: progress.total == 0 
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
                                                          color: progress.total == 0 
                                                              ? Colors.orange[700] 
                                                              : Colors.green[700],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (isIndexing && progress.total > 0)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4),
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
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.primaryContainer,
                                    child: Icon(
                                      Icons.music_note,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  title: Text(sound.title),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        'Chemin: ${sound.filePath}',
                                        style: const TextStyle(fontSize: 11),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text('Type: ${_getSoundTypeName(sound.type)}'),
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
                                  isThreeLine: true,
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

