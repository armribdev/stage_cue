/// Modèle pour les identifiants OAuth desktop (Windows/Linux).
///
/// Priorité effective (voir [GoogleOAuthConfig]) :
/// 1. `--dart-define=GOOGLE_OAUTH_CLIENT_ID/SECRET` (CI / release)
/// 2. Saisie dans l'app (stockage sécurisé, sans recompiler)
/// 3. Ce fichier local (dev)
///
/// Pour un setup local via fichier :
/// 1. Copiez ce fichier vers `google_oauth_secrets.dart` (même dossier).
/// 2. Créez un client OAuth « Web » dans Google Cloud Console.
/// 3. URI de redirection : `http://localhost:8000`
/// 4. Renseignez les constantes ci-dessous.
///
/// `google_oauth_secrets.dart` est ignoré par git — ne le commitez pas.
const String googleOAuthClientId = '';
const String googleOAuthClientSecret = '';
