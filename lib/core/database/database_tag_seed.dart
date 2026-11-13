part of 'database.dart';

/// Tags ajoutés après le seed initial : catégorie → (nom du tag → alias de
/// recherche). Voir `docs/tags.md` pour le rôle de chaque catégorie.
///
/// - MUSIQUE décrit ce qui distingue une musique à l'usage (voix, tempo), pas
///   l'instrumentation : l'ambiance se pose avec EMOTION_STYLE.
/// - Une entrée dont le tag existe déjà (Magie, Romantique) n'ajoute que ses
///   alias : `INSERT OR IGNORE` sur la clé d'unicité des tags.
const Map<String, Map<String, List<String>>> _extraTagCatalog = {
  'MUSIQUE': {
    'Chant': ['voix', 'vocal', 'chanson', 'chanté', 'paroles'],
    'Instrumental': ['sans paroles', 'sans voix'],
    'Lent': ['slow', 'tempo lent', 'très lent'],
    'Rythmé': ['rapide', 'dansant', 'tempo rapide'],
  },
  'EMOTION_STYLE': {
    'Joyeux': ['joie', 'gai', 'heureux', 'festif'],
    'Énergique': ['dynamique', 'entraînant'],
    'Nostalgique': ['nostalgie'],
    'Angoisse': ['angoissant', 'anxiété', 'peur'],
    'Calme': ['paisible', 'serein', 'apaisant', 'relaxant'],
    'Magie': ['merveilleux'],
    'Romantique': ['amour', 'sensuel'],
  },
};

/// Tags d'instrumentation posés par la v41 puis retirés en v42 (nom normalisé).
/// Seuls ceux qu'aucun son n'utilise sont supprimés.
const List<String> _withdrawnInstrumentTags = [
  'piano',
  'orchestral',
  'cordes',
  'electro',
  'drone',
  'guitare',
];

/// Tags par défaut posés à la création de la base et complétés ensuite
/// (`docs/tags.md`) : tous idempotents, rejoués sans risque à chaque besoin.
extension _AppDatabaseTagSeed on AppDatabase {
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
      await insertCategory(
        name: 'MUSIQUE',
        color: 0xFF00BCD4,
        sortOrder: 6,
        description: 'Rôle ou fonction de la musique dans la scène.',
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
      // MUSIQUE
      await insertTag('Musique d\'ambiance', 'MUSIQUE');

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
      await insertAlias('fond musical', 'Musique d\'ambiance');
      await insertAlias('musique de fond', 'Musique d\'ambiance');
      await insertAlias('ambiance musicale', 'Musique d\'ambiance');
      await insertAlias('instrumental', 'Musique d\'ambiance');
    });
  }

  /// Catégorie MUSIQUE + tag « Musique d'ambiance » pour les bases existantes.
  Future<void> _ensureMusicCategoryTags() async {
    const categoryName = 'MUSIQUE';
    const tagName = 'Musique d\'ambiance';
    const tagDescription =
        'Musique de fond pour installer une atmosphère, souvent sans paroles.';

    await transaction(() async {
      var categoryRow = await customSelect(
        'SELECT id FROM tag_categories WHERE name = ? LIMIT 1',
        variables: [Variable<String>(categoryName)],
      ).getSingleOrNull();

      if (categoryRow == null) {
        await customStatement(
          'INSERT INTO tag_categories (name, color, sort_order, description) '
          'VALUES (?, ?, ?, ?)',
          [
            categoryName,
            0xFF00BCD4,
            6,
            'Rôle ou fonction de la musique dans la scène.',
          ],
        );
        categoryRow = await customSelect(
          'SELECT id FROM tag_categories WHERE name = ? LIMIT 1',
          variables: [Variable<String>(categoryName)],
        ).getSingle();
      }

      final categoryId = categoryRow.read<int>('id');
      final normalizedTag = _normalize(tagName);
      var tagRow = await customSelect(
        'SELECT id FROM tags WHERE category_id = ? AND normalized_name = ? LIMIT 1',
        variables: [Variable<int>(categoryId), Variable<String>(normalizedTag)],
      ).getSingleOrNull();

      if (tagRow == null) {
        await customStatement(
          'INSERT INTO tags (category_id, name, normalized_name, description) '
          'VALUES (?, ?, ?, ?)',
          [categoryId, tagName, normalizedTag, tagDescription],
        );
        tagRow = await customSelect(
          'SELECT id FROM tags WHERE category_id = ? AND normalized_name = ? LIMIT 1',
          variables: [
            Variable<int>(categoryId),
            Variable<String>(normalizedTag),
          ],
        ).getSingle();
      }

      final tagId = tagRow.read<int>('id');
      Future<void> ensureAlias(String alias) async {
        final normalizedAlias = _normalize(alias);
        final existing = await customSelect(
          'SELECT id FROM tag_aliases WHERE tag_id = ? AND normalized_alias = ? LIMIT 1',
          variables: [Variable<int>(tagId), Variable<String>(normalizedAlias)],
        ).getSingleOrNull();
        if (existing != null) return;
        await customStatement(
          'INSERT INTO tag_aliases (tag_id, alias, normalized_alias) VALUES (?, ?, ?)',
          [tagId, alias, normalizedAlias],
        );
      }

      await ensureAlias('fond musical');
      await ensureAlias('musique de fond');
      await ensureAlias('ambiance musicale');
      await ensureAlias('instrumental');
    });
  }

  /// Complète le catalogue de tags avec [_extraTagCatalog], sans créer de
  /// catégorie (hors MUSIQUE, garantie par [_ensureMusicCategoryTags]).
  ///
  /// Idempotent (`INSERT OR IGNORE` sur les clés d'unicité `tags` et
  /// `tag_aliases`) : sert à la fois à l'installation neuve et à la migration
  /// des bases existantes. Un alias déjà pris par un autre tag est ignoré, il
  /// ne fait jamais échouer la migration.
  Future<void> _ensureExtraTags() async {
    await transaction(() async {
      // Garantit la catégorie (bases dont la v32 n'aurait pas tourné).
      await _ensureMusicCategoryTags();

      for (final category in _extraTagCatalog.entries) {
        final categoryRow = await customSelect(
          'SELECT id FROM tag_categories WHERE name = ? LIMIT 1',
          variables: [Variable<String>(category.key)],
        ).getSingleOrNull();
        if (categoryRow == null) {
          // Catégorie supprimée à la main : on ne la recrée pas (couleur et
          // ordre d'affichage sont un choix), mais on ne se tait pas.
          AppLog.warn(
            'Catégorie de tags « ${category.key} » absente : '
            '${category.value.length} tag(s) du catalogue non ajouté(s).',
          );
          continue;
        }
        final categoryId = categoryRow.read<int>('id');

        for (final entry in category.value.entries) {
          final normalizedTag = _normalize(entry.key);
          await customStatement(
            'INSERT OR IGNORE INTO tags (category_id, name, normalized_name) '
            'VALUES (?, ?, ?)',
            [categoryId, entry.key, normalizedTag],
          );
          final tagRow = await customSelect(
            'SELECT id FROM tags WHERE category_id = ? AND normalized_name = ? '
            'LIMIT 1',
            variables: [
              Variable<int>(categoryId),
              Variable<String>(normalizedTag),
            ],
          ).getSingle();
          final tagId = tagRow.read<int>('id');
          for (final alias in entry.value) {
            await customStatement(
              'INSERT OR IGNORE INTO tag_aliases '
              '(tag_id, alias, normalized_alias) VALUES (?, ?, ?)',
              [tagId, alias, _normalize(alias)],
            );
          }
        }
      }
    });
  }

  /// Retire les tags d'instrumentation de la v41 ([_withdrawnInstrumentTags])
  /// qu'aucun son n'utilise, avec leurs alias. Ceux déjà posés sur un son sont
  /// conservés : les supprimer effacerait un tagging fait par l'utilisateur.
  ///
  /// Les clés étrangères ne sont pas activées (cf. `database.md`) : le
  /// `ON DELETE CASCADE` ne joue pas, les alias sont donc supprimés à la main.
  Future<void> _removeUnusedInstrumentTags() async {
    final placeholders = List.filled(
      _withdrawnInstrumentTags.length,
      '?',
    ).join(',');
    // Tags MUSIQUE retirés et non utilisés, réutilisé pour les alias puis les tags.
    final unused =
        'SELECT id FROM tags WHERE normalized_name IN ($placeholders) '
        "AND category_id = (SELECT id FROM tag_categories WHERE name = 'MUSIQUE') "
        'AND id NOT IN (SELECT tag_id FROM sound_tags)';
    final args = [
      for (final n in _withdrawnInstrumentTags) Variable<String>(n),
    ];

    await transaction(() async {
      await customUpdate(
        'DELETE FROM tag_aliases WHERE tag_id IN ($unused)',
        variables: args,
        updates: {tagAliases},
      );
      final removed = await customUpdate(
        'DELETE FROM tags WHERE id IN ($unused)',
        variables: args,
        updates: {tagItems},
      );
      AppLog.info(
        "Tags d'instrumentation retirés : $removed "
        '(ceux déjà posés sur un son sont conservés).',
      );
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
