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

  /// Nom du fichier snapshot que cette révision désigne.
  ///
  /// Chaque push écrit son snapshot sous un nom UNIQUE, puis publie ce nom ici :
  /// deux appareils qui poussent en même temps ne peuvent donc plus écraser le
  /// snapshot l'un de l'autre. Le manifest devient le seul point de bascule, et
  /// le perdant de la course abandonne sans avoir rien détruit.
  ///
  /// `null` pour les manifests écrits avant ce schéma : l'appelant retombe alors
  /// sur le nom historique (`boards.db` / `library.db`).
  final String? dbFileName;

  const SyncManifest({
    required this.revision,
    required this.deviceId,
    required this.updatedAt,
    required this.schemaVersion,
    this.dbFileName,
  });

  Map<String, dynamic> toJson() => {
        'revision': revision,
        'deviceId': deviceId,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'schemaVersion': schemaVersion,
        if (dbFileName != null) 'dbFileName': dbFileName,
      };

  factory SyncManifest.fromJson(Map<String, dynamic> json) => SyncManifest(
        revision: json['revision'] as int,
        deviceId: json['deviceId'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        schemaVersion: json['schemaVersion'] as int,
        dbFileName: json['dbFileName'] as String?,
      );

  String encode() => jsonEncode(toJson());

  factory SyncManifest.decode(String raw) =>
      SyncManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
