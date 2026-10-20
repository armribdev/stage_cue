import 'dart:convert';
import 'dart:io';

import 'log_sink.dart';

/// Lecture du journal pour l'export et la copie dans le presse-papiers.
class LogExport {
  LogExport._();

  /// `stage-cue-logs-AAAA-MM-JJ-HHmm.txt`
  static String suggestedFileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'stage-cue-logs-${now.year}-${two(now.month)}-${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}.txt';
  }

  /// Contenu intégral : en-tête de session, puis archives et fichier courant
  /// dans l'ordre chronologique. Vide le buffer avant de lire.
  static Future<String> buildFullExport() async {
    await LogSink.flush();
    final body = StringBuffer();
    for (final file in LogSink.logFiles()) {
      body.write(await _readTolerant(file));
    }
    final out = StringBuffer();
    // L'en-tête de la session courante est déjà la première chose du fichier
    // tant qu'il n'a pas été rotaté ; ne le recopier en tête que s'il en a
    // disparu (session très longue), sinon il apparaîtrait deux fois.
    final header = LogSink.sessionHeader;
    final firstHeaderLine = header.split('\n').first;
    if (header.isNotEmpty && !body.toString().contains(firstHeaderLine)) {
      out
        ..writeln(header)
        ..writeln();
    }
    final lost = LogSink.lostLines;
    if (lost > 0) {
      out
        ..writeln('[$lost ligne(s) de journal perdue(s) pendant cette session]')
        ..writeln();
    }
    out.write(body);
    return out.toString();
  }

  /// Les [lineCount] dernières lignes (continuations de stack comprises).
  static Future<String> tail({int lineCount = 500}) async {
    await LogSink.flush();
    final lines = <String>[];
    for (final file in LogSink.logFiles().reversed) {
      final content = (await _readTolerant(file)).split('\n');
      if (content.isNotEmpty && content.last.isEmpty) content.removeLast();
      lines.insertAll(0, content);
      if (lines.length >= lineCount) break;
    }
    final start = lines.length > lineCount ? lines.length - lineCount : 0;
    return lines.sublist(start).join('\n');
  }

  static Future<String> _readTolerant(File file) async {
    try {
      return utf8.decode(await file.readAsBytes(), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }
}
