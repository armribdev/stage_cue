import 'dart:io';
import 'dart:typed_data';

/// Fichier que l'analyse automatique ne peut ou ne doit pas traiter. [reason]
/// est une phrase courte, destinée au journal (une ligne par événement).
class AudioNotAnalyzable implements Exception {
  final String reason;
  const AudioNotAnalyzable(this.reason);

  @override
  String toString() => 'AudioNotAnalyzable: $reason';
}

/// Fréquence native et durée d'un fichier audio, lues dans son en-tête.
///
/// Le décodeur natif renvoie les échantillons à la fréquence du fichier sans
/// l'exposer, et la base ne mémorise pas la durée : l'analyse les retrouve ici
/// (mp3, wav, flac, ogg/vorbis — les formats acceptés par le moteur audio).
class AudioStreamInfo {
  final int sampleRate;
  final double durationSeconds;

  const AudioStreamInfo({
    required this.sampleRate,
    required this.durationSeconds,
  });

  @override
  String toString() => 'AudioStreamInfo($sampleRate Hz, $durationSeconds s)';
}

/// Lit [AudioStreamInfo] dans [file] sans le charger entièrement.
///
/// Lève [AudioNotAnalyzable] si le format n'est pas reconnu, si la fréquence ou
/// la durée est introuvable, ou pour Opus (le décodeur d'échantillons ne lit les
/// Ogg qu'avec libvorbis).
Future<AudioStreamInfo> probeAudioStreamInfo(File file) async {
  final length = await file.length();
  final raf = await file.open();
  try {
    Future<Uint8List> readAt(int offset, int count) async {
      if (offset < 0 || offset >= length) return Uint8List(0);
      await raf.setPosition(offset);
      return raf.read(count);
    }

    final head = await readAt(0, 12);
    if (head.length < 4) throw const AudioNotAnalyzable('fichier trop court');
    if (_tag(head, 0, 'RIFF') && _tag(head, 8, 'WAVE')) {
      return await _probeWav(readAt, length);
    }
    if (_tag(head, 0, 'fLaC')) return await _probeFlac(readAt);
    if (_tag(head, 0, 'OggS')) return await _probeOgg(readAt, length);
    return await _probeMp3(readAt, length, head);
  } finally {
    await raf.close();
  }
}

typedef _ReadAt = Future<Uint8List> Function(int offset, int count);

bool _tag(Uint8List b, int at, String tag) {
  if (at + tag.length > b.length) return false;
  for (var i = 0; i < tag.length; i++) {
    if (b[at + i] != tag.codeUnitAt(i)) return false;
  }
  return true;
}

ByteData _view(Uint8List b) => ByteData.sublistView(b);

AudioStreamInfo _info(int sampleRate, double seconds, String format) {
  if (sampleRate <= 0) {
    throw AudioNotAnalyzable(
      'fréquence d\'échantillonnage illisible ($format)',
    );
  }
  if (!seconds.isFinite || seconds <= 0) {
    throw AudioNotAnalyzable('durée inconnue ($format)');
  }
  return AudioStreamInfo(sampleRate: sampleRate, durationSeconds: seconds);
}

// ── WAV ─────────────────────────────────────────────────────────────────────

Future<AudioStreamInfo> _probeWav(_ReadAt readAt, int length) async {
  var sampleRate = 0;
  var byteRate = 0;
  var pos = 12;
  for (var i = 0; i < 64; i++) {
    final h = await readAt(pos, 8);
    if (h.length < 8) break;
    final id = String.fromCharCodes(h.sublist(0, 4));
    final size = _view(h).getUint32(4, Endian.little);
    final body = pos + 8;
    if (id == 'fmt ') {
      final f = await readAt(body, 16);
      if (f.length < 16) break;
      final v = _view(f);
      sampleRate = v.getUint32(4, Endian.little);
      byteRate = v.getUint32(8, Endian.little);
    } else if (id == 'data') {
      // Taille nulle ou absurde (flux, en-tête non finalisé) : jusqu'à la fin.
      final remaining = length - body;
      final dataBytes = (size == 0 || size > remaining) ? remaining : size;
      if (byteRate <= 0) break;
      return _info(sampleRate, dataBytes / byteRate, 'wav');
    }
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  throw const AudioNotAnalyzable('wav sans bloc fmt/data exploitable');
}

// ── FLAC ────────────────────────────────────────────────────────────────────

Future<AudioStreamInfo> _probeFlac(_ReadAt readAt) async {
  // 'fLaC' + en-tête de bloc (4) + STREAMINFO (34 octets).
  final b = await readAt(0, 42);
  if (b.length < 42 || (b[4] & 0x7F) != 0) {
    throw const AudioNotAnalyzable('flac sans bloc STREAMINFO');
  }
  const s = 8; // début des données STREAMINFO
  final sampleRate = (b[s + 10] << 12) | (b[s + 11] << 4) | (b[s + 12] >> 4);
  final total =
      ((b[s + 13] & 0x0F) << 32) |
      (b[s + 14] << 24) |
      (b[s + 15] << 16) |
      (b[s + 16] << 8) |
      b[s + 17];
  if (total == 0) throw const AudioNotAnalyzable('durée inconnue (flac)');
  return _info(sampleRate, sampleRate > 0 ? total / sampleRate : 0, 'flac');
}

// ── Ogg Vorbis ──────────────────────────────────────────────────────────────

Future<AudioStreamInfo> _probeOgg(_ReadAt readAt, int length) async {
  final first = await readAt(0, 512);
  if (first.length < 28) throw const AudioNotAnalyzable('ogg tronqué');
  final payload = 27 + first[26];
  if (_tag(first, payload, 'OpusHead')) {
    throw const AudioNotAnalyzable('opus non pris en charge par le décodeur');
  }
  if (payload + 16 > first.length ||
      first[payload] != 1 ||
      !_tag(first, payload + 1, 'vorbis')) {
    throw const AudioNotAnalyzable('ogg qui n\'est pas du vorbis');
  }
  final sampleRate = _view(first).getUint32(payload + 12, Endian.little);

  // Durée = position granulaire de la dernière page (en échantillons).
  final tailLen = length < 65536 ? length : 65536;
  final tail = await readAt(length - tailLen, tailLen);
  for (var i = tail.length - 14; i >= 0; i--) {
    if (_tag(tail, i, 'OggS')) {
      final granule = _view(tail).getInt64(i + 6, Endian.little);
      if (granule <= 0) break;
      return _info(sampleRate, granule / sampleRate, 'ogg');
    }
  }
  throw const AudioNotAnalyzable('durée inconnue (ogg)');
}

// ── MP3 ─────────────────────────────────────────────────────────────────────

const _mp3SampleRates = {
  3: [44100, 48000, 32000], // MPEG-1
  2: [22050, 24000, 16000], // MPEG-2
  0: [11025, 12000, 8000], // MPEG-2.5
};

// Débits (kbit/s) indexés par [version 1 ou 2/2.5][couche 1..3][index 1..14].
const _mp3Bitrates = {
  'v1l1': [32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
  'v1l2': [32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
  'v1l3': [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
  'v2l1': [32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
  'v2l2': [8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
  'v2l3': [8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
};

class _Mp3Frame {
  final int sampleRate;
  final int bitrate; // bit/s
  final int samplesPerFrame;
  final int frameLength; // octets
  final bool mpeg1;
  final bool mono;
  final bool crc;
  const _Mp3Frame({
    required this.sampleRate,
    required this.bitrate,
    required this.samplesPerFrame,
    required this.frameLength,
    required this.mpeg1,
    required this.mono,
    required this.crc,
  });
}

/// Décode l'en-tête de trame MPEG à [at], ou `null` si ce n'en est pas un.
_Mp3Frame? _parseMp3Header(Uint8List b, int at) {
  if (at + 4 > b.length) return null;
  if (b[at] != 0xFF || (b[at + 1] & 0xE0) != 0xE0) return null;
  final version = (b[at + 1] >> 3) & 3; // 0 = 2.5, 2 = MPEG-2, 3 = MPEG-1
  final layer = (b[at + 1] >> 1) & 3; // 1 = III, 2 = II, 3 = I
  final bitrateIndex = b[at + 2] >> 4;
  final rateIndex = (b[at + 2] >> 2) & 3;
  if (version == 1 || layer == 0 || bitrateIndex == 0 || bitrateIndex == 15) {
    return null;
  }
  if (rateIndex == 3) return null;
  final mpeg1 = version == 3;
  final layerNo = 4 - layer; // 1, 2 ou 3
  final bitrate =
      _mp3Bitrates['${mpeg1 ? 'v1' : 'v2'}l$layerNo']![bitrateIndex - 1] * 1000;
  final sampleRate = _mp3SampleRates[version]![rateIndex];
  final padding = (b[at + 2] >> 1) & 1;
  final int samples;
  final int frameLength;
  if (layerNo == 1) {
    samples = 384;
    frameLength = (12 * bitrate ~/ sampleRate + padding) * 4;
  } else {
    samples = (layerNo == 3 && !mpeg1) ? 576 : 1152;
    final coeff = samples ~/ 8;
    frameLength = coeff * bitrate ~/ sampleRate + padding;
  }
  return _Mp3Frame(
    sampleRate: sampleRate,
    bitrate: bitrate,
    samplesPerFrame: samples,
    frameLength: frameLength,
    mpeg1: mpeg1,
    mono: (b[at + 3] >> 6) == 3,
    crc: (b[at + 1] & 1) == 0,
  );
}

Future<AudioStreamInfo> _probeMp3(
  _ReadAt readAt,
  int length,
  Uint8List head,
) async {
  // Saute l'étiquette ID3v2 (syncsafe), souvent chargée d'une pochette.
  var audioStart = 0;
  if (_tag(head, 0, 'ID3')) {
    final h = await readAt(0, 10);
    if (h.length < 10) throw const AudioNotAnalyzable('mp3 tronqué');
    final size =
        (h[6] & 0x7F) << 21 |
        (h[7] & 0x7F) << 14 |
        (h[8] & 0x7F) << 7 |
        (h[9] & 0x7F);
    audioStart = 10 + size + ((h[5] & 0x10) != 0 ? 10 : 0);
  }

  final buf = await readAt(audioStart, 32768);
  for (var i = 0; i + 4 <= buf.length; i++) {
    final frame = _parseMp3Header(buf, i);
    if (frame == null) continue;
    // Une fausse synchro est fréquente dans les données : exige que la trame
    // suivante soit elle aussi valide quand elle est dans le tampon.
    final next = i + frame.frameLength;
    if (next + 4 <= buf.length && _parseMp3Header(buf, next) == null) continue;

    final frames = _xingFrameCount(buf, i, frame);
    final seconds = frames != null
        ? frames * frame.samplesPerFrame / frame.sampleRate
        : (length - audioStart - i) * 8 / frame.bitrate; // CBR supposé
    return _info(frame.sampleRate, seconds, 'mp3');
  }
  throw const AudioNotAnalyzable('mp3 sans trame valide');
}

/// Nombre de trames annoncé par l'en-tête Xing/Info/VBRI de la 1re trame.
int? _xingFrameCount(Uint8List b, int frameAt, _Mp3Frame f) {
  final side = f.mpeg1 ? (f.mono ? 17 : 32) : (f.mono ? 9 : 17);
  final xing = frameAt + 4 + (f.crc ? 2 : 0) + side;
  if ((_tag(b, xing, 'Xing') || _tag(b, xing, 'Info')) &&
      xing + 12 <= b.length) {
    final v = _view(b);
    if (v.getUint32(xing + 4) & 1 != 0) return v.getUint32(xing + 8);
  }
  final vbri = frameAt + 36;
  if (_tag(b, vbri, 'VBRI') && vbri + 18 <= b.length) {
    return _view(b).getUint32(vbri + 14);
  }
  return null;
}
