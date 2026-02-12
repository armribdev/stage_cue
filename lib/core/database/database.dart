import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'sounds.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Sounds,
  SoundBoards,
  WatchedPaths,
  BoardSounds,
  TagCategories,
  TagItems,
  SoundTags,
  TagAliases,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await _seedDefaultTagsIfEmpty();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          // 1. Créer la nouvelle table WatchedPaths
          await m.createTable(watchedPaths); 

          // 2. Pour la table Sounds
          await m.deleteTable(sounds.actualTableName);
          await m.createTable(sounds);
        }
        if (from < 4) {
          // Créer la table des soundboards
          await m.createTable(soundBoards);
          final defaultBoardId = await into(soundBoards).insert(
            SoundBoardsCompanion.insert(
              name: 'Board 1',
              createdAt: Value(DateTime.now()),
            ),
          );

          if (from >= 3) {
            // Migration vers la nouvelle structure de board_sounds
            await customStatement('ALTER TABLE board_sounds RENAME TO board_sounds_old');
            await m.createTable(boardSounds);
            await customStatement('''
              INSERT INTO board_sounds (board_id, sound_id, added_at)
              SELECT $defaultBoardId, sound_id, added_at
              FROM board_sounds_old
            ''');
            await customStatement('DROP TABLE board_sounds_old');
          } else {
            await m.createTable(boardSounds);
          }
        }
        if (from < 5) {
          await m.addColumn(sounds, sounds.color);
          await m.addColumn(sounds, sounds.volume);
        }
        if (from < 6) {
          await m.addColumn(
            sounds,
            sounds.displayName as GeneratedColumn<Object>,
          );
        }
        if (from < 7) {
          await m.createTable(tagCategories);
          await m.createTable(tagItems);
          await m.createTable(soundTags);
          await m.createTable(tagAliases);
          await _seedDefaultTagsIfEmpty();
        }
      },
    );
  }

  Future<void> _seedDefaultTagsIfEmpty() async {
    final existingResult = await customSelect(
      'SELECT COUNT(*) AS c FROM tag_categories',
    ).getSingle();
    if (existingResult.read<int>('c') > 0) {
      return;
    }

    await transaction(() async {
      Future<void> insertCategory({
        required String name,
        required int color,
        required int sortOrder,
        required String description,
      }) async {
        await customStatement(
          'INSERT INTO tag_categories (name, color, sort_order, description) VALUES (?, ?, ?, ?)',
          [name, color, sortOrder, description],
        );
      }

      await insertCategory(
        name: 'ACTION',
        color: 0xFFFF5722,
        sortOrder: 1,
        description: 'Verbes et gestes associés aux actions des comédiens.',
      );
      await insertCategory(
        name: 'OBJET',
        color: 0xFF2196F3,
        sortOrder: 2,
        description: 'Accessoires utilisés ou évoqués dans la scène.',
      );
      await insertCategory(
        name: 'MATIERE',
        color: 0xFF4CAF50,
        sortOrder: 3,
        description: 'Texture sonore quand l’objet précis manque.',
      );
      await insertCategory(
        name: 'AMBIANCE',
        color: 0xFF7E57C2,
        sortOrder: 4,
        description: 'Décors sonores.',
      );
      await insertCategory(
        name: 'EMOTION_STYLE',
        color: 0xFFE91E63,
        sortOrder: 5,
        description: 'Couleur émotionnelle ou style de scène.',
      );

      Future<int> getCategoryId(String name) async {
        final row = await customSelect(
          'SELECT id FROM tag_categories WHERE name = ? LIMIT 1',
          variables: [Variable<String>(name)],
        ).getSingle();
        return row.read<int>('id');
      }

      final tagByName = <String, int>{};
      Future<void> insertTag(String name, String categoryName) async {
        final categoryId = await getCategoryId(categoryName);
        await customStatement(
          'INSERT INTO tags (category_id, name, normalized_name) VALUES (?, ?, ?)',
          [categoryId, name, _normalize(name)],
        );
        final row = await customSelect(
          'SELECT id FROM tags WHERE name = ? LIMIT 1',
          variables: [Variable<String>(name)],
        ).getSingle();
        tagByName[name] = row.read<int>('id');
      }

      // ACTION
      await insertTag('Casser', 'ACTION');
      await insertTag('Claquer', 'ACTION');
      await insertTag('Ouvrir', 'ACTION');
      await insertTag('Fermer', 'ACTION');
      await insertTag('Impact', 'ACTION');
      await insertTag('Glisser', 'ACTION');
      await insertTag('Frapper', 'ACTION');
      await insertTag('Exploser', 'ACTION');
      await insertTag('Actionner', 'ACTION');
      await insertTag('Marcher', 'ACTION');
      await insertTag('Courir', 'ACTION');
      await insertTag('Rire', 'ACTION');
      await insertTag('Pleurer', 'ACTION');
      await insertTag('Crier', 'ACTION');
      await insertTag('Chuchoter', 'ACTION');
      await insertTag('Siffler', 'ACTION');
      await insertTag('Applaudir', 'ACTION');
      // OBJET
      await insertTag('Porte', 'OBJET');
      await insertTag('Téléphone', 'OBJET');
      await insertTag('Voiture', 'OBJET');
      await insertTag('Arme', 'OBJET');
      await insertTag('Verre', 'OBJET');
      await insertTag('Clés', 'OBJET');
      await insertTag('Outil', 'OBJET');
      await insertTag('Cuisine', 'OBJET');
      await insertTag('Chaise', 'OBJET');
      await insertTag('Table', 'OBJET');
      await insertTag('Fenêtre', 'OBJET');
      await insertTag('Livre', 'OBJET');
      await insertTag('Lit', 'OBJET');
      // MATIERE
      await insertTag('Bois', 'MATIERE');
      await insertTag('Métal', 'MATIERE');
      await insertTag('Verre', 'MATIERE');
      await insertTag('Eau', 'MATIERE');
      await insertTag('Papier', 'MATIERE');
      await insertTag('Gravier', 'MATIERE');
      await insertTag('Électronique', 'MATIERE');
      await insertTag('Plastique', 'MATIERE');
      await insertTag('Tissu', 'MATIERE');
      await insertTag('Pierre', 'MATIERE');
      await insertTag('Caoutchouc', 'MATIERE');
      // AMBIANCE
      await insertTag('Nature', 'AMBIANCE');
      await insertTag('Urbain', 'AMBIANCE');
      await insertTag('Public', 'AMBIANCE');
      await insertTag('Horreur', 'AMBIANCE');
      await insertTag('Transport', 'AMBIANCE');
      await insertTag('Médiéval', 'AMBIANCE');
      await insertTag('Fantastique', 'AMBIANCE');
      await insertTag('Antiquité', 'AMBIANCE');
      await insertTag('Renaissance', 'AMBIANCE');
      await insertTag('Époque victorienne', 'AMBIANCE');
      await insertTag('Années 20', 'AMBIANCE');
      await insertTag('Années 50', 'AMBIANCE');
      await insertTag('Années 80', 'AMBIANCE');
      await insertTag('Futuriste', 'AMBIANCE');
      await insertTag('Intérieur', 'AMBIANCE');
      await insertTag('Extérieur', 'AMBIANCE');
      await insertTag('Foule', 'AMBIANCE');
      await insertTag('Silence', 'AMBIANCE');
      await insertTag('Pluie', 'AMBIANCE');
      await insertTag('Orage', 'AMBIANCE');
      await insertTag('Mer', 'AMBIANCE');
      await insertTag('Forêt', 'AMBIANCE');
      await insertTag('Nuit', 'AMBIANCE');
      await insertTag('Jour', 'AMBIANCE');
      // EMOTION_STYLE
      await insertTag('Comédie', 'EMOTION_STYLE');
      await insertTag('Tension', 'EMOTION_STYLE');
      await insertTag('Magie', 'EMOTION_STYLE');
      await insertTag('Urgence', 'EMOTION_STYLE');
      await insertTag('Romantique', 'EMOTION_STYLE');
      await insertTag('Triste', 'EMOTION_STYLE');
      await insertTag('Épique', 'EMOTION_STYLE');
      await insertTag('Drame', 'EMOTION_STYLE');
      await insertTag('Mystérieux', 'EMOTION_STYLE');
      await insertTag('Oppressant', 'EMOTION_STYLE');
      await insertTag('Sombre', 'EMOTION_STYLE');
      await insertTag('Léger', 'EMOTION_STYLE');
      await insertTag('Poétique', 'EMOTION_STYLE');

      Future<void> insertAlias(String alias, String tagName) async {
        final tagId = tagByName[tagName]!;
        await customStatement(
          'INSERT INTO tag_aliases (tag_id, alias, normalized_alias) VALUES (?, ?, ?)',
          [tagId, alias, _normalize(alias)],
        );
      }

      await insertAlias('tomber', 'Impact');
      await insertAlias('chute', 'Impact');
      await insertAlias('heurter', 'Impact');
      await insertAlias('impact', 'Impact');
      await insertAlias('briser', 'Casser');
      await insertAlias('coup de feu', 'Exploser');
      await insertAlias('tir', 'Exploser');
      await insertAlias('détonation', 'Exploser');
      await insertAlias('explosion', 'Exploser');
      await insertAlias('déraper', 'Glisser');
      await insertAlias('glissement', 'Glisser');
      await insertAlias('toquer', 'Frapper');
      await insertAlias('gifle', 'Claquer');
      await insertAlias('porte qui claque', 'Claquer');
      await insertAlias('bris de verre', 'Casser');
      await insertAlias('verre cassé', 'Casser');
      await insertAlias('liquide', 'Eau');
      await insertAlias('plastique', 'Plastique');
      await insertAlias('synthétique', 'Plastique');
      await insertAlias('terre', 'Gravier');
      await insertAlias('cailloux', 'Gravier');
      await insertAlias('caoutchouc', 'Caoutchouc');
      await insertAlias('mystère', 'Mystérieux');
      await insertAlias('fantasy', 'Fantastique');
      await insertAlias('ville', 'Urbain');
      await insertAlias('rue', 'Urbain');
      await insertAlias('extérieur', 'Extérieur');
      await insertAlias('intérieur', 'Intérieur');
      await insertAlias('applaudissements', 'Applaudir');
      await insertAlias('rire', 'Rire');
      await insertAlias('rires', 'Rire');
      await insertAlias('pleurs', 'Pleurer');
      await insertAlias('crier', 'Crier');
      await insertAlias('hurler', 'Crier');
      await insertAlias('chuchotement', 'Chuchoter');
      await insertAlias('sifflement', 'Siffler');
      await insertAlias('pas', 'Marcher');
      await insertAlias('course', 'Courir');
      await insertAlias('auto', 'Voiture');
      await insertAlias('bagnole', 'Voiture');
      await insertAlias('portable', 'Téléphone');
      await insertAlias('téléphone portable', 'Téléphone');
      await insertAlias('clef', 'Clés');
      await insertAlias('clé', 'Clés');
      await insertAlias('forêt', 'Forêt');
      await insertAlias('pluie', 'Pluie');
      await insertAlias('orage', 'Orage');
      await insertAlias('mer', 'Mer');
      await insertAlias('nuit', 'Nuit');
      await insertAlias('jour', 'Jour');
      await insertAlias('sf', 'Futuriste');
      await insertAlias('science fiction', 'Futuriste');
      await insertAlias('science-fiction', 'Futuriste');
      await insertAlias('cartoon', 'Comédie');
      await insertAlias('burlesque', 'Comédie');
      await insertAlias('suspense', 'Tension');
      await insertAlias('féerie', 'Magie');
      await insertAlias('mélancolique', 'Triste');
      await insertAlias('héroïque', 'Épique');
      await insertAlias('dramatique', 'Drame');
      await insertAlias('tragique', 'Drame');
      await insertAlias('enjoué', 'Léger');
    });
  }

  String _normalize(String value) {
    final lower = value.trim().toLowerCase();
    const replacements = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'á': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ì': 'i',
      'í': 'i',
      'ô': 'o',
      'ö': 'o',
      'ò': 'o',
      'ó': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ú': 'u',
      'ÿ': 'y',
      'œ': 'oe',
      'æ': 'ae',
    };
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(replacements[char] ?? char);
    }
    return buffer.toString();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // Initialiser les bibliothèques natives SQLite sur Android/iOS
    if (Platform.isAndroid || Platform.isIOS) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }
    
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
