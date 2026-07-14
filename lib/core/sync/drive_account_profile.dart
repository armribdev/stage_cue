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

  /// Sérialisation pour la persistance locale (affichage immédiat au lancement,
  /// avant tout appel réseau).
  Map<String, dynamic> toJson() => {
        'email': email,
        if (displayName != null) 'display_name': displayName,
        if (photoUrl != null) 'photo_url': photoUrl,
      };

  static DriveAccountProfile? fromJson(Map<String, dynamic> json) {
    final email = json['email'];
    if (email is! String || email.isEmpty) {
      return null;
    }
    return DriveAccountProfile(
      email: email,
      displayName: json['display_name'] as String?,
      photoUrl: json['photo_url'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DriveAccountProfile &&
      other.email == email &&
      other.displayName == displayName &&
      other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(email, displayName, photoUrl);

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

  /// URL de photo normalisée pour l'affichage (taille fixe Google).
  String? photoUrlForDisplay({int sizePx = 96}) {
    final url = photoUrl;
    if (url == null || url.isEmpty) return null;
    if (!url.contains('googleusercontent.com')) return url;
    final base = url.split('=').first;
    return '$base=s$sizePx-c';
  }
}
