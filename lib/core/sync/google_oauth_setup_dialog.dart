import 'dart:io';

import 'package:flutter/material.dart';

import 'google_oauth_config.dart';

/// Vérifie la config OAuth desktop et affiche un dialogue d'aide si besoin.
/// Retourne `true` si la connexion Drive peut être tentée.
Future<bool> ensureGoogleOAuthConfigured(BuildContext context) async {
  if (!Platform.isWindows && !Platform.isLinux) {
    return true;
  }
  if (GoogleOAuthConfig.isConfigured) {
    return true;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Configuration OAuth requise'),
        content: const SingleChildScrollView(
          child: Text(
            'Pour Google Drive sur Windows/Linux :\n\n'
            '1. Google Cloud Console → APIs et services → Identifiants\n'
            '2. Créer un client OAuth de type « Application Web »\n'
            '   (pas Android/iOS — un client Web distinct est nécessaire)\n'
            '3. URI de redirection autorisée : http://localhost:8000\n'
            '4. Éditer le fichier :\n'
            '   lib/core/sync/google_oauth_secrets.dart\n'
            '5. Renseigner googleOAuthClientId et googleOAuthClientSecret\n'
            '6. Redémarrer l\'app (un hot reload ne suffit pas)\n\n'
            'Même projet Google Cloud que pour la version mobile.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Compris'),
          ),
        ],
      );
    },
  );

  return false;
}
