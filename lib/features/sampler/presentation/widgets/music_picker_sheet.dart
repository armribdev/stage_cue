import 'package:flutter/material.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../utils/sound_type_ui.dart';
import '../providers/sampler_provider.dart';
import 'music_preview_panel.dart';

/// Feuille modale pour choisir une musique à lancer ou mettre en file.
class MusicPickerSheet extends StatefulWidget {
  final SoundRepository repository;
  final SamplerNotifier notifier;

  const MusicPickerSheet({
    super.key,
    required this.repository,
    required this.notifier,
  });

  static Future<void> show(
    BuildContext context, {
    required SoundRepository repository,
    required SamplerNotifier notifier,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surfaceContainerLow,
      builder: (context) => MusicPickerSheet(
        repository: repository,
        notifier: notifier,
      ),
    );
  }

  @override
  State<MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends State<MusicPickerSheet> {
  List<Sound> _musicSounds = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadMusic();
  }

  Future<void> _loadMusic() async {
    try {
      final allSounds = await widget.repository.getAllSounds();
      if (!mounted) return;
      setState(() {
        _musicSounds =
            allSounds.where((sound) => sound.type == SoundType.music).toList()
              ..sort(
                (a, b) => (a.displayName ?? a.title).compareTo(
                  b.displayName ?? b.title,
                ),
              );
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<Sound> get _filteredSounds {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _musicSounds;
    return _musicSounds.where((sound) {
      final title = (sound.displayName ?? sound.title).toLowerCase();
      return title.contains(query);
    }).toList();
  }

  bool _isOnBoard(Sound sound) {
    return widget.notifier.state.pads.any(
      (padItem) => padItem.pad.sounds.any((s) => s.id == sound.id),
    );
  }

  bool _isQueued(Sound sound) {
    final padItem = _padItemForSound(sound);
    if (padItem == null) return false;
    return widget.notifier.state.musicQueuePadIds.contains(padItem.pad.id);
  }

  Future<void> _playNow(Sound sound) async {
    final padItem = await widget.notifier.playMusicBySoundId(sound.id);
    if (!mounted) return;
    if (padItem == null) {
      _showPlaybackError();
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _enqueue(Sound sound) async {
    final padItem = await widget.notifier.enqueueMusicBySoundId(sound.id);
    if (!mounted) return;
    if (padItem == null) {
      _showPlaybackError();
      return;
    }
    Navigator.pop(context);
  }

  void _showPlaybackError() {
    final message =
        widget.notifier.state.error ??
        'Fichier audio introuvable ou indisponible hors-ligne.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  PadItem? _padItemForSound(Sound sound) {
    for (final padItem in widget.notifier.state.pads) {
      if (padItem.pad.sounds.any((s) => s.id == sound.id)) {
        return padItem;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final filtered = _filteredSounds;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Row(
                  children: [
                    Icon(SoundType.music.icon, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Sélectionner une musique',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Rechercher…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _musicSounds.isEmpty
                                ? 'Aucune musique dans la bibliothèque'
                                : 'Aucun résultat',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final sound = filtered[index];
                          return _PickerTrackRow(
                            sound: sound,
                            onBoard: _isOnBoard(sound),
                            queued: _isQueued(sound),
                            onPlayNow: () => _playNow(sound),
                            onEnqueue: () => _enqueue(sound),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PickerTrackRow extends StatelessWidget {
  final Sound sound;
  final bool onBoard;
  final bool queued;
  final VoidCallback onPlayNow;
  final VoidCallback onEnqueue;

  const _PickerTrackRow({
    required this.sound,
    required this.onBoard,
    required this.queued,
    required this.onPlayNow,
    required this.onEnqueue,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = sound.displayName ?? sound.title;
    final chipColor = sound.colorValue != null
        ? Color(sound.colorValue!)
        : musicChipColor(sound.id, scheme);
    final subtitle = queued
        ? 'En file de passage'
        : (onBoard ? 'Pad sur la scène' : 'Hors scène — sera ajoutée');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: chipColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Icon(
                SoundType.music.icon,
                color: chipColor.computeLuminance() > 0.55
                    ? Colors.black87
                    : Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: onPlayNow,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('GO'),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Mettre en file',
              onPressed: onEnqueue,
              icon: const Icon(Icons.playlist_add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
