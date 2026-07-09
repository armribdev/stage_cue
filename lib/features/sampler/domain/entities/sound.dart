import 'dart:typed_data';

/// Entité métier représentant un son
class Sound {
  final int id;
  final String title;
  final String? displayName;
  final String filePath;
  final SoundType? type;
  final int? colorValue;
  final double volume;
  final DateTime createdAt;

  /// Bibliothèque d'appartenance ; `null` = son purement local (legacy).
  final int? libraryId;

  /// Chemin relatif à la racine de la bibliothèque ; `null` pour les sons locaux.
  final String? relativePath;

  /// Identité forte du fichier sur Drive (immuable au renommage/déplacement) ;
  /// `null` pour les sons legacy non réconciliés. Sert à télécharger le fichier
  /// sans dépendre d'une résolution par nom fragile aux accents.
  final String? driveFileId;

  /// Empreinte de contenu pour réidentifier un fichier déplacé/renommé.
  final String? contentHash;

  /// Marqué favori par l'opérateur (accès rapide en recherche-éclair).
  final bool isFavorite;

  /// Dernière lecture (pré-écoute / déclenchement) — tri par récence.
  final DateTime? lastPlayedAt;

  /// Enveloppe RMS pré-calculée (1 octet 0–255 par barre) pour la waveform de
  /// régie musique ; `null` tant que non calculée.
  final Uint8List? waveform;

  /// Génération d'extraction lors du dernier échec « format » de la waveform ;
  /// `null` = jamais échoué / à (re)tenter. Gouverne le retry (cf.
  /// `waveformNeedsProbe`). Entier volontairement opaque au domaine : la
  /// politique de génération vit dans `core/audio/waveform_extractor.dart`.
  final int? waveformProbeGeneration;

  /// Point d'entrée de lecture en millisecondes : tout déclenchement démarre
  /// ici au lieu du sample 0. 0 = début du fichier.
  final int startOffsetMs;

  Sound({
    required this.id,
    required this.title,
    this.displayName,
    required this.filePath,
    this.type,
    this.colorValue,
    this.volume = 1.0,
    required this.createdAt,
    this.libraryId,
    this.relativePath,
    this.driveFileId,
    this.contentHash,
    this.isFavorite = false,
    this.lastPlayedAt,
    this.waveform,
    this.waveformProbeGeneration,
    this.startOffsetMs = 0,
  });
}

/// Type de son
enum SoundType {
  soundEffect,
  music,
  ambiance,
}

