part of 'database.dart';

/// Catégories de tags retirées → catégorie qui reçoit leurs tags (décision
/// 0040). Publique : l'import d'un snapshot d'un appareil pas encore à jour
/// y lit le nom d'une catégorie retirée, qu'il recréerait sinon.
const Map<String, String> retiredTagCategories = {'MUSIQUE': 'EMOTION_STYLE'};

/// Tags ajoutés après le seed initial : catégorie → (nom du tag → alias de
/// recherche). Voir `docs/tags.md` pour le rôle de chaque catégorie.
///
/// - Un tag est une **famille générique**, pas un nom que le titre du fichier
///   portera déjà : « train » est un alias de Véhicule, pas un tag (0040).
/// - Voix (Chant / Instrumental) et tempo (Lent / Rythmé) vivent dans
///   EMOTION_STYLE depuis la dissolution de MUSIQUE.
/// - Une entrée dont le tag existe déjà (Magie, Arme, Métal) n'ajoute que ses
///   alias : `INSERT OR IGNORE` sur la clé d'unicité des tags.
const Map<String, Map<String, List<String>>> _extraTagCatalog = {
  // Voix et Déplacement sont des familles : les verbes précis (applaudir,
  // chuchoter, marcher…) sont des alias, le titre du fichier les porte déjà.
  // Les autres actions (Ouvrir, Casser, Lancer…) restent des tags à part.
  'ACTION': {
    'Voix': [
      'rire',
      'rires',
      'laugh',
      'laughter',
      'giggle',
      'pleurer',
      'pleurs',
      'cry',
      'crying',
      'sob',
      'crier',
      'hurler',
      'cri',
      'cris',
      'scream',
      'shout',
      'yell',
      'chuchoter',
      'chuchotement',
      'whisper',
      'siffler',
      'sifflement',
      'whistle',
      'applaudir',
      'applaudissement',
      'applaudissements',
      'applause',
      'clapping',
      'clap',
    ],
    'Déplacement': [
      'marcher',
      'pas',
      'footsteps',
      'steps',
      'walking',
      'courir',
      'course',
      'run',
      'running',
      'sauter',
      'saut',
      'bondir',
      'glisser',
      'déraper',
      'glissement',
      'slide',
    ],
    'Lancer': ['jeter', 'projeter'],
    // Impact absorbe les coups (frapper), les détonations (exploser), les chocs
    // qui cassent (casser) et ceux qui claquent (claquer).
    'Impact': [
      'punch',
      'thud',
      'crash',
      'bump',
      'frapper',
      'toquer',
      'knock',
      'knocking',
      'exploser',
      'explode',
      'blast',
      'bomb',
      'gunshot',
      'bang',
      'coup de feu',
      'tir',
      'détonation',
      'explosion',
      'casser',
      'briser',
      'bris de verre',
      'verre cassé',
      'break',
      'shatter',
      'crack',
      'claquer',
      'gifle',
      'porte qui claque',
      'slam',
    ],
    'Ouvrir/Fermer': [
      'ouvrir',
      'fermer',
      'ouverture',
      'fermeture',
      'open',
      'close',
    ],
  },
  'OBJET': {
    'Arme': [
      'épée',
      'pistolet',
      'fusil',
      'couteau',
      'revolver',
      'gun',
      'sword',
      'knife',
      'pistol',
      'rifle',
    ],
    'Véhicule': [
      'moto',
      'train',
      'avion',
      'bateau',
      'camion',
      'bus',
      'vélo',
      'voiture',
      'auto',
      'bagnole',
      'car',
      'truck',
      'plane',
      'boat',
      'motorcycle',
    ],
    'Machine': [
      'moteur',
      'ordinateur',
      'radio',
      'télévision',
      'appareil',
      'aspirateur',
      'robot',
      'ascenseur',
      'ascenceur',
      'téléphone',
      'portable',
      'téléphone portable',
      'phone',
      'cellphone',
      'engine',
      'motor',
      'vacuum',
    ],
    'Sonnerie': [
      'cloche',
      'sonnette',
      'sonette',
      'klaxon',
      'buzzer',
      'bip',
      'réveil',
      'horloge',
      'carillon',
      'alarme',
      'ringing',
      'ringtone',
      'ring',
      'bell',
      'gong',
      'horn',
      'doorbell',
    ],
    'Contenant': ['bouteille', 'valise', 'coffre', 'sac', 'boîte'],
    'Meuble': ['armoire', 'tiroir', 'commode', 'chaise', 'table', 'lit'],
    'Outil': ['scie', 'établi', 'marteau'],
    'Animal': [
      'dog',
      'wolf',
      'cat',
      'pig',
      'duck',
      'horse',
      'frog',
      'seagull',
      'turkey',
      'bird',
      'chicken',
      'rooster',
      'cow',
      'sheep',
      'bark',
      'barking',
      'howl',
      'meow',
      'quack',
      'gobble',
      'animaux',
      'oiseaux',
      'birds',
      'chat',
      'chien',
      'cochon',
      'canard',
      'loup',
      'cheval',
      'grenouille',
      'mouette',
      'éléphant',
      'vache',
      'mouton',
      'poule',
      'coq',
    ],
  },
  'MATIERE': {
    'Bois': ['parquet', 'planche', 'wood', 'wooden'],
    'Métal': ['fer', 'acier', 'chaîne'],
    'Feu': ['flamme', 'brasier', 'crépitement', 'fire'],
    'Eau': ['river', 'water', 'splash', 'bubble', 'bubbles', 'drip'],
    'Glace': ['neige', 'givre'],
    'Sable': [],
    'Boue': ['bourbier'],
    'Cuir': [],
    'Verre': ['glass'],
    'Papier': ['paper'],
    'Gravier': ['gravel'],
    'Plastique': ['plastic'],
    'Tissu': ['cloth', 'fabric'],
    'Pierre': ['stone'],
    'Végétal': ['feuilles', 'herbe', 'branches', 'buisson'],
  },
  'AMBIANCE': {
    'Orage': ['tempête', 'thunder', 'storm'],
    'Pluie': ['rain'],
    'Nuit': ['night', 'crépuscule', 'soir', 'coucher de soleil'],
    'Jour': ['aube', 'lever du jour', 'matin'],
    'Mer': ['waves', 'ocean', 'sea'],
    'Médiéval': ['bardcore'],
    'Fantastique': ['fantôme'],
    'Public': ['café', 'banquet', 'bar', 'restaurant', 'foule', 'crowd'],
    'Intérieur': ['bureau', 'office', 'école', 'hôpital'],
    'Extérieur': ['jardin'],
    'Fête': ['soirée', 'bal', 'noël', 'christmas', 'cirque', 'foire', 'danse'],
    'Futuriste': [
      'cyberpunk',
      'espace',
      'spatial',
      'post-apocalyptique',
      'apocalypse',
      'postapo',
      'survie',
    ],
    'Souterrain': ['grotte', 'cave', 'catacombes', 'cachot'],
    'Sacré': [
      'église',
      'church',
      'temple',
      'religieux',
      'cathédrale',
      'chapelle',
    ],
    'Western': ['far west', 'cowboy'],
    'Polar': ['noir', 'film noir', 'enquête', 'détective'],
    'Années 30': ['thirties', '30s'],
    'Années 60': ['sixties', '60s'],
    'Années 70': ['seventies', '70s'],
    'Nature': [
      'jungle',
      'wildlife',
      'forêt',
      'forest',
      'campagne',
      'champs',
      'rural',
      'montagne',
      'désert',
    ],
    'Horreur': ['horror', 'scary', 'creepy'],
    'Années 90': ['nineties', '90s'],
  },
  'EMOTION_STYLE': {
    'Joyeux': ['joie', 'gai', 'heureux', 'festif', 'solaire', 'happy'],
    'Énergique': ['dynamique', 'entraînant'],
    'Nostalgique': ['nostalgie'],
    'Angoisse': ['angoissant', 'anxiété', 'peur'],
    'Calme': ['paisible', 'serein', 'apaisant', 'relaxant', 'relax', 'calm'],
    'Magie': ['merveilleux'],
    'Romantique': ['amour', 'sensuel'],
    'Menaçant': ['menace'],
    'Inquiétant': ['inquiétude'],
    'Lugubre': ['funèbre', 'macabre'],
    'Étrange': ['bizarre', 'insolite'],
    'Onirique': ['rêve', 'rêveur', 'planant', 'dream', 'rêverie'],
    'Solennel': ['cérémonie', 'officiel'],
    'Majestueux': ['grandiose', 'noble'],
    'Tendre': ['doux', 'douceur', 'affectueux'],
    'Combat': ['bataille', 'duel', 'baston', 'action'],
    'Poursuite': ['course-poursuite', 'traque'],
    'Victoire': ['triomphe', 'triomphant', 'succès'],
    'Triste': ['tristesse', 'mélancolie', 'sad'],
    'Urgence': ['danger', 'alerte', 'alert', 'alarm'],
    'Sombre': ['dark'],
    'Épique': ['epic'],
    'Colère': ['rage', 'furie', 'énervé', 'agressif'],
    'Aventure': ['exploration', 'quête', 'voyage', 'découverte'],
    'Lumineux': ['clair', 'radieux', 'éclatant'],
    'Remix': ['remixé', 'mix'],
    'Reprise': ['cover', 'covers'],
    'BO': [
      'bande originale',
      'ost',
      'soundtrack',
      'theme',
      'trailer',
      'opening',
      'générique',
    ],
    'Kitsch': ['kitsh', 'kitch', 'cheesy', 'ringard'],
    'Chant': ['voix', 'vocal', 'chanson', 'chanté', 'paroles'],
    'Instrumental': ['sans paroles', 'sans voix', 'karaoke'],
    'Lent': ['slow', 'tempo lent', 'très lent'],
    'Mystérieux': ['mystery'],
    'Comédie': ['comedy', 'funny'],
    'Rythmé': ['rapide', 'dansant', 'tempo rapide'],
    'Célèbre': [
      'connu',
      'populaire',
      'tube',
      'hit',
      'culte',
      'iconique',
      'reconnaissable',
    ],
  },
};

/// Tags trop précis absorbés par leur famille en v48 (décision 0040) :
/// (catégorie, tag) → (catégorie, tag d'accueil). Usages, suggestions et alias
/// suivent, même si le tag est posé sur des sons. Leur nom reste cherchable : il
/// figure comme alias du tag d'accueil dans [_extraTagCatalog].
const List<(String, String, String, String)> _mergedTags = [
  ('OBJET', 'Chaise', 'OBJET', 'Meuble'),
  ('OBJET', 'Table', 'OBJET', 'Meuble'),
  ('OBJET', 'Lit', 'OBJET', 'Meuble'),
  ('OBJET', 'Voiture', 'OBJET', 'Véhicule'),
  ('OBJET', 'Téléphone', 'OBJET', 'Machine'),
  // Même mot, même chose : la matière est le seul « Verre » conservé.
  ('OBJET', 'Verre', 'MATIERE', 'Verre'),
  // Actions : un verbe précis se lit dans le titre, il reste alias de sa famille.
  ('ACTION', 'Rire', 'ACTION', 'Voix'),
  ('ACTION', 'Pleurer', 'ACTION', 'Voix'),
  ('ACTION', 'Crier', 'ACTION', 'Voix'),
  ('ACTION', 'Chuchoter', 'ACTION', 'Voix'),
  ('ACTION', 'Siffler', 'ACTION', 'Voix'),
  ('ACTION', 'Applaudir', 'ACTION', 'Voix'),
  ('ACTION', 'Marcher', 'ACTION', 'Déplacement'),
  ('ACTION', 'Courir', 'ACTION', 'Déplacement'),
  ('ACTION', 'Sauter', 'ACTION', 'Déplacement'),
  ('ACTION', 'Glisser', 'ACTION', 'Déplacement'),
  ('ACTION', 'Frapper', 'ACTION', 'Impact'),
  ('ACTION', 'Casser', 'ACTION', 'Impact'),
  ('ACTION', 'Claquer', 'ACTION', 'Impact'),
  ('ACTION', 'Ouvrir', 'ACTION', 'Ouvrir/Fermer'),
  ('ACTION', 'Fermer', 'ACTION', 'Ouvrir/Fermer'),
  ('ACTION', 'Exploser', 'ACTION', 'Impact'),
  // Ambiances : un lieu précis, un moment fin ou un sous-genre → sa famille.
  ('AMBIANCE', 'Forêt', 'AMBIANCE', 'Nature'),
  ('AMBIANCE', 'Montagne', 'AMBIANCE', 'Nature'),
  ('AMBIANCE', 'Désert', 'AMBIANCE', 'Nature'),
  ('AMBIANCE', 'Campagne', 'AMBIANCE', 'Nature'),
  ('AMBIANCE', 'Aube', 'AMBIANCE', 'Jour'),
  ('AMBIANCE', 'Crépuscule', 'AMBIANCE', 'Nuit'),
  ('AMBIANCE', 'Foule', 'AMBIANCE', 'Public'),
  ('AMBIANCE', 'Post-apocalyptique', 'AMBIANCE', 'Futuriste'),
];

/// Tags retirés sans famille d'accueil (catégorie, tag) : supprimés
/// **seulement** s'ils ne sont posés ni suggérés sur aucun son, sinon conservés.
const List<(String, String)> _prunedTags = [
  ('OBJET', 'Livre'),
  ('OBJET', 'Fenêtre'),
  ('OBJET', 'Clés'),
  // Redondant avec `SoundType` (voie musique / ambiance).
  ('EMOTION_STYLE', "Musique d'ambiance"),
  // Gestes trop précis, sans famille : le titre les porte (ne sont plus créés).
  ('ACTION', 'Verser'),
  ('ACTION', 'Secouer'),
  ('ACTION', 'Déchirer'),
  ('ACTION', 'Frotter'),
];

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

      // ACTION : Voix et Déplacement viennent de [_extraTagCatalog], avec les
      // verbes précis en alias (décision 0040).
      await insertTag('Impact', 'ACTION');
      await insertTag('Actionner', 'ACTION');
      // OBJET
      await insertTag('Porte', 'OBJET');
      await insertTag('Arme', 'OBJET');
      await insertTag('Outil', 'OBJET');
      await insertTag('Cuisine', 'OBJET');
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
      await insertTag('Silence', 'AMBIANCE');
      await insertTag('Pluie', 'AMBIANCE');
      await insertTag('Orage', 'AMBIANCE');
      await insertTag('Mer', 'AMBIANCE');
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

  /// Catégorie MUSIQUE + tag « Musique d'ambiance » (migration v32). Historique :
  /// la catégorie est dissoute en v48 ([_dissolveRetiredTagCategories]), un
  /// seed neuf ne la crée plus.
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
  /// catégorie.
  ///
  /// Idempotent (`INSERT OR IGNORE` sur les clés d'unicité `tags` et
  /// `tag_aliases`) : sert à la fois à l'installation neuve et à la migration
  /// des bases existantes. Un alias déjà pris par un autre tag est ignoré, il
  /// ne fait jamais échouer la migration.
  Future<void> _ensureExtraTags() async {
    await transaction(() async {
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

  /// Dissout chaque catégorie de [retiredTagCategories] dans sa catégorie
  /// d'accueil (v48, décision 0040) : ses tags sont **déplacés**, pas recréés,
  /// si bien que les tags déjà posés sur des sons (`sound_tags`) et les
  /// suggestions (`sound_auto_tags`) restent valides. Si l'accueil a déjà un tag
  /// du même nom, les deux sont fusionnés. Idempotent : sans la catégorie
  /// retirée, ne fait rien.
  Future<void> _dissolveRetiredTagCategories() async {
    Future<int?> categoryId(String name) async {
      final row = await customSelect(
        'SELECT id FROM tag_categories WHERE name = ? LIMIT 1',
        variables: [Variable<String>(name)],
      ).getSingleOrNull();
      return row?.read<int>('id');
    }

    await transaction(() async {
      for (final entry in retiredTagCategories.entries) {
        final fromId = await categoryId(entry.key);
        if (fromId == null) continue;
        final toId = await categoryId(entry.value);
        if (toId == null) {
          // Accueil supprimé à la main : on ne devine pas où mettre les tags.
          AppLog.warn(
            'Catégorie de tags « ${entry.key} » non dissoute : '
            'la catégorie d’accueil « ${entry.value} » est absente.',
          );
          continue;
        }

        final tags = await customSelect(
          'SELECT id, normalized_name FROM tags WHERE category_id = ?',
          variables: [Variable<int>(fromId)],
        ).get();
        var moved = 0;
        var merged = 0;
        for (final tag in tags) {
          final tagId = tag.read<int>('id');
          final twin = await customSelect(
            'SELECT id FROM tags WHERE category_id = ? AND normalized_name = ? '
            'LIMIT 1',
            variables: [
              Variable<int>(toId),
              Variable<String>(tag.read<String>('normalized_name')),
            ],
          ).getSingleOrNull();
          if (twin == null) {
            await customStatement(
              'UPDATE tags SET category_id = ? WHERE id = ?',
              [toId, tagId],
            );
            moved++;
          } else {
            await _mergeTagInto(from: tagId, into: twin.read<int>('id'));
            merged++;
          }
        }
        await customStatement('DELETE FROM tag_categories WHERE id = ?', [
          fromId,
        ]);
        AppLog.info(
          'Catégorie de tags « ${entry.key} » dissoute dans « ${entry.value} » '
          ': $moved tag(s) déplacé(s), $merged fusionné(s).',
        );
      }
    });
  }

  /// Reporte les usages et les alias du tag [from] sur [into], puis supprime
  /// [from]. À appeler dans une transaction. Les clés étrangères ne sont pas
  /// activées : rien ne cascade, tout est fait à la main.
  Future<void> _mergeTagInto({required int from, required int into}) async {
    await customStatement(
      'INSERT OR IGNORE INTO sound_tags (sound_id, tag_id, added_at) '
      'SELECT sound_id, ?, added_at FROM sound_tags WHERE tag_id = ?',
      [into, from],
    );
    await customStatement('DELETE FROM sound_tags WHERE tag_id = ?', [from]);
    await customStatement(
      'INSERT OR IGNORE INTO sound_auto_tags '
      '(sound_id, tag_id, score, updated_at) '
      'SELECT sound_id, ?, score, updated_at FROM sound_auto_tags '
      'WHERE tag_id = ?',
      [into, from],
    );
    await customStatement('DELETE FROM sound_auto_tags WHERE tag_id = ?', [
      from,
    ]);
    await customStatement(
      'UPDATE OR IGNORE tag_aliases SET tag_id = ? WHERE tag_id = ?',
      [into, from],
    );
    await customStatement('DELETE FROM tag_aliases WHERE tag_id = ?', [from]);
    await customStatement('DELETE FROM tags WHERE id = ?', [from]);
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

  /// Identifiant du tag [tag] de la catégorie [category], ou null.
  Future<int?> _tagIdIn(String category, String tag) async {
    final row = await customSelect(
      'SELECT t.id AS id FROM tags t JOIN tag_categories c '
      'ON c.id = t.category_id WHERE c.name = ? AND t.normalized_name = ? '
      'LIMIT 1',
      variables: [
        Variable<String>(category),
        Variable<String>(_normalize(tag)),
      ],
    ).getSingleOrNull();
    return row?.read<int>('id');
  }

  /// Retire les tags trop précis (v48, décision 0040) : fusionne ceux de
  /// [_mergedTags] dans leur famille, supprime ceux de [_prunedTags] qu'aucun
  /// son n'utilise. À appeler **après** [_ensureExtraTags], qui crée les tags
  /// d'accueil. Idempotent.
  Future<void> _withdrawSpecificTags() async {
    await transaction(() async {
      var merged = 0;
      var pruned = 0;
      for (final (category, tag, intoCategory, into) in _mergedTags) {
        final fromId = await _tagIdIn(category, tag);
        if (fromId == null) continue;
        final intoId = await _tagIdIn(intoCategory, into);
        if (intoId == null) {
          AppLog.warn(
            'Tag « $tag » non fusionné : le tag d’accueil « $into » est absent.',
          );
          continue;
        }
        await _mergeTagInto(from: fromId, into: intoId);
        merged++;
      }
      for (final (category, tag) in _prunedTags) {
        final id = await _tagIdIn(category, tag);
        if (id == null) continue;
        final used = await customSelect(
          'SELECT (SELECT COUNT(*) FROM sound_tags WHERE tag_id = ?) + '
          '(SELECT COUNT(*) FROM sound_auto_tags WHERE tag_id = ?) AS c',
          variables: [Variable<int>(id), Variable<int>(id)],
        ).getSingle();
        if (used.read<int>('c') > 0) continue;
        await customStatement('DELETE FROM tag_aliases WHERE tag_id = ?', [id]);
        await customStatement('DELETE FROM tags WHERE id = ?', [id]);
        pruned++;
      }
      AppLog.info(
        'Tags trop précis retirés : $merged fusionné(s), $pruned supprimé(s) '
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
