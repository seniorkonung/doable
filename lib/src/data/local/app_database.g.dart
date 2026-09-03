// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class Intentions extends Table with TableInfo<Intentions, Intention> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Intentions(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (title <> \'\')',
  );
  static const VerificationMeta _titleSearchKeyMeta = const VerificationMeta(
    'titleSearchKey',
  );
  late final GeneratedColumn<String> titleSearchKey = GeneratedColumn<String>(
    'title_search_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (title_search_key <> \'\')',
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (description IS NULL OR length(trim(description, char(9) || char(10) || char(11) || char(12) || char(13) || char(32))) > 0)',
  );
  static const VerificationMeta _isActionReadyMeta = const VerificationMeta(
    'isActionReady',
  );
  late final GeneratedColumn<bool> isActionReady = GeneratedColumn<bool>(
    'is_action_ready',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT FALSE CHECK (is_action_ready IN (0, 1))',
    defaultValue: const CustomExpression('FALSE'),
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT FALSE CHECK (is_archived IN (0, 1))',
    defaultValue: const CustomExpression('FALSE'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    titleSearchKey,
    description,
    isActionReady,
    isArchived,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'intentions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Intention> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('title_search_key')) {
      context.handle(
        _titleSearchKeyMeta,
        titleSearchKey.isAcceptableOrUnknown(
          data['title_search_key']!,
          _titleSearchKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_titleSearchKeyMeta);
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
    if (data.containsKey('is_action_ready')) {
      context.handle(
        _isActionReadyMeta,
        isActionReady.isAcceptableOrUnknown(
          data['is_action_ready']!,
          _isActionReadyMeta,
        ),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Intention map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Intention(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      titleSearchKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_search_key'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      isActionReady: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_action_ready'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  Intentions createAlias(String alias) {
    return Intentions(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Intention extends DataClass implements Insertable<Intention> {
  final String id;
  final String title;
  final String titleSearchKey;
  final String? description;
  final bool isActionReady;
  final bool isArchived;
  final int createdAt;
  final int updatedAt;
  const Intention({
    required this.id,
    required this.title,
    required this.titleSearchKey,
    this.description,
    required this.isActionReady,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['title_search_key'] = Variable<String>(titleSearchKey);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['is_action_ready'] = Variable<bool>(isActionReady);
    map['is_archived'] = Variable<bool>(isArchived);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  IntentionsCompanion toCompanion(bool nullToAbsent) {
    return IntentionsCompanion(
      id: Value(id),
      title: Value(title),
      titleSearchKey: Value(titleSearchKey),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      isActionReady: Value(isActionReady),
      isArchived: Value(isArchived),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Intention.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Intention(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      titleSearchKey: serializer.fromJson<String>(json['title_search_key']),
      description: serializer.fromJson<String?>(json['description']),
      isActionReady: serializer.fromJson<bool>(json['is_action_ready']),
      isArchived: serializer.fromJson<bool>(json['is_archived']),
      createdAt: serializer.fromJson<int>(json['created_at']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'title_search_key': serializer.toJson<String>(titleSearchKey),
      'description': serializer.toJson<String?>(description),
      'is_action_ready': serializer.toJson<bool>(isActionReady),
      'is_archived': serializer.toJson<bool>(isArchived),
      'created_at': serializer.toJson<int>(createdAt),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  Intention copyWith({
    String? id,
    String? title,
    String? titleSearchKey,
    Value<String?> description = const Value.absent(),
    bool? isActionReady,
    bool? isArchived,
    int? createdAt,
    int? updatedAt,
  }) => Intention(
    id: id ?? this.id,
    title: title ?? this.title,
    titleSearchKey: titleSearchKey ?? this.titleSearchKey,
    description: description.present ? description.value : this.description,
    isActionReady: isActionReady ?? this.isActionReady,
    isArchived: isArchived ?? this.isArchived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Intention copyWithCompanion(IntentionsCompanion data) {
    return Intention(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      titleSearchKey: data.titleSearchKey.present
          ? data.titleSearchKey.value
          : this.titleSearchKey,
      description: data.description.present
          ? data.description.value
          : this.description,
      isActionReady: data.isActionReady.present
          ? data.isActionReady.value
          : this.isActionReady,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Intention(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('titleSearchKey: $titleSearchKey, ')
          ..write('description: $description, ')
          ..write('isActionReady: $isActionReady, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    titleSearchKey,
    description,
    isActionReady,
    isArchived,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Intention &&
          other.id == this.id &&
          other.title == this.title &&
          other.titleSearchKey == this.titleSearchKey &&
          other.description == this.description &&
          other.isActionReady == this.isActionReady &&
          other.isArchived == this.isArchived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class IntentionsCompanion extends UpdateCompanion<Intention> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> titleSearchKey;
  final Value<String?> description;
  final Value<bool> isActionReady;
  final Value<bool> isArchived;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const IntentionsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.titleSearchKey = const Value.absent(),
    this.description = const Value.absent(),
    this.isActionReady = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IntentionsCompanion.insert({
    required String id,
    required String title,
    required String titleSearchKey,
    this.description = const Value.absent(),
    this.isActionReady = const Value.absent(),
    this.isArchived = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       titleSearchKey = Value(titleSearchKey),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Intention> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? titleSearchKey,
    Expression<String>? description,
    Expression<bool>? isActionReady,
    Expression<bool>? isArchived,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (titleSearchKey != null) 'title_search_key': titleSearchKey,
      if (description != null) 'description': description,
      if (isActionReady != null) 'is_action_ready': isActionReady,
      if (isArchived != null) 'is_archived': isArchived,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IntentionsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? titleSearchKey,
    Value<String?>? description,
    Value<bool>? isActionReady,
    Value<bool>? isArchived,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return IntentionsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      titleSearchKey: titleSearchKey ?? this.titleSearchKey,
      description: description ?? this.description,
      isActionReady: isActionReady ?? this.isActionReady,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (titleSearchKey.present) {
      map['title_search_key'] = Variable<String>(titleSearchKey.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (isActionReady.present) {
      map['is_action_ready'] = Variable<bool>(isActionReady.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IntentionsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('titleSearchKey: $titleSearchKey, ')
          ..write('description: $description, ')
          ..write('isActionReady: $isActionReady, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class IntentionTitlesFts extends Table
    with
        TableInfo<IntentionTitlesFts, IntentionTitlesFt>,
        VirtualTableInfo<IntentionTitlesFts, IntentionTitlesFt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  IntentionTitlesFts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _titleSearchKeyMeta = const VerificationMeta(
    'titleSearchKey',
  );
  late final GeneratedColumn<String> titleSearchKey = GeneratedColumn<String>(
    'title_search_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [title, titleSearchKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'intention_titles_fts';
  @override
  VerificationContext validateIntegrity(
    Insertable<IntentionTitlesFt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('title_search_key')) {
      context.handle(
        _titleSearchKeyMeta,
        titleSearchKey.isAcceptableOrUnknown(
          data['title_search_key']!,
          _titleSearchKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_titleSearchKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  IntentionTitlesFt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IntentionTitlesFt(
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      titleSearchKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_search_key'],
      )!,
    );
  }

  @override
  IntentionTitlesFts createAlias(String alias) {
    return IntentionTitlesFts(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
  @override
  String get moduleAndArgs =>
      'fts5(title, title_search_key, content = \'intentions\', content_rowid = \'rowid\', tokenize = \'trigram case_sensitive 0 remove_diacritics 0\')';
}

class IntentionTitlesFt extends DataClass
    implements Insertable<IntentionTitlesFt> {
  final String title;
  final String titleSearchKey;
  const IntentionTitlesFt({required this.title, required this.titleSearchKey});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['title'] = Variable<String>(title);
    map['title_search_key'] = Variable<String>(titleSearchKey);
    return map;
  }

  IntentionTitlesFtsCompanion toCompanion(bool nullToAbsent) {
    return IntentionTitlesFtsCompanion(
      title: Value(title),
      titleSearchKey: Value(titleSearchKey),
    );
  }

  factory IntentionTitlesFt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IntentionTitlesFt(
      title: serializer.fromJson<String>(json['title']),
      titleSearchKey: serializer.fromJson<String>(json['title_search_key']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'title': serializer.toJson<String>(title),
      'title_search_key': serializer.toJson<String>(titleSearchKey),
    };
  }

  IntentionTitlesFt copyWith({String? title, String? titleSearchKey}) =>
      IntentionTitlesFt(
        title: title ?? this.title,
        titleSearchKey: titleSearchKey ?? this.titleSearchKey,
      );
  IntentionTitlesFt copyWithCompanion(IntentionTitlesFtsCompanion data) {
    return IntentionTitlesFt(
      title: data.title.present ? data.title.value : this.title,
      titleSearchKey: data.titleSearchKey.present
          ? data.titleSearchKey.value
          : this.titleSearchKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IntentionTitlesFt(')
          ..write('title: $title, ')
          ..write('titleSearchKey: $titleSearchKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(title, titleSearchKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IntentionTitlesFt &&
          other.title == this.title &&
          other.titleSearchKey == this.titleSearchKey);
}

class IntentionTitlesFtsCompanion extends UpdateCompanion<IntentionTitlesFt> {
  final Value<String> title;
  final Value<String> titleSearchKey;
  final Value<int> rowid;
  const IntentionTitlesFtsCompanion({
    this.title = const Value.absent(),
    this.titleSearchKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IntentionTitlesFtsCompanion.insert({
    required String title,
    required String titleSearchKey,
    this.rowid = const Value.absent(),
  }) : title = Value(title),
       titleSearchKey = Value(titleSearchKey);
  static Insertable<IntentionTitlesFt> custom({
    Expression<String>? title,
    Expression<String>? titleSearchKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (title != null) 'title': title,
      if (titleSearchKey != null) 'title_search_key': titleSearchKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IntentionTitlesFtsCompanion copyWith({
    Value<String>? title,
    Value<String>? titleSearchKey,
    Value<int>? rowid,
  }) {
    return IntentionTitlesFtsCompanion(
      title: title ?? this.title,
      titleSearchKey: titleSearchKey ?? this.titleSearchKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (titleSearchKey.present) {
      map['title_search_key'] = Variable<String>(titleSearchKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IntentionTitlesFtsCompanion(')
          ..write('title: $title, ')
          ..write('titleSearchKey: $titleSearchKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final Intentions intentions = Intentions(this);
  late final IntentionTitlesFts intentionTitlesFts = IntentionTitlesFts(this);
  late final Trigger intentionsFtsAfterInsert = Trigger(
    'CREATE TRIGGER intentions_fts_after_insert AFTER INSERT ON intentions BEGIN INSERT INTO intention_titles_fts ("rowid", title, title_search_key) VALUES (new."rowid", new.title, new.title_search_key);END',
    'intentions_fts_after_insert',
  );
  late final Trigger intentionsFtsAfterUpdateSearchContent = Trigger(
    'CREATE TRIGGER intentions_fts_after_update_search_content AFTER UPDATE OF title, title_search_key ON intentions BEGIN INSERT INTO intention_titles_fts (intention_titles_fts, "rowid", title, title_search_key) VALUES (\'delete\', old."rowid", old.title, old.title_search_key);INSERT INTO intention_titles_fts ("rowid", title, title_search_key) VALUES (new."rowid", new.title, new.title_search_key);END',
    'intentions_fts_after_update_search_content',
  );
  late final Trigger intentionsFtsAfterDelete = Trigger(
    'CREATE TRIGGER intentions_fts_after_delete AFTER DELETE ON intentions BEGIN INSERT INTO intention_titles_fts (intention_titles_fts, "rowid", title, title_search_key) VALUES (\'delete\', old."rowid", old.title, old.title_search_key);END',
    'intentions_fts_after_delete',
  );
  late final Index intentionsActiveCreatedAtAscIdAsc = Index(
    'intentions_active_created_at_asc_id_asc',
    'CREATE INDEX intentions_active_created_at_asc_id_asc ON intentions (created_at ASC, id ASC) WHERE is_archived = 0',
  );
  late final Index intentionsActiveCreatedAtDescIdAsc = Index(
    'intentions_active_created_at_desc_id_asc',
    'CREATE INDEX intentions_active_created_at_desc_id_asc ON intentions (created_at DESC, id ASC) WHERE is_archived = 0',
  );
  late final Index intentionsActiveUpdatedAtAscIdAsc = Index(
    'intentions_active_updated_at_asc_id_asc',
    'CREATE INDEX intentions_active_updated_at_asc_id_asc ON intentions (updated_at ASC, id ASC) WHERE is_archived = 0',
  );
  late final Index intentionsActiveUpdatedAtDescIdAsc = Index(
    'intentions_active_updated_at_desc_id_asc',
    'CREATE INDEX intentions_active_updated_at_desc_id_asc ON intentions (updated_at DESC, id ASC) WHERE is_archived = 0',
  );
  late final Index intentionsArchivedCreatedAtAscIdAsc = Index(
    'intentions_archived_created_at_asc_id_asc',
    'CREATE INDEX intentions_archived_created_at_asc_id_asc ON intentions (created_at ASC, id ASC) WHERE is_archived = 1',
  );
  late final Index intentionsArchivedCreatedAtDescIdAsc = Index(
    'intentions_archived_created_at_desc_id_asc',
    'CREATE INDEX intentions_archived_created_at_desc_id_asc ON intentions (created_at DESC, id ASC) WHERE is_archived = 1',
  );
  late final Index intentionsArchivedUpdatedAtAscIdAsc = Index(
    'intentions_archived_updated_at_asc_id_asc',
    'CREATE INDEX intentions_archived_updated_at_asc_id_asc ON intentions (updated_at ASC, id ASC) WHERE is_archived = 1',
  );
  late final Index intentionsArchivedUpdatedAtDescIdAsc = Index(
    'intentions_archived_updated_at_desc_id_asc',
    'CREATE INDEX intentions_archived_updated_at_desc_id_asc ON intentions (updated_at DESC, id ASC) WHERE is_archived = 1',
  );
  late final Index intentionsAllCreatedAtAscIdAsc = Index(
    'intentions_all_created_at_asc_id_asc',
    'CREATE INDEX intentions_all_created_at_asc_id_asc ON intentions (created_at ASC, id ASC)',
  );
  late final Index intentionsAllCreatedAtDescIdAsc = Index(
    'intentions_all_created_at_desc_id_asc',
    'CREATE INDEX intentions_all_created_at_desc_id_asc ON intentions (created_at DESC, id ASC)',
  );
  late final Index intentionsAllUpdatedAtAscIdAsc = Index(
    'intentions_all_updated_at_asc_id_asc',
    'CREATE INDEX intentions_all_updated_at_asc_id_asc ON intentions (updated_at ASC, id ASC)',
  );
  late final Index intentionsAllUpdatedAtDescIdAsc = Index(
    'intentions_all_updated_at_desc_id_asc',
    'CREATE INDEX intentions_all_updated_at_desc_id_asc ON intentions (updated_at DESC, id ASC)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    intentions,
    intentionTitlesFts,
    intentionsFtsAfterInsert,
    intentionsFtsAfterUpdateSearchContent,
    intentionsFtsAfterDelete,
    intentionsActiveCreatedAtAscIdAsc,
    intentionsActiveCreatedAtDescIdAsc,
    intentionsActiveUpdatedAtAscIdAsc,
    intentionsActiveUpdatedAtDescIdAsc,
    intentionsArchivedCreatedAtAscIdAsc,
    intentionsArchivedCreatedAtDescIdAsc,
    intentionsArchivedUpdatedAtAscIdAsc,
    intentionsArchivedUpdatedAtDescIdAsc,
    intentionsAllCreatedAtAscIdAsc,
    intentionsAllCreatedAtDescIdAsc,
    intentionsAllUpdatedAtAscIdAsc,
    intentionsAllUpdatedAtDescIdAsc,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'intentions',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [TableUpdate('intention_titles_fts', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'intentions',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [TableUpdate('intention_titles_fts', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'intentions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('intention_titles_fts', kind: UpdateKind.insert)],
    ),
  ]);
}

typedef $IntentionsCreateCompanionBuilder = IntentionsCompanion Function({
  required String id,
  required String title,
  required String titleSearchKey,
  Value<String?> description,
  Value<bool> isActionReady,
  Value<bool> isArchived,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $IntentionsUpdateCompanionBuilder = IntentionsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> titleSearchKey,
  Value<String?> description,
  Value<bool> isActionReady,
  Value<bool> isArchived,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $IntentionsFilterComposer extends Composer<_$AppDatabase, Intentions> {
  $IntentionsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleSearchKey => $composableBuilder(
    column: $table.titleSearchKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActionReady => $composableBuilder(
    column: $table.isActionReady,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $IntentionsOrderingComposer extends Composer<_$AppDatabase, Intentions> {
  $IntentionsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleSearchKey => $composableBuilder(
    column: $table.titleSearchKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActionReady => $composableBuilder(
    column: $table.isActionReady,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $IntentionsAnnotationComposer
    extends Composer<_$AppDatabase, Intentions> {
  $IntentionsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get titleSearchKey => $composableBuilder(
    column: $table.titleSearchKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActionReady => $composableBuilder(
    column: $table.isActionReady,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $IntentionsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Intentions,
          Intention,
          $IntentionsFilterComposer,
          $IntentionsOrderingComposer,
          $IntentionsAnnotationComposer,
          $IntentionsCreateCompanionBuilder,
          $IntentionsUpdateCompanionBuilder,
          (Intention, BaseReferences<_$AppDatabase, Intentions, Intention>),
          Intention,
          PrefetchHooks Function()
        > {
  $IntentionsTableManager(_$AppDatabase db, Intentions table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $IntentionsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $IntentionsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $IntentionsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> titleSearchKey = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<bool> isActionReady = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IntentionsCompanion(
                id: id,
                title: title,
                titleSearchKey: titleSearchKey,
                description: description,
                isActionReady: isActionReady,
                isArchived: isArchived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String titleSearchKey,
                Value<String?> description = const Value.absent(),
                Value<bool> isActionReady = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => IntentionsCompanion.insert(
                id: id,
                title: title,
                titleSearchKey: titleSearchKey,
                description: description,
                isActionReady: isActionReady,
                isArchived: isArchived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $IntentionsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Intentions,
      Intention,
      $IntentionsFilterComposer,
      $IntentionsOrderingComposer,
      $IntentionsAnnotationComposer,
      $IntentionsCreateCompanionBuilder,
      $IntentionsUpdateCompanionBuilder,
      (Intention, BaseReferences<_$AppDatabase, Intentions, Intention>),
      Intention,
      PrefetchHooks Function()
    >;
typedef $IntentionTitlesFtsCreateCompanionBuilder =
    IntentionTitlesFtsCompanion Function({
      required String title,
      required String titleSearchKey,
      Value<int> rowid,
    });
typedef $IntentionTitlesFtsUpdateCompanionBuilder =
    IntentionTitlesFtsCompanion Function({
      Value<String> title,
      Value<String> titleSearchKey,
      Value<int> rowid,
    });

class $IntentionTitlesFtsFilterComposer
    extends Composer<_$AppDatabase, IntentionTitlesFts> {
  $IntentionTitlesFtsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleSearchKey => $composableBuilder(
    column: $table.titleSearchKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $IntentionTitlesFtsOrderingComposer
    extends Composer<_$AppDatabase, IntentionTitlesFts> {
  $IntentionTitlesFtsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleSearchKey => $composableBuilder(
    column: $table.titleSearchKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $IntentionTitlesFtsAnnotationComposer
    extends Composer<_$AppDatabase, IntentionTitlesFts> {
  $IntentionTitlesFtsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get titleSearchKey => $composableBuilder(
    column: $table.titleSearchKey,
    builder: (column) => column,
  );
}

class $IntentionTitlesFtsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          IntentionTitlesFts,
          IntentionTitlesFt,
          $IntentionTitlesFtsFilterComposer,
          $IntentionTitlesFtsOrderingComposer,
          $IntentionTitlesFtsAnnotationComposer,
          $IntentionTitlesFtsCreateCompanionBuilder,
          $IntentionTitlesFtsUpdateCompanionBuilder,
          (
            IntentionTitlesFt,
            BaseReferences<
              _$AppDatabase,
              IntentionTitlesFts,
              IntentionTitlesFt
            >,
          ),
          IntentionTitlesFt,
          PrefetchHooks Function()
        > {
  $IntentionTitlesFtsTableManager(_$AppDatabase db, IntentionTitlesFts table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $IntentionTitlesFtsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $IntentionTitlesFtsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $IntentionTitlesFtsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> title = const Value.absent(),
                Value<String> titleSearchKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IntentionTitlesFtsCompanion(
                title: title,
                titleSearchKey: titleSearchKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String title,
                required String titleSearchKey,
                Value<int> rowid = const Value.absent(),
              }) => IntentionTitlesFtsCompanion.insert(
                title: title,
                titleSearchKey: titleSearchKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $IntentionTitlesFtsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      IntentionTitlesFts,
      IntentionTitlesFt,
      $IntentionTitlesFtsFilterComposer,
      $IntentionTitlesFtsOrderingComposer,
      $IntentionTitlesFtsAnnotationComposer,
      $IntentionTitlesFtsCreateCompanionBuilder,
      $IntentionTitlesFtsUpdateCompanionBuilder,
      (
        IntentionTitlesFt,
        BaseReferences<_$AppDatabase, IntentionTitlesFts, IntentionTitlesFt>,
      ),
      IntentionTitlesFt,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $IntentionsTableManager get intentions =>
      $IntentionsTableManager(_db, _db.intentions);
  $IntentionTitlesFtsTableManager get intentionTitlesFts =>
      $IntentionTitlesFtsTableManager(_db, _db.intentionTitlesFts);
}
