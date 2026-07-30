import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'drive_account_profile.dart';
import 'sync_log.dart';

/// Persiste le profil du compte Google (e-mail, nom, URL photo) pour un
/// affichage immédiat au lancement, avant toute reconnexion réseau.
class DriveProfileStore {
  const DriveProfileStore();

  static const String _kKey = 'drive_account_profile_v1';

  Future<void> save(DriveAccountProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(profile.toJson()));
  }

  Future<DriveAccountProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null) {
      return null;
    }
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return DriveAccountProfile.fromJson(map);
    } catch (e) {
      // Le profil restauré au lancement disparaît (ni e-mail ni avatar affichés)
      // alors que la session Drive, elle, est intacte : dissociation trompeuse
      // qui n'avait aucune trace.
      SyncLog.warn('Profil Drive en cache illisible — $e');
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}

/// Cache disque de la photo de profil : évite de re-télécharger l'avatar à
/// chaque lancement et permet son affichage hors-ligne (`Image.network` ne
/// dispose que d'un cache mémoire, perdu à la fermeture de l'app).
///
/// Le cache est indexé sur l'**identité du compte** (e-mail), pas sur l'URL :
/// un même compte n'a qu'un seul fichier, réutilisé quelle que soit la variante
/// d'URL fournie par Google (userinfo vs id_token, tailles différentes). On
/// évite ainsi l'accumulation de fichiers et le clignotement quand l'URL change
/// entre deux lancements alors que la photo, elle, est la même.
class DriveAvatarCache {
  DriveAvatarCache({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  Directory? _cachedDir;

  Future<Directory> _dir() async {
    final existing = _cachedDir;
    if (existing != null) {
      return existing;
    }
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'drive_avatars'));
    await dir.create(recursive: true);
    return _cachedDir = dir;
  }

  /// Clé stable et déterministe pour [value] (FNV-1a 32 bits) :
  /// `String.hashCode` est semé aléatoirement par isolate et changerait entre
  /// deux lancements, invalidant le cache.
  static String _keyFor(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = (hash ^ unit) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// Extension d'image réelle déduite du `Content-Type`. Surtout, on n'utilise
  /// jamais `.img` : sous Windows cette extension est associée aux images
  /// disque, et l'explorateur affiche alors l'avatar comme un fichier disque.
  static String _extForContentType(String? contentType) {
    switch (contentType?.split(';').first.trim().toLowerCase()) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      case 'image/jpeg':
      default:
        return 'jpg';
    }
  }

  /// Fichier en cache pour [identity], quelle que soit son extension.
  Future<File?> _existingFileFor(String identity) async {
    final dir = await _dir();
    final prefix = 'avatar_${_keyFor(identity)}.';
    await for (final entity in dir.list()) {
      if (entity is File && p.basename(entity.path).startsWith(prefix)) {
        return entity;
      }
    }
    return null;
  }

  /// Renvoie le fichier local de l'avatar de [identity] (l'e-mail du compte),
  /// téléchargé depuis [url]. Le fichier existant est renvoyé immédiatement s'il
  /// est présent ; on ne re-télécharge que s'il manque ou que la source a
  /// changé. En cas d'échec réseau on retombe sur le fichier existant (photo
  /// éventuellement un peu périmée, mais jamais de trou visuel). Null si aucune
  /// photo n'est disponible.
  Future<File?> resolve({required String identity, required String url}) async {
    final prefs = await SharedPreferences.getInstance();
    final srcKey = 'drive_avatar_src_${_keyFor(identity)}';
    final existing = await _existingFileFor(identity);
    if (existing != null && prefs.getString(srcKey) == url) {
      return existing;
    }

    final downloaded = await _download(identity, url);
    if (downloaded != null) {
      await prefs.setString(srcKey, url);
      return downloaded;
    }
    // Hors-ligne ou URL périmée : on garde l'ancienne photo si on en a une.
    return existing;
  }

  Future<File?> _download(String identity, String url) async {
    try {
      final response = await _http.get(Uri.parse(url));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final dir = await _dir();
        final ext = _extForContentType(response.headers['content-type']);
        final file =
            File(p.join(dir.path, 'avatar_${_keyFor(identity)}.$ext'));
        await file.writeAsBytes(response.bodyBytes, flush: true);
        await _pruneExcept(file);
        return file;
      }
    } catch (e) {
      // Hors-ligne ou URL périmée : pas d'avatar frais à écrire cette fois-ci.
      // Purement cosmétique (l'avatar en cache reste affiché), d'où la trace.
      SyncLog.trace('avatar non rafraîchi — $e');
    }
    return null;
  }

  /// Supprime tout fichier du dossier autre que [keep] : purge les anciennes
  /// variantes d'URL et les fichiers `.img` hérités des versions précédentes.
  Future<void> _pruneExcept(File keep) async {
    try {
      final dir = await _dir();
      await for (final entity in dir.list()) {
        if (entity is File && !p.equals(entity.path, keep.path)) {
          await entity.delete();
        }
      }
    } catch (e) {
      // Best-effort : un fichier résiduel n'est pas bloquant.
      SyncLog.trace('purge des avatars obsolètes incomplète — $e');
    }
  }

  /// Supprime toutes les photos mises en cache (déconnexion).
  Future<void> clear() async {
    try {
      final dir = await _dir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _cachedDir = null;
    } catch (e) {
      // Best-effort, mais c'est une DÉCONNEXION : la photo du compte quitté
      // reste sur le disque. Sans conséquence fonctionnelle, à savoir tout de
      // même si la question de ce qui subsiste après déconnexion se pose.
      SyncLog.warn(
        'Photos de compte non purgées à la déconnexion — $e',
      );
    }
  }

  void dispose() {
    _http.close();
  }
}
