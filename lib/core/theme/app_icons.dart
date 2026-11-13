import 'lucide_paths.dart';
import 'stroke_icon.dart';

/// Icônes de l'application — jeu Lucide à trait fin, **dessinées en tracés
/// vectoriels** ([StrokeIcon]) plutôt qu'en police : un glyphe de police est
/// rasterisé au pixel près par Skia, d'où des escaliers sur un trait de ~1 px
/// sous Windows à 100 %. Les tracés sont embarqués dans l'app
/// ([LucidePaths], généré par `tool/gen_lucide_paths.mjs`) : elle reste
/// utilisable backstage hors ligne.
///
/// Nommées par **concept** (`delete`, `cloudOff`…), pas par glyphe : changer
/// de jeu ou d'épaisseur se fait ici, en un seul endroit. Pour une nouvelle
/// icône, ajouter un concept ici (puis relancer le générateur) plutôt que
/// d'importer Lucide dans un écran, et ne jamais utiliser `Icons.*` (Material).
///
/// Lucide n'a pas de variante pleine : un état « actif » (case cochée…) se
/// distingue par la couleur ou un autre glyphe. Seule exception, l'étoile de
/// favori : `StrokeIcon(AppIcons.favorite, filled: true)` la remplit.
abstract final class AppIcons {
  // ── Actions flottantes d'un pad ───────────────────────────────────────────
  // Mêmes tracés que le reste du jeu, nommés à part : posées sans fond ni
  // bordure sur un pad de couleur arbitraire, elles pourront être ajustées
  // sans toucher aux autres usages.
  static const StrokeIconData padCue = StrokeIconData(LucidePaths.headphones);
  static const StrokeIconData padSounds = StrokeIconData(LucidePaths.listMusic);
  static const StrokeIconData padEdit = StrokeIconData(LucidePaths.pencil);
  static const StrokeIconData padRemove = StrokeIconData(LucidePaths.x);

  // ── Actions courantes ─────────────────────────────────────────────────────
  static const StrokeIconData add = StrokeIconData(LucidePaths.plus);
  static const StrokeIconData close = StrokeIconData(LucidePaths.x);
  static const StrokeIconData check = StrokeIconData(LucidePaths.check);
  static const StrokeIconData edit = StrokeIconData(LucidePaths.pencil);
  static const StrokeIconData copy = StrokeIconData(LucidePaths.copy);
  static const StrokeIconData delete = StrokeIconData(LucidePaths.trash2);
  static const StrokeIconData cut = StrokeIconData(LucidePaths.scissors);
  static const StrokeIconData refresh = StrokeIconData(LucidePaths.refreshCw);
  static const StrokeIconData search = StrokeIconData(LucidePaths.search);
  static const StrokeIconData swap = StrokeIconData(LucidePaths.arrowLeftRight);
  static const StrokeIconData more = StrokeIconData(
    LucidePaths.ellipsisVertical,
  );
  static const StrokeIconData settings = StrokeIconData(LucidePaths.settings);
  static const StrokeIconData menu = StrokeIconData(LucidePaths.menu);
  static const StrokeIconData tune = StrokeIconData(
    LucidePaths.slidersHorizontal,
  );
  static const StrokeIconData text = StrokeIconData(LucidePaths.type);
  static const StrokeIconData lock = StrokeIconData(LucidePaths.lock);
  static const StrokeIconData keyboard = StrokeIconData(LucidePaths.keyboard);

  // ── Navigation ────────────────────────────────────────────────────────────
  static const StrokeIconData back = StrokeIconData(LucidePaths.arrowLeft);
  static const StrokeIconData arrowUp = StrokeIconData(LucidePaths.arrowUp);
  static const StrokeIconData chevronRight = StrokeIconData(
    LucidePaths.chevronRight,
  );
  static const StrokeIconData chevronDown = StrokeIconData(
    LucidePaths.chevronDown,
  );
  static const StrokeIconData chevronUp = StrokeIconData(LucidePaths.chevronUp);
  static const StrokeIconData fullscreen = StrokeIconData(LucidePaths.maximize);
  static const StrokeIconData fullscreenExit = StrokeIconData(
    LucidePaths.minimize,
  );
  static const StrokeIconData logout = StrokeIconData(LucidePaths.logOut);
  static const StrokeIconData library = StrokeIconData(LucidePaths.libraryBig);
  static const StrokeIconData allSounds = StrokeIconData(
    LucidePaths.layoutGrid,
  );
  static const StrokeIconData theater = StrokeIconData(LucidePaths.drama);

  // ── États et retours ──────────────────────────────────────────────────────
  static const StrokeIconData info = StrokeIconData(LucidePaths.info);
  static const StrokeIconData help = StrokeIconData(LucidePaths.circleHelp);
  static const StrokeIconData error = StrokeIconData(LucidePaths.circleAlert);
  static const StrokeIconData warning = StrokeIconData(
    LucidePaths.triangleAlert,
  );
  static const StrokeIconData blocked = StrokeIconData(LucidePaths.ban);
  static const StrokeIconData checkCircle = StrokeIconData(
    LucidePaths.circleCheck,
  );
  static const StrokeIconData checkboxOn = StrokeIconData(
    LucidePaths.squareCheck,
  );
  static const StrokeIconData checkboxOff = StrokeIconData(LucidePaths.square);
  static const StrokeIconData visible = StrokeIconData(LucidePaths.eye);
  static const StrokeIconData hidden = StrokeIconData(LucidePaths.eyeOff);
  static const StrokeIconData favorite = StrokeIconData(LucidePaths.star);
  static const StrokeIconData sparkles = StrokeIconData(LucidePaths.sparkles);
  static const StrokeIconData offline = StrokeIconData(LucidePaths.zap);

  // ── Lecture et audio ──────────────────────────────────────────────────────
  static const StrokeIconData rewind = StrokeIconData(LucidePaths.rewind);
  static const StrokeIconData fastForward = StrokeIconData(
    LucidePaths.fastForward,
  );
  static const StrokeIconData shuffle = StrokeIconData(LucidePaths.shuffle);
  static const StrokeIconData repeatOne = StrokeIconData(LucidePaths.repeat1);
  static const StrokeIconData volumeOn = StrokeIconData(LucidePaths.volume2);
  static const StrokeIconData volumeOff = StrokeIconData(LucidePaths.volumeX);
  static const StrokeIconData headphones = StrokeIconData(
    LucidePaths.headphones,
  );
  static const StrokeIconData headphonesOff = StrokeIconData(
    LucidePaths.headphoneOff,
  );
  static const StrokeIconData onAir = StrokeIconData(LucidePaths.radio);
  static const StrokeIconData merge = StrokeIconData(LucidePaths.merge);

  // ── Types de son ──────────────────────────────────────────────────────────
  static const StrokeIconData soundEffect = StrokeIconData(
    LucidePaths.audioLines,
  );
  static const StrokeIconData music = StrokeIconData(LucidePaths.music);
  static const StrokeIconData ambiance = StrokeIconData(LucidePaths.waves);
  static const StrokeIconData queue = StrokeIconData(LucidePaths.listMusic);
  static const StrokeIconData playlistAdd = StrokeIconData(
    LucidePaths.listPlus,
  );
  static const StrokeIconData layers = StrokeIconData(LucidePaths.layers);
  static const StrokeIconData audioFile = StrokeIconData(LucidePaths.fileAudio);

  // ── Dossiers, Drive et cache ──────────────────────────────────────────────
  static const StrokeIconData folder = StrokeIconData(LucidePaths.folder);
  static const StrokeIconData folderOpen = StrokeIconData(
    LucidePaths.folderOpen,
  );
  static const StrokeIconData folders = StrokeIconData(LucidePaths.folders);
  static const StrokeIconData folderOff = StrokeIconData(LucidePaths.folderX);
  static const StrokeIconData folderShared = StrokeIconData(
    LucidePaths.folderSymlink,
  );
  static const StrokeIconData cloud = StrokeIconData(LucidePaths.cloud);
  static const StrokeIconData cloudOff = StrokeIconData(LucidePaths.cloudOff);
  static const StrokeIconData cloudDone = StrokeIconData(
    LucidePaths.cloudCheck,
  );
  static const StrokeIconData cloudDownload = StrokeIconData(
    LucidePaths.cloudDownload,
  );
  static const StrokeIconData download = StrokeIconData(LucidePaths.download);
  static const StrokeIconData downloading = StrokeIconData(
    LucidePaths.circleArrowDown,
  );
  static const StrokeIconData downloadDone = StrokeIconData(
    LucidePaths.circleCheckBig,
  );
  static const StrokeIconData appUpdate = StrokeIconData(
    LucidePaths.monitorDown,
  );
  static const StrokeIconData storage = StrokeIconData(LucidePaths.hardDrive);
  static const StrokeIconData diagnostic = StrokeIconData(LucidePaths.receipt);
  static const StrokeIconData smartphone = StrokeIconData(
    LucidePaths.smartphone,
  );

  // ── Comptes ───────────────────────────────────────────────────────────────
  static const StrokeIconData account = StrokeIconData(LucidePaths.circleUser);
  static const StrokeIconData person = StrokeIconData(LucidePaths.user);
  static const StrokeIconData groups = StrokeIconData(LucidePaths.users);
}
