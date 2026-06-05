/// Profil public d'un compte Google connecté à Drive.
class DriveAccountProfile {
  final String email;
  final String? displayName;
  final String? photoUrl;

  const DriveAccountProfile({
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  String get label => displayName?.trim().isNotEmpty == true
      ? displayName!.trim()
      : email;

  String get initials {
    final source = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : email;
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    if (source.isEmpty) return '?';
    return source.substring(0, 1).toUpperCase();
  }
}
