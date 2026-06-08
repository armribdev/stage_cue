import 'package:flutter/material.dart';
import '../../../../core/utils/sound_color_utils.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../utils/sound_type_ui.dart';
import '../providers/sampler_provider.dart';
import 'app_bottom_sheet.dart';
import 'sound_picker_actions.dart';

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
    return showAppBottomSheet<void>(
      context: context,
      child: MusicPickerSheet(
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
            allSounds
                .where(
                  (sound) =>
                      sound.matchesSoundType(SoundType.music),
                )
                .toList()
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

  PadItem? _padItemForSound(Sound sound) {
    return widget.notifier.findMusicPadForSound(sound.id);
  }

  bool _isOnAir(Sound sound) {
    final padItem = _padItemForSound(sound);
    if (padItem == null) return false;
    final current = widget.notifier.state.currentMusicPad;
    return current?.pad.id == padItem.pad.id && (current?.isPlaying ?? false);
  }

  bool _isQueued(Sound sound) {
    final padItem = _padItemForSound(sound);
    if (padItem == null) return false;
    return widget.notifier.state.musicQueuePadIds.contains(padItem.pad.id);
  }

  Future<void> _playNow(Sound sound) async {
    final padItem = await widget.notifier.playMusicBySoundId(sound.id);
    if (!mounted) return;
    if (padItem == null) return;
    Navigator.pop(context);
  }

  Future<void> _enqueue(Sound sound) async {
    final wasOnAir = _isOnAir(sound);
    final wasQueued = _isQueued(sound);

    final padItem = await widget.notifier.enqueueMusicBySoundId(sound.id);
    if (!mounted) return;
    if (padItem == null) return;

    if (wasOnAir || wasQueued) return;
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: TextField(
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Rechercher un son...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSounds;
    return AppBottomSheetShell(
      title: 'Sélectionner une musique',
      leadingIcon: SoundType.music.icon,
      header: _buildSearchField(),
      bodyBuilder: (context, scrollController) {
        if (_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (filtered.isEmpty) {
          return Center(
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
          );
        }
        return ListenableBuilder(
          listenable: widget.notifier,
          builder: (context, _) {
            return ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final sound = filtered[index];
                return _PickerTrackRow(
                  sound: sound,
                  onBoard: _isOnBoard(sound),
                  onAir: _isOnAir(sound),
                  queued: _isQueued(sound),
                  onPlayNow: () => _playNow(sound),
                  onEnqueue: () => _enqueue(sound),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PickerTrackRow extends StatelessWidget {
  final Sound sound;
  final bool onBoard;
  final bool onAir;
  final bool queued;
  final VoidCallback onPlayNow;
  final VoidCallback onEnqueue;

  const _PickerTrackRow({
    required this.sound,
    required this.onBoard,
    required this.onAir,
    required this.queued,
    required this.onPlayNow,
    required this.onEnqueue,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = sound.displayName ?? sound.title;
    final chipColor = soundEffectiveColor(sound, scheme);
    final subtitle = onAir
        ? 'À l\'antenne'
        : queued
        ? 'En file de passage'
        : (onBoard ? 'Pad sur la scène' : 'Lecture directe en régie');
    final canEnqueue = !onAir && !queued;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: onAir || queued
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: onAir || queued
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
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
                      color: onAir || queued
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      fontWeight: onAir || queued
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            SoundPickerActionButtons(
              goEnabled: !onAir,
              onGo: onPlayNow,
              secondaryEnabled: canEnqueue,
              onSecondary: onEnqueue,
              secondaryIcon: queued
                  ? Icons.check_rounded
                  : Icons.playlist_add_rounded,
              secondaryTooltip:
                  canEnqueue ? 'Mettre en file' : 'Déjà planifié',
            ),
          ],
        ),
      ),
    );
  }
}
