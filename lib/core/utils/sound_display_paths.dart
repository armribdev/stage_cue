import '../../features/sampler/domain/entities/library.dart';
import '../../features/sampler/domain/entities/sound.dart';
import 'indexed_folder_labels.dart' show normalizeDrivePathForDisplay;

/// Chemins affichés pour les sons dans l'UI.
///
/// Les sons de bibliothèque Drive utilisent le chemin distant ; les sons locaux
/// conservent leur [Sound.filePath].
class SoundDisplayPaths {
  SoundDisplayPaths._();

  /// Chemin à afficher pour [sound] (Drive ou local).
  static String forSound(
    Sound sound, {
    Library? library,
  }) {
    final relativePath = sound.relativePath?.trim();
    if (sound.libraryId != null &&
        relativePath != null &&
        relativePath.isNotEmpty) {
      return drivePathForSound(
        relativePath: relativePath,
        library: library,
      );
    }
    return sound.filePath;
  }

  /// Chemin Drive d'un son de bibliothèque (sans tenir compte du cache local).
  static String drivePathForSound({
    required String relativePath,
    Library? library,
  }) {
    final drivePath = _joinLibraryAndRelativePath(
      library?.drivePath,
      relativePath,
    );
    final owner = library?.ownerEmail?.trim();

    if (owner != null && owner.isNotEmpty && drivePath.isNotEmpty) {
      return '$owner/$drivePath';
    }
    if (drivePath.isNotEmpty) {
      return drivePath;
    }
    if (owner != null && owner.isNotEmpty) {
      return owner;
    }
    return relativePath.replaceAll('\\', '/');
  }

  /// Assemble le chemin bibliothèque et le chemin relatif du son pour l'affichage.
  static String _joinLibraryAndRelativePath(
    String? libraryDrivePath,
    String relativePath,
  ) {
    final relDisplay = normalizeDrivePathForDisplay(relativePath);

    final libraryPath = libraryDrivePath?.trim() ?? '';
    if (libraryPath.isEmpty) {
      return relDisplay;
    }
    if (relDisplay.isEmpty) {
      return normalizeDrivePathForDisplay(libraryPath);
    }
    return '${normalizeDrivePathForDisplay(libraryPath)}/$relDisplay';
  }
}
