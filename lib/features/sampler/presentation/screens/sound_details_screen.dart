import 'package:flutter/material.dart';
import '../../domain/entities/sound.dart';
import '../providers/sampler_provider.dart';

/// Écran de détails d'un son
class SoundDetailScreen extends StatefulWidget {
  final SoundItem soundItem;
  final SamplerNotifier notifier;

  const SoundDetailScreen({
    super.key,
    required this.soundItem,
    required this.notifier,
  });

  @override
  State<SoundDetailScreen> createState() => _SoundDetailScreenState();
}

class _SoundDetailScreenState extends State<SoundDetailScreen> {
  late Color? _selectedColor;
  late double _volume;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.soundItem.buttonColor;
    _volume = widget.soundItem.volume.clamp(0.0, 1.0);
  }

  String _getSoundTypeLabel(SoundType type) {
    switch (type) {
      case SoundType.soundEffect:
        return 'Bruitage';
      case SoundType.music:
        return 'Musique';
      case SoundType.ambiance:
        return 'Son d\'ambiance';
    }
  }

  void _updateColor(Color? color) {
    setState(() {
      _selectedColor = color;
    });
    widget.notifier.updateSoundItemSettings(
      widget.soundItem,
      buttonColor: color,
      updateColor: true,
    );
  }

  void _updateVolume(double value) {
    final clamped = value.clamp(0.0, 1.0);
    setState(() {
      _volume = clamped;
    });
    widget.notifier.updateSoundItemSettings(
      widget.soundItem,
      volume: clamped,
    );
    widget.soundItem.player.setVolume(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final sound = widget.soundItem.sound;
    final colorChoices = <Color>[
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.brown,
      Colors.grey,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détails du son'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sound.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      context,
                      'Type',
                      _getSoundTypeLabel(sound.type),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      context,
                      'Chemin',
                      sound.filePath,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      context,
                      'Date de création',
                      _formatDate(sound.createdAt),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      context,
                      'ID',
                      sound.id.toString(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Réglages du pad',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Couleur du bouton',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Par défaut'),
                          selected: _selectedColor == null,
                          onSelected: (_) => _updateColor(null),
                        ),
                        for (final color in colorChoices)
                          ChoiceChip(
                            label: const Text(''),
                            selected: _selectedColor == color,
                            onSelected: (_) => _updateColor(color),
                            avatar: CircleAvatar(
                              backgroundColor: color,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Volume',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text('${(_volume * 100).round()}%'),
                      ],
                    ),
                    Slider(
                      value: _volume,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      label: '${(_volume * 100).round()}%',
                      onChanged: _updateVolume,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

