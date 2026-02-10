// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $SoundsTable extends Sounds with TableInfo<$SoundsTable, Sound> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SoundsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SoundType, int> type =
      GeneratedColumn<int>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<SoundType>($SoundsTable.$convertertype);
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _volumeMeta = const VerificationMeta('volume');
  @override
  late final GeneratedColumn<double> volume = GeneratedColumn<double>(
    'volume',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1.0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    displayName,
    filePath,
    type,
    color,
    volume,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sounds';
  @override
  VerificationContext validateIntegrity(
    Insertable<Sound> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('volume')) {
      context.handle(
        _volumeMeta,
        volume.isAcceptableOrUnknown(data['volume']!, _volumeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Sound map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Sound(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      type: $SoundsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}type'],
        )!,
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      ),
      volume: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}volume'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SoundsTable createAlias(String alias) {
    return $SoundsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SoundType, int, int> $convertertype =
      const EnumIndexConverter<SoundType>(SoundType.values);
}

class Sound extends DataClass implements Insertable<Sound> {
  final int id;
  final String title;
  final String? displayName;
  final String filePath;
  final SoundType type;
  final int? color;
  final double volume;
  final DateTime createdAt;
  const Sound({
    required this.id,
    required this.title,
    this.displayName,
    required this.filePath,
    required this.type,
    this.color,
    required this.volume,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    map['file_path'] = Variable<String>(filePath);
    {
      map['type'] = Variable<int>($SoundsTable.$convertertype.toSql(type));
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<int>(color);
    }
    map['volume'] = Variable<double>(volume);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SoundsCompanion toCompanion(bool nullToAbsent) {
    return SoundsCompanion(
      id: Value(id),
      title: Value(title),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      filePath: Value(filePath),
      type: Value(type),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      volume: Value(volume),
      createdAt: Value(createdAt),
    );
  }

  factory Sound.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Sound(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      filePath: serializer.fromJson<String>(json['filePath']),
      type: $SoundsTable.$convertertype.fromJson(
        serializer.fromJson<int>(json['type']),
      ),
      color: serializer.fromJson<int?>(json['color']),
      volume: serializer.fromJson<double>(json['volume']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'displayName': serializer.toJson<String?>(displayName),
      'filePath': serializer.toJson<String>(filePath),
      'type': serializer.toJson<int>($SoundsTable.$convertertype.toJson(type)),
      'color': serializer.toJson<int?>(color),
      'volume': serializer.toJson<double>(volume),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Sound copyWith({
    int? id,
    String? title,
    Value<String?> displayName = const Value.absent(),
    String? filePath,
    SoundType? type,
    Value<int?> color = const Value.absent(),
    double? volume,
    DateTime? createdAt,
  }) => Sound(
    id: id ?? this.id,
    title: title ?? this.title,
    displayName: displayName.present ? displayName.value : this.displayName,
    filePath: filePath ?? this.filePath,
    type: type ?? this.type,
    color: color.present ? color.value : this.color,
    volume: volume ?? this.volume,
    createdAt: createdAt ?? this.createdAt,
  );
  Sound copyWithCompanion(SoundsCompanion data) {
    return Sound(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      type: data.type.present ? data.type.value : this.type,
      color: data.color.present ? data.color.value : this.color,
      volume: data.volume.present ? data.volume.value : this.volume,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Sound(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('displayName: $displayName, ')
          ..write('filePath: $filePath, ')
          ..write('type: $type, ')
          ..write('color: $color, ')
          ..write('volume: $volume, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    displayName,
    filePath,
    type,
    color,
    volume,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Sound &&
          other.id == this.id &&
          other.title == this.title &&
          other.displayName == this.displayName &&
          other.filePath == this.filePath &&
          other.type == this.type &&
          other.color == this.color &&
          other.volume == this.volume &&
          other.createdAt == this.createdAt);
}

class SoundsCompanion extends UpdateCompanion<Sound> {
  final Value<int> id;
  final Value<String> title;
  final Value<String?> displayName;
  final Value<String> filePath;
  final Value<SoundType> type;
  final Value<int?> color;
  final Value<double> volume;
  final Value<DateTime> createdAt;
  const SoundsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.displayName = const Value.absent(),
    this.filePath = const Value.absent(),
    this.type = const Value.absent(),
    this.color = const Value.absent(),
    this.volume = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SoundsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    this.displayName = const Value.absent(),
    required String filePath,
    required SoundType type,
    this.color = const Value.absent(),
    this.volume = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : title = Value(title),
       filePath = Value(filePath),
       type = Value(type);
  static Insertable<Sound> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? displayName,
    Expression<String>? filePath,
    Expression<int>? type,
    Expression<int>? color,
    Expression<double>? volume,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (displayName != null) 'display_name': displayName,
      if (filePath != null) 'file_path': filePath,
      if (type != null) 'type': type,
      if (color != null) 'color': color,
      if (volume != null) 'volume': volume,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SoundsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String?>? displayName,
    Value<String>? filePath,
    Value<SoundType>? type,
    Value<int?>? color,
    Value<double>? volume,
    Value<DateTime>? createdAt,
  }) {
    return SoundsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      displayName: displayName ?? this.displayName,
      filePath: filePath ?? this.filePath,
      type: type ?? this.type,
      color: color ?? this.color,
      volume: volume ?? this.volume,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(
        $SoundsTable.$convertertype.toSql(type.value),
      );
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (volume.present) {
      map['volume'] = Variable<double>(volume.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SoundsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('displayName: $displayName, ')
          ..write('filePath: $filePath, ')
          ..write('type: $type, ')
          ..write('color: $color, ')
          ..write('volume: $volume, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SoundBoardsTable extends SoundBoards
    with TableInfo<$SoundBoardsTable, SoundBoard> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SoundBoardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sound_boards';
  @override
  VerificationContext validateIntegrity(
    Insertable<SoundBoard> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SoundBoard map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SoundBoard(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SoundBoardsTable createAlias(String alias) {
    return $SoundBoardsTable(attachedDatabase, alias);
  }
}

class SoundBoard extends DataClass implements Insertable<SoundBoard> {
  final int id;
  final String name;
  final DateTime createdAt;
  const SoundBoard({
    required this.id,
    required this.name,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SoundBoardsCompanion toCompanion(bool nullToAbsent) {
    return SoundBoardsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory SoundBoard.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SoundBoard(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SoundBoard copyWith({int? id, String? name, DateTime? createdAt}) =>
      SoundBoard(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
      );
  SoundBoard copyWithCompanion(SoundBoardsCompanion data) {
    return SoundBoard(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SoundBoard(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SoundBoard &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class SoundBoardsCompanion extends UpdateCompanion<SoundBoard> {
  final Value<int> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  const SoundBoardsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SoundBoardsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.createdAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<SoundBoard> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SoundBoardsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
  }) {
    return SoundBoardsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SoundBoardsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $WatchedPathsTable extends WatchedPaths
    with TableInfo<$WatchedPathsTable, WatchedPath> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchedPathsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDirectoryMeta = const VerificationMeta(
    'isDirectory',
  );
  @override
  late final GeneratedColumn<bool> isDirectory = GeneratedColumn<bool>(
    'is_directory',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_directory" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, path, isDirectory, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watched_paths';
  @override
  VerificationContext validateIntegrity(
    Insertable<WatchedPath> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('is_directory')) {
      context.handle(
        _isDirectoryMeta,
        isDirectory.isAcceptableOrUnknown(
          data['is_directory']!,
          _isDirectoryMeta,
        ),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WatchedPath map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchedPath(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      isDirectory: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_directory'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $WatchedPathsTable createAlias(String alias) {
    return $WatchedPathsTable(attachedDatabase, alias);
  }
}

class WatchedPath extends DataClass implements Insertable<WatchedPath> {
  final int id;
  final String path;
  final bool isDirectory;
  final DateTime addedAt;
  const WatchedPath({
    required this.id,
    required this.path,
    required this.isDirectory,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['path'] = Variable<String>(path);
    map['is_directory'] = Variable<bool>(isDirectory);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  WatchedPathsCompanion toCompanion(bool nullToAbsent) {
    return WatchedPathsCompanion(
      id: Value(id),
      path: Value(path),
      isDirectory: Value(isDirectory),
      addedAt: Value(addedAt),
    );
  }

  factory WatchedPath.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchedPath(
      id: serializer.fromJson<int>(json['id']),
      path: serializer.fromJson<String>(json['path']),
      isDirectory: serializer.fromJson<bool>(json['isDirectory']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'path': serializer.toJson<String>(path),
      'isDirectory': serializer.toJson<bool>(isDirectory),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  WatchedPath copyWith({
    int? id,
    String? path,
    bool? isDirectory,
    DateTime? addedAt,
  }) => WatchedPath(
    id: id ?? this.id,
    path: path ?? this.path,
    isDirectory: isDirectory ?? this.isDirectory,
    addedAt: addedAt ?? this.addedAt,
  );
  WatchedPath copyWithCompanion(WatchedPathsCompanion data) {
    return WatchedPath(
      id: data.id.present ? data.id.value : this.id,
      path: data.path.present ? data.path.value : this.path,
      isDirectory: data.isDirectory.present
          ? data.isDirectory.value
          : this.isDirectory,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchedPath(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('isDirectory: $isDirectory, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, path, isDirectory, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchedPath &&
          other.id == this.id &&
          other.path == this.path &&
          other.isDirectory == this.isDirectory &&
          other.addedAt == this.addedAt);
}

class WatchedPathsCompanion extends UpdateCompanion<WatchedPath> {
  final Value<int> id;
  final Value<String> path;
  final Value<bool> isDirectory;
  final Value<DateTime> addedAt;
  const WatchedPathsCompanion({
    this.id = const Value.absent(),
    this.path = const Value.absent(),
    this.isDirectory = const Value.absent(),
    this.addedAt = const Value.absent(),
  });
  WatchedPathsCompanion.insert({
    this.id = const Value.absent(),
    required String path,
    this.isDirectory = const Value.absent(),
    this.addedAt = const Value.absent(),
  }) : path = Value(path);
  static Insertable<WatchedPath> custom({
    Expression<int>? id,
    Expression<String>? path,
    Expression<bool>? isDirectory,
    Expression<DateTime>? addedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (isDirectory != null) 'is_directory': isDirectory,
      if (addedAt != null) 'added_at': addedAt,
    });
  }

  WatchedPathsCompanion copyWith({
    Value<int>? id,
    Value<String>? path,
    Value<bool>? isDirectory,
    Value<DateTime>? addedAt,
  }) {
    return WatchedPathsCompanion(
      id: id ?? this.id,
      path: path ?? this.path,
      isDirectory: isDirectory ?? this.isDirectory,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (isDirectory.present) {
      map['is_directory'] = Variable<bool>(isDirectory.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchedPathsCompanion(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('isDirectory: $isDirectory, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }
}

class $BoardSoundsTable extends BoardSounds
    with TableInfo<$BoardSoundsTable, BoardSound> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BoardSoundsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _boardIdMeta = const VerificationMeta(
    'boardId',
  );
  @override
  late final GeneratedColumn<int> boardId = GeneratedColumn<int>(
    'board_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sound_boards (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _soundIdMeta = const VerificationMeta(
    'soundId',
  );
  @override
  late final GeneratedColumn<int> soundId = GeneratedColumn<int>(
    'sound_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sounds (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [boardId, soundId, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'board_sounds';
  @override
  VerificationContext validateIntegrity(
    Insertable<BoardSound> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('board_id')) {
      context.handle(
        _boardIdMeta,
        boardId.isAcceptableOrUnknown(data['board_id']!, _boardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_boardIdMeta);
    }
    if (data.containsKey('sound_id')) {
      context.handle(
        _soundIdMeta,
        soundId.isAcceptableOrUnknown(data['sound_id']!, _soundIdMeta),
      );
    } else if (isInserting) {
      context.missing(_soundIdMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {boardId, soundId};
  @override
  BoardSound map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BoardSound(
      boardId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}board_id'],
      )!,
      soundId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sound_id'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $BoardSoundsTable createAlias(String alias) {
    return $BoardSoundsTable(attachedDatabase, alias);
  }
}

class BoardSound extends DataClass implements Insertable<BoardSound> {
  final int boardId;
  final int soundId;
  final DateTime addedAt;
  const BoardSound({
    required this.boardId,
    required this.soundId,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['board_id'] = Variable<int>(boardId);
    map['sound_id'] = Variable<int>(soundId);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  BoardSoundsCompanion toCompanion(bool nullToAbsent) {
    return BoardSoundsCompanion(
      boardId: Value(boardId),
      soundId: Value(soundId),
      addedAt: Value(addedAt),
    );
  }

  factory BoardSound.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BoardSound(
      boardId: serializer.fromJson<int>(json['boardId']),
      soundId: serializer.fromJson<int>(json['soundId']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'boardId': serializer.toJson<int>(boardId),
      'soundId': serializer.toJson<int>(soundId),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  BoardSound copyWith({int? boardId, int? soundId, DateTime? addedAt}) =>
      BoardSound(
        boardId: boardId ?? this.boardId,
        soundId: soundId ?? this.soundId,
        addedAt: addedAt ?? this.addedAt,
      );
  BoardSound copyWithCompanion(BoardSoundsCompanion data) {
    return BoardSound(
      boardId: data.boardId.present ? data.boardId.value : this.boardId,
      soundId: data.soundId.present ? data.soundId.value : this.soundId,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BoardSound(')
          ..write('boardId: $boardId, ')
          ..write('soundId: $soundId, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(boardId, soundId, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BoardSound &&
          other.boardId == this.boardId &&
          other.soundId == this.soundId &&
          other.addedAt == this.addedAt);
}

class BoardSoundsCompanion extends UpdateCompanion<BoardSound> {
  final Value<int> boardId;
  final Value<int> soundId;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const BoardSoundsCompanion({
    this.boardId = const Value.absent(),
    this.soundId = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BoardSoundsCompanion.insert({
    required int boardId,
    required int soundId,
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : boardId = Value(boardId),
       soundId = Value(soundId);
  static Insertable<BoardSound> custom({
    Expression<int>? boardId,
    Expression<int>? soundId,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (boardId != null) 'board_id': boardId,
      if (soundId != null) 'sound_id': soundId,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BoardSoundsCompanion copyWith({
    Value<int>? boardId,
    Value<int>? soundId,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return BoardSoundsCompanion(
      boardId: boardId ?? this.boardId,
      soundId: soundId ?? this.soundId,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (boardId.present) {
      map['board_id'] = Variable<int>(boardId.value);
    }
    if (soundId.present) {
      map['sound_id'] = Variable<int>(soundId.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BoardSoundsCompanion(')
          ..write('boardId: $boardId, ')
          ..write('soundId: $soundId, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagCategoriesTable extends TagCategories
    with TableInfo<$TagCategoriesTable, TagCategory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    color,
    sortOrder,
    description,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tag_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagCategory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagCategory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagCategory(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
    );
  }

  @override
  $TagCategoriesTable createAlias(String alias) {
    return $TagCategoriesTable(attachedDatabase, alias);
  }
}

class TagCategory extends DataClass implements Insertable<TagCategory> {
  final int id;
  final String name;
  final int color;
  final int sortOrder;
  final String? description;
  const TagCategory({
    required this.id,
    required this.name,
    required this.color,
    required this.sortOrder,
    this.description,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<int>(color);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    return map;
  }

  TagCategoriesCompanion toCompanion(bool nullToAbsent) {
    return TagCategoriesCompanion(
      id: Value(id),
      name: Value(name),
      color: Value(color),
      sortOrder: Value(sortOrder),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
    );
  }

  factory TagCategory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagCategory(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<int>(json['color']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      description: serializer.fromJson<String?>(json['description']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<int>(color),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'description': serializer.toJson<String?>(description),
    };
  }

  TagCategory copyWith({
    int? id,
    String? name,
    int? color,
    int? sortOrder,
    Value<String?> description = const Value.absent(),
  }) => TagCategory(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
    sortOrder: sortOrder ?? this.sortOrder,
    description: description.present ? description.value : this.description,
  );
  TagCategory copyWithCompanion(TagCategoriesCompanion data) {
    return TagCategory(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      description: data.description.present
          ? data.description.value
          : this.description,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagCategory(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('description: $description')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, color, sortOrder, description);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagCategory &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color &&
          other.sortOrder == this.sortOrder &&
          other.description == this.description);
}

class TagCategoriesCompanion extends UpdateCompanion<TagCategory> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> color;
  final Value<int> sortOrder;
  final Value<String?> description;
  const TagCategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.description = const Value.absent(),
  });
  TagCategoriesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required int color,
    this.sortOrder = const Value.absent(),
    this.description = const Value.absent(),
  }) : name = Value(name),
       color = Value(color);
  static Insertable<TagCategory> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? color,
    Expression<int>? sortOrder,
    Expression<String>? description,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (description != null) 'description': description,
    });
  }

  TagCategoriesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? color,
    Value<int>? sortOrder,
    Value<String?>? description,
  }) {
    return TagCategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      description: description ?? this.description,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagCategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('description: $description')
          ..write(')'))
        .toString();
  }
}

class $TagItemsTable extends TagItems with TableInfo<$TagItemsTable, TagItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tag_categories (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedNameMeta = const VerificationMeta(
    'normalizedName',
  );
  @override
  late final GeneratedColumn<String> normalizedName = GeneratedColumn<String>(
    'normalized_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    categoryId,
    name,
    normalizedName,
    description,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('normalized_name')) {
      context.handle(
        _normalizedNameMeta,
        normalizedName.isAcceptableOrUnknown(
          data['normalized_name']!,
          _normalizedNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedNameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {categoryId, normalizedName},
  ];
  @override
  TagItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}category_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      normalizedName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
    );
  }

  @override
  $TagItemsTable createAlias(String alias) {
    return $TagItemsTable(attachedDatabase, alias);
  }
}

class TagItem extends DataClass implements Insertable<TagItem> {
  final int id;
  final int categoryId;
  final String name;
  final String normalizedName;
  final String? description;
  const TagItem({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.normalizedName,
    this.description,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['category_id'] = Variable<int>(categoryId);
    map['name'] = Variable<String>(name);
    map['normalized_name'] = Variable<String>(normalizedName);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    return map;
  }

  TagItemsCompanion toCompanion(bool nullToAbsent) {
    return TagItemsCompanion(
      id: Value(id),
      categoryId: Value(categoryId),
      name: Value(name),
      normalizedName: Value(normalizedName),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
    );
  }

  factory TagItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagItem(
      id: serializer.fromJson<int>(json['id']),
      categoryId: serializer.fromJson<int>(json['categoryId']),
      name: serializer.fromJson<String>(json['name']),
      normalizedName: serializer.fromJson<String>(json['normalizedName']),
      description: serializer.fromJson<String?>(json['description']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'categoryId': serializer.toJson<int>(categoryId),
      'name': serializer.toJson<String>(name),
      'normalizedName': serializer.toJson<String>(normalizedName),
      'description': serializer.toJson<String?>(description),
    };
  }

  TagItem copyWith({
    int? id,
    int? categoryId,
    String? name,
    String? normalizedName,
    Value<String?> description = const Value.absent(),
  }) => TagItem(
    id: id ?? this.id,
    categoryId: categoryId ?? this.categoryId,
    name: name ?? this.name,
    normalizedName: normalizedName ?? this.normalizedName,
    description: description.present ? description.value : this.description,
  );
  TagItem copyWithCompanion(TagItemsCompanion data) {
    return TagItem(
      id: data.id.present ? data.id.value : this.id,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      name: data.name.present ? data.name.value : this.name,
      normalizedName: data.normalizedName.present
          ? data.normalizedName.value
          : this.normalizedName,
      description: data.description.present
          ? data.description.value
          : this.description,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagItem(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('name: $name, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('description: $description')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, categoryId, name, normalizedName, description);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagItem &&
          other.id == this.id &&
          other.categoryId == this.categoryId &&
          other.name == this.name &&
          other.normalizedName == this.normalizedName &&
          other.description == this.description);
}

class TagItemsCompanion extends UpdateCompanion<TagItem> {
  final Value<int> id;
  final Value<int> categoryId;
  final Value<String> name;
  final Value<String> normalizedName;
  final Value<String?> description;
  const TagItemsCompanion({
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.name = const Value.absent(),
    this.normalizedName = const Value.absent(),
    this.description = const Value.absent(),
  });
  TagItemsCompanion.insert({
    this.id = const Value.absent(),
    required int categoryId,
    required String name,
    required String normalizedName,
    this.description = const Value.absent(),
  }) : categoryId = Value(categoryId),
       name = Value(name),
       normalizedName = Value(normalizedName);
  static Insertable<TagItem> custom({
    Expression<int>? id,
    Expression<int>? categoryId,
    Expression<String>? name,
    Expression<String>? normalizedName,
    Expression<String>? description,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (categoryId != null) 'category_id': categoryId,
      if (name != null) 'name': name,
      if (normalizedName != null) 'normalized_name': normalizedName,
      if (description != null) 'description': description,
    });
  }

  TagItemsCompanion copyWith({
    Value<int>? id,
    Value<int>? categoryId,
    Value<String>? name,
    Value<String>? normalizedName,
    Value<String?>? description,
  }) {
    return TagItemsCompanion(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      description: description ?? this.description,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (normalizedName.present) {
      map['normalized_name'] = Variable<String>(normalizedName.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagItemsCompanion(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('name: $name, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('description: $description')
          ..write(')'))
        .toString();
  }
}

class $SoundTagsTable extends SoundTags
    with TableInfo<$SoundTagsTable, SoundTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SoundTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _soundIdMeta = const VerificationMeta(
    'soundId',
  );
  @override
  late final GeneratedColumn<int> soundId = GeneratedColumn<int>(
    'sound_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sounds (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<int> tagId = GeneratedColumn<int>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tags (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [soundId, tagId, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sound_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<SoundTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sound_id')) {
      context.handle(
        _soundIdMeta,
        soundId.isAcceptableOrUnknown(data['sound_id']!, _soundIdMeta),
      );
    } else if (isInserting) {
      context.missing(_soundIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {soundId, tagId};
  @override
  SoundTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SoundTag(
      soundId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sound_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tag_id'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $SoundTagsTable createAlias(String alias) {
    return $SoundTagsTable(attachedDatabase, alias);
  }
}

class SoundTag extends DataClass implements Insertable<SoundTag> {
  final int soundId;
  final int tagId;
  final DateTime addedAt;
  const SoundTag({
    required this.soundId,
    required this.tagId,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sound_id'] = Variable<int>(soundId);
    map['tag_id'] = Variable<int>(tagId);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  SoundTagsCompanion toCompanion(bool nullToAbsent) {
    return SoundTagsCompanion(
      soundId: Value(soundId),
      tagId: Value(tagId),
      addedAt: Value(addedAt),
    );
  }

  factory SoundTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SoundTag(
      soundId: serializer.fromJson<int>(json['soundId']),
      tagId: serializer.fromJson<int>(json['tagId']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'soundId': serializer.toJson<int>(soundId),
      'tagId': serializer.toJson<int>(tagId),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  SoundTag copyWith({int? soundId, int? tagId, DateTime? addedAt}) => SoundTag(
    soundId: soundId ?? this.soundId,
    tagId: tagId ?? this.tagId,
    addedAt: addedAt ?? this.addedAt,
  );
  SoundTag copyWithCompanion(SoundTagsCompanion data) {
    return SoundTag(
      soundId: data.soundId.present ? data.soundId.value : this.soundId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SoundTag(')
          ..write('soundId: $soundId, ')
          ..write('tagId: $tagId, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(soundId, tagId, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SoundTag &&
          other.soundId == this.soundId &&
          other.tagId == this.tagId &&
          other.addedAt == this.addedAt);
}

class SoundTagsCompanion extends UpdateCompanion<SoundTag> {
  final Value<int> soundId;
  final Value<int> tagId;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const SoundTagsCompanion({
    this.soundId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SoundTagsCompanion.insert({
    required int soundId,
    required int tagId,
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : soundId = Value(soundId),
       tagId = Value(tagId);
  static Insertable<SoundTag> custom({
    Expression<int>? soundId,
    Expression<int>? tagId,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (soundId != null) 'sound_id': soundId,
      if (tagId != null) 'tag_id': tagId,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SoundTagsCompanion copyWith({
    Value<int>? soundId,
    Value<int>? tagId,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return SoundTagsCompanion(
      soundId: soundId ?? this.soundId,
      tagId: tagId ?? this.tagId,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (soundId.present) {
      map['sound_id'] = Variable<int>(soundId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<int>(tagId.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SoundTagsCompanion(')
          ..write('soundId: $soundId, ')
          ..write('tagId: $tagId, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagAliasesTable extends TagAliases
    with TableInfo<$TagAliasesTable, TagAliase> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagAliasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<int> tagId = GeneratedColumn<int>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tags (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _aliasMeta = const VerificationMeta('alias');
  @override
  late final GeneratedColumn<String> alias = GeneratedColumn<String>(
    'alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedAliasMeta = const VerificationMeta(
    'normalizedAlias',
  );
  @override
  late final GeneratedColumn<String> normalizedAlias = GeneratedColumn<String>(
    'normalized_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, tagId, alias, normalizedAlias];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tag_aliases';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagAliase> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    if (data.containsKey('alias')) {
      context.handle(
        _aliasMeta,
        alias.isAcceptableOrUnknown(data['alias']!, _aliasMeta),
      );
    } else if (isInserting) {
      context.missing(_aliasMeta);
    }
    if (data.containsKey('normalized_alias')) {
      context.handle(
        _normalizedAliasMeta,
        normalizedAlias.isAcceptableOrUnknown(
          data['normalized_alias']!,
          _normalizedAliasMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedAliasMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {normalizedAlias},
  ];
  @override
  TagAliase map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagAliase(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tag_id'],
      )!,
      alias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alias'],
      )!,
      normalizedAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_alias'],
      )!,
    );
  }

  @override
  $TagAliasesTable createAlias(String alias) {
    return $TagAliasesTable(attachedDatabase, alias);
  }
}

class TagAliase extends DataClass implements Insertable<TagAliase> {
  final int id;
  final int tagId;
  final String alias;
  final String normalizedAlias;
  const TagAliase({
    required this.id,
    required this.tagId,
    required this.alias,
    required this.normalizedAlias,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['tag_id'] = Variable<int>(tagId);
    map['alias'] = Variable<String>(alias);
    map['normalized_alias'] = Variable<String>(normalizedAlias);
    return map;
  }

  TagAliasesCompanion toCompanion(bool nullToAbsent) {
    return TagAliasesCompanion(
      id: Value(id),
      tagId: Value(tagId),
      alias: Value(alias),
      normalizedAlias: Value(normalizedAlias),
    );
  }

  factory TagAliase.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagAliase(
      id: serializer.fromJson<int>(json['id']),
      tagId: serializer.fromJson<int>(json['tagId']),
      alias: serializer.fromJson<String>(json['alias']),
      normalizedAlias: serializer.fromJson<String>(json['normalizedAlias']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'tagId': serializer.toJson<int>(tagId),
      'alias': serializer.toJson<String>(alias),
      'normalizedAlias': serializer.toJson<String>(normalizedAlias),
    };
  }

  TagAliase copyWith({
    int? id,
    int? tagId,
    String? alias,
    String? normalizedAlias,
  }) => TagAliase(
    id: id ?? this.id,
    tagId: tagId ?? this.tagId,
    alias: alias ?? this.alias,
    normalizedAlias: normalizedAlias ?? this.normalizedAlias,
  );
  TagAliase copyWithCompanion(TagAliasesCompanion data) {
    return TagAliase(
      id: data.id.present ? data.id.value : this.id,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      alias: data.alias.present ? data.alias.value : this.alias,
      normalizedAlias: data.normalizedAlias.present
          ? data.normalizedAlias.value
          : this.normalizedAlias,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagAliase(')
          ..write('id: $id, ')
          ..write('tagId: $tagId, ')
          ..write('alias: $alias, ')
          ..write('normalizedAlias: $normalizedAlias')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, tagId, alias, normalizedAlias);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagAliase &&
          other.id == this.id &&
          other.tagId == this.tagId &&
          other.alias == this.alias &&
          other.normalizedAlias == this.normalizedAlias);
}

class TagAliasesCompanion extends UpdateCompanion<TagAliase> {
  final Value<int> id;
  final Value<int> tagId;
  final Value<String> alias;
  final Value<String> normalizedAlias;
  const TagAliasesCompanion({
    this.id = const Value.absent(),
    this.tagId = const Value.absent(),
    this.alias = const Value.absent(),
    this.normalizedAlias = const Value.absent(),
  });
  TagAliasesCompanion.insert({
    this.id = const Value.absent(),
    required int tagId,
    required String alias,
    required String normalizedAlias,
  }) : tagId = Value(tagId),
       alias = Value(alias),
       normalizedAlias = Value(normalizedAlias);
  static Insertable<TagAliase> custom({
    Expression<int>? id,
    Expression<int>? tagId,
    Expression<String>? alias,
    Expression<String>? normalizedAlias,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tagId != null) 'tag_id': tagId,
      if (alias != null) 'alias': alias,
      if (normalizedAlias != null) 'normalized_alias': normalizedAlias,
    });
  }

  TagAliasesCompanion copyWith({
    Value<int>? id,
    Value<int>? tagId,
    Value<String>? alias,
    Value<String>? normalizedAlias,
  }) {
    return TagAliasesCompanion(
      id: id ?? this.id,
      tagId: tagId ?? this.tagId,
      alias: alias ?? this.alias,
      normalizedAlias: normalizedAlias ?? this.normalizedAlias,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<int>(tagId.value);
    }
    if (alias.present) {
      map['alias'] = Variable<String>(alias.value);
    }
    if (normalizedAlias.present) {
      map['normalized_alias'] = Variable<String>(normalizedAlias.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagAliasesCompanion(')
          ..write('id: $id, ')
          ..write('tagId: $tagId, ')
          ..write('alias: $alias, ')
          ..write('normalizedAlias: $normalizedAlias')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SoundsTable sounds = $SoundsTable(this);
  late final $SoundBoardsTable soundBoards = $SoundBoardsTable(this);
  late final $WatchedPathsTable watchedPaths = $WatchedPathsTable(this);
  late final $BoardSoundsTable boardSounds = $BoardSoundsTable(this);
  late final $TagCategoriesTable tagCategories = $TagCategoriesTable(this);
  late final $TagItemsTable tagItems = $TagItemsTable(this);
  late final $SoundTagsTable soundTags = $SoundTagsTable(this);
  late final $TagAliasesTable tagAliases = $TagAliasesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sounds,
    soundBoards,
    watchedPaths,
    boardSounds,
    tagCategories,
    tagItems,
    soundTags,
    tagAliases,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sound_boards',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('board_sounds', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sounds',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('board_sounds', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tag_categories',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tags', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sounds',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('sound_tags', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tags',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('sound_tags', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tags',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tag_aliases', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$SoundsTableCreateCompanionBuilder =
    SoundsCompanion Function({
      Value<int> id,
      required String title,
      Value<String?> displayName,
      required String filePath,
      required SoundType type,
      Value<int?> color,
      Value<double> volume,
      Value<DateTime> createdAt,
    });
typedef $$SoundsTableUpdateCompanionBuilder =
    SoundsCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String?> displayName,
      Value<String> filePath,
      Value<SoundType> type,
      Value<int?> color,
      Value<double> volume,
      Value<DateTime> createdAt,
    });

final class $$SoundsTableReferences
    extends BaseReferences<_$AppDatabase, $SoundsTable, Sound> {
  $$SoundsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BoardSoundsTable, List<BoardSound>>
  _boardSoundsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.boardSounds,
    aliasName: $_aliasNameGenerator(db.sounds.id, db.boardSounds.soundId),
  );

  $$BoardSoundsTableProcessedTableManager get boardSoundsRefs {
    final manager = $$BoardSoundsTableTableManager(
      $_db,
      $_db.boardSounds,
    ).filter((f) => f.soundId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_boardSoundsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SoundTagsTable, List<SoundTag>>
  _soundTagsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.soundTags,
    aliasName: $_aliasNameGenerator(db.sounds.id, db.soundTags.soundId),
  );

  $$SoundTagsTableProcessedTableManager get soundTagsRefs {
    final manager = $$SoundTagsTableTableManager(
      $_db,
      $_db.soundTags,
    ).filter((f) => f.soundId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_soundTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SoundsTableFilterComposer
    extends Composer<_$AppDatabase, $SoundsTable> {
  $$SoundsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SoundType, SoundType, int> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> boardSoundsRefs(
    Expression<bool> Function($$BoardSoundsTableFilterComposer f) f,
  ) {
    final $$BoardSoundsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.boardSounds,
      getReferencedColumn: (t) => t.soundId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardSoundsTableFilterComposer(
            $db: $db,
            $table: $db.boardSounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> soundTagsRefs(
    Expression<bool> Function($$SoundTagsTableFilterComposer f) f,
  ) {
    final $$SoundTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.soundTags,
      getReferencedColumn: (t) => t.soundId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SoundTagsTableFilterComposer(
            $db: $db,
            $table: $db.soundTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SoundsTableOrderingComposer
    extends Composer<_$AppDatabase, $SoundsTable> {
  $$SoundsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SoundsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SoundsTable> {
  $$SoundsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SoundType, int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<double> get volume =>
      $composableBuilder(column: $table.volume, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> boardSoundsRefs<T extends Object>(
    Expression<T> Function($$BoardSoundsTableAnnotationComposer a) f,
  ) {
    final $$BoardSoundsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.boardSounds,
      getReferencedColumn: (t) => t.soundId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardSoundsTableAnnotationComposer(
            $db: $db,
            $table: $db.boardSounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> soundTagsRefs<T extends Object>(
    Expression<T> Function($$SoundTagsTableAnnotationComposer a) f,
  ) {
    final $$SoundTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.soundTags,
      getReferencedColumn: (t) => t.soundId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SoundTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.soundTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SoundsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SoundsTable,
          Sound,
          $$SoundsTableFilterComposer,
          $$SoundsTableOrderingComposer,
          $$SoundsTableAnnotationComposer,
          $$SoundsTableCreateCompanionBuilder,
          $$SoundsTableUpdateCompanionBuilder,
          (Sound, $$SoundsTableReferences),
          Sound,
          PrefetchHooks Function({bool boardSoundsRefs, bool soundTagsRefs})
        > {
  $$SoundsTableTableManager(_$AppDatabase db, $SoundsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SoundsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SoundsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SoundsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<SoundType> type = const Value.absent(),
                Value<int?> color = const Value.absent(),
                Value<double> volume = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SoundsCompanion(
                id: id,
                title: title,
                displayName: displayName,
                filePath: filePath,
                type: type,
                color: color,
                volume: volume,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                Value<String?> displayName = const Value.absent(),
                required String filePath,
                required SoundType type,
                Value<int?> color = const Value.absent(),
                Value<double> volume = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SoundsCompanion.insert(
                id: id,
                title: title,
                displayName: displayName,
                filePath: filePath,
                type: type,
                color: color,
                volume: volume,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$SoundsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({boardSoundsRefs = false, soundTagsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (boardSoundsRefs) db.boardSounds,
                    if (soundTagsRefs) db.soundTags,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (boardSoundsRefs)
                        await $_getPrefetchedData<
                          Sound,
                          $SoundsTable,
                          BoardSound
                        >(
                          currentTable: table,
                          referencedTable: $$SoundsTableReferences
                              ._boardSoundsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SoundsTableReferences(
                                db,
                                table,
                                p0,
                              ).boardSoundsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.soundId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (soundTagsRefs)
                        await $_getPrefetchedData<
                          Sound,
                          $SoundsTable,
                          SoundTag
                        >(
                          currentTable: table,
                          referencedTable: $$SoundsTableReferences
                              ._soundTagsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SoundsTableReferences(
                                db,
                                table,
                                p0,
                              ).soundTagsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.soundId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SoundsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SoundsTable,
      Sound,
      $$SoundsTableFilterComposer,
      $$SoundsTableOrderingComposer,
      $$SoundsTableAnnotationComposer,
      $$SoundsTableCreateCompanionBuilder,
      $$SoundsTableUpdateCompanionBuilder,
      (Sound, $$SoundsTableReferences),
      Sound,
      PrefetchHooks Function({bool boardSoundsRefs, bool soundTagsRefs})
    >;
typedef $$SoundBoardsTableCreateCompanionBuilder =
    SoundBoardsCompanion Function({
      Value<int> id,
      required String name,
      Value<DateTime> createdAt,
    });
typedef $$SoundBoardsTableUpdateCompanionBuilder =
    SoundBoardsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<DateTime> createdAt,
    });

final class $$SoundBoardsTableReferences
    extends BaseReferences<_$AppDatabase, $SoundBoardsTable, SoundBoard> {
  $$SoundBoardsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BoardSoundsTable, List<BoardSound>>
  _boardSoundsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.boardSounds,
    aliasName: $_aliasNameGenerator(db.soundBoards.id, db.boardSounds.boardId),
  );

  $$BoardSoundsTableProcessedTableManager get boardSoundsRefs {
    final manager = $$BoardSoundsTableTableManager(
      $_db,
      $_db.boardSounds,
    ).filter((f) => f.boardId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_boardSoundsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SoundBoardsTableFilterComposer
    extends Composer<_$AppDatabase, $SoundBoardsTable> {
  $$SoundBoardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> boardSoundsRefs(
    Expression<bool> Function($$BoardSoundsTableFilterComposer f) f,
  ) {
    final $$BoardSoundsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.boardSounds,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardSoundsTableFilterComposer(
            $db: $db,
            $table: $db.boardSounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SoundBoardsTableOrderingComposer
    extends Composer<_$AppDatabase, $SoundBoardsTable> {
  $$SoundBoardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SoundBoardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SoundBoardsTable> {
  $$SoundBoardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> boardSoundsRefs<T extends Object>(
    Expression<T> Function($$BoardSoundsTableAnnotationComposer a) f,
  ) {
    final $$BoardSoundsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.boardSounds,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardSoundsTableAnnotationComposer(
            $db: $db,
            $table: $db.boardSounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SoundBoardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SoundBoardsTable,
          SoundBoard,
          $$SoundBoardsTableFilterComposer,
          $$SoundBoardsTableOrderingComposer,
          $$SoundBoardsTableAnnotationComposer,
          $$SoundBoardsTableCreateCompanionBuilder,
          $$SoundBoardsTableUpdateCompanionBuilder,
          (SoundBoard, $$SoundBoardsTableReferences),
          SoundBoard,
          PrefetchHooks Function({bool boardSoundsRefs})
        > {
  $$SoundBoardsTableTableManager(_$AppDatabase db, $SoundBoardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SoundBoardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SoundBoardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SoundBoardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SoundBoardsCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<DateTime> createdAt = const Value.absent(),
              }) => SoundBoardsCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SoundBoardsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({boardSoundsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (boardSoundsRefs) db.boardSounds],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (boardSoundsRefs)
                    await $_getPrefetchedData<
                      SoundBoard,
                      $SoundBoardsTable,
                      BoardSound
                    >(
                      currentTable: table,
                      referencedTable: $$SoundBoardsTableReferences
                          ._boardSoundsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$SoundBoardsTableReferences(
                            db,
                            table,
                            p0,
                          ).boardSoundsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.boardId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SoundBoardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SoundBoardsTable,
      SoundBoard,
      $$SoundBoardsTableFilterComposer,
      $$SoundBoardsTableOrderingComposer,
      $$SoundBoardsTableAnnotationComposer,
      $$SoundBoardsTableCreateCompanionBuilder,
      $$SoundBoardsTableUpdateCompanionBuilder,
      (SoundBoard, $$SoundBoardsTableReferences),
      SoundBoard,
      PrefetchHooks Function({bool boardSoundsRefs})
    >;
typedef $$WatchedPathsTableCreateCompanionBuilder =
    WatchedPathsCompanion Function({
      Value<int> id,
      required String path,
      Value<bool> isDirectory,
      Value<DateTime> addedAt,
    });
typedef $$WatchedPathsTableUpdateCompanionBuilder =
    WatchedPathsCompanion Function({
      Value<int> id,
      Value<String> path,
      Value<bool> isDirectory,
      Value<DateTime> addedAt,
    });

class $$WatchedPathsTableFilterComposer
    extends Composer<_$AppDatabase, $WatchedPathsTable> {
  $$WatchedPathsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDirectory => $composableBuilder(
    column: $table.isDirectory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WatchedPathsTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchedPathsTable> {
  $$WatchedPathsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDirectory => $composableBuilder(
    column: $table.isDirectory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WatchedPathsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchedPathsTable> {
  $$WatchedPathsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<bool> get isDirectory => $composableBuilder(
    column: $table.isDirectory,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$WatchedPathsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WatchedPathsTable,
          WatchedPath,
          $$WatchedPathsTableFilterComposer,
          $$WatchedPathsTableOrderingComposer,
          $$WatchedPathsTableAnnotationComposer,
          $$WatchedPathsTableCreateCompanionBuilder,
          $$WatchedPathsTableUpdateCompanionBuilder,
          (
            WatchedPath,
            BaseReferences<_$AppDatabase, $WatchedPathsTable, WatchedPath>,
          ),
          WatchedPath,
          PrefetchHooks Function()
        > {
  $$WatchedPathsTableTableManager(_$AppDatabase db, $WatchedPathsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchedPathsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchedPathsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchedPathsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<bool> isDirectory = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
              }) => WatchedPathsCompanion(
                id: id,
                path: path,
                isDirectory: isDirectory,
                addedAt: addedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String path,
                Value<bool> isDirectory = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
              }) => WatchedPathsCompanion.insert(
                id: id,
                path: path,
                isDirectory: isDirectory,
                addedAt: addedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WatchedPathsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WatchedPathsTable,
      WatchedPath,
      $$WatchedPathsTableFilterComposer,
      $$WatchedPathsTableOrderingComposer,
      $$WatchedPathsTableAnnotationComposer,
      $$WatchedPathsTableCreateCompanionBuilder,
      $$WatchedPathsTableUpdateCompanionBuilder,
      (
        WatchedPath,
        BaseReferences<_$AppDatabase, $WatchedPathsTable, WatchedPath>,
      ),
      WatchedPath,
      PrefetchHooks Function()
    >;
typedef $$BoardSoundsTableCreateCompanionBuilder =
    BoardSoundsCompanion Function({
      required int boardId,
      required int soundId,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });
typedef $$BoardSoundsTableUpdateCompanionBuilder =
    BoardSoundsCompanion Function({
      Value<int> boardId,
      Value<int> soundId,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

final class $$BoardSoundsTableReferences
    extends BaseReferences<_$AppDatabase, $BoardSoundsTable, BoardSound> {
  $$BoardSoundsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SoundBoardsTable _boardIdTable(_$AppDatabase db) =>
      db.soundBoards.createAlias(
        $_aliasNameGenerator(db.boardSounds.boardId, db.soundBoards.id),
      );

  $$SoundBoardsTableProcessedTableManager get boardId {
    final $_column = $_itemColumn<int>('board_id')!;

    final manager = $$SoundBoardsTableTableManager(
      $_db,
      $_db.soundBoards,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_boardIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SoundsTable _soundIdTable(_$AppDatabase db) => db.sounds.createAlias(
    $_aliasNameGenerator(db.boardSounds.soundId, db.sounds.id),
  );

  $$SoundsTableProcessedTableManager get soundId {
    final $_column = $_itemColumn<int>('sound_id')!;

    final manager = $$SoundsTableTableManager(
      $_db,
      $_db.sounds,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_soundIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BoardSoundsTableFilterComposer
    extends Composer<_$AppDatabase, $BoardSoundsTable> {
  $$BoardSoundsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SoundBoardsTableFilterComposer get boardId {
    final $$SoundBoardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.soundBoards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SoundBoardsTableFilterComposer(
            $db: $db,
            $table: $db.soundBoards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SoundsTableFilterComposer get soundId {
    final $$SoundsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.soundId,
      referencedTable: $db.sounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SoundsTableFilterComposer(
            $db: $db,
            $table: $db.sounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BoardSoundsTableOrderingComposer
    extends Composer<_$AppDatabase, $BoardSoundsTable> {
  $$BoardSoundsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SoundBoardsTableOrderingComposer get boardId {
    final $$SoundBoardsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.soundBoards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SoundBoardsTableOrderingComposer(
            $db: $db,
            $table: $db.soundBoards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SoundsTableOrderingComposer get soundId {
    final $$SoundsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.soundId,
      referencedTable: $db.sounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SoundsTableOrderingComposer(
            $db: $db,
            $table: $db.sounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BoardSoundsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BoardSoundsTable> {
  $$BoardSoundsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  $$SoundBoardsTableAnnotationComposer get boardId {
    final $$SoundBoardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.soundBoards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SoundBoardsTableAnnotationComposer(
            $db: $db,
            $table: $db.soundBoards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SoundsTableAnnotationComposer get soundId {
    final $$SoundsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.soundId,
      referencedTable: $db.sounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SoundsTableAnnotationComposer(
            $db: $db,
            $table: $db.sounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BoardSoundsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BoardSoundsTable,
          BoardSound,
          $$BoardSoundsTableFilterComposer,
          $$BoardSoundsTableOrderingComposer,
          $$BoardSoundsTableAnnotationComposer,
          $$BoardSoundsTableCreateCompanionBuilder,
          $$BoardSoundsTableUpdateCompanionBuilder,
          (BoardSound, $$BoardSoundsTableReferences),
          BoardSound,
          PrefetchHooks Function({bool boardId, bool soundId})
        > {
  $$BoardSoundsTableTableManager(_$AppDatabase db, $BoardSoundsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BoardSoundsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BoardSoundsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BoardSoundsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> boardId = const Value.absent(),
                Value<int> soundId = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BoardSoundsCompanion(
                boardId: boardId,
                soundId: soundId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int boardId,
                required int soundId,
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BoardSoundsCompanion.insert(
                boardId: boardId,
                soundId: soundId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BoardSoundsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({boardId = false, soundId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (boardId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.boardId,
                                referencedTable: $$BoardSoundsTableReferences
                                    ._boardIdTable(db),
                                referencedColumn: $$BoardSoundsTableReferences
                                    ._boardIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (soundId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.soundId,
                                referencedTable: $$BoardSoundsTableReferences
                                    ._soundIdTable(db),
                                referencedColumn: $$BoardSoundsTableReferences
                                    ._soundIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BoardSoundsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BoardSoundsTable,
      BoardSound,
      $$BoardSoundsTableFilterComposer,
      $$BoardSoundsTableOrderingComposer,
      $$BoardSoundsTableAnnotationComposer,
      $$BoardSoundsTableCreateCompanionBuilder,
      $$BoardSoundsTableUpdateCompanionBuilder,
      (BoardSound, $$BoardSoundsTableReferences),
      BoardSound,
      PrefetchHooks Function({bool boardId, bool soundId})
    >;
typedef $$TagCategoriesTableCreateCompanionBuilder =
    TagCategoriesCompanion Function({
      Value<int> id,
      required String name,
      required int color,
      Value<int> sortOrder,
      Value<String?> description,
    });
typedef $$TagCategoriesTableUpdateCompanionBuilder =
    TagCategoriesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int> color,
      Value<int> sortOrder,
      Value<String?> description,
    });

final class $$TagCategoriesTableReferences
    extends BaseReferences<_$AppDatabase, $TagCategoriesTable, TagCategory> {
  $$TagCategoriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$TagItemsTable, List<TagItem>> _tagItemsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tagItems,
    aliasName: $_aliasNameGenerator(
      db.tagCategories.id,
      db.tagItems.categoryId,
    ),
  );

  $$TagItemsTableProcessedTableManager get tagItemsRefs {
    final manager = $$TagItemsTableTableManager(
      $_db,
      $_db.tagItems,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_tagItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TagCategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $TagCategoriesTable> {
  $$TagCategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> tagItemsRefs(
    Expression<bool> Function($$TagItemsTableFilterComposer f) f,
  ) {
    final $$TagItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tagItems,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagItemsTableFilterComposer(
            $db: $db,
            $table: $db.tagItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagCategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $TagCategoriesTable> {
  $$TagCategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagCategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagCategoriesTable> {
  $$TagCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  Expression<T> tagItemsRefs<T extends Object>(
    Expression<T> Function($$TagItemsTableAnnotationComposer a) f,
  ) {
    final $$TagItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tagItems,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.tagItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagCategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagCategoriesTable,
          TagCategory,
          $$TagCategoriesTableFilterComposer,
          $$TagCategoriesTableOrderingComposer,
          $$TagCategoriesTableAnnotationComposer,
          $$TagCategoriesTableCreateCompanionBuilder,
          $$TagCategoriesTableUpdateCompanionBuilder,
          (TagCategory, $$TagCategoriesTableReferences),
          TagCategory,
          PrefetchHooks Function({bool tagItemsRefs})
        > {
  $$TagCategoriesTableTableManager(_$AppDatabase db, $TagCategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagCategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagCategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String?> description = const Value.absent(),
              }) => TagCategoriesCompanion(
                id: id,
                name: name,
                color: color,
                sortOrder: sortOrder,
                description: description,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required int color,
                Value<int> sortOrder = const Value.absent(),
                Value<String?> description = const Value.absent(),
              }) => TagCategoriesCompanion.insert(
                id: id,
                name: name,
                color: color,
                sortOrder: sortOrder,
                description: description,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TagCategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({tagItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (tagItemsRefs) db.tagItems],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (tagItemsRefs)
                    await $_getPrefetchedData<
                      TagCategory,
                      $TagCategoriesTable,
                      TagItem
                    >(
                      currentTable: table,
                      referencedTable: $$TagCategoriesTableReferences
                          ._tagItemsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$TagCategoriesTableReferences(
                            db,
                            table,
                            p0,
                          ).tagItemsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.categoryId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TagCategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagCategoriesTable,
      TagCategory,
      $$TagCategoriesTableFilterComposer,
      $$TagCategoriesTableOrderingComposer,
      $$TagCategoriesTableAnnotationComposer,
      $$TagCategoriesTableCreateCompanionBuilder,
      $$TagCategoriesTableUpdateCompanionBuilder,
      (TagCategory, $$TagCategoriesTableReferences),
      TagCategory,
      PrefetchHooks Function({bool tagItemsRefs})
    >;
typedef $$TagItemsTableCreateCompanionBuilder =
    TagItemsCompanion Function({
      Value<int> id,
      required int categoryId,
      required String name,
      required String normalizedName,
      Value<String?> description,
    });
typedef $$TagItemsTableUpdateCompanionBuilder =
    TagItemsCompanion Function({
      Value<int> id,
      Value<int> categoryId,
      Value<String> name,
      Value<String> normalizedName,
      Value<String?> description,
    });

final class $$TagItemsTableReferences
    extends BaseReferences<_$AppDatabase, $TagItemsTable, TagItem> {
  $$TagItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TagCategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.tagCategories.createAlias(
        $_aliasNameGenerator(db.tagItems.categoryId, db.tagCategories.id),
      );

  $$TagCategoriesTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<int>('category_id')!;

    final manager = $$TagCategoriesTableTableManager(
      $_db,
      $_db.tagCategories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SoundTagsTable, List<SoundTag>>
  _soundTagsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.soundTags,
    aliasName: $_aliasNameGenerator(db.tagItems.id, db.soundTags.tagId),
  );

  $$SoundTagsTableProcessedTableManager get soundTagsRefs {
    final manager = $$SoundTagsTableTableManager(
      $_db,
      $_db.soundTags,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_soundTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TagAliasesTable, List<TagAliase>>
  _tagAliasesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.tagAliases,
    aliasName: $_aliasNameGenerator(db.tagItems.id, db.tagAliases.tagId),
  );

  $$TagAliasesTableProcessedTableManager get tagAliasesRefs {
    final manager = $$TagAliasesTableTableManager(
      $_db,
      $_db.tagAliases,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_tagAliasesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TagItemsTableFilterComposer
    extends Composer<_$AppDatabase, $TagItemsTable> {
  $$TagItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  $$TagCategoriesTableFilterComposer get categoryId {
    final $$TagCategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.tagCategories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagCategoriesTableFilterComposer(
            $db: $db,
            $table: $db.tagCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> soundTagsRefs(
    Expression<bool> Function($$SoundTagsTableFilterComposer f) f,
  ) {
    final $$SoundTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.soundTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SoundTagsTableFilterComposer(
            $db: $db,
            $table: $db.soundTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> tagAliasesRefs(
    Expression<bool> Function($$TagAliasesTableFilterComposer f) f,
  ) {
    final $$TagAliasesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tagAliases,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagAliasesTableFilterComposer(
            $db: $db,
            $table: $db.tagAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $TagItemsTable> {
  $$TagItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  $$TagCategoriesTableOrderingComposer get categoryId {
    final $$TagCategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.tagCategories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagCategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.tagCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TagItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagItemsTable> {
  $$TagItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  $$TagCategoriesTableAnnotationComposer get categoryId {
    final $$TagCategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.tagCategories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagCategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.tagCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> soundTagsRefs<T extends Object>(
    Expression<T> Function($$SoundTagsTableAnnotationComposer a) f,
  ) {
    final $$SoundTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.soundTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SoundTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.soundTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> tagAliasesRefs<T extends Object>(
    Expression<T> Function($$TagAliasesTableAnnotationComposer a) f,
  ) {
    final $$TagAliasesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tagAliases,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagAliasesTableAnnotationComposer(
            $db: $db,
            $table: $db.tagAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagItemsTable,
          TagItem,
          $$TagItemsTableFilterComposer,
          $$TagItemsTableOrderingComposer,
          $$TagItemsTableAnnotationComposer,
          $$TagItemsTableCreateCompanionBuilder,
          $$TagItemsTableUpdateCompanionBuilder,
          (TagItem, $$TagItemsTableReferences),
          TagItem,
          PrefetchHooks Function({
            bool categoryId,
            bool soundTagsRefs,
            bool tagAliasesRefs,
          })
        > {
  $$TagItemsTableTableManager(_$AppDatabase db, $TagItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> categoryId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> normalizedName = const Value.absent(),
                Value<String?> description = const Value.absent(),
              }) => TagItemsCompanion(
                id: id,
                categoryId: categoryId,
                name: name,
                normalizedName: normalizedName,
                description: description,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int categoryId,
                required String name,
                required String normalizedName,
                Value<String?> description = const Value.absent(),
              }) => TagItemsCompanion.insert(
                id: id,
                categoryId: categoryId,
                name: name,
                normalizedName: normalizedName,
                description: description,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TagItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                categoryId = false,
                soundTagsRefs = false,
                tagAliasesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (soundTagsRefs) db.soundTags,
                    if (tagAliasesRefs) db.tagAliases,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (categoryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.categoryId,
                                    referencedTable: $$TagItemsTableReferences
                                        ._categoryIdTable(db),
                                    referencedColumn: $$TagItemsTableReferences
                                        ._categoryIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (soundTagsRefs)
                        await $_getPrefetchedData<
                          TagItem,
                          $TagItemsTable,
                          SoundTag
                        >(
                          currentTable: table,
                          referencedTable: $$TagItemsTableReferences
                              ._soundTagsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TagItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).soundTagsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.tagId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (tagAliasesRefs)
                        await $_getPrefetchedData<
                          TagItem,
                          $TagItemsTable,
                          TagAliase
                        >(
                          currentTable: table,
                          referencedTable: $$TagItemsTableReferences
                              ._tagAliasesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TagItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).tagAliasesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.tagId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TagItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagItemsTable,
      TagItem,
      $$TagItemsTableFilterComposer,
      $$TagItemsTableOrderingComposer,
      $$TagItemsTableAnnotationComposer,
      $$TagItemsTableCreateCompanionBuilder,
      $$TagItemsTableUpdateCompanionBuilder,
      (TagItem, $$TagItemsTableReferences),
      TagItem,
      PrefetchHooks Function({
        bool categoryId,
        bool soundTagsRefs,
        bool tagAliasesRefs,
      })
    >;
typedef $$SoundTagsTableCreateCompanionBuilder =
    SoundTagsCompanion Function({
      required int soundId,
      required int tagId,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });
typedef $$SoundTagsTableUpdateCompanionBuilder =
    SoundTagsCompanion Function({
      Value<int> soundId,
      Value<int> tagId,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

final class $$SoundTagsTableReferences
    extends BaseReferences<_$AppDatabase, $SoundTagsTable, SoundTag> {
  $$SoundTagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SoundsTable _soundIdTable(_$AppDatabase db) => db.sounds.createAlias(
    $_aliasNameGenerator(db.soundTags.soundId, db.sounds.id),
  );

  $$SoundsTableProcessedTableManager get soundId {
    final $_column = $_itemColumn<int>('sound_id')!;

    final manager = $$SoundsTableTableManager(
      $_db,
      $_db.sounds,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_soundIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TagItemsTable _tagIdTable(_$AppDatabase db) => db.tagItems
      .createAlias($_aliasNameGenerator(db.soundTags.tagId, db.tagItems.id));

  $$TagItemsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<int>('tag_id')!;

    final manager = $$TagItemsTableTableManager(
      $_db,
      $_db.tagItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SoundTagsTableFilterComposer
    extends Composer<_$AppDatabase, $SoundTagsTable> {
  $$SoundTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SoundsTableFilterComposer get soundId {
    final $$SoundsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.soundId,
      referencedTable: $db.sounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SoundsTableFilterComposer(
            $db: $db,
            $table: $db.sounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagItemsTableFilterComposer get tagId {
    final $$TagItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tagItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagItemsTableFilterComposer(
            $db: $db,
            $table: $db.tagItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SoundTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $SoundTagsTable> {
  $$SoundTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SoundsTableOrderingComposer get soundId {
    final $$SoundsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.soundId,
      referencedTable: $db.sounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SoundsTableOrderingComposer(
            $db: $db,
            $table: $db.sounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagItemsTableOrderingComposer get tagId {
    final $$TagItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tagItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagItemsTableOrderingComposer(
            $db: $db,
            $table: $db.tagItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SoundTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SoundTagsTable> {
  $$SoundTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  $$SoundsTableAnnotationComposer get soundId {
    final $$SoundsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.soundId,
      referencedTable: $db.sounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SoundsTableAnnotationComposer(
            $db: $db,
            $table: $db.sounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagItemsTableAnnotationComposer get tagId {
    final $$TagItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tagItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.tagItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SoundTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SoundTagsTable,
          SoundTag,
          $$SoundTagsTableFilterComposer,
          $$SoundTagsTableOrderingComposer,
          $$SoundTagsTableAnnotationComposer,
          $$SoundTagsTableCreateCompanionBuilder,
          $$SoundTagsTableUpdateCompanionBuilder,
          (SoundTag, $$SoundTagsTableReferences),
          SoundTag,
          PrefetchHooks Function({bool soundId, bool tagId})
        > {
  $$SoundTagsTableTableManager(_$AppDatabase db, $SoundTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SoundTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SoundTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SoundTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> soundId = const Value.absent(),
                Value<int> tagId = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SoundTagsCompanion(
                soundId: soundId,
                tagId: tagId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int soundId,
                required int tagId,
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SoundTagsCompanion.insert(
                soundId: soundId,
                tagId: tagId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SoundTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({soundId = false, tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (soundId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.soundId,
                                referencedTable: $$SoundTagsTableReferences
                                    ._soundIdTable(db),
                                referencedColumn: $$SoundTagsTableReferences
                                    ._soundIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (tagId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.tagId,
                                referencedTable: $$SoundTagsTableReferences
                                    ._tagIdTable(db),
                                referencedColumn: $$SoundTagsTableReferences
                                    ._tagIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SoundTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SoundTagsTable,
      SoundTag,
      $$SoundTagsTableFilterComposer,
      $$SoundTagsTableOrderingComposer,
      $$SoundTagsTableAnnotationComposer,
      $$SoundTagsTableCreateCompanionBuilder,
      $$SoundTagsTableUpdateCompanionBuilder,
      (SoundTag, $$SoundTagsTableReferences),
      SoundTag,
      PrefetchHooks Function({bool soundId, bool tagId})
    >;
typedef $$TagAliasesTableCreateCompanionBuilder =
    TagAliasesCompanion Function({
      Value<int> id,
      required int tagId,
      required String alias,
      required String normalizedAlias,
    });
typedef $$TagAliasesTableUpdateCompanionBuilder =
    TagAliasesCompanion Function({
      Value<int> id,
      Value<int> tagId,
      Value<String> alias,
      Value<String> normalizedAlias,
    });

final class $$TagAliasesTableReferences
    extends BaseReferences<_$AppDatabase, $TagAliasesTable, TagAliase> {
  $$TagAliasesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TagItemsTable _tagIdTable(_$AppDatabase db) => db.tagItems
      .createAlias($_aliasNameGenerator(db.tagAliases.tagId, db.tagItems.id));

  $$TagItemsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<int>('tag_id')!;

    final manager = $$TagItemsTableTableManager(
      $_db,
      $_db.tagItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TagAliasesTableFilterComposer
    extends Composer<_$AppDatabase, $TagAliasesTable> {
  $$TagAliasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedAlias => $composableBuilder(
    column: $table.normalizedAlias,
    builder: (column) => ColumnFilters(column),
  );

  $$TagItemsTableFilterComposer get tagId {
    final $$TagItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tagItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagItemsTableFilterComposer(
            $db: $db,
            $table: $db.tagItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TagAliasesTableOrderingComposer
    extends Composer<_$AppDatabase, $TagAliasesTable> {
  $$TagAliasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedAlias => $composableBuilder(
    column: $table.normalizedAlias,
    builder: (column) => ColumnOrderings(column),
  );

  $$TagItemsTableOrderingComposer get tagId {
    final $$TagItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tagItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagItemsTableOrderingComposer(
            $db: $db,
            $table: $db.tagItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TagAliasesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagAliasesTable> {
  $$TagAliasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get alias =>
      $composableBuilder(column: $table.alias, builder: (column) => column);

  GeneratedColumn<String> get normalizedAlias => $composableBuilder(
    column: $table.normalizedAlias,
    builder: (column) => column,
  );

  $$TagItemsTableAnnotationComposer get tagId {
    final $$TagItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tagItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.tagItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TagAliasesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagAliasesTable,
          TagAliase,
          $$TagAliasesTableFilterComposer,
          $$TagAliasesTableOrderingComposer,
          $$TagAliasesTableAnnotationComposer,
          $$TagAliasesTableCreateCompanionBuilder,
          $$TagAliasesTableUpdateCompanionBuilder,
          (TagAliase, $$TagAliasesTableReferences),
          TagAliase,
          PrefetchHooks Function({bool tagId})
        > {
  $$TagAliasesTableTableManager(_$AppDatabase db, $TagAliasesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagAliasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagAliasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagAliasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> tagId = const Value.absent(),
                Value<String> alias = const Value.absent(),
                Value<String> normalizedAlias = const Value.absent(),
              }) => TagAliasesCompanion(
                id: id,
                tagId: tagId,
                alias: alias,
                normalizedAlias: normalizedAlias,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int tagId,
                required String alias,
                required String normalizedAlias,
              }) => TagAliasesCompanion.insert(
                id: id,
                tagId: tagId,
                alias: alias,
                normalizedAlias: normalizedAlias,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TagAliasesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (tagId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.tagId,
                                referencedTable: $$TagAliasesTableReferences
                                    ._tagIdTable(db),
                                referencedColumn: $$TagAliasesTableReferences
                                    ._tagIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TagAliasesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagAliasesTable,
      TagAliase,
      $$TagAliasesTableFilterComposer,
      $$TagAliasesTableOrderingComposer,
      $$TagAliasesTableAnnotationComposer,
      $$TagAliasesTableCreateCompanionBuilder,
      $$TagAliasesTableUpdateCompanionBuilder,
      (TagAliase, $$TagAliasesTableReferences),
      TagAliase,
      PrefetchHooks Function({bool tagId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SoundsTableTableManager get sounds =>
      $$SoundsTableTableManager(_db, _db.sounds);
  $$SoundBoardsTableTableManager get soundBoards =>
      $$SoundBoardsTableTableManager(_db, _db.soundBoards);
  $$WatchedPathsTableTableManager get watchedPaths =>
      $$WatchedPathsTableTableManager(_db, _db.watchedPaths);
  $$BoardSoundsTableTableManager get boardSounds =>
      $$BoardSoundsTableTableManager(_db, _db.boardSounds);
  $$TagCategoriesTableTableManager get tagCategories =>
      $$TagCategoriesTableTableManager(_db, _db.tagCategories);
  $$TagItemsTableTableManager get tagItems =>
      $$TagItemsTableTableManager(_db, _db.tagItems);
  $$SoundTagsTableTableManager get soundTags =>
      $$SoundTagsTableTableManager(_db, _db.soundTags);
  $$TagAliasesTableTableManager get tagAliases =>
      $$TagAliasesTableTableManager(_db, _db.tagAliases);
}
