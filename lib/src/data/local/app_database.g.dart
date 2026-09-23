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
    $customConstraints: 'NOT NULL CHECK (title <> \'\' AND instr(CAST(title AS BLOB), X\'00\') = 0)',
  );
  static const VerificationMeta _titleSearchKeyMeta = const VerificationMeta(
    'titleSearchKey',
  );
  late final GeneratedColumn<String> titleSearchKey = GeneratedColumn<String>(
    'title_search_key',
    aliasedName,
    false,
    generatedAs: GeneratedAs(
      const CustomExpression('doable_title_search_key(title)'),
      true,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL GENERATED ALWAYS AS (doable_title_search_key(title)) STORED CHECK (title_search_key <> \'\' AND instr(CAST(title_search_key AS BLOB), X\'00\') = 0)',
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
    $customConstraints: 'CHECK (description IS NULL OR(instr(CAST(description AS BLOB), X\'00\') = 0 AND length(trim(description, char(9) || char(10) || char(11) || char(12) || char(13) || char(32))) > 0))',
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
  final Value<String?> description;
  final Value<bool> isActionReady;
  final Value<bool> isArchived;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const IntentionsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
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
    this.description = const Value.absent(),
    this.isActionReady = const Value.absent(),
    this.isArchived = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Intention> custom({
    Expression<String>? id,
    Expression<String>? title,
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

class DailyChoices extends Table with TableInfo<DailyChoices, DailyChoice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DailyChoices(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _creationSequenceMeta = const VerificationMeta(
    'creationSequence',
  );
  late final GeneratedColumn<int> creationSequence = GeneratedColumn<int>(
    'creation_sequence',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL PRIMARY KEY AUTOINCREMENT CHECK (creation_sequence > 0)',
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE',
  );
  static const VerificationMeta _sourceIntentionIdMeta = const VerificationMeta(
    'sourceIntentionId',
  );
  late final GeneratedColumn<String> sourceIntentionId =
      GeneratedColumn<String>(
        'source_intention_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL REFERENCES intentions(id)ON UPDATE RESTRICT ON DELETE RESTRICT',
      );
  static const VerificationMeta _selectedIntentionIdMeta =
      const VerificationMeta('selectedIntentionId');
  late final GeneratedColumn<String> selectedIntentionId =
      GeneratedColumn<String>(
        'selected_intention_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL REFERENCES intentions(id)ON UPDATE RESTRICT ON DELETE RESTRICT',
      );
  static const VerificationMeta _choiceDateMeta = const VerificationMeta(
    'choiceDate',
  );
  late final GeneratedColumn<String> choiceDate = GeneratedColumn<String>(
    'choice_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(choice_date) = \'text\' AND length(choice_date) = 10 AND choice_date GLOB \'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\')',
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
    $customConstraints: 'CHECK (description IS NULL OR(typeof(description) = \'text\' AND instr(CAST(description AS BLOB), X\'00\') = 0))',
  );
  static const VerificationMeta _isCompletedMeta = const VerificationMeta(
    'isCompleted',
  );
  late final GeneratedColumn<bool> isCompleted = GeneratedColumn<bool>(
    'is_completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(is_completed) = \'integer\' AND is_completed IN (0, 1))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    creationSequence,
    id,
    sourceIntentionId,
    selectedIntentionId,
    choiceDate,
    description,
    isCompleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_choices';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyChoice> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('creation_sequence')) {
      context.handle(
        _creationSequenceMeta,
        creationSequence.isAcceptableOrUnknown(
          data['creation_sequence']!,
          _creationSequenceMeta,
        ),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_intention_id')) {
      context.handle(
        _sourceIntentionIdMeta,
        sourceIntentionId.isAcceptableOrUnknown(
          data['source_intention_id']!,
          _sourceIntentionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceIntentionIdMeta);
    }
    if (data.containsKey('selected_intention_id')) {
      context.handle(
        _selectedIntentionIdMeta,
        selectedIntentionId.isAcceptableOrUnknown(
          data['selected_intention_id']!,
          _selectedIntentionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_selectedIntentionIdMeta);
    }
    if (data.containsKey('choice_date')) {
      context.handle(
        _choiceDateMeta,
        choiceDate.isAcceptableOrUnknown(data['choice_date']!, _choiceDateMeta),
      );
    } else if (isInserting) {
      context.missing(_choiceDateMeta);
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
    if (data.containsKey('is_completed')) {
      context.handle(
        _isCompletedMeta,
        isCompleted.isAcceptableOrUnknown(
          data['is_completed']!,
          _isCompletedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_isCompletedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {creationSequence};
  @override
  DailyChoice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyChoice(
      creationSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}creation_sequence'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceIntentionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_intention_id'],
      )!,
      selectedIntentionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}selected_intention_id'],
      )!,
      choiceDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}choice_date'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      isCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_completed'],
      )!,
    );
  }

  @override
  DailyChoices createAlias(String alias) {
    return DailyChoices(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK(source_intention_id <> selected_intention_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class DailyChoice extends DataClass implements Insertable<DailyChoice> {
  final int creationSequence;
  final String id;
  final String sourceIntentionId;
  final String selectedIntentionId;
  final String choiceDate;
  final String? description;
  final bool isCompleted;
  const DailyChoice({
    required this.creationSequence,
    required this.id,
    required this.sourceIntentionId,
    required this.selectedIntentionId,
    required this.choiceDate,
    this.description,
    required this.isCompleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['creation_sequence'] = Variable<int>(creationSequence);
    map['id'] = Variable<String>(id);
    map['source_intention_id'] = Variable<String>(sourceIntentionId);
    map['selected_intention_id'] = Variable<String>(selectedIntentionId);
    map['choice_date'] = Variable<String>(choiceDate);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['is_completed'] = Variable<bool>(isCompleted);
    return map;
  }

  DailyChoicesCompanion toCompanion(bool nullToAbsent) {
    return DailyChoicesCompanion(
      creationSequence: Value(creationSequence),
      id: Value(id),
      sourceIntentionId: Value(sourceIntentionId),
      selectedIntentionId: Value(selectedIntentionId),
      choiceDate: Value(choiceDate),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      isCompleted: Value(isCompleted),
    );
  }

  factory DailyChoice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyChoice(
      creationSequence: serializer.fromJson<int>(json['creation_sequence']),
      id: serializer.fromJson<String>(json['id']),
      sourceIntentionId: serializer.fromJson<String>(
        json['source_intention_id'],
      ),
      selectedIntentionId: serializer.fromJson<String>(
        json['selected_intention_id'],
      ),
      choiceDate: serializer.fromJson<String>(json['choice_date']),
      description: serializer.fromJson<String?>(json['description']),
      isCompleted: serializer.fromJson<bool>(json['is_completed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'creation_sequence': serializer.toJson<int>(creationSequence),
      'id': serializer.toJson<String>(id),
      'source_intention_id': serializer.toJson<String>(sourceIntentionId),
      'selected_intention_id': serializer.toJson<String>(selectedIntentionId),
      'choice_date': serializer.toJson<String>(choiceDate),
      'description': serializer.toJson<String?>(description),
      'is_completed': serializer.toJson<bool>(isCompleted),
    };
  }

  DailyChoice copyWith({
    int? creationSequence,
    String? id,
    String? sourceIntentionId,
    String? selectedIntentionId,
    String? choiceDate,
    Value<String?> description = const Value.absent(),
    bool? isCompleted,
  }) => DailyChoice(
    creationSequence: creationSequence ?? this.creationSequence,
    id: id ?? this.id,
    sourceIntentionId: sourceIntentionId ?? this.sourceIntentionId,
    selectedIntentionId: selectedIntentionId ?? this.selectedIntentionId,
    choiceDate: choiceDate ?? this.choiceDate,
    description: description.present ? description.value : this.description,
    isCompleted: isCompleted ?? this.isCompleted,
  );
  DailyChoice copyWithCompanion(DailyChoicesCompanion data) {
    return DailyChoice(
      creationSequence: data.creationSequence.present
          ? data.creationSequence.value
          : this.creationSequence,
      id: data.id.present ? data.id.value : this.id,
      sourceIntentionId: data.sourceIntentionId.present
          ? data.sourceIntentionId.value
          : this.sourceIntentionId,
      selectedIntentionId: data.selectedIntentionId.present
          ? data.selectedIntentionId.value
          : this.selectedIntentionId,
      choiceDate: data.choiceDate.present
          ? data.choiceDate.value
          : this.choiceDate,
      description: data.description.present
          ? data.description.value
          : this.description,
      isCompleted: data.isCompleted.present
          ? data.isCompleted.value
          : this.isCompleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyChoice(')
          ..write('creationSequence: $creationSequence, ')
          ..write('id: $id, ')
          ..write('sourceIntentionId: $sourceIntentionId, ')
          ..write('selectedIntentionId: $selectedIntentionId, ')
          ..write('choiceDate: $choiceDate, ')
          ..write('description: $description, ')
          ..write('isCompleted: $isCompleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    creationSequence,
    id,
    sourceIntentionId,
    selectedIntentionId,
    choiceDate,
    description,
    isCompleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyChoice &&
          other.creationSequence == this.creationSequence &&
          other.id == this.id &&
          other.sourceIntentionId == this.sourceIntentionId &&
          other.selectedIntentionId == this.selectedIntentionId &&
          other.choiceDate == this.choiceDate &&
          other.description == this.description &&
          other.isCompleted == this.isCompleted);
}

class DailyChoicesCompanion extends UpdateCompanion<DailyChoice> {
  final Value<int> creationSequence;
  final Value<String> id;
  final Value<String> sourceIntentionId;
  final Value<String> selectedIntentionId;
  final Value<String> choiceDate;
  final Value<String?> description;
  final Value<bool> isCompleted;
  const DailyChoicesCompanion({
    this.creationSequence = const Value.absent(),
    this.id = const Value.absent(),
    this.sourceIntentionId = const Value.absent(),
    this.selectedIntentionId = const Value.absent(),
    this.choiceDate = const Value.absent(),
    this.description = const Value.absent(),
    this.isCompleted = const Value.absent(),
  });
  DailyChoicesCompanion.insert({
    this.creationSequence = const Value.absent(),
    required String id,
    required String sourceIntentionId,
    required String selectedIntentionId,
    required String choiceDate,
    this.description = const Value.absent(),
    required bool isCompleted,
  }) : id = Value(id),
       sourceIntentionId = Value(sourceIntentionId),
       selectedIntentionId = Value(selectedIntentionId),
       choiceDate = Value(choiceDate),
       isCompleted = Value(isCompleted);
  static Insertable<DailyChoice> custom({
    Expression<int>? creationSequence,
    Expression<String>? id,
    Expression<String>? sourceIntentionId,
    Expression<String>? selectedIntentionId,
    Expression<String>? choiceDate,
    Expression<String>? description,
    Expression<bool>? isCompleted,
  }) {
    return RawValuesInsertable({
      if (creationSequence != null) 'creation_sequence': creationSequence,
      if (id != null) 'id': id,
      if (sourceIntentionId != null) 'source_intention_id': sourceIntentionId,
      if (selectedIntentionId != null)
        'selected_intention_id': selectedIntentionId,
      if (choiceDate != null) 'choice_date': choiceDate,
      if (description != null) 'description': description,
      if (isCompleted != null) 'is_completed': isCompleted,
    });
  }

  DailyChoicesCompanion copyWith({
    Value<int>? creationSequence,
    Value<String>? id,
    Value<String>? sourceIntentionId,
    Value<String>? selectedIntentionId,
    Value<String>? choiceDate,
    Value<String?>? description,
    Value<bool>? isCompleted,
  }) {
    return DailyChoicesCompanion(
      creationSequence: creationSequence ?? this.creationSequence,
      id: id ?? this.id,
      sourceIntentionId: sourceIntentionId ?? this.sourceIntentionId,
      selectedIntentionId: selectedIntentionId ?? this.selectedIntentionId,
      choiceDate: choiceDate ?? this.choiceDate,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (creationSequence.present) {
      map['creation_sequence'] = Variable<int>(creationSequence.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceIntentionId.present) {
      map['source_intention_id'] = Variable<String>(sourceIntentionId.value);
    }
    if (selectedIntentionId.present) {
      map['selected_intention_id'] = Variable<String>(
        selectedIntentionId.value,
      );
    }
    if (choiceDate.present) {
      map['choice_date'] = Variable<String>(choiceDate.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (isCompleted.present) {
      map['is_completed'] = Variable<bool>(isCompleted.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyChoicesCompanion(')
          ..write('creationSequence: $creationSequence, ')
          ..write('id: $id, ')
          ..write('sourceIntentionId: $sourceIntentionId, ')
          ..write('selectedIntentionId: $selectedIntentionId, ')
          ..write('choiceDate: $choiceDate, ')
          ..write('description: $description, ')
          ..write('isCompleted: $isCompleted')
          ..write(')'))
        .toString();
  }
}

class LongTermRelations extends Table
    with TableInfo<LongTermRelations, LongTermRelation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  LongTermRelations(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _creationSequenceMeta = const VerificationMeta(
    'creationSequence',
  );
  late final GeneratedColumn<int> creationSequence = GeneratedColumn<int>(
    'creation_sequence',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL PRIMARY KEY AUTOINCREMENT CHECK (creation_sequence > 0)',
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE',
  );
  static const VerificationMeta _sourceIntentionIdMeta = const VerificationMeta(
    'sourceIntentionId',
  );
  late final GeneratedColumn<String> sourceIntentionId =
      GeneratedColumn<String>(
        'source_intention_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL REFERENCES intentions(id)ON UPDATE RESTRICT ON DELETE RESTRICT',
      );
  static const VerificationMeta _relatedIntentionIdMeta =
      const VerificationMeta('relatedIntentionId');
  late final GeneratedColumn<String> relatedIntentionId =
      GeneratedColumn<String>(
        'related_intention_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL REFERENCES intentions(id)ON UPDATE RESTRICT ON DELETE RESTRICT',
      );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(type) = \'text\' AND type IN (\'need\', \'can\'))',
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(priority) = \'integer\' AND priority BETWEEN 1 AND 4)',
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
    $customConstraints: 'CHECK (description IS NULL OR(typeof(description) = \'text\' AND instr(CAST(description AS BLOB), X\'00\') = 0))',
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
    $customConstraints: 'NOT NULL DEFAULT FALSE CHECK (typeof(is_archived) = \'integer\' AND is_archived IN (0, 1))',
    defaultValue: const CustomExpression('FALSE'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    creationSequence,
    id,
    sourceIntentionId,
    relatedIntentionId,
    type,
    priority,
    description,
    isArchived,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'long_term_relations';
  @override
  VerificationContext validateIntegrity(
    Insertable<LongTermRelation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('creation_sequence')) {
      context.handle(
        _creationSequenceMeta,
        creationSequence.isAcceptableOrUnknown(
          data['creation_sequence']!,
          _creationSequenceMeta,
        ),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_intention_id')) {
      context.handle(
        _sourceIntentionIdMeta,
        sourceIntentionId.isAcceptableOrUnknown(
          data['source_intention_id']!,
          _sourceIntentionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceIntentionIdMeta);
    }
    if (data.containsKey('related_intention_id')) {
      context.handle(
        _relatedIntentionIdMeta,
        relatedIntentionId.isAcceptableOrUnknown(
          data['related_intention_id']!,
          _relatedIntentionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relatedIntentionIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    } else if (isInserting) {
      context.missing(_priorityMeta);
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
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {creationSequence};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sourceIntentionId, relatedIntentionId},
  ];
  @override
  LongTermRelation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LongTermRelation(
      creationSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}creation_sequence'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceIntentionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_intention_id'],
      )!,
      relatedIntentionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}related_intention_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
    );
  }

  @override
  LongTermRelations createAlias(String alias) {
    return LongTermRelations(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'UNIQUE(source_intention_id, related_intention_id)',
    'CHECK(source_intention_id <> related_intention_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class LongTermRelation extends DataClass
    implements Insertable<LongTermRelation> {
  final int creationSequence;
  final String id;
  final String sourceIntentionId;
  final String relatedIntentionId;
  final String type;
  final int priority;
  final String? description;
  final bool isArchived;
  const LongTermRelation({
    required this.creationSequence,
    required this.id,
    required this.sourceIntentionId,
    required this.relatedIntentionId,
    required this.type,
    required this.priority,
    this.description,
    required this.isArchived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['creation_sequence'] = Variable<int>(creationSequence);
    map['id'] = Variable<String>(id);
    map['source_intention_id'] = Variable<String>(sourceIntentionId);
    map['related_intention_id'] = Variable<String>(relatedIntentionId);
    map['type'] = Variable<String>(type);
    map['priority'] = Variable<int>(priority);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['is_archived'] = Variable<bool>(isArchived);
    return map;
  }

  LongTermRelationsCompanion toCompanion(bool nullToAbsent) {
    return LongTermRelationsCompanion(
      creationSequence: Value(creationSequence),
      id: Value(id),
      sourceIntentionId: Value(sourceIntentionId),
      relatedIntentionId: Value(relatedIntentionId),
      type: Value(type),
      priority: Value(priority),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      isArchived: Value(isArchived),
    );
  }

  factory LongTermRelation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LongTermRelation(
      creationSequence: serializer.fromJson<int>(json['creation_sequence']),
      id: serializer.fromJson<String>(json['id']),
      sourceIntentionId: serializer.fromJson<String>(
        json['source_intention_id'],
      ),
      relatedIntentionId: serializer.fromJson<String>(
        json['related_intention_id'],
      ),
      type: serializer.fromJson<String>(json['type']),
      priority: serializer.fromJson<int>(json['priority']),
      description: serializer.fromJson<String?>(json['description']),
      isArchived: serializer.fromJson<bool>(json['is_archived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'creation_sequence': serializer.toJson<int>(creationSequence),
      'id': serializer.toJson<String>(id),
      'source_intention_id': serializer.toJson<String>(sourceIntentionId),
      'related_intention_id': serializer.toJson<String>(relatedIntentionId),
      'type': serializer.toJson<String>(type),
      'priority': serializer.toJson<int>(priority),
      'description': serializer.toJson<String?>(description),
      'is_archived': serializer.toJson<bool>(isArchived),
    };
  }

  LongTermRelation copyWith({
    int? creationSequence,
    String? id,
    String? sourceIntentionId,
    String? relatedIntentionId,
    String? type,
    int? priority,
    Value<String?> description = const Value.absent(),
    bool? isArchived,
  }) => LongTermRelation(
    creationSequence: creationSequence ?? this.creationSequence,
    id: id ?? this.id,
    sourceIntentionId: sourceIntentionId ?? this.sourceIntentionId,
    relatedIntentionId: relatedIntentionId ?? this.relatedIntentionId,
    type: type ?? this.type,
    priority: priority ?? this.priority,
    description: description.present ? description.value : this.description,
    isArchived: isArchived ?? this.isArchived,
  );
  LongTermRelation copyWithCompanion(LongTermRelationsCompanion data) {
    return LongTermRelation(
      creationSequence: data.creationSequence.present
          ? data.creationSequence.value
          : this.creationSequence,
      id: data.id.present ? data.id.value : this.id,
      sourceIntentionId: data.sourceIntentionId.present
          ? data.sourceIntentionId.value
          : this.sourceIntentionId,
      relatedIntentionId: data.relatedIntentionId.present
          ? data.relatedIntentionId.value
          : this.relatedIntentionId,
      type: data.type.present ? data.type.value : this.type,
      priority: data.priority.present ? data.priority.value : this.priority,
      description: data.description.present
          ? data.description.value
          : this.description,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LongTermRelation(')
          ..write('creationSequence: $creationSequence, ')
          ..write('id: $id, ')
          ..write('sourceIntentionId: $sourceIntentionId, ')
          ..write('relatedIntentionId: $relatedIntentionId, ')
          ..write('type: $type, ')
          ..write('priority: $priority, ')
          ..write('description: $description, ')
          ..write('isArchived: $isArchived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    creationSequence,
    id,
    sourceIntentionId,
    relatedIntentionId,
    type,
    priority,
    description,
    isArchived,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LongTermRelation &&
          other.creationSequence == this.creationSequence &&
          other.id == this.id &&
          other.sourceIntentionId == this.sourceIntentionId &&
          other.relatedIntentionId == this.relatedIntentionId &&
          other.type == this.type &&
          other.priority == this.priority &&
          other.description == this.description &&
          other.isArchived == this.isArchived);
}

class LongTermRelationsCompanion extends UpdateCompanion<LongTermRelation> {
  final Value<int> creationSequence;
  final Value<String> id;
  final Value<String> sourceIntentionId;
  final Value<String> relatedIntentionId;
  final Value<String> type;
  final Value<int> priority;
  final Value<String?> description;
  final Value<bool> isArchived;
  const LongTermRelationsCompanion({
    this.creationSequence = const Value.absent(),
    this.id = const Value.absent(),
    this.sourceIntentionId = const Value.absent(),
    this.relatedIntentionId = const Value.absent(),
    this.type = const Value.absent(),
    this.priority = const Value.absent(),
    this.description = const Value.absent(),
    this.isArchived = const Value.absent(),
  });
  LongTermRelationsCompanion.insert({
    this.creationSequence = const Value.absent(),
    required String id,
    required String sourceIntentionId,
    required String relatedIntentionId,
    required String type,
    required int priority,
    this.description = const Value.absent(),
    this.isArchived = const Value.absent(),
  }) : id = Value(id),
       sourceIntentionId = Value(sourceIntentionId),
       relatedIntentionId = Value(relatedIntentionId),
       type = Value(type),
       priority = Value(priority);
  static Insertable<LongTermRelation> custom({
    Expression<int>? creationSequence,
    Expression<String>? id,
    Expression<String>? sourceIntentionId,
    Expression<String>? relatedIntentionId,
    Expression<String>? type,
    Expression<int>? priority,
    Expression<String>? description,
    Expression<bool>? isArchived,
  }) {
    return RawValuesInsertable({
      if (creationSequence != null) 'creation_sequence': creationSequence,
      if (id != null) 'id': id,
      if (sourceIntentionId != null) 'source_intention_id': sourceIntentionId,
      if (relatedIntentionId != null)
        'related_intention_id': relatedIntentionId,
      if (type != null) 'type': type,
      if (priority != null) 'priority': priority,
      if (description != null) 'description': description,
      if (isArchived != null) 'is_archived': isArchived,
    });
  }

  LongTermRelationsCompanion copyWith({
    Value<int>? creationSequence,
    Value<String>? id,
    Value<String>? sourceIntentionId,
    Value<String>? relatedIntentionId,
    Value<String>? type,
    Value<int>? priority,
    Value<String?>? description,
    Value<bool>? isArchived,
  }) {
    return LongTermRelationsCompanion(
      creationSequence: creationSequence ?? this.creationSequence,
      id: id ?? this.id,
      sourceIntentionId: sourceIntentionId ?? this.sourceIntentionId,
      relatedIntentionId: relatedIntentionId ?? this.relatedIntentionId,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      description: description ?? this.description,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (creationSequence.present) {
      map['creation_sequence'] = Variable<int>(creationSequence.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceIntentionId.present) {
      map['source_intention_id'] = Variable<String>(sourceIntentionId.value);
    }
    if (relatedIntentionId.present) {
      map['related_intention_id'] = Variable<String>(relatedIntentionId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LongTermRelationsCompanion(')
          ..write('creationSequence: $creationSequence, ')
          ..write('id: $id, ')
          ..write('sourceIntentionId: $sourceIntentionId, ')
          ..write('relatedIntentionId: $relatedIntentionId, ')
          ..write('type: $type, ')
          ..write('priority: $priority, ')
          ..write('description: $description, ')
          ..write('isArchived: $isArchived')
          ..write(')'))
        .toString();
  }
}

class DailyChoicePathSteps extends Table
    with TableInfo<DailyChoicePathSteps, DailyChoicePathStep> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DailyChoicePathSteps(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _dailyChoiceIdMeta = const VerificationMeta(
    'dailyChoiceId',
  );
  late final GeneratedColumn<String> dailyChoiceId = GeneratedColumn<String>(
    'daily_choice_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES daily_choices(id)ON UPDATE RESTRICT ON DELETE CASCADE',
  );
  static const VerificationMeta _longTermRelationIdMeta =
      const VerificationMeta('longTermRelationId');
  late final GeneratedColumn<String> longTermRelationId =
      GeneratedColumn<String>(
        'long_term_relation_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL REFERENCES long_term_relations(id)ON UPDATE RESTRICT ON DELETE RESTRICT',
      );
  static const VerificationMeta _previousStepIdMeta = const VerificationMeta(
    'previousStepId',
  );
  late final GeneratedColumn<String> previousStepId = GeneratedColumn<String>(
    'previous_step_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    dailyChoiceId,
    longTermRelationId,
    previousStepId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_choice_path_steps';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyChoicePathStep> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('daily_choice_id')) {
      context.handle(
        _dailyChoiceIdMeta,
        dailyChoiceId.isAcceptableOrUnknown(
          data['daily_choice_id']!,
          _dailyChoiceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dailyChoiceIdMeta);
    }
    if (data.containsKey('long_term_relation_id')) {
      context.handle(
        _longTermRelationIdMeta,
        longTermRelationId.isAcceptableOrUnknown(
          data['long_term_relation_id']!,
          _longTermRelationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_longTermRelationIdMeta);
    }
    if (data.containsKey('previous_step_id')) {
      context.handle(
        _previousStepIdMeta,
        previousStepId.isAcceptableOrUnknown(
          data['previous_step_id']!,
          _previousStepIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {dailyChoiceId, id},
  ];
  @override
  DailyChoicePathStep map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyChoicePathStep(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      dailyChoiceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}daily_choice_id'],
      )!,
      longTermRelationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}long_term_relation_id'],
      )!,
      previousStepId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}previous_step_id'],
      ),
    );
  }

  @override
  DailyChoicePathSteps createAlias(String alias) {
    return DailyChoicePathSteps(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'UNIQUE(daily_choice_id, id)',
    'FOREIGN KEY(daily_choice_id, previous_step_id)REFERENCES daily_choice_path_steps(daily_choice_id, id)ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED',
    'CHECK(previous_step_id IS NULL OR previous_step_id <> id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class DailyChoicePathStep extends DataClass
    implements Insertable<DailyChoicePathStep> {
  final String id;
  final String dailyChoiceId;
  final String longTermRelationId;
  final String? previousStepId;
  const DailyChoicePathStep({
    required this.id,
    required this.dailyChoiceId,
    required this.longTermRelationId,
    this.previousStepId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['daily_choice_id'] = Variable<String>(dailyChoiceId);
    map['long_term_relation_id'] = Variable<String>(longTermRelationId);
    if (!nullToAbsent || previousStepId != null) {
      map['previous_step_id'] = Variable<String>(previousStepId);
    }
    return map;
  }

  DailyChoicePathStepsCompanion toCompanion(bool nullToAbsent) {
    return DailyChoicePathStepsCompanion(
      id: Value(id),
      dailyChoiceId: Value(dailyChoiceId),
      longTermRelationId: Value(longTermRelationId),
      previousStepId: previousStepId == null && nullToAbsent
          ? const Value.absent()
          : Value(previousStepId),
    );
  }

  factory DailyChoicePathStep.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyChoicePathStep(
      id: serializer.fromJson<String>(json['id']),
      dailyChoiceId: serializer.fromJson<String>(json['daily_choice_id']),
      longTermRelationId: serializer.fromJson<String>(
        json['long_term_relation_id'],
      ),
      previousStepId: serializer.fromJson<String?>(json['previous_step_id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'daily_choice_id': serializer.toJson<String>(dailyChoiceId),
      'long_term_relation_id': serializer.toJson<String>(longTermRelationId),
      'previous_step_id': serializer.toJson<String?>(previousStepId),
    };
  }

  DailyChoicePathStep copyWith({
    String? id,
    String? dailyChoiceId,
    String? longTermRelationId,
    Value<String?> previousStepId = const Value.absent(),
  }) => DailyChoicePathStep(
    id: id ?? this.id,
    dailyChoiceId: dailyChoiceId ?? this.dailyChoiceId,
    longTermRelationId: longTermRelationId ?? this.longTermRelationId,
    previousStepId: previousStepId.present
        ? previousStepId.value
        : this.previousStepId,
  );
  DailyChoicePathStep copyWithCompanion(DailyChoicePathStepsCompanion data) {
    return DailyChoicePathStep(
      id: data.id.present ? data.id.value : this.id,
      dailyChoiceId: data.dailyChoiceId.present
          ? data.dailyChoiceId.value
          : this.dailyChoiceId,
      longTermRelationId: data.longTermRelationId.present
          ? data.longTermRelationId.value
          : this.longTermRelationId,
      previousStepId: data.previousStepId.present
          ? data.previousStepId.value
          : this.previousStepId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyChoicePathStep(')
          ..write('id: $id, ')
          ..write('dailyChoiceId: $dailyChoiceId, ')
          ..write('longTermRelationId: $longTermRelationId, ')
          ..write('previousStepId: $previousStepId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, dailyChoiceId, longTermRelationId, previousStepId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyChoicePathStep &&
          other.id == this.id &&
          other.dailyChoiceId == this.dailyChoiceId &&
          other.longTermRelationId == this.longTermRelationId &&
          other.previousStepId == this.previousStepId);
}

class DailyChoicePathStepsCompanion
    extends UpdateCompanion<DailyChoicePathStep> {
  final Value<String> id;
  final Value<String> dailyChoiceId;
  final Value<String> longTermRelationId;
  final Value<String?> previousStepId;
  final Value<int> rowid;
  const DailyChoicePathStepsCompanion({
    this.id = const Value.absent(),
    this.dailyChoiceId = const Value.absent(),
    this.longTermRelationId = const Value.absent(),
    this.previousStepId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyChoicePathStepsCompanion.insert({
    required String id,
    required String dailyChoiceId,
    required String longTermRelationId,
    this.previousStepId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       dailyChoiceId = Value(dailyChoiceId),
       longTermRelationId = Value(longTermRelationId);
  static Insertable<DailyChoicePathStep> custom({
    Expression<String>? id,
    Expression<String>? dailyChoiceId,
    Expression<String>? longTermRelationId,
    Expression<String>? previousStepId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dailyChoiceId != null) 'daily_choice_id': dailyChoiceId,
      if (longTermRelationId != null)
        'long_term_relation_id': longTermRelationId,
      if (previousStepId != null) 'previous_step_id': previousStepId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyChoicePathStepsCompanion copyWith({
    Value<String>? id,
    Value<String>? dailyChoiceId,
    Value<String>? longTermRelationId,
    Value<String?>? previousStepId,
    Value<int>? rowid,
  }) {
    return DailyChoicePathStepsCompanion(
      id: id ?? this.id,
      dailyChoiceId: dailyChoiceId ?? this.dailyChoiceId,
      longTermRelationId: longTermRelationId ?? this.longTermRelationId,
      previousStepId: previousStepId ?? this.previousStepId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (dailyChoiceId.present) {
      map['daily_choice_id'] = Variable<String>(dailyChoiceId.value);
    }
    if (longTermRelationId.present) {
      map['long_term_relation_id'] = Variable<String>(longTermRelationId.value);
    }
    if (previousStepId.present) {
      map['previous_step_id'] = Variable<String>(previousStepId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyChoicePathStepsCompanion(')
          ..write('id: $id, ')
          ..write('dailyChoiceId: $dailyChoiceId, ')
          ..write('longTermRelationId: $longTermRelationId, ')
          ..write('previousStepId: $previousStepId, ')
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
  List<GeneratedColumn> get $columns => [titleSearchKey];
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
      'fts5(title_search_key, content = \'intentions\', content_rowid = \'rowid\', tokenize = \'trigram case_sensitive 0 remove_diacritics 0\')';
}

class IntentionTitlesFt extends DataClass
    implements Insertable<IntentionTitlesFt> {
  final String titleSearchKey;
  const IntentionTitlesFt({required this.titleSearchKey});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['title_search_key'] = Variable<String>(titleSearchKey);
    return map;
  }

  IntentionTitlesFtsCompanion toCompanion(bool nullToAbsent) {
    return IntentionTitlesFtsCompanion(titleSearchKey: Value(titleSearchKey));
  }

  factory IntentionTitlesFt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IntentionTitlesFt(
      titleSearchKey: serializer.fromJson<String>(json['title_search_key']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'title_search_key': serializer.toJson<String>(titleSearchKey),
    };
  }

  IntentionTitlesFt copyWith({String? titleSearchKey}) =>
      IntentionTitlesFt(titleSearchKey: titleSearchKey ?? this.titleSearchKey);
  IntentionTitlesFt copyWithCompanion(IntentionTitlesFtsCompanion data) {
    return IntentionTitlesFt(
      titleSearchKey: data.titleSearchKey.present
          ? data.titleSearchKey.value
          : this.titleSearchKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IntentionTitlesFt(')
          ..write('titleSearchKey: $titleSearchKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => titleSearchKey.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IntentionTitlesFt &&
          other.titleSearchKey == this.titleSearchKey);
}

class IntentionTitlesFtsCompanion extends UpdateCompanion<IntentionTitlesFt> {
  final Value<String> titleSearchKey;
  final Value<int> rowid;
  const IntentionTitlesFtsCompanion({
    this.titleSearchKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IntentionTitlesFtsCompanion.insert({
    required String titleSearchKey,
    this.rowid = const Value.absent(),
  }) : titleSearchKey = Value(titleSearchKey);
  static Insertable<IntentionTitlesFt> custom({
    Expression<String>? titleSearchKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (titleSearchKey != null) 'title_search_key': titleSearchKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IntentionTitlesFtsCompanion copyWith({
    Value<String>? titleSearchKey,
    Value<int>? rowid,
  }) {
    return IntentionTitlesFtsCompanion(
      titleSearchKey: titleSearchKey ?? this.titleSearchKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
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
  late final DailyChoices dailyChoices = DailyChoices(this);
  late final Index dailyChoicesDateCreationOrder = Index(
    'daily_choices_date_creation_order',
    'CREATE INDEX daily_choices_date_creation_order ON daily_choices (choice_date, creation_sequence)',
  );
  late final Index dailyChoicesSourceDateCreationOrder = Index(
    'daily_choices_source_date_creation_order',
    'CREATE INDEX daily_choices_source_date_creation_order ON daily_choices (source_intention_id, choice_date, creation_sequence)',
  );
  late final Index dailyChoicesSelectedDateCreationOrder = Index(
    'daily_choices_selected_date_creation_order',
    'CREATE INDEX daily_choices_selected_date_creation_order ON daily_choices (selected_intention_id, choice_date, creation_sequence)',
  );
  late final Index dailyChoicesSourceRecent = Index(
    'daily_choices_source_recent',
    'CREATE INDEX daily_choices_source_recent ON daily_choices (source_intention_id, creation_sequence DESC)',
  );
  late final Index dailyChoicesSelectedRecent = Index(
    'daily_choices_selected_recent',
    'CREATE INDEX daily_choices_selected_recent ON daily_choices (selected_intention_id, creation_sequence DESC)',
  );
  late final Trigger dailyChoicesImmutableIdentity = Trigger(
    'CREATE TRIGGER daily_choices_immutable_identity AFTER UPDATE OF creation_sequence, id ON daily_choices WHEN new.creation_sequence <> old.creation_sequence OR new.id <> old.id BEGIN SELECT RAISE (ABORT, \'daily choice identity is immutable\');END',
    'daily_choices_immutable_identity',
  );
  late final LongTermRelations longTermRelations = LongTermRelations(this);
  late final DailyChoicePathSteps dailyChoicePathSteps = DailyChoicePathSteps(
    this,
  );
  late final Index dailyChoicePathStepsOneRoot = Index(
    'daily_choice_path_steps_one_root',
    'CREATE UNIQUE INDEX daily_choice_path_steps_one_root ON daily_choice_path_steps (daily_choice_id) WHERE previous_step_id IS NULL',
  );
  late final Index dailyChoicePathStepsOneSuccessor = Index(
    'daily_choice_path_steps_one_successor',
    'CREATE UNIQUE INDEX daily_choice_path_steps_one_successor ON daily_choice_path_steps (daily_choice_id, previous_step_id) WHERE previous_step_id IS NOT NULL',
  );
  late final Index dailyChoicePathStepsRelation = Index(
    'daily_choice_path_steps_relation',
    'CREATE INDEX daily_choice_path_steps_relation ON daily_choice_path_steps (long_term_relation_id)',
  );
  late final Trigger longTermRelationsProtectDailyChoicePath = Trigger(
    'CREATE TRIGGER long_term_relations_protect_daily_choice_path BEFORE UPDATE OF type, source_intention_id, related_intention_id ON long_term_relations WHEN(new.type <> old.type OR new.source_intention_id <> old.source_intention_id OR new.related_intention_id <> old.related_intention_id)AND EXISTS (SELECT 1 FROM daily_choice_path_steps WHERE long_term_relation_id = old.id) BEGIN SELECT RAISE (ABORT, \'long-term relation is used by a daily choice path\');END',
    'long_term_relations_protect_daily_choice_path',
  );
  late final Index longTermRelationsSourceGroupOrder = Index(
    'long_term_relations_source_group_order',
    'CREATE INDEX long_term_relations_source_group_order ON long_term_relations (source_intention_id, type, is_archived, priority, creation_sequence)',
  );
  late final Index longTermRelationsRelatedGroupOrder = Index(
    'long_term_relations_related_group_order',
    'CREATE INDEX long_term_relations_related_group_order ON long_term_relations (related_intention_id, type, is_archived, priority, creation_sequence)',
  );
  late final Trigger longTermRelationsImmutableIdentity = Trigger(
    'CREATE TRIGGER long_term_relations_immutable_identity AFTER UPDATE OF creation_sequence, id ON long_term_relations WHEN new.creation_sequence <> old.creation_sequence OR new.id <> old.id BEGIN SELECT RAISE (ABORT, \'long-term relation identity is immutable\');END',
    'long_term_relations_immutable_identity',
  );
  late final Trigger longTermRelationsActiveParticipantsAfterInsert = Trigger(
    'CREATE TRIGGER long_term_relations_active_participants_after_insert AFTER INSERT ON long_term_relations WHEN new.is_archived = 0 AND(NOT EXISTS (SELECT 1 FROM intentions WHERE id = new.source_intention_id AND is_archived = 0) OR NOT EXISTS (SELECT 1 FROM intentions WHERE id = new.related_intention_id AND is_archived = 0))BEGIN SELECT RAISE (ABORT, \'active relation requires active intentions\');END',
    'long_term_relations_active_participants_after_insert',
  );
  late final Trigger longTermRelationsActiveParticipantsAfterUpdate = Trigger(
    'CREATE TRIGGER long_term_relations_active_participants_after_update AFTER UPDATE OF source_intention_id, related_intention_id, is_archived ON long_term_relations WHEN new.is_archived = 0 AND(NOT EXISTS (SELECT 1 FROM intentions WHERE id = new.source_intention_id AND is_archived = 0) OR NOT EXISTS (SELECT 1 FROM intentions WHERE id = new.related_intention_id AND is_archived = 0))BEGIN SELECT RAISE (ABORT, \'active relation requires active intentions\');END',
    'long_term_relations_active_participants_after_update',
  );
  late final Trigger intentionsArchiveRequiresNoActiveRelations = Trigger(
    'CREATE TRIGGER intentions_archive_requires_no_active_relations AFTER UPDATE OF is_archived ON intentions WHEN old.is_archived = 0 AND new.is_archived = 1 AND EXISTS (SELECT 1 FROM long_term_relations WHERE is_archived = 0 AND(source_intention_id = new.id OR related_intention_id = new.id)) BEGIN SELECT RAISE (ABORT, \'active relations must be archived first\');END',
    'intentions_archive_requires_no_active_relations',
  );
  late final IntentionTitlesFts intentionTitlesFts = IntentionTitlesFts(this);
  late final Trigger intentionsFtsAfterInsert = Trigger(
    'CREATE TRIGGER intentions_fts_after_insert AFTER INSERT ON intentions BEGIN INSERT INTO intention_titles_fts ("rowid", title_search_key) VALUES (new."rowid", new.title_search_key);END',
    'intentions_fts_after_insert',
  );
  late final Trigger intentionsFtsAfterUpdateSearchContent = Trigger(
    'CREATE TRIGGER intentions_fts_after_update_search_content AFTER UPDATE ON intentions BEGIN INSERT INTO intention_titles_fts (intention_titles_fts, "rowid", title_search_key) VALUES (\'delete\', old."rowid", old.title_search_key);INSERT INTO intention_titles_fts ("rowid", title_search_key) VALUES (new."rowid", new.title_search_key);END',
    'intentions_fts_after_update_search_content',
  );
  late final Trigger intentionsFtsAfterDelete = Trigger(
    'CREATE TRIGGER intentions_fts_after_delete AFTER DELETE ON intentions BEGIN INSERT INTO intention_titles_fts (intention_titles_fts, "rowid", title_search_key) VALUES (\'delete\', old."rowid", old.title_search_key);END',
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
    dailyChoices,
    dailyChoicesDateCreationOrder,
    dailyChoicesSourceDateCreationOrder,
    dailyChoicesSelectedDateCreationOrder,
    dailyChoicesSourceRecent,
    dailyChoicesSelectedRecent,
    dailyChoicesImmutableIdentity,
    longTermRelations,
    dailyChoicePathSteps,
    dailyChoicePathStepsOneRoot,
    dailyChoicePathStepsOneSuccessor,
    dailyChoicePathStepsRelation,
    longTermRelationsProtectDailyChoicePath,
    longTermRelationsSourceGroupOrder,
    longTermRelationsRelatedGroupOrder,
    longTermRelationsImmutableIdentity,
    longTermRelationsActiveParticipantsAfterInsert,
    longTermRelationsActiveParticipantsAfterUpdate,
    intentionsArchiveRequiresNoActiveRelations,
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
        'daily_choices',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'daily_choices',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('daily_choice_path_steps', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'long_term_relations',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'long_term_relations',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'long_term_relations',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'long_term_relations',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'intentions',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
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
                Value<String?> description = const Value.absent(),
                Value<bool> isActionReady = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IntentionsCompanion(
                id: id,
                title: title,
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
                Value<String?> description = const Value.absent(),
                Value<bool> isActionReady = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => IntentionsCompanion.insert(
                id: id,
                title: title,
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
typedef $DailyChoicesCreateCompanionBuilder = DailyChoicesCompanion Function({
  Value<int> creationSequence,
  required String id,
  required String sourceIntentionId,
  required String selectedIntentionId,
  required String choiceDate,
  Value<String?> description,
  required bool isCompleted,
});
typedef $DailyChoicesUpdateCompanionBuilder = DailyChoicesCompanion Function({
  Value<int> creationSequence,
  Value<String> id,
  Value<String> sourceIntentionId,
  Value<String> selectedIntentionId,
  Value<String> choiceDate,
  Value<String?> description,
  Value<bool> isCompleted,
});

final class $DailyChoicesReferences
    extends BaseReferences<_$AppDatabase, DailyChoices, DailyChoice> {
  $DailyChoicesReferences(super.$_db, super.$_table, super.$_typedResult);

  static Intentions _sourceIntentionIdTable(_$AppDatabase db) => db.intentions
      .createAlias('daily_choices__source_intention_id__intentions__id');

  $IntentionsProcessedTableManager get sourceIntentionId {
    final $_column = $_itemColumn<String>('source_intention_id')!;

    final manager = $IntentionsTableManager(
      $_db,
      $_db.intentions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceIntentionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static Intentions _selectedIntentionIdTable(_$AppDatabase db) => db.intentions
      .createAlias('daily_choices__selected_intention_id__intentions__id');

  $IntentionsProcessedTableManager get selectedIntentionId {
    final $_column = $_itemColumn<String>('selected_intention_id')!;

    final manager = $IntentionsTableManager(
      $_db,
      $_db.intentions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_selectedIntentionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<DailyChoicePathSteps, List<DailyChoicePathStep>>
  _dailyChoicePathStepsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.dailyChoicePathSteps,
        aliasName:
            'daily_choices__id__daily_choice_path_steps__daily_choice_id',
      );

  $DailyChoicePathStepsProcessedTableManager get dailyChoicePathStepsRefs {
    final manager = $DailyChoicePathStepsTableManager(
      $_db,
      $_db.dailyChoicePathSteps,
    ).filter((f) => f.dailyChoiceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _dailyChoicePathStepsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $DailyChoicesFilterComposer
    extends Composer<_$AppDatabase, DailyChoices> {
  $DailyChoicesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get creationSequence => $composableBuilder(
    column: $table.creationSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get choiceDate => $composableBuilder(
    column: $table.choiceDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnFilters(column),
  );

  $IntentionsFilterComposer get sourceIntentionId {
    final $IntentionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceIntentionId,
      referencedTable: $db.intentions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $IntentionsFilterComposer(
            $db: $db,
            $table: $db.intentions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $IntentionsFilterComposer get selectedIntentionId {
    final $IntentionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.selectedIntentionId,
      referencedTable: $db.intentions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $IntentionsFilterComposer(
            $db: $db,
            $table: $db.intentions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> dailyChoicePathStepsRefs(
    Expression<bool> Function($DailyChoicePathStepsFilterComposer f) f,
  ) {
    final $DailyChoicePathStepsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyChoicePathSteps,
      getReferencedColumn: (t) => t.dailyChoiceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DailyChoicePathStepsFilterComposer(
            $db: $db,
            $table: $db.dailyChoicePathSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $DailyChoicesOrderingComposer
    extends Composer<_$AppDatabase, DailyChoices> {
  $DailyChoicesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get creationSequence => $composableBuilder(
    column: $table.creationSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get choiceDate => $composableBuilder(
    column: $table.choiceDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnOrderings(column),
  );

  $IntentionsOrderingComposer get sourceIntentionId {
    final $IntentionsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceIntentionId,
      referencedTable: $db.intentions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $IntentionsOrderingComposer(
            $db: $db,
            $table: $db.intentions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $IntentionsOrderingComposer get selectedIntentionId {
    final $IntentionsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.selectedIntentionId,
      referencedTable: $db.intentions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $IntentionsOrderingComposer(
            $db: $db,
            $table: $db.intentions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $DailyChoicesAnnotationComposer
    extends Composer<_$AppDatabase, DailyChoices> {
  $DailyChoicesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get creationSequence => $composableBuilder(
    column: $table.creationSequence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get choiceDate => $composableBuilder(
    column: $table.choiceDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => column,
  );

  $IntentionsAnnotationComposer get sourceIntentionId {
    final $IntentionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceIntentionId,
      referencedTable: $db.intentions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $IntentionsAnnotationComposer(
            $db: $db,
            $table: $db.intentions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $IntentionsAnnotationComposer get selectedIntentionId {
    final $IntentionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.selectedIntentionId,
      referencedTable: $db.intentions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $IntentionsAnnotationComposer(
            $db: $db,
            $table: $db.intentions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> dailyChoicePathStepsRefs<T extends Object>(
    Expression<T> Function($DailyChoicePathStepsAnnotationComposer a) f,
  ) {
    final $DailyChoicePathStepsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyChoicePathSteps,
      getReferencedColumn: (t) => t.dailyChoiceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DailyChoicePathStepsAnnotationComposer(
            $db: $db,
            $table: $db.dailyChoicePathSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $DailyChoicesTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          DailyChoices,
          DailyChoice,
          $DailyChoicesFilterComposer,
          $DailyChoicesOrderingComposer,
          $DailyChoicesAnnotationComposer,
          $DailyChoicesCreateCompanionBuilder,
          $DailyChoicesUpdateCompanionBuilder,
          (DailyChoice, $DailyChoicesReferences),
          DailyChoice,
          PrefetchHooks Function({
            bool sourceIntentionId,
            bool selectedIntentionId,
            bool dailyChoicePathStepsRefs,
          })
        > {
  $DailyChoicesTableManager(_$AppDatabase db, DailyChoices table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $DailyChoicesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $DailyChoicesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $DailyChoicesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> creationSequence = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> sourceIntentionId = const Value.absent(),
                Value<String> selectedIntentionId = const Value.absent(),
                Value<String> choiceDate = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<bool> isCompleted = const Value.absent(),
              }) => DailyChoicesCompanion(
                creationSequence: creationSequence,
                id: id,
                sourceIntentionId: sourceIntentionId,
                selectedIntentionId: selectedIntentionId,
                choiceDate: choiceDate,
                description: description,
                isCompleted: isCompleted,
              ),
          createCompanionCallback:
              ({
                Value<int> creationSequence = const Value.absent(),
                required String id,
                required String sourceIntentionId,
                required String selectedIntentionId,
                required String choiceDate,
                Value<String?> description = const Value.absent(),
                required bool isCompleted,
              }) => DailyChoicesCompanion.insert(
                creationSequence: creationSequence,
                id: id,
                sourceIntentionId: sourceIntentionId,
                selectedIntentionId: selectedIntentionId,
                choiceDate: choiceDate,
                description: description,
                isCompleted: isCompleted,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $DailyChoicesReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                sourceIntentionId = false,
                selectedIntentionId = false,
                dailyChoicePathStepsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (dailyChoicePathStepsRefs) db.dailyChoicePathSteps,
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
                        if (sourceIntentionId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.sourceIntentionId,
                            referencedTable: $DailyChoicesReferences
                                ._sourceIntentionIdTable(db),
                            referencedColumn: $DailyChoicesReferences
                                ._sourceIntentionIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (selectedIntentionId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.selectedIntentionId,
                            referencedTable: $DailyChoicesReferences
                                ._selectedIntentionIdTable(db),
                            referencedColumn: $DailyChoicesReferences
                                ._selectedIntentionIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (dailyChoicePathStepsRefs)
                        await $_getPrefetchedData<
                          DailyChoice,
                          DailyChoices,
                          DailyChoicePathStep
                        >(
                          currentTable: table,
                          referencedTable: $DailyChoicesReferences
                              ._dailyChoicePathStepsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $DailyChoicesReferences(
                                db,
                                table,
                                p0,
                              ).dailyChoicePathStepsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.dailyChoiceId == item.id,
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

typedef $DailyChoicesProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      DailyChoices,
      DailyChoice,
      $DailyChoicesFilterComposer,
      $DailyChoicesOrderingComposer,
      $DailyChoicesAnnotationComposer,
      $DailyChoicesCreateCompanionBuilder,
      $DailyChoicesUpdateCompanionBuilder,
      (DailyChoice, $DailyChoicesReferences),
      DailyChoice,
      PrefetchHooks Function({
        bool sourceIntentionId,
        bool selectedIntentionId,
        bool dailyChoicePathStepsRefs,
      })
    >;
typedef $LongTermRelationsCreateCompanionBuilder =
    LongTermRelationsCompanion Function({
      Value<int> creationSequence,
      required String id,
      required String sourceIntentionId,
      required String relatedIntentionId,
      required String type,
      required int priority,
      Value<String?> description,
      Value<bool> isArchived,
    });
typedef $LongTermRelationsUpdateCompanionBuilder =
    LongTermRelationsCompanion Function({
      Value<int> creationSequence,
      Value<String> id,
      Value<String> sourceIntentionId,
      Value<String> relatedIntentionId,
      Value<String> type,
      Value<int> priority,
      Value<String?> description,
      Value<bool> isArchived,
    });

final class $LongTermRelationsReferences
    extends BaseReferences<_$AppDatabase, LongTermRelations, LongTermRelation> {
  $LongTermRelationsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Intentions _sourceIntentionIdTable(_$AppDatabase db) => db.intentions
      .createAlias('long_term_relations__source_intention_id__intentions__id');

  $IntentionsProcessedTableManager get sourceIntentionId {
    final $_column = $_itemColumn<String>('source_intention_id')!;

    final manager = $IntentionsTableManager(
      $_db,
      $_db.intentions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceIntentionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static Intentions _relatedIntentionIdTable(_$AppDatabase db) => db.intentions
      .createAlias('long_term_relations__related_intention_id__intentions__id');

  $IntentionsProcessedTableManager get relatedIntentionId {
    final $_column = $_itemColumn<String>('related_intention_id')!;

    final manager = $IntentionsTableManager(
      $_db,
      $_db.intentions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_relatedIntentionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<DailyChoicePathSteps, List<DailyChoicePathStep>>
  _dailyChoicePathStepsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.dailyChoicePathSteps,
        aliasName: 'long_term_relations__id__daily_choice_path_steps__long_term_relation_id',
      );

  $DailyChoicePathStepsProcessedTableManager get dailyChoicePathStepsRefs {
    final manager =
        $DailyChoicePathStepsTableManager(
          $_db,
          $_db.dailyChoicePathSteps,
        ).filter(
          (f) => f.longTermRelationId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _dailyChoicePathStepsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $LongTermRelationsFilterComposer
    extends Composer<_$AppDatabase, LongTermRelations> {
  $LongTermRelationsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get creationSequence => $composableBuilder(
    column: $table.creationSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  $IntentionsFilterComposer get sourceIntentionId {
    final $IntentionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceIntentionId,
      referencedTable: $db.intentions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $IntentionsFilterComposer(
            $db: $db,
            $table: $db.intentions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $IntentionsFilterComposer get relatedIntentionId {
    final $IntentionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.relatedIntentionId,
      referencedTable: $db.intentions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $IntentionsFilterComposer(
            $db: $db,
            $table: $db.intentions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> dailyChoicePathStepsRefs(
    Expression<bool> Function($DailyChoicePathStepsFilterComposer f) f,
  ) {
    final $DailyChoicePathStepsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyChoicePathSteps,
      getReferencedColumn: (t) => t.longTermRelationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DailyChoicePathStepsFilterComposer(
            $db: $db,
            $table: $db.dailyChoicePathSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $LongTermRelationsOrderingComposer
    extends Composer<_$AppDatabase, LongTermRelations> {
  $LongTermRelationsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get creationSequence => $composableBuilder(
    column: $table.creationSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  $IntentionsOrderingComposer get sourceIntentionId {
    final $IntentionsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceIntentionId,
      referencedTable: $db.intentions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $IntentionsOrderingComposer(
            $db: $db,
            $table: $db.intentions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $IntentionsOrderingComposer get relatedIntentionId {
    final $IntentionsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.relatedIntentionId,
      referencedTable: $db.intentions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $IntentionsOrderingComposer(
            $db: $db,
            $table: $db.intentions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $LongTermRelationsAnnotationComposer
    extends Composer<_$AppDatabase, LongTermRelations> {
  $LongTermRelationsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get creationSequence => $composableBuilder(
    column: $table.creationSequence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  $IntentionsAnnotationComposer get sourceIntentionId {
    final $IntentionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceIntentionId,
      referencedTable: $db.intentions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $IntentionsAnnotationComposer(
            $db: $db,
            $table: $db.intentions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $IntentionsAnnotationComposer get relatedIntentionId {
    final $IntentionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.relatedIntentionId,
      referencedTable: $db.intentions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $IntentionsAnnotationComposer(
            $db: $db,
            $table: $db.intentions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> dailyChoicePathStepsRefs<T extends Object>(
    Expression<T> Function($DailyChoicePathStepsAnnotationComposer a) f,
  ) {
    final $DailyChoicePathStepsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyChoicePathSteps,
      getReferencedColumn: (t) => t.longTermRelationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DailyChoicePathStepsAnnotationComposer(
            $db: $db,
            $table: $db.dailyChoicePathSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $LongTermRelationsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          LongTermRelations,
          LongTermRelation,
          $LongTermRelationsFilterComposer,
          $LongTermRelationsOrderingComposer,
          $LongTermRelationsAnnotationComposer,
          $LongTermRelationsCreateCompanionBuilder,
          $LongTermRelationsUpdateCompanionBuilder,
          (LongTermRelation, $LongTermRelationsReferences),
          LongTermRelation,
          PrefetchHooks Function({
            bool sourceIntentionId,
            bool relatedIntentionId,
            bool dailyChoicePathStepsRefs,
          })
        > {
  $LongTermRelationsTableManager(_$AppDatabase db, LongTermRelations table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $LongTermRelationsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $LongTermRelationsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $LongTermRelationsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> creationSequence = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> sourceIntentionId = const Value.absent(),
                Value<String> relatedIntentionId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
              }) => LongTermRelationsCompanion(
                creationSequence: creationSequence,
                id: id,
                sourceIntentionId: sourceIntentionId,
                relatedIntentionId: relatedIntentionId,
                type: type,
                priority: priority,
                description: description,
                isArchived: isArchived,
              ),
          createCompanionCallback:
              ({
                Value<int> creationSequence = const Value.absent(),
                required String id,
                required String sourceIntentionId,
                required String relatedIntentionId,
                required String type,
                required int priority,
                Value<String?> description = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
              }) => LongTermRelationsCompanion.insert(
                creationSequence: creationSequence,
                id: id,
                sourceIntentionId: sourceIntentionId,
                relatedIntentionId: relatedIntentionId,
                type: type,
                priority: priority,
                description: description,
                isArchived: isArchived,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $LongTermRelationsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                sourceIntentionId = false,
                relatedIntentionId = false,
                dailyChoicePathStepsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (dailyChoicePathStepsRefs) db.dailyChoicePathSteps,
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
                        if (sourceIntentionId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.sourceIntentionId,
                            referencedTable: $LongTermRelationsReferences
                                ._sourceIntentionIdTable(db),
                            referencedColumn: $LongTermRelationsReferences
                                ._sourceIntentionIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (relatedIntentionId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.relatedIntentionId,
                            referencedTable: $LongTermRelationsReferences
                                ._relatedIntentionIdTable(db),
                            referencedColumn: $LongTermRelationsReferences
                                ._relatedIntentionIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (dailyChoicePathStepsRefs)
                        await $_getPrefetchedData<
                          LongTermRelation,
                          LongTermRelations,
                          DailyChoicePathStep
                        >(
                          currentTable: table,
                          referencedTable: $LongTermRelationsReferences
                              ._dailyChoicePathStepsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $LongTermRelationsReferences(
                                db,
                                table,
                                p0,
                              ).dailyChoicePathStepsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.longTermRelationId == item.id,
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

typedef $LongTermRelationsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      LongTermRelations,
      LongTermRelation,
      $LongTermRelationsFilterComposer,
      $LongTermRelationsOrderingComposer,
      $LongTermRelationsAnnotationComposer,
      $LongTermRelationsCreateCompanionBuilder,
      $LongTermRelationsUpdateCompanionBuilder,
      (LongTermRelation, $LongTermRelationsReferences),
      LongTermRelation,
      PrefetchHooks Function({
        bool sourceIntentionId,
        bool relatedIntentionId,
        bool dailyChoicePathStepsRefs,
      })
    >;
typedef $DailyChoicePathStepsCreateCompanionBuilder =
    DailyChoicePathStepsCompanion Function({
      required String id,
      required String dailyChoiceId,
      required String longTermRelationId,
      Value<String?> previousStepId,
      Value<int> rowid,
    });
typedef $DailyChoicePathStepsUpdateCompanionBuilder =
    DailyChoicePathStepsCompanion Function({
      Value<String> id,
      Value<String> dailyChoiceId,
      Value<String> longTermRelationId,
      Value<String?> previousStepId,
      Value<int> rowid,
    });

final class $DailyChoicePathStepsReferences
    extends
        BaseReferences<
          _$AppDatabase,
          DailyChoicePathSteps,
          DailyChoicePathStep
        > {
  $DailyChoicePathStepsReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static DailyChoices _dailyChoiceIdTable(_$AppDatabase db) =>
      db.dailyChoices.createAlias(
        'daily_choice_path_steps__daily_choice_id__daily_choices__id',
      );

  $DailyChoicesProcessedTableManager get dailyChoiceId {
    final $_column = $_itemColumn<String>('daily_choice_id')!;

    final manager = $DailyChoicesTableManager(
      $_db,
      $_db.dailyChoices,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_dailyChoiceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static LongTermRelations _longTermRelationIdTable(
    _$AppDatabase db,
  ) => db.longTermRelations.createAlias(
    'daily_choice_path_steps__long_term_relation_id__long_term_relations__id',
  );

  $LongTermRelationsProcessedTableManager get longTermRelationId {
    final $_column = $_itemColumn<String>('long_term_relation_id')!;

    final manager = $LongTermRelationsTableManager(
      $_db,
      $_db.longTermRelations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_longTermRelationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $DailyChoicePathStepsFilterComposer
    extends Composer<_$AppDatabase, DailyChoicePathSteps> {
  $DailyChoicePathStepsFilterComposer({
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

  ColumnFilters<String> get previousStepId => $composableBuilder(
    column: $table.previousStepId,
    builder: (column) => ColumnFilters(column),
  );

  $DailyChoicesFilterComposer get dailyChoiceId {
    final $DailyChoicesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.dailyChoiceId,
      referencedTable: $db.dailyChoices,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DailyChoicesFilterComposer(
            $db: $db,
            $table: $db.dailyChoices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $LongTermRelationsFilterComposer get longTermRelationId {
    final $LongTermRelationsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.longTermRelationId,
      referencedTable: $db.longTermRelations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LongTermRelationsFilterComposer(
            $db: $db,
            $table: $db.longTermRelations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $DailyChoicePathStepsOrderingComposer
    extends Composer<_$AppDatabase, DailyChoicePathSteps> {
  $DailyChoicePathStepsOrderingComposer({
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

  ColumnOrderings<String> get previousStepId => $composableBuilder(
    column: $table.previousStepId,
    builder: (column) => ColumnOrderings(column),
  );

  $DailyChoicesOrderingComposer get dailyChoiceId {
    final $DailyChoicesOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.dailyChoiceId,
      referencedTable: $db.dailyChoices,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DailyChoicesOrderingComposer(
            $db: $db,
            $table: $db.dailyChoices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $LongTermRelationsOrderingComposer get longTermRelationId {
    final $LongTermRelationsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.longTermRelationId,
      referencedTable: $db.longTermRelations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LongTermRelationsOrderingComposer(
            $db: $db,
            $table: $db.longTermRelations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $DailyChoicePathStepsAnnotationComposer
    extends Composer<_$AppDatabase, DailyChoicePathSteps> {
  $DailyChoicePathStepsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get previousStepId => $composableBuilder(
    column: $table.previousStepId,
    builder: (column) => column,
  );

  $DailyChoicesAnnotationComposer get dailyChoiceId {
    final $DailyChoicesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.dailyChoiceId,
      referencedTable: $db.dailyChoices,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $DailyChoicesAnnotationComposer(
            $db: $db,
            $table: $db.dailyChoices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $LongTermRelationsAnnotationComposer get longTermRelationId {
    final $LongTermRelationsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.longTermRelationId,
      referencedTable: $db.longTermRelations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LongTermRelationsAnnotationComposer(
            $db: $db,
            $table: $db.longTermRelations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $DailyChoicePathStepsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          DailyChoicePathSteps,
          DailyChoicePathStep,
          $DailyChoicePathStepsFilterComposer,
          $DailyChoicePathStepsOrderingComposer,
          $DailyChoicePathStepsAnnotationComposer,
          $DailyChoicePathStepsCreateCompanionBuilder,
          $DailyChoicePathStepsUpdateCompanionBuilder,
          (DailyChoicePathStep, $DailyChoicePathStepsReferences),
          DailyChoicePathStep,
          PrefetchHooks Function({bool dailyChoiceId, bool longTermRelationId})
        > {
  $DailyChoicePathStepsTableManager(
    _$AppDatabase db,
    DailyChoicePathSteps table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $DailyChoicePathStepsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $DailyChoicePathStepsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $DailyChoicePathStepsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> dailyChoiceId = const Value.absent(),
                Value<String> longTermRelationId = const Value.absent(),
                Value<String?> previousStepId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyChoicePathStepsCompanion(
                id: id,
                dailyChoiceId: dailyChoiceId,
                longTermRelationId: longTermRelationId,
                previousStepId: previousStepId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String dailyChoiceId,
                required String longTermRelationId,
                Value<String?> previousStepId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyChoicePathStepsCompanion.insert(
                id: id,
                dailyChoiceId: dailyChoiceId,
                longTermRelationId: longTermRelationId,
                previousStepId: previousStepId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $DailyChoicePathStepsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({dailyChoiceId = false, longTermRelationId = false}) {
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
                        if (dailyChoiceId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.dailyChoiceId,
                            referencedTable: $DailyChoicePathStepsReferences
                                ._dailyChoiceIdTable(db),
                            referencedColumn: $DailyChoicePathStepsReferences
                                ._dailyChoiceIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (longTermRelationId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.longTermRelationId,
                            referencedTable: $DailyChoicePathStepsReferences
                                ._longTermRelationIdTable(db),
                            referencedColumn: $DailyChoicePathStepsReferences
                                ._longTermRelationIdTable(db)
                                .id,
                          ) as T;
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

typedef $DailyChoicePathStepsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      DailyChoicePathSteps,
      DailyChoicePathStep,
      $DailyChoicePathStepsFilterComposer,
      $DailyChoicePathStepsOrderingComposer,
      $DailyChoicePathStepsAnnotationComposer,
      $DailyChoicePathStepsCreateCompanionBuilder,
      $DailyChoicePathStepsUpdateCompanionBuilder,
      (DailyChoicePathStep, $DailyChoicePathStepsReferences),
      DailyChoicePathStep,
      PrefetchHooks Function({bool dailyChoiceId, bool longTermRelationId})
    >;
typedef $IntentionTitlesFtsCreateCompanionBuilder =
    IntentionTitlesFtsCompanion Function({
      required String titleSearchKey,
      Value<int> rowid,
    });
typedef $IntentionTitlesFtsUpdateCompanionBuilder =
    IntentionTitlesFtsCompanion Function({
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
                Value<String> titleSearchKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IntentionTitlesFtsCompanion(
                titleSearchKey: titleSearchKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String titleSearchKey,
                Value<int> rowid = const Value.absent(),
              }) => IntentionTitlesFtsCompanion.insert(
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
  $DailyChoicesTableManager get dailyChoices =>
      $DailyChoicesTableManager(_db, _db.dailyChoices);
  $LongTermRelationsTableManager get longTermRelations =>
      $LongTermRelationsTableManager(_db, _db.longTermRelations);
  $DailyChoicePathStepsTableManager get dailyChoicePathSteps =>
      $DailyChoicePathStepsTableManager(_db, _db.dailyChoicePathSteps);
  $IntentionTitlesFtsTableManager get intentionTitlesFts =>
      $IntentionTitlesFtsTableManager(_db, _db.intentionTitlesFts);
}
