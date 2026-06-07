import 'dart:io';
import 'dart:typed_data';

/// Taille minimale d'un fichier audio exploitable (octets).
///
/// En dessous, il s'agit quasi systématiquement d'un cache tronqué ou d'un
/// stub de téléchargement raté — SoLoud échoue avec fileLoadFailed.
const int kMinimumValidAudioFileBytes = 512;

/// Vérifie qu'un fichier local a une taille et un en-tête plausibles.
Future<bool> isPlausibleAudioFile(File file) async {
  if (!await file.exists()) return false;

  final length = await file.length();
  if (length < kMinimumValidAudioFileBytes) return false;

  final raf = await file.open();
  try {
    final header = await raf.read(24);
    if (header.isEmpty) return false;
    return hasPlausibleAudioHeader(header);
  } finally {
    await raf.close();
  }
}

/// Fichiers déjà identifiés comme illisibles — évite les boucles de retry.
final Set<String> _knownUnloadablePaths = {};

String normalizeAudioPath(String path) =>
    path.replaceAll('\\', '/').toLowerCase();

bool isKnownUnloadablePath(String path) =>
    _knownUnloadablePaths.contains(normalizeAudioPath(path));

void markPathUnloadable(String path) {
  _knownUnloadablePaths.add(normalizeAudioPath(path));
}

void clearUnloadablePath(String path) {
  _knownUnloadablePaths.remove(normalizeAudioPath(path));
}

/// En-tête non HTML/JSON ; la taille minimale est vérifiée à part.
bool hasPlausibleAudioHeader(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  return !_isObviousNonAudioHeader(bytes);
}

bool _isObviousNonAudioHeader(Uint8List bytes) {
  if (bytes.length < 4) return true;

  final asciiPrefix = String.fromCharCodes(
    bytes.take(24).where((b) => b >= 32 && b < 127),
  ).toLowerCase();
  if (asciiPrefix.startsWith('<!doctype') ||
      asciiPrefix.startsWith('<html') ||
      asciiPrefix.startsWith('<?xml')) {
    return true;
  }
  if (bytes[0] == 0x7B || bytes[0] == 0x5B) return true;
  return false;
}
