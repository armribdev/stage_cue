// ignore_for_file: invalid_use_of_protected_member
// `setState` est appelé depuis une extension du State (mêmes appels qu'avant le
// découpage en `part`) : l'avertissement ne vise pas un vrai mauvais usage.

part of '../settings_screen.dart';

/// Journal (maintenance) : export et copie du journal fichier persistant
/// (cf. ADR 0025). Méthodes de [_SettingsScreenState] extraites via extension
/// dans le même `part`.
extension _SettingsDiagnostic on _SettingsScreenState {
  static const int _kClipboardLineCount = 500;

  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// Diagnostic de la maintenance : explication, état (version, taille, dossier)
  /// puis les trois actions.
  Widget _buildDiagnosticRows() {
    final folder = LogSink.directory?.path;
    final lost = LogSink.lostLines;
    final exported = _confirmedAction == _kExportLogsAction;
    final copied = _confirmedAction == _kCopyLogsAction;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsRow(
          title: 'Diagnostic',
          description:
              'Événements (lecture, synchro, erreurs), conservés sur cet '
              'appareil. À joindre à un signalement de problème.',
        ),
        const SizedBox(height: AppSpacing.xs),
        if (_appVersion != null) ...[
          _buildInfoRow('Version', _appVersion!),
          const SizedBox(height: AppSpacing.xs + 2),
        ],
        _buildInfoRow('Journal', _logStateLabel()),
        if (folder != null) ...[
          const SizedBox(height: AppSpacing.xs + 2),
          _buildInfoRow('Dossier des logs', folder, isPath: true),
        ],
        if (lost > 0) ...[
          const SizedBox(height: AppSpacing.xs + 2),
          SettingsNote(
            '$lost ligne(s) de journal n\'ont pas pu être écrites sur disque '
            'pendant cette session.',
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            SettingsButton(
              label: exported ? 'Logs exportés' : 'Exporter les logs',
              icon: exported ? AppIcons.check : AppIcons.download,
              busy: _isDiagnosticBusy,
              onPressed: _exportLogs,
            ),
            SettingsButton(
              label: copied
                  ? 'Copié'
                  : 'Copier les $_kClipboardLineCount dernières lignes',
              icon: copied ? AppIcons.check : AppIcons.copy,
              onPressed: _isDiagnosticBusy ? null : _copyLogsToClipboard,
            ),
            if (_isDesktopPlatform)
              SettingsButton(
                label: 'Ouvrir le dossier des logs',
                icon: AppIcons.folderOpen,
                onPressed: folder == null ? null : _openLogsFolder,
              ),
          ],
        ),
      ],
    );
  }

  /// « 1.23 MB sur disque · session démarrée à 14:02 » : de quoi juger si le
  /// journal contient la session qu'on veut joindre à un signalement.
  String _logStateLabel() {
    String two(int v) => v.toString().padLeft(2, '0');
    final start = LogSink.sessionStart;
    final session =
        'session démarrée à ${two(start.hour)}:${two(start.minute)}';
    final bytes = _logDiskBytes;
    return bytes == null
        ? session
        : '${_formatBytes(bytes)} sur disque · $session';
  }

  /// Taille cumulée du fichier courant et de ses archives. Meilleur effort : un
  /// fichier illisible n'empêche pas d'afficher les autres, et la taille n'est
  /// qu'une indication (l'export, lui, signale ses propres erreurs).
  Future<void> _loadLogDiskSize() async {
    var total = 0;
    for (final file in LogSink.logFiles()) {
      try {
        if (await file.exists()) total += await file.length();
      } catch (_) {
        // Ignoré : voir ci-dessus.
      }
    }
    if (mounted) setState(() => _logDiskBytes = total);
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
      _flashConfirmation(_kExportLogsAction);
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
      _flashConfirmation(_kCopyLogsAction);
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
      await Process.start(executable, [path], mode: ProcessStartMode.detached);
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
