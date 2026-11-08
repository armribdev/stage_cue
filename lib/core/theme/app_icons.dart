import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';
import 'package:lucide_icons_flutter/lucide_icons_400.dart';

/// Icônes de l'application — jeu Lucide à trait fin (graisse 300 ≈ 1,5 px sur
/// une grille de 24), police bundlée en local : l'app reste utilisable
/// backstage hors ligne.
///
/// Nommées par **concept** (`delete`, `cloudOff`…), pas par glyphe : changer
/// de jeu ou de graisse se fait ici, en un seul endroit. Pour une nouvelle
/// icône, ajouter un concept ici plutôt que d'importer Lucide dans un écran, et
/// ne jamais utiliser `Icons.*` (Material).
///
/// Lucide n'a pas de variante pleine : un état « actif » (favori, case cochée)
/// se distingue par la couleur ou un autre glyphe, pas par le remplissage.
abstract final class AppIcons {
  // ── Actions flottantes d'un pad (graisse 400) ─────────────────────────────
  // Posées sans fond ni bordure sur un pad de couleur arbitraire : à trait
  // 300 elles se lisent trop fines, d'où la graisse au-dessus du reste du jeu.
  static const IconData padCue = LucideIcons400.headphones;
  static const IconData padSounds = LucideIcons400.listMusic;
  static const IconData padEdit = LucideIcons400.pencil;
  static const IconData padRemove = LucideIcons400.x;

  // ── Actions courantes ─────────────────────────────────────────────────────
  static const IconData add = LucideIcons300.plus;
  static const IconData close = LucideIcons300.x;
  static const IconData check = LucideIcons300.check;
  static const IconData edit = LucideIcons300.pencil;
  static const IconData copy = LucideIcons300.copy;
  static const IconData delete = LucideIcons300.trash2;
  static const IconData cut = LucideIcons300.scissors;
  static const IconData refresh = LucideIcons300.refreshCw;
  static const IconData search = LucideIcons300.search;
  static const IconData swap = LucideIcons300.arrowLeftRight;
  static const IconData more = LucideIcons300.ellipsisVertical;
  static const IconData settings = LucideIcons300.settings;
  static const IconData menu = LucideIcons300.menu;
  static const IconData tune = LucideIcons300.slidersHorizontal;
  static const IconData text = LucideIcons300.type;
  static const IconData lock = LucideIcons300.lock;
  static const IconData keyboard = LucideIcons300.keyboard;

  // ── Navigation ────────────────────────────────────────────────────────────
  static const IconData back = LucideIcons300.arrowLeft;
  static const IconData arrowUp = LucideIcons300.arrowUp;
  static const IconData chevronRight = LucideIcons300.chevronRight;
  static const IconData chevronDown = LucideIcons300.chevronDown;
  static const IconData chevronUp = LucideIcons300.chevronUp;
  static const IconData fullscreen = LucideIcons300.maximize;
  static const IconData fullscreenExit = LucideIcons300.minimize;
  static const IconData logout = LucideIcons300.logOut;
  static const IconData library = LucideIcons300.libraryBig;
  static const IconData allSounds = LucideIcons300.layoutGrid;
  static const IconData theater = LucideIcons300.drama;

  // ── États et retours ──────────────────────────────────────────────────────
  static const IconData info = LucideIcons300.info;
  static const IconData help = LucideIcons300.circleHelp;
  static const IconData error = LucideIcons300.circleAlert;
  static const IconData warning = LucideIcons300.triangleAlert;
  static const IconData blocked = LucideIcons300.ban;
  static const IconData checkCircle = LucideIcons300.circleCheck;
  static const IconData checkboxOn = LucideIcons300.squareCheck;
  static const IconData checkboxOff = LucideIcons300.square;
  static const IconData visible = LucideIcons300.eye;
  static const IconData hidden = LucideIcons300.eyeOff;
  static const IconData favorite = LucideIcons300.star;
  static const IconData sparkles = LucideIcons300.sparkles;
  static const IconData offline = LucideIcons300.zap;

  // ── Lecture et audio ──────────────────────────────────────────────────────
  static const IconData rewind = LucideIcons300.rewind;
  static const IconData fastForward = LucideIcons300.fastForward;
  static const IconData shuffle = LucideIcons300.shuffle;
  static const IconData repeatOne = LucideIcons300.repeat1;
  static const IconData volumeOn = LucideIcons300.volume2;
  static const IconData volumeOff = LucideIcons300.volumeX;
  static const IconData headphones = LucideIcons300.headphones;
  static const IconData headphonesOff = LucideIcons300.headphoneOff;
  static const IconData onAir = LucideIcons300.radio;
  static const IconData merge = LucideIcons300.merge;

  // ── Types de son ──────────────────────────────────────────────────────────
  static const IconData soundEffect = LucideIcons300.audioLines;
  static const IconData music = LucideIcons300.music;
  static const IconData ambiance = LucideIcons300.waves;
  static const IconData queue = LucideIcons300.listMusic;
  static const IconData playlistAdd = LucideIcons300.listPlus;
  static const IconData layers = LucideIcons300.layers;
  static const IconData audioFile = LucideIcons300.fileAudio;

  // ── Dossiers, Drive et cache ──────────────────────────────────────────────
  static const IconData folder = LucideIcons300.folder;
  static const IconData folderOpen = LucideIcons300.folderOpen;
  static const IconData folders = LucideIcons300.folders;
  static const IconData folderOff = LucideIcons300.folderX;
  static const IconData folderShared = LucideIcons300.folderSymlink;
  static const IconData cloud = LucideIcons300.cloud;
  static const IconData cloudOff = LucideIcons300.cloudOff;
  static const IconData cloudDone = LucideIcons300.cloudCheck;
  static const IconData cloudDownload = LucideIcons300.cloudDownload;
  static const IconData download = LucideIcons300.download;
  static const IconData downloading = LucideIcons300.circleArrowDown;
  static const IconData downloadDone = LucideIcons300.circleCheckBig;
  static const IconData appUpdate = LucideIcons300.monitorDown;
  static const IconData storage = LucideIcons300.hardDrive;
  static const IconData diagnostic = LucideIcons300.receipt;
  static const IconData smartphone = LucideIcons300.smartphone;

  // ── Comptes ───────────────────────────────────────────────────────────────
  static const IconData account = LucideIcons300.circleUser;
  static const IconData person = LucideIcons300.user;
  static const IconData groups = LucideIcons300.users;
}
