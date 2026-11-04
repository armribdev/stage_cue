import 'package:flutter/foundation.dart';

import 'auto_tag_pack.dart';
import 'auto_tag_pack_installer.dart';

enum AutoTagPackStatus { unknown, notInstalled, downloading, installed }

/// État du pack de modèles pour l'écran Paramètres : installé ou non,
/// progression, dernière erreur. Ne décide de rien d'autre : le lancement de
/// l'analyse reste à `AutoSyncCoordinator` ([onInstalled] le prévient).
class AutoTagPackController extends ChangeNotifier {
  final AutoTagPack _pack;
  final AutoTagPackInstaller _installer;

  /// Appelé quand le pack vient d'être installé : l'analyse peut démarrer.
  VoidCallback? onInstalled;

  AutoTagPackStatus _status = AutoTagPackStatus.unknown;
  int _received = 0;
  int _notifiedAt = 0;
  Object? _lastError;
  AutoTagPackCancelToken? _cancel;
  bool _disposed = false;

  AutoTagPackController(this._pack, this._installer);

  AutoTagPackStatus get status => _status;

  /// Octets reçus / taille attendue, pendant le téléchargement.
  int get receivedBytes => _received;
  int get totalBytes => _installer.release.sizeBytes;

  /// Dernière erreur de téléchargement (jamais l'annulation), `null` sinon.
  Object? get lastError => _lastError;

  Future<void> refresh() async {
    if (_status == AutoTagPackStatus.downloading) return;
    await _recheck();
  }

  /// Relit l'état réel sur disque (un échec ou une annulation ne laisse rien,
  /// mais un pack précédent peut être déjà installé).
  Future<void> _recheck() async => _set(
    await _pack.isInstalled()
        ? AutoTagPackStatus.installed
        : AutoTagPackStatus.notInstalled,
  );

  Future<void> install() async {
    if (_status == AutoTagPackStatus.downloading) return;
    _lastError = null;
    _received = 0;
    _notifiedAt = 0;
    final cancel = _cancel = AutoTagPackCancelToken();
    _set(AutoTagPackStatus.downloading);
    try {
      await _installer.install(
        cancel: cancel,
        onProgress: (received, total) {
          _received = received;
          // ~1 notification par Mo : assez fluide, sans reconstruire l'écran à
          // chaque paquet réseau.
          if (received - _notifiedAt >= (1 << 20) || received == total) {
            _notifiedAt = received;
            if (!_disposed) notifyListeners();
          }
        },
      );
      _cancel = null;
      _set(AutoTagPackStatus.installed);
      onInstalled?.call();
    } on AutoTagPackCancelled {
      _cancel = null;
      await _recheck();
    } catch (e) {
      _cancel = null;
      _lastError = e;
      await _recheck();
    }
  }

  void cancel() => _cancel?.cancel();

  Future<void> remove() async {
    if (_status == AutoTagPackStatus.downloading) return;
    await _installer.remove();
    await _recheck();
  }

  void _set(AutoTagPackStatus status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }
}
