import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';
import '../theme/app_theme.dart';
import '../../features/sampler/presentation/screens/sampler_screen.dart';
import 'app_services.dart';

/// Widget racine de l'application
class SoundboardApp extends StatefulWidget {
  final AppServices services;

  const SoundboardApp({
    super.key,
    required this.services,
  });

  @override
  State<SoundboardApp> createState() => _SoundboardAppState();
}

/// Largeur max des snackbars — au-delà, elles paraissent démesurées sur un
/// écran de bureau large ; en dessous, on laisse la largeur s'adapter pour
/// ne pas déborder sur un écran de téléphone étroit.
const double _maxSnackBarWidth = 420;

class _SoundboardAppState extends State<SoundboardApp>
    with WindowListener, WidgetsBindingObserver {
  static bool get _isWindowsDesktop => !kIsWeb && Platform.isWindows;

  /// Bornes de la fenêtre avant passage en plein écran — `null` hors plein
  /// écran. Sert à restaurer taille/position exactes à la sortie.
  Rect? _boundsBeforeFullScreen;

  /// Style Win32 (`GWL_STYLE`) avant retrait de `WS_THICKFRAME`/
  /// `WS_MAXIMIZEBOX` — à restaurer à la sortie du plein écran.
  int? _windowStyleBeforeFullScreen;

  /// La fenêtre était-elle déjà maximisée avant le passage en plein écran ?
  /// Si non, on la maximise nous-mêmes avant le reste (voir `_enterFullScreen`)
  /// et on la restaure en sortant.
  bool _wasMaximizedBeforeFullScreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_isWindowsDesktop) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
      windowManager.addListener(this);
      // Rouvre l'app dans le dernier état plein écran/fenêtré connu.
      if (widget.services.appPreferences.isWindowsFullScreen) {
        unawaited(
          _enterFullScreen().then((_) {
            if (mounted) setState(() {});
          }),
        );
      }
    }
  }

  /// Retour au premier plan : c'est le moment le plus probable où Drive a bougé
  /// sans nous (fichiers déposés depuis un navigateur ou un téléphone). On ne
  /// fait que rapporter l'état — l'anti-rebond, le Mode Spectacle et le verrou
  /// de passe sont du ressort d'`AutoSyncCoordinator`.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final coordinator = widget.services.autoSyncCoordinator;
    switch (state) {
      case AppLifecycleState.resumed:
        coordinator.onAppResumed();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        coordinator.onAppBackgrounded();
      case AppLifecycleState.inactive:
        // Desktop : la fenêtre a seulement perdu le focus (alt-tab) — souvent
        // pour aller justement déposer des fichiers sur Drive. La veille
        // continue de tourner.
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isWindowsDesktop) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
      windowManager.removeListener(this);
      // Filet de sécurité si l'app se ferme pendant le plein écran : la barre
      // des tâches Windows ne doit pas rester masquée après coup.
      if (_boundsBeforeFullScreen != null) {
        _setWindowsTaskbarVisible(true);
      }
    }
    widget.services.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleFullScreen();
      return true;
    }
    return false;
  }

  // La barre des tâches doit réapparaître dès que la fenêtre perd le focus
  // (Alt-Tab, touche Windows) — sinon Explorer la restaure lui-même dans un
  // état visuellement cassé (transparente) puisqu'on l'avait masquée à la
  // main. On la re-masque au retour du focus si toujours en plein écran.
  @override
  void onWindowBlur() {
    if (_boundsBeforeFullScreen != null) {
      _setWindowsTaskbarVisible(true);
    }
  }

  @override
  void onWindowFocus() {
    if (_boundsBeforeFullScreen != null) {
      _setWindowsTaskbarVisible(false);
    }
  }

  Future<void> _toggleFullScreen() async {
    if (_boundsBeforeFullScreen == null) {
      await _enterFullScreen();
    } else {
      await _exitFullScreen();
    }
    await widget.services.appPreferences.setWindowsFullScreen(
      _boundsBeforeFullScreen != null,
    );
    if (mounted) setState(() {});
  }

  Future<void> _quitApp() async {
    await windowManager.close();
  }

  // On évite `windowManager.setFullScreen` : sa restauration native sous
  // Windows ne redimensionne pas toujours la vue Flutter enfant quand la
  // fenêtre n'était pas maximisée avant le passage en plein écran (le
  // rattrapage interne du plugin n'est déclenché que dans le cas maximisé →
  // voir windows/window_manager.cpp de la dépendance, ForceChildRefresh
  // appelé uniquement sur SIZE_MAXIMIZED/SIZE_RESTORED). On étend donc la
  // fenêtre nous-mêmes aux bornes du moniteur, ce qui passe toujours par un
  // SetWindowPos explicite avec une vraie taille.
  Future<void> _enterFullScreen() async {
    final hwnd = _mainWindowHandle();
    final bounds = await windowManager.getBounds();
    // Sans passer par l'état maximisé d'abord, la fenêtre garde l'ombre
    // portée / bordure de redimensionnement invisible que DWM dessine autour
    // des fenêtres WS_THICKFRAME en état restauré — visible en plein écran
    // comme un liseré sur les bords. Une fenêtre maximisée n'a pas cette
    // marge (Windows la retire nativement), donc on maximise d'abord.
    _wasMaximizedBeforeFullScreen = await windowManager.isMaximized();
    if (!_wasMaximizedBeforeFullScreen) {
      await windowManager.maximize();
    }
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    // Tant que la fenêtre garde WS_THICKFRAME/WS_MAXIMIZEBOX, Windows la
    // re-snap silencieusement sur la zone de travail (moniteur moins barre
    // des tâches) dès qu'elle couvre exactement les bornes du moniteur —
    // d'où le trou à la hauteur de la barre. On retire ces styles avant
    // de redimensionner, comme le fait le SetFullScreen natif du plugin.
    if (hwnd != null) {
      final style = win32.GetWindowLongPtr(hwnd, win32.GWL_STYLE);
      _windowStyleBeforeFullScreen = style;
      win32.SetWindowLongPtr(
        hwnd,
        win32.GWL_STYLE,
        style & ~(win32.WS_THICKFRAME | win32.WS_MAXIMIZEBOX),
      );
      _forceFrameRefresh(hwnd);
    }
    await windowManager.setBounds(_primaryMonitorBounds());
    _setWindowsTaskbarVisible(false);
    _boundsBeforeFullScreen = bounds;
  }

  Future<void> _exitFullScreen() async {
    final hwnd = _mainWindowHandle();
    final bounds = _boundsBeforeFullScreen!;
    _boundsBeforeFullScreen = null;
    _setWindowsTaskbarVisible(true);
    final style = _windowStyleBeforeFullScreen;
    if (hwnd != null && style != null) {
      win32.SetWindowLongPtr(hwnd, win32.GWL_STYLE, style);
      _forceFrameRefresh(hwnd);
      _windowStyleBeforeFullScreen = null;
    }
    if (!_wasMaximizedBeforeFullScreen) {
      await windowManager.unmaximize();
    }
    await windowManager.setBounds(bounds);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
  }

  int? _mainWindowHandle() {
    final classNamePtr = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    try {
      final hwnd = win32.FindWindow(classNamePtr, nullptr);
      return hwnd == 0 ? null : hwnd;
    } finally {
      calloc.free(classNamePtr);
    }
  }

  /// Recalcule la zone non cliente après un changement de style (`GWL_STYLE`)
  /// sans déplacer/redimensionner la fenêtre — requis par Win32 pour que le
  /// nouveau style prenne effet visuellement.
  void _forceFrameRefresh(int hwnd) {
    win32.SetWindowPos(
      hwnd,
      0,
      0,
      0,
      0,
      0,
      win32.SWP_NOMOVE |
          win32.SWP_NOSIZE |
          win32.SWP_NOZORDER |
          win32.SWP_FRAMECHANGED,
    );
  }

  // Bornes complètes du moniteur principal (`rcMonitor`, pas `rcWork` —
  // celui-ci exclut la zone de la barre des tâches, ce qui laissait un trou
  // à l'écran une fois la barre masquée). On interroge Win32 directement
  // plutôt que `screen_retriever` : son calcul de `Display.size` soustrait
  // la position de la zone de travail au lieu d'utiliser `rcMonitor` telle
  // quelle, ce qui rognait la hauteur disponible.
  Rect _primaryMonitorBounds() {
    final monitor = win32.MonitorFromWindow(
      win32.GetDesktopWindow(),
      win32.MONITOR_DEFAULTTOPRIMARY,
    );
    final info = calloc<win32.MONITORINFO>();
    try {
      info.ref.cbSize = sizeOf<win32.MONITORINFO>();
      win32.GetMonitorInfo(monitor, info);
      final rect = info.ref.rcMonitor;
      final devicePixelRatio = windowManager.getDevicePixelRatio();
      return Rect.fromLTRB(
        rect.left / devicePixelRatio,
        rect.top / devicePixelRatio,
        rect.right / devicePixelRatio,
        rect.bottom / devicePixelRatio,
      );
    } finally {
      calloc.free(info);
    }
  }

  // `window_manager` n'a pas d'API pour masquer la barre des tâches elle-même
  // (`setSkipTaskbar` ne fait que retirer l'icône de la barre, pas la barre) —
  // appel Win32 direct sur la fenêtre `Shell_TrayWnd` de l'explorateur.
  void _setWindowsTaskbarVisible(bool visible) {
    final classNamePtr = 'Shell_TrayWnd'.toNativeUtf16();
    try {
      final hwnd = win32.FindWindow(classNamePtr, nullptr);
      if (hwnd != 0) {
        win32.ShowWindow(hwnd, visible ? win32.SW_SHOW : win32.SW_HIDE);
      }
    } finally {
      calloc.free(classNamePtr);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stage Cue - Soundboard',
      theme: AppTheme.darkTheme,
      builder: (context, child) {
        final theme = Theme.of(context);
        final availableWidth = MediaQuery.sizeOf(context).width - 48;
        final snackBarWidth = availableWidth.clamp(0, _maxSnackBarWidth).toDouble();
        return Theme(
          data: theme.copyWith(
            snackBarTheme: theme.snackBarTheme.copyWith(width: snackBarWidth),
          ),
          child: child!,
        );
      },
      home: SamplerScreen(
        services: widget.services,
        isWindowsFullScreen:
            _isWindowsDesktop ? _boundsBeforeFullScreen != null : null,
        onToggleWindowsFullScreen:
            _isWindowsDesktop ? () => unawaited(_toggleFullScreen()) : null,
        onQuitApp: _isWindowsDesktop ? () => unawaited(_quitApp()) : null,
      ),
    );
  }
}

