/// Garde-fou de confidentialité du journal fichier.
///
/// Filet de sécurité appliqué par [LogSink] à tout ce qui est écrit sur disque
/// (message, erreur, stack trace) : il ne dispense pas les appelants de ne
/// jamais passer un jeton ou une adresse e-mail à un log. Le but est qu'une
/// interpolation `$e` malheureuse — une exception HTTP qui embarque son en-tête
/// `Authorization`, un corps de réponse OAuth — ne finisse pas dans un fichier
/// que l'utilisateur exporte et envoie.
class LogRedactor {
  LogRedactor._();

  static const _masked = '[masqué]';

  /// Ordre significatif : les motifs spécifiques (jeton Google, JWT) passent
  /// avant les motifs génériques (`clé=valeur`, e-mail).
  static final List<(RegExp, String)> _rules = [
    // Jeton d'accès Google.
    (RegExp(r'ya29\.[A-Za-z0-9_\-\.]+'), 'ya29.$_masked'),
    // Jeton de rafraîchissement Google (préfixe « 1// »).
    (RegExp(r'\b1//[A-Za-z0-9_\-]{20,}'), '1//$_masked'),
    // JWT (ID token) : trois segments base64url dont l'en-tête commence par eyJ.
    (
      RegExp(r'\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]*'),
      'eyJ$_masked',
    ),
    // En-tête HTTP « Bearer xxx ».
    (
      RegExp(r'\bBearer\s+[A-Za-z0-9\-\._~\+/]+=*', caseSensitive: false),
      'Bearer $_masked',
    ),
    // Paires clé/valeur sensibles, en JSON, en query string ou en `clé: valeur`.
    (
      RegExp(
        r'''(refresh_token|access_token|id_token|client_secret|authorization_code|code_verifier)(["']?\s*[:=]\s*["']?)[^\s"',}&]+''',
        caseSensitive: false,
      ),
      r'$1$2' + _masked,
    ),
    // Adresse e-mail.
    (
      RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}'),
      '[e-mail masqué]',
    ),
  ];

  static String redact(String input) {
    var out = input;
    for (final (pattern, replacement) in _rules) {
      out = out.replaceAllMapped(pattern, (m) {
        // Les groupes `$1`/`$2` ne sont interpolés que par ce remplacement
        // maison : `replaceAll` de Dart ne les gère pas.
        var result = replacement;
        for (var i = m.groupCount; i >= 1; i--) {
          result = result.replaceAll('\$$i', m.group(i) ?? '');
        }
        return result;
      });
    }
    return out;
  }
}
