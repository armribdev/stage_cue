import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'drive_account_profile.dart';

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
    } catch (_) {
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

  /// Nom de fichier stable et déterministe pour [url] (FNV-1a 32 bits) :
  /// `String.hashCode` est semé aléatoirement par isolate et changerait entre
  /// deux lancements, invalidant le cache.
  static String _keyFor(String url) {
    var hash = 0x811c9dc5;
    for (final unit in url.codeUnits) {
      hash = (hash ^ unit) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  Future<File> _fileFor(String url) async {
    final dir = await _dir();
    return File(p.join(dir.path, 'avatar_${_keyFor(url)}.img'));
  }

  /// Renvoie le fichier local de l'avatar : depuis le cache s'il existe, sinon
  /// après téléchargement. Null si indisponible (hors-ligne sans cache).
  Future<File?> resolve(String url) async {
    final file = await _fileFor(url);
    if (await file.exists()) {
      return file;
    }
    return _download(url, file);
  }

  Future<File?> _download(String url, File file) async {
    try {
      final response = await _http.get(Uri.parse(url));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
        return file;
      }
    } catch (_) {
      // Hors-ligne ou URL périmée : pas d'avatar à afficher cette fois-ci.
    }
    return null;
  }

  /// Supprime toutes les photos mises en cache (déconnexion).
  Future<void> clear() async {
    try {
      final dir = await _dir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _cachedDir = null;
    } catch (_) {
      // Best-effort : un cache résiduel n'est pas bloquant.
    }
  }

  void dispose() {
    _http.close();
  }
}
