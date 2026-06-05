import 'dart:convert';

/// Métadonnées de synchronisation stockées à côté du snapshot DB dans Drive
/// (`.stagecue/manifest.json`). Sert d'arbitre pour la détection de conflits :
/// chaque push incrémente [revision] ; un appareil ne peut pousser que s'il
/// connaît la révision distante courante.
class SyncManifest {
  final int revision;
  final String deviceId;
  final DateTime updatedAt;
  final int schemaVersion;

  const SyncManifest({
    required this.revision,
    required this.deviceId,
    required this.updatedAt,
    required this.schemaVersion,
  });

  Map<String, dynamic> toJson() => {
        'revision': revision,
        'deviceId': deviceId,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'schemaVersion': schemaVersion,
      };

  factory SyncManifest.fromJson(Map<String, dynamic> json) => SyncManifest(
        revision: json['revision'] as int,
        deviceId: json['deviceId'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        schemaVersion: json['schemaVersion'] as int,
      );

  String encode() => jsonEncode(toJson());

  factory SyncManifest.decode(String raw) =>
      SyncManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
