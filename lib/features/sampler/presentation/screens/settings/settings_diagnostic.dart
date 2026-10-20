// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../settings_screen.dart';

/// Section « Diagnostic » : export et copie du journal fichier persistant
/// (cf. ADR 0025). Méthodes de [_SettingsScreenState] extraites via extension
/// dans le même `part`.
extension _SettingsDiagnostic on _SettingsScreenState {
  static const int _kClipboardLineCount = 500;

  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  // Pas de Card : un libellé de section, son contenu, puis le séparateur posé
  // par `_buildSettingsBody` (direction « Console Linear », ADR 0023).
  Widget _buildDiagnosticSection() {
    final scheme = Theme.of(context).colorScheme;
    final folder = LogSink.directory?.path;
    final lost = LogSink.lostLines;
    // Boutons côte à côte : `minimumSize` surchargé, sinon le thème global
    // (`Size.fromHeight`) leur donne une largeur infinie et ils disparaissent.
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(64, 42),
    );

    return _buildSettingsSectionCard(
      title: _buildSectionTitleRow(
        icon: Icons.receipt_long_outlined,
        title: 'Diagnostic',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Journal des événements de l\'application (lecture, synchro, '
            'erreurs), conservé sur cet appareil. À joindre à un signalement '
            'de problème.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (folder != null) ...[
            const SizedBox(height: 10),
            _buildInfoRow('Dossier des logs', folder, isPath: true),
          ],
          if (lost > 0) ...[
            const SizedBox(height: 6),
            Text(
              '$lost ligne(s) de journal n\'ont pas pu être écrites sur disque '
              'pendant cette session.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: buttonStyle,
                onPressed: _isDiagnosticBusy ? null : _exportLogs,
                icon: _isDiagnosticBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined, size: 18),
                label: const Text('Exporter les logs'),
              ),
              OutlinedButton.icon(
                style: buttonStyle,
                onPressed: _isDiagnosticBusy ? null : _copyLogsToClipboard,
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Copier dans le presse-papiers'),
              ),
              if (_isDesktopPlatform)
                OutlinedButton.icon(
                  style: buttonStyle,
                  onPressed: folder == null ? null : _openLogsFolder,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Ouvrir le dossier des logs'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Concatène les fichiers de journal en un seul `.txt` daté et le sauvegarde
  /// via le sélecteur de fichier. L'annulation du sélecteur n'est pas une
  /// erreur : aucun message.
  Future<void> _exportLogs() async {
    if (_isDiagnosticBusy) return;
    setState(() => _isDiagnosticBusy = true);
    try {
      final content = await LogExport.buildFullExport();
      if (!mounted) return;
      if (content.trim().isEmpty) {
        AppSnackBar.show(context, 'Le journal est vide : rien à exporter.');
        return;
      }
      final bytes = Uint8List.fromList(utf8.encode(content));
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Exporter les logs',
        fileName: LogExport.suggestedFileName(DateTime.now()),
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        bytes: bytes,
      );
      if (!mounted) return;
      if (savedPath == null) return; // Sélecteur fermé par l'utilisateur.

      // Le plugin écrit les octets lui-même sur Windows ; on ne se fie pas à
      // cette promesse pour les autres bureaux : un export « réussi » mais
      // vide serait pire qu'un échec annoncé.
      if (_isDesktopPlatform) {
        final file = File(savedPath);
        if (!await file.exists() || await file.length() == 0) {
          await file.writeAsBytes(bytes);
        }
        if (!mounted) return;
      }
      AppSnackBar.show(context, 'Logs exportés : ${p.basename(savedPath)}');
    } catch (e) {
      AppLog.warn('Export des logs échoué : $e');
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Export des logs impossible : $e',
        copyable: true,
      );
    } finally {
      if (mounted) setState(() => _isDiagnosticBusy = false);
    }
  }

  Future<void> _copyLogsToClipboard() async {
    if (_isDiagnosticBusy) return;
    setState(() => _isDiagnosticBusy = true);
    try {
      final text = await LogExport.tail(lineCount: _kClipboardLineCount);
      if (!mounted) return;
      if (text.trim().isEmpty) {
        AppSnackBar.show(context, 'Le journal est vide : rien à copier.');
        return;
      }
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      final lines = '\n'.allMatches(text).length + 1;
      AppSnackBar.show(
        context,
        '$lines dernière(s) ligne(s) du journal copiée(s).',
      );
    } catch (e) {
      AppLog.warn('Copie des logs échouée : $e');
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Copie des logs impossible : $e',
        copyable: true,
      );
    } finally {
      if (mounted) setState(() => _isDiagnosticBusy = false);
    }
  }

  /// Ouvre le dossier des logs dans l'explorateur du système (bureau seulement :
  /// pas de `url_launcher` dans le projet, on lance l'opener natif).
  Future<void> _openLogsFolder() async {
    final path = LogSink.directory?.path;
    if (path == null) return;
    try {
      final String executable;
      if (Platform.isWindows) {
        executable = 'explorer.exe';
      } else if (Platform.isMacOS) {
        executable = 'open';
      } else {
        executable = 'xdg-open';
      }
      // `explorer.exe` rend un code de sortie 1 même quand il réussit : on ne
      // juge que le lancement du processus.
      await Process.start(
        executable,
        [path],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      AppLog.warn('Ouverture du dossier des logs échouée : $e');
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Impossible d\'ouvrir le dossier des logs : $e',
        copyable: true,
      );
    }
  }
}
