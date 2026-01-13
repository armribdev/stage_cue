import 'package:flutter/material.dart';
import '../../domain/entities/sound.dart';

/// Écran de détails d'un son
class SoundDetailScreen extends StatelessWidget {
  final Sound sound;

  const SoundDetailScreen({
    super.key,
    required this.sound,
  });

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

  @override
  Widget build(BuildContext context) {
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

