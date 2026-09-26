import 'dart:io';
import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'google_oauth_config.dart';

/// Vérifie la config OAuth desktop et propose la saisie des credentials si besoin.
/// Retourne `true` si la connexion Drive peut être tentée.
Future<bool> ensureGoogleOAuthConfigured(BuildContext context) async {
  if (!Platform.isWindows && !Platform.isLinux) {
    return true;
  }
  if (GoogleOAuthConfig.isConfigured) {
    return true;
  }

  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _GoogleOAuthCredentialsDialog(),
  );

  return saved == true && GoogleOAuthConfig.isConfigured;
}

class _GoogleOAuthCredentialsDialog extends StatefulWidget {
  const _GoogleOAuthCredentialsDialog();

  @override
  State<_GoogleOAuthCredentialsDialog> createState() =>
      _GoogleOAuthCredentialsDialogState();
}

class _GoogleOAuthCredentialsDialogState
    extends State<_GoogleOAuthCredentialsDialog> {
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  var _obscureSecret = true;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _saving = true);
    try {
      await GoogleOAuthConfig.saveRuntimeCredentials(
        clientId: _clientIdController.text,
        clientSecret: _clientSecretController.text,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = 'Impossible d\'enregistrer les identifiants : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dialogWidth = min(560.0, MediaQuery.sizeOf(context).width - 48);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusLg),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      title: const Text('Configuration Google Drive'),
      content: SizedBox(
        width: dialogWidth,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pour synchroniser Drive sur Windows/Linux, créez un client '
                  'OAuth « Application Web » dans Google Cloud Console '
                  '(même projet que la version mobile), avec l\'URI de '
                  'redirection http://localhost:8000, puis collez les '
                  'identifiants ci-dessous. Ils sont stockés de façon sécurisée '
                  'sur cet appareil — pas besoin de recompiler.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.8),
                      ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _clientIdController,
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: 'Client ID',
                    hintText: 'xxxxx.apps.googleusercontent.com',
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'Client ID requis';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _clientSecretController,
                  enabled: !_saving,
                  obscureText: _obscureSecret,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Client Secret',
                    suffixIcon: IconButton(
                      tooltip: _obscureSecret ? 'Afficher' : 'Masquer',
                      onPressed: _saving
                          ? null
                          : () => setState(
                                () => _obscureSecret = !_obscureSecret,
                              ),
                      icon: Icon(
                        _obscureSecret
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'Client Secret requis';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    style: TextStyle(color: scheme.error, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
