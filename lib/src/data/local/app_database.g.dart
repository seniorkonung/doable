// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class GraphLogControl extends Table
    with TableInfo<GraphLogControl, GraphLogControlData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  GraphLogControl(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (id = 1)',
  );
  static const VerificationMeta _captureMeta = const VerificationMeta(
    'capture',
  );
  late final GeneratedColumn<bool> capture = GeneratedColumn<bool>(
    'capture',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (typeof(capture) = \'integer\' AND capture IN (0, 1))',
  );
  static const VerificationMeta _writingMeta = const VerificationMeta(
    'writing',
  );
  late final GeneratedColumn<bool> writing = GeneratedColumn<bool>(
    'writing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (typeof(writing) = \'integer\' AND writing IN (0, 1))',
  );
  @override
  List<GeneratedColumn> get $columns => [id, capture, writing];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graph_log_control';
  @override
  VerificationContext validateIntegrity(
    Insertable<GraphLogControlData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('capture')) {
      context.handle(
        _captureMeta,
        capture.isAcceptableOrUnknown(data['capture']!, _captureMeta),
      );
    } else if (isInserting) {
      context.missing(_captureMeta);
    }
    if (data.containsKey('writing')) {
      context.handle(
        _writingMeta,
        writing.isAcceptableOrUnknown(data['writing']!, _writingMeta),
      );
    } else if (isInserting) {
      context.missing(_writingMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GraphLogControlData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GraphLogControlData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      capture: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}capture'],
      )!,
      writing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}writing'],
      )!,
    );
  }

  @override
  GraphLogControl createAlias(String alias) {
    return GraphLogControl(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class GraphLogControlData extends DataClass
    implements Insertable<GraphLogControlData> {
  final int id;
  final bool capture;
  final bool writing;
  const GraphLogControlData({
    required this.id,
    required this.capture,
    required this.writing,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['capture'] = Variable<bool>(capture);
    map['writing'] = Variable<bool>(writing);
    return map;
  }

  GraphLogControlCompanion toCompanion(bool nullToAbsent) {
    return GraphLogControlCompanion(
      id: Value(id),
      capture: Value(capture),
      writing: Value(writing),
    );
  }

  factory GraphLogControlData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GraphLogControlData(
      id: serializer.fromJson<int>(json['id']),
      capture: serializer.fromJson<bool>(json['capture']),
      writing: serializer.fromJson<bool>(json['writing']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'capture': serializer.toJson<bool>(capture),
      'writing': serializer.toJson<bool>(writing),
    };
  }

  GraphLogControlData copyWith({int? id, bool? capture, bool? writing}) =>
      GraphLogControlData(
        id: id ?? this.id,
        capture: capture ?? this.capture,
        writing: writing ?? this.writing,
      );
  GraphLogControlData copyWithCompanion(GraphLogControlCompanion data) {
    return GraphLogControlData(
      id: data.id.present ? data.id.value : this.id,
      capture: data.capture.present ? data.capture.value : this.capture,
      writing: data.writing.present ? data.writing.value : this.writing,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogControlData(')
          ..write('id: $id, ')
          ..write('capture: $capture, ')
          ..write('writing: $writing')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, capture, writing);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GraphLogControlData &&
          other.id == this.id &&
          other.capture == this.capture &&
          other.writing == this.writing);
}

class GraphLogControlCompanion extends UpdateCompanion<GraphLogControlData> {
  final Value<int> id;
  final Value<bool> capture;
  final Value<bool> writing;
  const GraphLogControlCompanion({
    this.id = const Value.absent(),
    this.capture = const Value.absent(),
    this.writing = const Value.absent(),
  });
  GraphLogControlCompanion.insert({
    this.id = const Value.absent(),
    required bool capture,
    required bool writing,
  }) : capture = Value(capture),
       writing = Value(writing);
  static Insertable<GraphLogControlData> custom({
    Expression<int>? id,
    Expression<bool>? capture,
    Expression<bool>? writing,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (capture != null) 'capture': capture,
      if (writing != null) 'writing': writing,
    });
  }

  GraphLogControlCompanion copyWith({
    Value<int>? id,
    Value<bool>? capture,
    Value<bool>? writing,
  }) {
    return GraphLogControlCompanion(
      id: id ?? this.id,
      capture: capture ?? this.capture,
      writing: writing ?? this.writing,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (capture.present) {
      map['capture'] = Variable<bool>(capture.value);
    }
    if (writing.present) {
      map['writing'] = Variable<bool>(writing.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogControlCompanion(')
          ..write('id: $id, ')
          ..write('capture: $capture, ')
          ..write('writing: $writing')
          ..write(')'))
        .toString();
  }
}

class GraphLogTagMarks extends Table
    with TableInfo<GraphLogTagMarks, GraphLogTagMark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  GraphLogTagMarks(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _firstOperationMeta = const VerificationMeta(
    'firstOperation',
  );
  late final GeneratedColumn<String> firstOperation = GeneratedColumn<String>(
    'first_operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (first_operation IN (\'insert\', \'update\', \'delete\'))',
  );
  @override
  List<GeneratedColumn> get $columns => [tagId, firstOperation];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graph_log_tag_marks';
  @override
  VerificationContext validateIntegrity(
    Insertable<GraphLogTagMark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    if (data.containsKey('first_operation')) {
      context.handle(
        _firstOperationMeta,
        firstOperation.isAcceptableOrUnknown(
          data['first_operation']!,
          _firstOperationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstOperationMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tagId};
  @override
  GraphLogTagMark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GraphLogTagMark(
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
      firstOperation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_operation'],
      )!,
    );
  }

  @override
  GraphLogTagMarks createAlias(String alias) {
    return GraphLogTagMarks(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class GraphLogTagMark extends DataClass implements Insertable<GraphLogTagMark> {
  final String tagId;
  final String firstOperation;
  const GraphLogTagMark({required this.tagId, required this.firstOperation});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tag_id'] = Variable<String>(tagId);
    map['first_operation'] = Variable<String>(firstOperation);
    return map;
  }

  GraphLogTagMarksCompanion toCompanion(bool nullToAbsent) {
    return GraphLogTagMarksCompanion(
      tagId: Value(tagId),
      firstOperation: Value(firstOperation),
    );
  }

  factory GraphLogTagMark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GraphLogTagMark(
      tagId: serializer.fromJson<String>(json['tag_id']),
      firstOperation: serializer.fromJson<String>(json['first_operation']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tag_id': serializer.toJson<String>(tagId),
      'first_operation': serializer.toJson<String>(firstOperation),
    };
  }

  GraphLogTagMark copyWith({String? tagId, String? firstOperation}) =>
      GraphLogTagMark(
        tagId: tagId ?? this.tagId,
        firstOperation: firstOperation ?? this.firstOperation,
      );
  GraphLogTagMark copyWithCompanion(GraphLogTagMarksCompanion data) {
    return GraphLogTagMark(
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      firstOperation: data.firstOperation.present
          ? data.firstOperation.value
          : this.firstOperation,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogTagMark(')
          ..write('tagId: $tagId, ')
          ..write('firstOperation: $firstOperation')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tagId, firstOperation);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GraphLogTagMark &&
          other.tagId == this.tagId &&
          other.firstOperation == this.firstOperation);
}

class GraphLogTagMarksCompanion extends UpdateCompanion<GraphLogTagMark> {
  final Value<String> tagId;
  final Value<String> firstOperation;
  final Value<int> rowid;
  const GraphLogTagMarksCompanion({
    this.tagId = const Value.absent(),
    this.firstOperation = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GraphLogTagMarksCompanion.insert({
    required String tagId,
    required String firstOperation,
    this.rowid = const Value.absent(),
  }) : tagId = Value(tagId),
       firstOperation = Value(firstOperation);
  static Insertable<GraphLogTagMark> custom({
    Expression<String>? tagId,
    Expression<String>? firstOperation,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tagId != null) 'tag_id': tagId,
      if (firstOperation != null) 'first_operation': firstOperation,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GraphLogTagMarksCompanion copyWith({
    Value<String>? tagId,
    Value<String>? firstOperation,
    Value<int>? rowid,
  }) {
    return GraphLogTagMarksCompanion(
      tagId: tagId ?? this.tagId,
      firstOperation: firstOperation ?? this.firstOperation,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (firstOperation.present) {
      map['first_operation'] = Variable<String>(firstOperation.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogTagMarksCompanion(')
          ..write('tagId: $tagId, ')
          ..write('firstOperation: $firstOperation, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class GraphLogIntentionMarks extends Table
    with TableInfo<GraphLogIntentionMarks, GraphLogIntentionMark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  GraphLogIntentionMarks(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _intentionIdMeta = const VerificationMeta(
    'intentionId',
  );
  late final GeneratedColumn<String> intentionId = GeneratedColumn<String>(
    'intention_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _firstOperationMeta = const VerificationMeta(
    'firstOperation',
  );
  late final GeneratedColumn<String> firstOperation = GeneratedColumn<String>(
    'first_operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (first_operation IN (\'insert\', \'update\', \'delete\'))',
  );
  @override
  List<GeneratedColumn> get $columns => [intentionId, firstOperation];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graph_log_intention_marks';
  @override
  VerificationContext validateIntegrity(
    Insertable<GraphLogIntentionMark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('intention_id')) {
      context.handle(
        _intentionIdMeta,
        intentionId.isAcceptableOrUnknown(
          data['intention_id']!,
          _intentionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_intentionIdMeta);
    }
    if (data.containsKey('first_operation')) {
      context.handle(
        _firstOperationMeta,
        firstOperation.isAcceptableOrUnknown(
          data['first_operation']!,
          _firstOperationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstOperationMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {intentionId};
  @override
  GraphLogIntentionMark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GraphLogIntentionMark(
      intentionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intention_id'],
      )!,
      firstOperation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_operation'],
      )!,
    );
  }

  @override
  GraphLogIntentionMarks createAlias(String alias) {
    return GraphLogIntentionMarks(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class GraphLogIntentionMark extends DataClass
    implements Insertable<GraphLogIntentionMark> {
  final String intentionId;
  final String firstOperation;
  const GraphLogIntentionMark({
    required this.intentionId,
    required this.firstOperation,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['intention_id'] = Variable<String>(intentionId);
    map['first_operation'] = Variable<String>(firstOperation);
    return map;
  }

  GraphLogIntentionMarksCompanion toCompanion(bool nullToAbsent) {
    return GraphLogIntentionMarksCompanion(
      intentionId: Value(intentionId),
      firstOperation: Value(firstOperation),
    );
  }

  factory GraphLogIntentionMark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GraphLogIntentionMark(
      intentionId: serializer.fromJson<String>(json['intention_id']),
      firstOperation: serializer.fromJson<String>(json['first_operation']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'intention_id': serializer.toJson<String>(intentionId),
      'first_operation': serializer.toJson<String>(firstOperation),
    };
  }

  GraphLogIntentionMark copyWith({
    String? intentionId,
    String? firstOperation,
  }) => GraphLogIntentionMark(
    intentionId: intentionId ?? this.intentionId,
    firstOperation: firstOperation ?? this.firstOperation,
  );
  GraphLogIntentionMark copyWithCompanion(
    GraphLogIntentionMarksCompanion data,
  ) {
    return GraphLogIntentionMark(
      intentionId: data.intentionId.present
          ? data.intentionId.value
          : this.intentionId,
      firstOperation: data.firstOperation.present
          ? data.firstOperation.value
          : this.firstOperation,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogIntentionMark(')
          ..write('intentionId: $intentionId, ')
          ..write('firstOperation: $firstOperation')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(intentionId, firstOperation);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GraphLogIntentionMark &&
          other.intentionId == this.intentionId &&
          other.firstOperation == this.firstOperation);
}

class GraphLogIntentionMarksCompanion
    extends UpdateCompanion<GraphLogIntentionMark> {
  final Value<String> intentionId;
  final Value<String> firstOperation;
  final Value<int> rowid;
  const GraphLogIntentionMarksCompanion({
    this.intentionId = const Value.absent(),
    this.firstOperation = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GraphLogIntentionMarksCompanion.insert({
    required String intentionId,
    required String firstOperation,
    this.rowid = const Value.absent(),
  }) : intentionId = Value(intentionId),
       firstOperation = Value(firstOperation);
  static Insertable<GraphLogIntentionMark> custom({
    Expression<String>? intentionId,
    Expression<String>? firstOperation,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (intentionId != null) 'intention_id': intentionId,
      if (firstOperation != null) 'first_operation': firstOperation,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GraphLogIntentionMarksCompanion copyWith({
    Value<String>? intentionId,
    Value<String>? firstOperation,
    Value<int>? rowid,
  }) {
    return GraphLogIntentionMarksCompanion(
      intentionId: intentionId ?? this.intentionId,
      firstOperation: firstOperation ?? this.firstOperation,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (intentionId.present) {
      map['intention_id'] = Variable<String>(intentionId.value);
    }
    if (firstOperation.present) {
      map['first_operation'] = Variable<String>(firstOperation.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogIntentionMarksCompanion(')
          ..write('intentionId: $intentionId, ')
          ..write('firstOperation: $firstOperation, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class GraphLogTagAssignmentMarks extends Table
    with TableInfo<GraphLogTagAssignmentMarks, GraphLogTagAssignmentMark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  GraphLogTagAssignmentMarks(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _intentionIdMeta = const VerificationMeta(
    'intentionId',
  );
  late final GeneratedColumn<String> intentionId = GeneratedColumn<String>(
    'intention_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _firstOperationMeta = const VerificationMeta(
    'firstOperation',
  );
  late final GeneratedColumn<String> firstOperation = GeneratedColumn<String>(
    'first_operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (first_operation IN (\'insert\', \'update\', \'delete\'))',
  );
  @override
  List<GeneratedColumn> get $columns => [tagId, intentionId, firstOperation];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graph_log_tag_assignment_marks';
  @override
  VerificationContext validateIntegrity(
    Insertable<GraphLogTagAssignmentMark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    if (data.containsKey('intention_id')) {
      context.handle(
        _intentionIdMeta,
        intentionId.isAcceptableOrUnknown(
          data['intention_id']!,
          _intentionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_intentionIdMeta);
    }
    if (data.containsKey('first_operation')) {
      context.handle(
        _firstOperationMeta,
        firstOperation.isAcceptableOrUnknown(
          data['first_operation']!,
          _firstOperationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstOperationMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tagId, intentionId};
  @override
  GraphLogTagAssignmentMark map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GraphLogTagAssignmentMark(
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
      intentionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intention_id'],
      )!,
      firstOperation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_operation'],
      )!,
    );
  }

  @override
  GraphLogTagAssignmentMarks createAlias(String alias) {
    return GraphLogTagAssignmentMarks(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(tag_id, intention_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class GraphLogTagAssignmentMark extends DataClass
    implements Insertable<GraphLogTagAssignmentMark> {
  final String tagId;
  final String intentionId;
  final String firstOperation;
  const GraphLogTagAssignmentMark({
    required this.tagId,
    required this.intentionId,
    required this.firstOperation,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tag_id'] = Variable<String>(tagId);
    map['intention_id'] = Variable<String>(intentionId);
    map['first_operation'] = Variable<String>(firstOperation);
    return map;
  }

  GraphLogTagAssignmentMarksCompanion toCompanion(bool nullToAbsent) {
    return GraphLogTagAssignmentMarksCompanion(
      tagId: Value(tagId),
      intentionId: Value(intentionId),
      firstOperation: Value(firstOperation),
    );
  }

  factory GraphLogTagAssignmentMark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GraphLogTagAssignmentMark(
      tagId: serializer.fromJson<String>(json['tag_id']),
      intentionId: serializer.fromJson<String>(json['intention_id']),
      firstOperation: serializer.fromJson<String>(json['first_operation']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tag_id': serializer.toJson<String>(tagId),
      'intention_id': serializer.toJson<String>(intentionId),
      'first_operation': serializer.toJson<String>(firstOperation),
    };
  }

  GraphLogTagAssignmentMark copyWith({
    String? tagId,
    String? intentionId,
    String? firstOperation,
  }) => GraphLogTagAssignmentMark(
    tagId: tagId ?? this.tagId,
    intentionId: intentionId ?? this.intentionId,
    firstOperation: firstOperation ?? this.firstOperation,
  );
  GraphLogTagAssignmentMark copyWithCompanion(
    GraphLogTagAssignmentMarksCompanion data,
  ) {
    return GraphLogTagAssignmentMark(
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      intentionId: data.intentionId.present
          ? data.intentionId.value
          : this.intentionId,
      firstOperation: data.firstOperation.present
          ? data.firstOperation.value
          : this.firstOperation,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogTagAssignmentMark(')
          ..write('tagId: $tagId, ')
          ..write('intentionId: $intentionId, ')
          ..write('firstOperation: $firstOperation')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tagId, intentionId, firstOperation);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GraphLogTagAssignmentMark &&
          other.tagId == this.tagId &&
          other.intentionId == this.intentionId &&
          other.firstOperation == this.firstOperation);
}

class GraphLogTagAssignmentMarksCompanion
    extends UpdateCompanion<GraphLogTagAssignmentMark> {
  final Value<String> tagId;
  final Value<String> intentionId;
  final Value<String> firstOperation;
  final Value<int> rowid;
  const GraphLogTagAssignmentMarksCompanion({
    this.tagId = const Value.absent(),
    this.intentionId = const Value.absent(),
    this.firstOperation = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GraphLogTagAssignmentMarksCompanion.insert({
    required String tagId,
    required String intentionId,
    required String firstOperation,
    this.rowid = const Value.absent(),
  }) : tagId = Value(tagId),
       intentionId = Value(intentionId),
       firstOperation = Value(firstOperation);
  static Insertable<GraphLogTagAssignmentMark> custom({
    Expression<String>? tagId,
    Expression<String>? intentionId,
    Expression<String>? firstOperation,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tagId != null) 'tag_id': tagId,
      if (intentionId != null) 'intention_id': intentionId,
      if (firstOperation != null) 'first_operation': firstOperation,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GraphLogTagAssignmentMarksCompanion copyWith({
    Value<String>? tagId,
    Value<String>? intentionId,
    Value<String>? firstOperation,
    Value<int>? rowid,
  }) {
    return GraphLogTagAssignmentMarksCompanion(
      tagId: tagId ?? this.tagId,
      intentionId: intentionId ?? this.intentionId,
      firstOperation: firstOperation ?? this.firstOperation,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (intentionId.present) {
      map['intention_id'] = Variable<String>(intentionId.value);
    }
    if (firstOperation.present) {
      map['first_operation'] = Variable<String>(firstOperation.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogTagAssignmentMarksCompanion(')
          ..write('tagId: $tagId, ')
          ..write('intentionId: $intentionId, ')
          ..write('firstOperation: $firstOperation, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class GraphLogLongTermRelationMarks extends Table
    with
        TableInfo<GraphLogLongTermRelationMarks, GraphLogLongTermRelationMark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  GraphLogLongTermRelationMarks(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _longTermRelationIdMeta =
      const VerificationMeta('longTermRelationId');
  late final GeneratedColumn<String> longTermRelationId =
      GeneratedColumn<String>(
        'long_term_relation_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL PRIMARY KEY',
      );
  static const VerificationMeta _firstOperationMeta = const VerificationMeta(
    'firstOperation',
  );
  late final GeneratedColumn<String> firstOperation = GeneratedColumn<String>(
    'first_operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (first_operation IN (\'insert\', \'update\', \'delete\'))',
  );
  @override
  List<GeneratedColumn> get $columns => [longTermRelationId, firstOperation];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graph_log_long_term_relation_marks';
  @override
  VerificationContext validateIntegrity(
    Insertable<GraphLogLongTermRelationMark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('first_operation')) {
      context.handle(
        _firstOperationMeta,
        firstOperation.isAcceptableOrUnknown(
          data['first_operation']!,
          _firstOperationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstOperationMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {longTermRelationId};
  @override
  GraphLogLongTermRelationMark map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GraphLogLongTermRelationMark(
      longTermRelationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}long_term_relation_id'],
      )!,
      firstOperation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_operation'],
      )!,
    );
  }

  @override
  GraphLogLongTermRelationMarks createAlias(String alias) {
    return GraphLogLongTermRelationMarks(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class GraphLogLongTermRelationMark extends DataClass
    implements Insertable<GraphLogLongTermRelationMark> {
  final String longTermRelationId;
  final String firstOperation;
  const GraphLogLongTermRelationMark({
    required this.longTermRelationId,
    required this.firstOperation,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['long_term_relation_id'] = Variable<String>(longTermRelationId);
    map['first_operation'] = Variable<String>(firstOperation);
    return map;
  }

  GraphLogLongTermRelationMarksCompanion toCompanion(bool nullToAbsent) {
    return GraphLogLongTermRelationMarksCompanion(
      longTermRelationId: Value(longTermRelationId),
      firstOperation: Value(firstOperation),
    );
  }

  factory GraphLogLongTermRelationMark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GraphLogLongTermRelationMark(
      longTermRelationId: serializer.fromJson<String>(
        json['long_term_relation_id'],
      ),
      firstOperation: serializer.fromJson<String>(json['first_operation']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'long_term_relation_id': serializer.toJson<String>(longTermRelationId),
      'first_operation': serializer.toJson<String>(firstOperation),
    };
  }

  GraphLogLongTermRelationMark copyWith({
    String? longTermRelationId,
    String? firstOperation,
  }) => GraphLogLongTermRelationMark(
    longTermRelationId: longTermRelationId ?? this.longTermRelationId,
    firstOperation: firstOperation ?? this.firstOperation,
  );
  GraphLogLongTermRelationMark copyWithCompanion(
    GraphLogLongTermRelationMarksCompanion data,
  ) {
    return GraphLogLongTermRelationMark(
      longTermRelationId: data.longTermRelationId.present
          ? data.longTermRelationId.value
          : this.longTermRelationId,
      firstOperation: data.firstOperation.present
          ? data.firstOperation.value
          : this.firstOperation,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogLongTermRelationMark(')
          ..write('longTermRelationId: $longTermRelationId, ')
          ..write('firstOperation: $firstOperation')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(longTermRelationId, firstOperation);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GraphLogLongTermRelationMark &&
          other.longTermRelationId == this.longTermRelationId &&
          other.firstOperation == this.firstOperation);
}

class GraphLogLongTermRelationMarksCompanion
    extends UpdateCompanion<GraphLogLongTermRelationMark> {
  final Value<String> longTermRelationId;
  final Value<String> firstOperation;
  final Value<int> rowid;
  const GraphLogLongTermRelationMarksCompanion({
    this.longTermRelationId = const Value.absent(),
    this.firstOperation = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GraphLogLongTermRelationMarksCompanion.insert({
    required String longTermRelationId,
    required String firstOperation,
    this.rowid = const Value.absent(),
  }) : longTermRelationId = Value(longTermRelationId),
       firstOperation = Value(firstOperation);
  static Insertable<GraphLogLongTermRelationMark> custom({
    Expression<String>? longTermRelationId,
    Expression<String>? firstOperation,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (longTermRelationId != null)
        'long_term_relation_id': longTermRelationId,
      if (firstOperation != null) 'first_operation': firstOperation,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GraphLogLongTermRelationMarksCompanion copyWith({
    Value<String>? longTermRelationId,
    Value<String>? firstOperation,
    Value<int>? rowid,
  }) {
    return GraphLogLongTermRelationMarksCompanion(
      longTermRelationId: longTermRelationId ?? this.longTermRelationId,
      firstOperation: firstOperation ?? this.firstOperation,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (longTermRelationId.present) {
      map['long_term_relation_id'] = Variable<String>(longTermRelationId.value);
    }
    if (firstOperation.present) {
      map['first_operation'] = Variable<String>(firstOperation.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogLongTermRelationMarksCompanion(')
          ..write('longTermRelationId: $longTermRelationId, ')
          ..write('firstOperation: $firstOperation, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class GraphLogActionMarks extends Table
    with TableInfo<GraphLogActionMarks, GraphLogActionMark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  GraphLogActionMarks(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _actionIdMeta = const VerificationMeta(
    'actionId',
  );
  late final GeneratedColumn<String> actionId = GeneratedColumn<String>(
    'action_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _firstOperationMeta = const VerificationMeta(
    'firstOperation',
  );
  late final GeneratedColumn<String> firstOperation = GeneratedColumn<String>(
    'first_operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (first_operation IN (\'insert\', \'update\', \'delete\'))',
  );
  @override
  List<GeneratedColumn> get $columns => [actionId, firstOperation];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graph_log_action_marks';
  @override
  VerificationContext validateIntegrity(
    Insertable<GraphLogActionMark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('action_id')) {
      context.handle(
        _actionIdMeta,
        actionId.isAcceptableOrUnknown(data['action_id']!, _actionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actionIdMeta);
    }
    if (data.containsKey('first_operation')) {
      context.handle(
        _firstOperationMeta,
        firstOperation.isAcceptableOrUnknown(
          data['first_operation']!,
          _firstOperationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstOperationMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {actionId};
  @override
  GraphLogActionMark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GraphLogActionMark(
      actionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_id'],
      )!,
      firstOperation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_operation'],
      )!,
    );
  }

  @override
  GraphLogActionMarks createAlias(String alias) {
    return GraphLogActionMarks(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class GraphLogActionMark extends DataClass
    implements Insertable<GraphLogActionMark> {
  final String actionId;
  final String firstOperation;
  const GraphLogActionMark({
    required this.actionId,
    required this.firstOperation,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['action_id'] = Variable<String>(actionId);
    map['first_operation'] = Variable<String>(firstOperation);
    return map;
  }

  GraphLogActionMarksCompanion toCompanion(bool nullToAbsent) {
    return GraphLogActionMarksCompanion(
      actionId: Value(actionId),
      firstOperation: Value(firstOperation),
    );
  }

  factory GraphLogActionMark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GraphLogActionMark(
      actionId: serializer.fromJson<String>(json['action_id']),
      firstOperation: serializer.fromJson<String>(json['first_operation']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'action_id': serializer.toJson<String>(actionId),
      'first_operation': serializer.toJson<String>(firstOperation),
    };
  }

  GraphLogActionMark copyWith({String? actionId, String? firstOperation}) =>
      GraphLogActionMark(
        actionId: actionId ?? this.actionId,
        firstOperation: firstOperation ?? this.firstOperation,
      );
  GraphLogActionMark copyWithCompanion(GraphLogActionMarksCompanion data) {
    return GraphLogActionMark(
      actionId: data.actionId.present ? data.actionId.value : this.actionId,
      firstOperation: data.firstOperation.present
          ? data.firstOperation.value
          : this.firstOperation,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogActionMark(')
          ..write('actionId: $actionId, ')
          ..write('firstOperation: $firstOperation')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(actionId, firstOperation);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GraphLogActionMark &&
          other.actionId == this.actionId &&
          other.firstOperation == this.firstOperation);
}

class GraphLogActionMarksCompanion extends UpdateCompanion<GraphLogActionMark> {
  final Value<String> actionId;
  final Value<String> firstOperation;
  final Value<int> rowid;
  const GraphLogActionMarksCompanion({
    this.actionId = const Value.absent(),
    this.firstOperation = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GraphLogActionMarksCompanion.insert({
    required String actionId,
    required String firstOperation,
    this.rowid = const Value.absent(),
  }) : actionId = Value(actionId),
       firstOperation = Value(firstOperation);
  static Insertable<GraphLogActionMark> custom({
    Expression<String>? actionId,
    Expression<String>? firstOperation,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (actionId != null) 'action_id': actionId,
      if (firstOperation != null) 'first_operation': firstOperation,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GraphLogActionMarksCompanion copyWith({
    Value<String>? actionId,
    Value<String>? firstOperation,
    Value<int>? rowid,
  }) {
    return GraphLogActionMarksCompanion(
      actionId: actionId ?? this.actionId,
      firstOperation: firstOperation ?? this.firstOperation,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (actionId.present) {
      map['action_id'] = Variable<String>(actionId.value);
    }
    if (firstOperation.present) {
      map['first_operation'] = Variable<String>(firstOperation.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogActionMarksCompanion(')
          ..write('actionId: $actionId, ')
          ..write('firstOperation: $firstOperation, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class GraphLogDeletedIntentionMarks extends Table
    with
        TableInfo<GraphLogDeletedIntentionMarks, GraphLogDeletedIntentionMark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  GraphLogDeletedIntentionMarks(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _intentionIdMeta = const VerificationMeta(
    'intentionId',
  );
  late final GeneratedColumn<String> intentionId = GeneratedColumn<String>(
    'intention_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _firstOperationMeta = const VerificationMeta(
    'firstOperation',
  );
  late final GeneratedColumn<String> firstOperation = GeneratedColumn<String>(
    'first_operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (first_operation IN (\'insert\', \'delete\'))',
  );
  @override
  List<GeneratedColumn> get $columns => [intentionId, firstOperation];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graph_log_deleted_intention_marks';
  @override
  VerificationContext validateIntegrity(
    Insertable<GraphLogDeletedIntentionMark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('intention_id')) {
      context.handle(
        _intentionIdMeta,
        intentionId.isAcceptableOrUnknown(
          data['intention_id']!,
          _intentionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_intentionIdMeta);
    }
    if (data.containsKey('first_operation')) {
      context.handle(
        _firstOperationMeta,
        firstOperation.isAcceptableOrUnknown(
          data['first_operation']!,
          _firstOperationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstOperationMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {intentionId};
  @override
  GraphLogDeletedIntentionMark map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GraphLogDeletedIntentionMark(
      intentionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intention_id'],
      )!,
      firstOperation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_operation'],
      )!,
    );
  }

  @override
  GraphLogDeletedIntentionMarks createAlias(String alias) {
    return GraphLogDeletedIntentionMarks(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class GraphLogDeletedIntentionMark extends DataClass
    implements Insertable<GraphLogDeletedIntentionMark> {
  final String intentionId;
  final String firstOperation;
  const GraphLogDeletedIntentionMark({
    required this.intentionId,
    required this.firstOperation,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['intention_id'] = Variable<String>(intentionId);
    map['first_operation'] = Variable<String>(firstOperation);
    return map;
  }

  GraphLogDeletedIntentionMarksCompanion toCompanion(bool nullToAbsent) {
    return GraphLogDeletedIntentionMarksCompanion(
      intentionId: Value(intentionId),
      firstOperation: Value(firstOperation),
    );
  }

  factory GraphLogDeletedIntentionMark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GraphLogDeletedIntentionMark(
      intentionId: serializer.fromJson<String>(json['intention_id']),
      firstOperation: serializer.fromJson<String>(json['first_operation']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'intention_id': serializer.toJson<String>(intentionId),
      'first_operation': serializer.toJson<String>(firstOperation),
    };
  }

  GraphLogDeletedIntentionMark copyWith({
    String? intentionId,
    String? firstOperation,
  }) => GraphLogDeletedIntentionMark(
    intentionId: intentionId ?? this.intentionId,
    firstOperation: firstOperation ?? this.firstOperation,
  );
  GraphLogDeletedIntentionMark copyWithCompanion(
    GraphLogDeletedIntentionMarksCompanion data,
  ) {
    return GraphLogDeletedIntentionMark(
      intentionId: data.intentionId.present
          ? data.intentionId.value
          : this.intentionId,
      firstOperation: data.firstOperation.present
          ? data.firstOperation.value
          : this.firstOperation,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogDeletedIntentionMark(')
          ..write('intentionId: $intentionId, ')
          ..write('firstOperation: $firstOperation')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(intentionId, firstOperation);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GraphLogDeletedIntentionMark &&
          other.intentionId == this.intentionId &&
          other.firstOperation == this.firstOperation);
}

class GraphLogDeletedIntentionMarksCompanion
    extends UpdateCompanion<GraphLogDeletedIntentionMark> {
  final Value<String> intentionId;
  final Value<String> firstOperation;
  final Value<int> rowid;
  const GraphLogDeletedIntentionMarksCompanion({
    this.intentionId = const Value.absent(),
    this.firstOperation = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GraphLogDeletedIntentionMarksCompanion.insert({
    required String intentionId,
    required String firstOperation,
    this.rowid = const Value.absent(),
  }) : intentionId = Value(intentionId),
       firstOperation = Value(firstOperation);
  static Insertable<GraphLogDeletedIntentionMark> custom({
    Expression<String>? intentionId,
    Expression<String>? firstOperation,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (intentionId != null) 'intention_id': intentionId,
      if (firstOperation != null) 'first_operation': firstOperation,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GraphLogDeletedIntentionMarksCompanion copyWith({
    Value<String>? intentionId,
    Value<String>? firstOperation,
    Value<int>? rowid,
  }) {
    return GraphLogDeletedIntentionMarksCompanion(
      intentionId: intentionId ?? this.intentionId,
      firstOperation: firstOperation ?? this.firstOperation,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (intentionId.present) {
      map['intention_id'] = Variable<String>(intentionId.value);
    }
    if (firstOperation.present) {
      map['first_operation'] = Variable<String>(firstOperation.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogDeletedIntentionMarksCompanion(')
          ..write('intentionId: $intentionId, ')
          ..write('firstOperation: $firstOperation, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class GraphLogDeletedRelationPairMarks extends Table
    with
        TableInfo<
          GraphLogDeletedRelationPairMarks,
          GraphLogDeletedRelationPairMark
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  GraphLogDeletedRelationPairMarks(this.attachedDatabase, [this._alias]);
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
        $customConstraints: 'NOT NULL',
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
        $customConstraints: 'NOT NULL',
      );
  static const VerificationMeta _firstOperationMeta = const VerificationMeta(
    'firstOperation',
  );
  late final GeneratedColumn<String> firstOperation = GeneratedColumn<String>(
    'first_operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (first_operation IN (\'insert\', \'delete\'))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceIntentionId,
    relatedIntentionId,
    firstOperation,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graph_log_deleted_relation_pair_marks';
  @override
  VerificationContext validateIntegrity(
    Insertable<GraphLogDeletedRelationPairMark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('first_operation')) {
      context.handle(
        _firstOperationMeta,
        firstOperation.isAcceptableOrUnknown(
          data['first_operation']!,
          _firstOperationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstOperationMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    sourceIntentionId,
    relatedIntentionId,
  };
  @override
  GraphLogDeletedRelationPairMark map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GraphLogDeletedRelationPairMark(
      sourceIntentionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_intention_id'],
      )!,
      relatedIntentionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}related_intention_id'],
      )!,
      firstOperation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_operation'],
      )!,
    );
  }

  @override
  GraphLogDeletedRelationPairMarks createAlias(String alias) {
    return GraphLogDeletedRelationPairMarks(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(source_intention_id, related_intention_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class GraphLogDeletedRelationPairMark extends DataClass
    implements Insertable<GraphLogDeletedRelationPairMark> {
  final String sourceIntentionId;
  final String relatedIntentionId;
  final String firstOperation;
  const GraphLogDeletedRelationPairMark({
    required this.sourceIntentionId,
    required this.relatedIntentionId,
    required this.firstOperation,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_intention_id'] = Variable<String>(sourceIntentionId);
    map['related_intention_id'] = Variable<String>(relatedIntentionId);
    map['first_operation'] = Variable<String>(firstOperation);
    return map;
  }

  GraphLogDeletedRelationPairMarksCompanion toCompanion(bool nullToAbsent) {
    return GraphLogDeletedRelationPairMarksCompanion(
      sourceIntentionId: Value(sourceIntentionId),
      relatedIntentionId: Value(relatedIntentionId),
      firstOperation: Value(firstOperation),
    );
  }

  factory GraphLogDeletedRelationPairMark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GraphLogDeletedRelationPairMark(
      sourceIntentionId: serializer.fromJson<String>(
        json['source_intention_id'],
      ),
      relatedIntentionId: serializer.fromJson<String>(
        json['related_intention_id'],
      ),
      firstOperation: serializer.fromJson<String>(json['first_operation']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source_intention_id': serializer.toJson<String>(sourceIntentionId),
      'related_intention_id': serializer.toJson<String>(relatedIntentionId),
      'first_operation': serializer.toJson<String>(firstOperation),
    };
  }

  GraphLogDeletedRelationPairMark copyWith({
    String? sourceIntentionId,
    String? relatedIntentionId,
    String? firstOperation,
  }) => GraphLogDeletedRelationPairMark(
    sourceIntentionId: sourceIntentionId ?? this.sourceIntentionId,
    relatedIntentionId: relatedIntentionId ?? this.relatedIntentionId,
    firstOperation: firstOperation ?? this.firstOperation,
  );
  GraphLogDeletedRelationPairMark copyWithCompanion(
    GraphLogDeletedRelationPairMarksCompanion data,
  ) {
    return GraphLogDeletedRelationPairMark(
      sourceIntentionId: data.sourceIntentionId.present
          ? data.sourceIntentionId.value
          : this.sourceIntentionId,
      relatedIntentionId: data.relatedIntentionId.present
          ? data.relatedIntentionId.value
          : this.relatedIntentionId,
      firstOperation: data.firstOperation.present
          ? data.firstOperation.value
          : this.firstOperation,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogDeletedRelationPairMark(')
          ..write('sourceIntentionId: $sourceIntentionId, ')
          ..write('relatedIntentionId: $relatedIntentionId, ')
          ..write('firstOperation: $firstOperation')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sourceIntentionId, relatedIntentionId, firstOperation);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GraphLogDeletedRelationPairMark &&
          other.sourceIntentionId == this.sourceIntentionId &&
          other.relatedIntentionId == this.relatedIntentionId &&
          other.firstOperation == this.firstOperation);
}

class GraphLogDeletedRelationPairMarksCompanion
    extends UpdateCompanion<GraphLogDeletedRelationPairMark> {
  final Value<String> sourceIntentionId;
  final Value<String> relatedIntentionId;
  final Value<String> firstOperation;
  final Value<int> rowid;
  const GraphLogDeletedRelationPairMarksCompanion({
    this.sourceIntentionId = const Value.absent(),
    this.relatedIntentionId = const Value.absent(),
    this.firstOperation = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GraphLogDeletedRelationPairMarksCompanion.insert({
    required String sourceIntentionId,
    required String relatedIntentionId,
    required String firstOperation,
    this.rowid = const Value.absent(),
  }) : sourceIntentionId = Value(sourceIntentionId),
       relatedIntentionId = Value(relatedIntentionId),
       firstOperation = Value(firstOperation);
  static Insertable<GraphLogDeletedRelationPairMark> custom({
    Expression<String>? sourceIntentionId,
    Expression<String>? relatedIntentionId,
    Expression<String>? firstOperation,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceIntentionId != null) 'source_intention_id': sourceIntentionId,
      if (relatedIntentionId != null)
        'related_intention_id': relatedIntentionId,
      if (firstOperation != null) 'first_operation': firstOperation,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GraphLogDeletedRelationPairMarksCompanion copyWith({
    Value<String>? sourceIntentionId,
    Value<String>? relatedIntentionId,
    Value<String>? firstOperation,
    Value<int>? rowid,
  }) {
    return GraphLogDeletedRelationPairMarksCompanion(
      sourceIntentionId: sourceIntentionId ?? this.sourceIntentionId,
      relatedIntentionId: relatedIntentionId ?? this.relatedIntentionId,
      firstOperation: firstOperation ?? this.firstOperation,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceIntentionId.present) {
      map['source_intention_id'] = Variable<String>(sourceIntentionId.value);
    }
    if (relatedIntentionId.present) {
      map['related_intention_id'] = Variable<String>(relatedIntentionId.value);
    }
    if (firstOperation.present) {
      map['first_operation'] = Variable<String>(firstOperation.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogDeletedRelationPairMarksCompanion(')
          ..write('sourceIntentionId: $sourceIntentionId, ')
          ..write('relatedIntentionId: $relatedIntentionId, ')
          ..write('firstOperation: $firstOperation, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class GraphSnapshots extends Table
    with TableInfo<GraphSnapshots, RegisteredGraphSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  GraphSnapshots(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT CHECK (id > 0)',
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (typeof(position) = \'integer\' AND position >= 0)',
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE CHECK (typeof(file_name) = \'text\' AND file_name <> \'\')',
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (typeof(byte_size) = \'integer\' AND byte_size > 0)',
  );
  static const VerificationMeta _checksumMeta = const VerificationMeta(
    'checksum',
  );
  late final GeneratedColumn<Uint8List> checksum = GeneratedColumn<Uint8List>(
    'checksum',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(checksum) = \'blob\' AND length(checksum) = 32)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    position,
    fileName,
    byteSize,
    checksum,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graph_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<RegisteredGraphSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_byteSizeMeta);
    }
    if (data.containsKey('checksum')) {
      context.handle(
        _checksumMeta,
        checksum.isAcceptableOrUnknown(data['checksum']!, _checksumMeta),
      );
    } else if (isInserting) {
      context.missing(_checksumMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RegisteredGraphSnapshot map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RegisteredGraphSnapshot(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
      checksum: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}checksum'],
      )!,
    );
  }

  @override
  GraphSnapshots createAlias(String alias) {
    return GraphSnapshots(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class RegisteredGraphSnapshot extends DataClass
    implements Insertable<RegisteredGraphSnapshot> {
  final int id;
  final int position;
  final String fileName;
  final int byteSize;

  /// SHA-256 файла снимка.
  final Uint8List checksum;
  const RegisteredGraphSnapshot({
    required this.id,
    required this.position,
    required this.fileName,
    required this.byteSize,
    required this.checksum,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['position'] = Variable<int>(position);
    map['file_name'] = Variable<String>(fileName);
    map['byte_size'] = Variable<int>(byteSize);
    map['checksum'] = Variable<Uint8List>(checksum);
    return map;
  }

  GraphSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return GraphSnapshotsCompanion(
      id: Value(id),
      position: Value(position),
      fileName: Value(fileName),
      byteSize: Value(byteSize),
      checksum: Value(checksum),
    );
  }

  factory RegisteredGraphSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RegisteredGraphSnapshot(
      id: serializer.fromJson<int>(json['id']),
      position: serializer.fromJson<int>(json['position']),
      fileName: serializer.fromJson<String>(json['file_name']),
      byteSize: serializer.fromJson<int>(json['byte_size']),
      checksum: serializer.fromJson<Uint8List>(json['checksum']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'position': serializer.toJson<int>(position),
      'file_name': serializer.toJson<String>(fileName),
      'byte_size': serializer.toJson<int>(byteSize),
      'checksum': serializer.toJson<Uint8List>(checksum),
    };
  }

  RegisteredGraphSnapshot copyWith({
    int? id,
    int? position,
    String? fileName,
    int? byteSize,
    Uint8List? checksum,
  }) => RegisteredGraphSnapshot(
    id: id ?? this.id,
    position: position ?? this.position,
    fileName: fileName ?? this.fileName,
    byteSize: byteSize ?? this.byteSize,
    checksum: checksum ?? this.checksum,
  );
  RegisteredGraphSnapshot copyWithCompanion(GraphSnapshotsCompanion data) {
    return RegisteredGraphSnapshot(
      id: data.id.present ? data.id.value : this.id,
      position: data.position.present ? data.position.value : this.position,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      checksum: data.checksum.present ? data.checksum.value : this.checksum,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RegisteredGraphSnapshot(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('fileName: $fileName, ')
          ..write('byteSize: $byteSize, ')
          ..write('checksum: $checksum')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    position,
    fileName,
    byteSize,
    $driftBlobEquality.hash(checksum),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RegisteredGraphSnapshot &&
          other.id == this.id &&
          other.position == this.position &&
          other.fileName == this.fileName &&
          other.byteSize == this.byteSize &&
          $driftBlobEquality.equals(other.checksum, this.checksum));
}

class GraphSnapshotsCompanion extends UpdateCompanion<RegisteredGraphSnapshot> {
  final Value<int> id;
  final Value<int> position;
  final Value<String> fileName;
  final Value<int> byteSize;
  final Value<Uint8List> checksum;
  const GraphSnapshotsCompanion({
    this.id = const Value.absent(),
    this.position = const Value.absent(),
    this.fileName = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.checksum = const Value.absent(),
  });
  GraphSnapshotsCompanion.insert({
    this.id = const Value.absent(),
    required int position,
    required String fileName,
    required int byteSize,
    required Uint8List checksum,
  }) : position = Value(position),
       fileName = Value(fileName),
       byteSize = Value(byteSize),
       checksum = Value(checksum);
  static Insertable<RegisteredGraphSnapshot> custom({
    Expression<int>? id,
    Expression<int>? position,
    Expression<String>? fileName,
    Expression<int>? byteSize,
    Expression<Uint8List>? checksum,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (position != null) 'position': position,
      if (fileName != null) 'file_name': fileName,
      if (byteSize != null) 'byte_size': byteSize,
      if (checksum != null) 'checksum': checksum,
    });
  }

  GraphSnapshotsCompanion copyWith({
    Value<int>? id,
    Value<int>? position,
    Value<String>? fileName,
    Value<int>? byteSize,
    Value<Uint8List>? checksum,
  }) {
    return GraphSnapshotsCompanion(
      id: id ?? this.id,
      position: position ?? this.position,
      fileName: fileName ?? this.fileName,
      byteSize: byteSize ?? this.byteSize,
      checksum: checksum ?? this.checksum,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (checksum.present) {
      map['checksum'] = Variable<Uint8List>(checksum.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GraphSnapshotsCompanion(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('fileName: $fileName, ')
          ..write('byteSize: $byteSize, ')
          ..write('checksum: $checksum')
          ..write(')'))
        .toString();
  }
}

class GraphLogPackages extends Table
    with TableInfo<GraphLogPackages, GraphLogPackage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  GraphLogPackages(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL PRIMARY KEY AUTOINCREMENT CHECK (position > 0)',
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  late final GeneratedColumn<int> recordedAt = GeneratedColumn<int>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(recorded_at) = \'integer\')',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(kind) = \'text\' AND kind IN (\'change\', \'reset\'))',
  );
  static const VerificationMeta _formatVersionMeta = const VerificationMeta(
    'formatVersion',
  );
  late final GeneratedColumn<int> formatVersion = GeneratedColumn<int>(
    'format_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (format_version IS NULL OR(typeof(format_version) = \'integer\' AND format_version > 0))',
  );
  static const VerificationMeta _factsMeta = const VerificationMeta('facts');
  late final GeneratedColumn<Uint8List> facts = GeneratedColumn<Uint8List>(
    'facts',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (facts IS NULL OR typeof(facts) = \'blob\')',
  );
  static const VerificationMeta _snapshotIdMeta = const VerificationMeta(
    'snapshotId',
  );
  late final GeneratedColumn<int> snapshotId = GeneratedColumn<int>(
    'snapshot_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'REFERENCES graph_snapshots(id)ON UPDATE RESTRICT ON DELETE RESTRICT',
  );
  @override
  List<GeneratedColumn> get $columns => [
    position,
    recordedAt,
    kind,
    formatVersion,
    facts,
    snapshotId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graph_log_packages';
  @override
  VerificationContext validateIntegrity(
    Insertable<GraphLogPackage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('format_version')) {
      context.handle(
        _formatVersionMeta,
        formatVersion.isAcceptableOrUnknown(
          data['format_version']!,
          _formatVersionMeta,
        ),
      );
    }
    if (data.containsKey('facts')) {
      context.handle(
        _factsMeta,
        facts.isAcceptableOrUnknown(data['facts']!, _factsMeta),
      );
    }
    if (data.containsKey('snapshot_id')) {
      context.handle(
        _snapshotIdMeta,
        snapshotId.isAcceptableOrUnknown(data['snapshot_id']!, _snapshotIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {position};
  @override
  GraphLogPackage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GraphLogPackage(
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recorded_at'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      formatVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}format_version'],
      ),
      facts: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}facts'],
      ),
      snapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snapshot_id'],
      ),
    );
  }

  @override
  GraphLogPackages createAlias(String alias) {
    return GraphLogPackages(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK((kind = \'change\' AND format_version IS NOT NULL AND facts IS NOT NULL AND snapshot_id IS NULL)OR(kind = \'reset\' AND format_version IS NULL AND facts IS NULL AND snapshot_id IS NOT NULL))',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class GraphLogPackage extends DataClass implements Insertable<GraphLogPackage> {
  final int position;
  final int recordedAt;
  final String kind;
  final int? formatVersion;
  final Uint8List? facts;
  final int? snapshotId;
  const GraphLogPackage({
    required this.position,
    required this.recordedAt,
    required this.kind,
    this.formatVersion,
    this.facts,
    this.snapshotId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['position'] = Variable<int>(position);
    map['recorded_at'] = Variable<int>(recordedAt);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || formatVersion != null) {
      map['format_version'] = Variable<int>(formatVersion);
    }
    if (!nullToAbsent || facts != null) {
      map['facts'] = Variable<Uint8List>(facts);
    }
    if (!nullToAbsent || snapshotId != null) {
      map['snapshot_id'] = Variable<int>(snapshotId);
    }
    return map;
  }

  GraphLogPackagesCompanion toCompanion(bool nullToAbsent) {
    return GraphLogPackagesCompanion(
      position: Value(position),
      recordedAt: Value(recordedAt),
      kind: Value(kind),
      formatVersion: formatVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(formatVersion),
      facts: facts == null && nullToAbsent
          ? const Value.absent()
          : Value(facts),
      snapshotId: snapshotId == null && nullToAbsent
          ? const Value.absent()
          : Value(snapshotId),
    );
  }

  factory GraphLogPackage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GraphLogPackage(
      position: serializer.fromJson<int>(json['position']),
      recordedAt: serializer.fromJson<int>(json['recorded_at']),
      kind: serializer.fromJson<String>(json['kind']),
      formatVersion: serializer.fromJson<int?>(json['format_version']),
      facts: serializer.fromJson<Uint8List?>(json['facts']),
      snapshotId: serializer.fromJson<int?>(json['snapshot_id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'position': serializer.toJson<int>(position),
      'recorded_at': serializer.toJson<int>(recordedAt),
      'kind': serializer.toJson<String>(kind),
      'format_version': serializer.toJson<int?>(formatVersion),
      'facts': serializer.toJson<Uint8List?>(facts),
      'snapshot_id': serializer.toJson<int?>(snapshotId),
    };
  }

  GraphLogPackage copyWith({
    int? position,
    int? recordedAt,
    String? kind,
    Value<int?> formatVersion = const Value.absent(),
    Value<Uint8List?> facts = const Value.absent(),
    Value<int?> snapshotId = const Value.absent(),
  }) => GraphLogPackage(
    position: position ?? this.position,
    recordedAt: recordedAt ?? this.recordedAt,
    kind: kind ?? this.kind,
    formatVersion: formatVersion.present
        ? formatVersion.value
        : this.formatVersion,
    facts: facts.present ? facts.value : this.facts,
    snapshotId: snapshotId.present ? snapshotId.value : this.snapshotId,
  );
  GraphLogPackage copyWithCompanion(GraphLogPackagesCompanion data) {
    return GraphLogPackage(
      position: data.position.present ? data.position.value : this.position,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
      kind: data.kind.present ? data.kind.value : this.kind,
      formatVersion: data.formatVersion.present
          ? data.formatVersion.value
          : this.formatVersion,
      facts: data.facts.present ? data.facts.value : this.facts,
      snapshotId: data.snapshotId.present
          ? data.snapshotId.value
          : this.snapshotId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogPackage(')
          ..write('position: $position, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('kind: $kind, ')
          ..write('formatVersion: $formatVersion, ')
          ..write('facts: $facts, ')
          ..write('snapshotId: $snapshotId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    position,
    recordedAt,
    kind,
    formatVersion,
    $driftBlobEquality.hash(facts),
    snapshotId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GraphLogPackage &&
          other.position == this.position &&
          other.recordedAt == this.recordedAt &&
          other.kind == this.kind &&
          other.formatVersion == this.formatVersion &&
          $driftBlobEquality.equals(other.facts, this.facts) &&
          other.snapshotId == this.snapshotId);
}

class GraphLogPackagesCompanion extends UpdateCompanion<GraphLogPackage> {
  final Value<int> position;
  final Value<int> recordedAt;
  final Value<String> kind;
  final Value<int?> formatVersion;
  final Value<Uint8List?> facts;
  final Value<int?> snapshotId;
  const GraphLogPackagesCompanion({
    this.position = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.kind = const Value.absent(),
    this.formatVersion = const Value.absent(),
    this.facts = const Value.absent(),
    this.snapshotId = const Value.absent(),
  });
  GraphLogPackagesCompanion.insert({
    this.position = const Value.absent(),
    required int recordedAt,
    required String kind,
    this.formatVersion = const Value.absent(),
    this.facts = const Value.absent(),
    this.snapshotId = const Value.absent(),
  }) : recordedAt = Value(recordedAt),
       kind = Value(kind);
  static Insertable<GraphLogPackage> custom({
    Expression<int>? position,
    Expression<int>? recordedAt,
    Expression<String>? kind,
    Expression<int>? formatVersion,
    Expression<Uint8List>? facts,
    Expression<int>? snapshotId,
  }) {
    return RawValuesInsertable({
      if (position != null) 'position': position,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (kind != null) 'kind': kind,
      if (formatVersion != null) 'format_version': formatVersion,
      if (facts != null) 'facts': facts,
      if (snapshotId != null) 'snapshot_id': snapshotId,
    });
  }

  GraphLogPackagesCompanion copyWith({
    Value<int>? position,
    Value<int>? recordedAt,
    Value<String>? kind,
    Value<int?>? formatVersion,
    Value<Uint8List?>? facts,
    Value<int?>? snapshotId,
  }) {
    return GraphLogPackagesCompanion(
      position: position ?? this.position,
      recordedAt: recordedAt ?? this.recordedAt,
      kind: kind ?? this.kind,
      formatVersion: formatVersion ?? this.formatVersion,
      facts: facts ?? this.facts,
      snapshotId: snapshotId ?? this.snapshotId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<int>(recordedAt.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (formatVersion.present) {
      map['format_version'] = Variable<int>(formatVersion.value);
    }
    if (facts.present) {
      map['facts'] = Variable<Uint8List>(facts.value);
    }
    if (snapshotId.present) {
      map['snapshot_id'] = Variable<int>(snapshotId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GraphLogPackagesCompanion(')
          ..write('position: $position, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('kind: $kind, ')
          ..write('formatVersion: $formatVersion, ')
          ..write('facts: $facts, ')
          ..write('snapshotId: $snapshotId')
          ..write(')'))
        .toString();
  }
}

class GraphBackups extends Table with TableInfo<GraphBackups, GraphBackup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  GraphBackups(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT CHECK (id > 0)',
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (typeof(position) = \'integer\' AND position >= 0)',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(kind) = \'text\' AND kind IN (\'daily\', \'manual\', \'before_replacement\'))',
  );
  static const VerificationMeta _madeAtMeta = const VerificationMeta('madeAt');
  late final GeneratedColumn<int> madeAt = GeneratedColumn<int>(
    'made_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(made_at) = \'integer\')',
  );
  static const VerificationMeta _graphReplacedMeta = const VerificationMeta(
    'graphReplaced',
  );
  late final GeneratedColumn<bool> graphReplaced = GeneratedColumn<bool>(
    'graph_replaced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(graph_replaced) = \'integer\' AND graph_replaced IN (0, 1))',
  );
  static const VerificationMeta _addedCountMeta = const VerificationMeta(
    'addedCount',
  );
  late final GeneratedColumn<int> addedCount = GeneratedColumn<int>(
    'added_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (added_count IS NULL OR(typeof(added_count) = \'integer\' AND added_count >= 0))',
  );
  static const VerificationMeta _changedCountMeta = const VerificationMeta(
    'changedCount',
  );
  late final GeneratedColumn<int> changedCount = GeneratedColumn<int>(
    'changed_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (changed_count IS NULL OR(typeof(changed_count) = \'integer\' AND changed_count >= 0))',
  );
  static const VerificationMeta _deletedCountMeta = const VerificationMeta(
    'deletedCount',
  );
  late final GeneratedColumn<int> deletedCount = GeneratedColumn<int>(
    'deleted_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (deleted_count IS NULL OR(typeof(deleted_count) = \'integer\' AND deleted_count >= 0))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    position,
    kind,
    madeAt,
    graphReplaced,
    addedCount,
    changedCount,
    deletedCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graph_backups';
  @override
  VerificationContext validateIntegrity(
    Insertable<GraphBackup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('made_at')) {
      context.handle(
        _madeAtMeta,
        madeAt.isAcceptableOrUnknown(data['made_at']!, _madeAtMeta),
      );
    } else if (isInserting) {
      context.missing(_madeAtMeta);
    }
    if (data.containsKey('graph_replaced')) {
      context.handle(
        _graphReplacedMeta,
        graphReplaced.isAcceptableOrUnknown(
          data['graph_replaced']!,
          _graphReplacedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_graphReplacedMeta);
    }
    if (data.containsKey('added_count')) {
      context.handle(
        _addedCountMeta,
        addedCount.isAcceptableOrUnknown(data['added_count']!, _addedCountMeta),
      );
    }
    if (data.containsKey('changed_count')) {
      context.handle(
        _changedCountMeta,
        changedCount.isAcceptableOrUnknown(
          data['changed_count']!,
          _changedCountMeta,
        ),
      );
    }
    if (data.containsKey('deleted_count')) {
      context.handle(
        _deletedCountMeta,
        deletedCount.isAcceptableOrUnknown(
          data['deleted_count']!,
          _deletedCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GraphBackup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GraphBackup(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      madeAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}made_at'],
      )!,
      graphReplaced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}graph_replaced'],
      )!,
      addedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_count'],
      ),
      changedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}changed_count'],
      ),
      deletedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_count'],
      ),
    );
  }

  @override
  GraphBackups createAlias(String alias) {
    return GraphBackups(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK((graph_replaced = 0 AND added_count IS NOT NULL AND changed_count IS NOT NULL AND deleted_count IS NOT NULL)OR(graph_replaced = 1 AND added_count IS NULL AND changed_count IS NULL AND deleted_count IS NULL))',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class GraphBackup extends DataClass implements Insertable<GraphBackup> {
  final int id;
  final int position;
  final String kind;
  final int madeAt;
  final bool graphReplaced;
  final int? addedCount;
  final int? changedCount;
  final int? deletedCount;
  const GraphBackup({
    required this.id,
    required this.position,
    required this.kind,
    required this.madeAt,
    required this.graphReplaced,
    this.addedCount,
    this.changedCount,
    this.deletedCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['position'] = Variable<int>(position);
    map['kind'] = Variable<String>(kind);
    map['made_at'] = Variable<int>(madeAt);
    map['graph_replaced'] = Variable<bool>(graphReplaced);
    if (!nullToAbsent || addedCount != null) {
      map['added_count'] = Variable<int>(addedCount);
    }
    if (!nullToAbsent || changedCount != null) {
      map['changed_count'] = Variable<int>(changedCount);
    }
    if (!nullToAbsent || deletedCount != null) {
      map['deleted_count'] = Variable<int>(deletedCount);
    }
    return map;
  }

  GraphBackupsCompanion toCompanion(bool nullToAbsent) {
    return GraphBackupsCompanion(
      id: Value(id),
      position: Value(position),
      kind: Value(kind),
      madeAt: Value(madeAt),
      graphReplaced: Value(graphReplaced),
      addedCount: addedCount == null && nullToAbsent
          ? const Value.absent()
          : Value(addedCount),
      changedCount: changedCount == null && nullToAbsent
          ? const Value.absent()
          : Value(changedCount),
      deletedCount: deletedCount == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedCount),
    );
  }

  factory GraphBackup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GraphBackup(
      id: serializer.fromJson<int>(json['id']),
      position: serializer.fromJson<int>(json['position']),
      kind: serializer.fromJson<String>(json['kind']),
      madeAt: serializer.fromJson<int>(json['made_at']),
      graphReplaced: serializer.fromJson<bool>(json['graph_replaced']),
      addedCount: serializer.fromJson<int?>(json['added_count']),
      changedCount: serializer.fromJson<int?>(json['changed_count']),
      deletedCount: serializer.fromJson<int?>(json['deleted_count']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'position': serializer.toJson<int>(position),
      'kind': serializer.toJson<String>(kind),
      'made_at': serializer.toJson<int>(madeAt),
      'graph_replaced': serializer.toJson<bool>(graphReplaced),
      'added_count': serializer.toJson<int?>(addedCount),
      'changed_count': serializer.toJson<int?>(changedCount),
      'deleted_count': serializer.toJson<int?>(deletedCount),
    };
  }

  GraphBackup copyWith({
    int? id,
    int? position,
    String? kind,
    int? madeAt,
    bool? graphReplaced,
    Value<int?> addedCount = const Value.absent(),
    Value<int?> changedCount = const Value.absent(),
    Value<int?> deletedCount = const Value.absent(),
  }) => GraphBackup(
    id: id ?? this.id,
    position: position ?? this.position,
    kind: kind ?? this.kind,
    madeAt: madeAt ?? this.madeAt,
    graphReplaced: graphReplaced ?? this.graphReplaced,
    addedCount: addedCount.present ? addedCount.value : this.addedCount,
    changedCount: changedCount.present ? changedCount.value : this.changedCount,
    deletedCount: deletedCount.present ? deletedCount.value : this.deletedCount,
  );
  GraphBackup copyWithCompanion(GraphBackupsCompanion data) {
    return GraphBackup(
      id: data.id.present ? data.id.value : this.id,
      position: data.position.present ? data.position.value : this.position,
      kind: data.kind.present ? data.kind.value : this.kind,
      madeAt: data.madeAt.present ? data.madeAt.value : this.madeAt,
      graphReplaced: data.graphReplaced.present
          ? data.graphReplaced.value
          : this.graphReplaced,
      addedCount: data.addedCount.present
          ? data.addedCount.value
          : this.addedCount,
      changedCount: data.changedCount.present
          ? data.changedCount.value
          : this.changedCount,
      deletedCount: data.deletedCount.present
          ? data.deletedCount.value
          : this.deletedCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GraphBackup(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('kind: $kind, ')
          ..write('madeAt: $madeAt, ')
          ..write('graphReplaced: $graphReplaced, ')
          ..write('addedCount: $addedCount, ')
          ..write('changedCount: $changedCount, ')
          ..write('deletedCount: $deletedCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    position,
    kind,
    madeAt,
    graphReplaced,
    addedCount,
    changedCount,
    deletedCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GraphBackup &&
          other.id == this.id &&
          other.position == this.position &&
          other.kind == this.kind &&
          other.madeAt == this.madeAt &&
          other.graphReplaced == this.graphReplaced &&
          other.addedCount == this.addedCount &&
          other.changedCount == this.changedCount &&
          other.deletedCount == this.deletedCount);
}

class GraphBackupsCompanion extends UpdateCompanion<GraphBackup> {
  final Value<int> id;
  final Value<int> position;
  final Value<String> kind;
  final Value<int> madeAt;
  final Value<bool> graphReplaced;
  final Value<int?> addedCount;
  final Value<int?> changedCount;
  final Value<int?> deletedCount;
  const GraphBackupsCompanion({
    this.id = const Value.absent(),
    this.position = const Value.absent(),
    this.kind = const Value.absent(),
    this.madeAt = const Value.absent(),
    this.graphReplaced = const Value.absent(),
    this.addedCount = const Value.absent(),
    this.changedCount = const Value.absent(),
    this.deletedCount = const Value.absent(),
  });
  GraphBackupsCompanion.insert({
    this.id = const Value.absent(),
    required int position,
    required String kind,
    required int madeAt,
    required bool graphReplaced,
    this.addedCount = const Value.absent(),
    this.changedCount = const Value.absent(),
    this.deletedCount = const Value.absent(),
  }) : position = Value(position),
       kind = Value(kind),
       madeAt = Value(madeAt),
       graphReplaced = Value(graphReplaced);
  static Insertable<GraphBackup> custom({
    Expression<int>? id,
    Expression<int>? position,
    Expression<String>? kind,
    Expression<int>? madeAt,
    Expression<bool>? graphReplaced,
    Expression<int>? addedCount,
    Expression<int>? changedCount,
    Expression<int>? deletedCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (position != null) 'position': position,
      if (kind != null) 'kind': kind,
      if (madeAt != null) 'made_at': madeAt,
      if (graphReplaced != null) 'graph_replaced': graphReplaced,
      if (addedCount != null) 'added_count': addedCount,
      if (changedCount != null) 'changed_count': changedCount,
      if (deletedCount != null) 'deleted_count': deletedCount,
    });
  }

  GraphBackupsCompanion copyWith({
    Value<int>? id,
    Value<int>? position,
    Value<String>? kind,
    Value<int>? madeAt,
    Value<bool>? graphReplaced,
    Value<int?>? addedCount,
    Value<int?>? changedCount,
    Value<int?>? deletedCount,
  }) {
    return GraphBackupsCompanion(
      id: id ?? this.id,
      position: position ?? this.position,
      kind: kind ?? this.kind,
      madeAt: madeAt ?? this.madeAt,
      graphReplaced: graphReplaced ?? this.graphReplaced,
      addedCount: addedCount ?? this.addedCount,
      changedCount: changedCount ?? this.changedCount,
      deletedCount: deletedCount ?? this.deletedCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (madeAt.present) {
      map['made_at'] = Variable<int>(madeAt.value);
    }
    if (graphReplaced.present) {
      map['graph_replaced'] = Variable<bool>(graphReplaced.value);
    }
    if (addedCount.present) {
      map['added_count'] = Variable<int>(addedCount.value);
    }
    if (changedCount.present) {
      map['changed_count'] = Variable<int>(changedCount.value);
    }
    if (deletedCount.present) {
      map['deleted_count'] = Variable<int>(deletedCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GraphBackupsCompanion(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('kind: $kind, ')
          ..write('madeAt: $madeAt, ')
          ..write('graphReplaced: $graphReplaced, ')
          ..write('addedCount: $addedCount, ')
          ..write('changedCount: $changedCount, ')
          ..write('deletedCount: $deletedCount')
          ..write(')'))
        .toString();
  }
}

class Tags extends Table with TableInfo<Tags, Tag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Tags(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(name) = \'text\' AND instr(CAST(name AS BLOB), X\'00\') = 0 AND substr(name, 1, 1) <> char(65279) AND doable_tag_name_valid_v1(name) = 1)',
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (color IS NULL OR color IN (\'brown\', \'orange\', \'olive\', \'green\', \'teal\', \'blue\', \'violet\', \'purple\', \'pink\'))',
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  late final GeneratedColumn<String> position = GeneratedColumn<String>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL COLLATE BINARY UNIQUE CHECK (typeof(position) = \'text\' AND length(position) > 0 AND instr(CAST(position AS BLOB), X\'00\') = 0 AND NOT position GLOB \'*[^0-9A-Za-z]*\')',
  );
  static const VerificationMeta _nameKeyMeta = const VerificationMeta(
    'nameKey',
  );
  late final GeneratedColumn<String> nameKey = GeneratedColumn<String>(
    'name_key',
    aliasedName,
    false,
    generatedAs: GeneratedAs(
      const CustomExpression('doable_tag_name_key_v1(name)'),
      true,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL COLLATE BINARY UNIQUE GENERATED ALWAYS AS (doable_tag_name_key_v1(name)) STORED',
  );
  @override
  List<GeneratedColumn> get $columns => [
    creationSequence,
    id,
    name,
    color,
    position,
    nameKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<Tag> instance, {
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
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('name_key')) {
      context.handle(
        _nameKeyMeta,
        nameKey.isAcceptableOrUnknown(data['name_key']!, _nameKeyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {creationSequence};
  @override
  Tag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tag(
      creationSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}creation_sequence'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}position'],
      )!,
      nameKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_key'],
      )!,
    );
  }

  @override
  Tags createAlias(String alias) {
    return Tags(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Tag extends DataClass implements Insertable<Tag> {
  final int creationSequence;
  final String id;
  final String name;

  /// NULL — тег без цвета; иначе устойчивый код `TagColor`.
  final String? color;

  /// Место в ручном порядке: дробный ключ `TagPosition`. Схема проверяет
  /// только алфавит, полную каноническую форму — декодер при чтении.
  final String position;
  final String nameKey;
  const Tag({
    required this.creationSequence,
    required this.id,
    required this.name,
    this.color,
    required this.position,
    required this.nameKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['creation_sequence'] = Variable<int>(creationSequence);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    map['position'] = Variable<String>(position);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      creationSequence: Value(creationSequence),
      id: Value(id),
      name: Value(name),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      position: Value(position),
    );
  }

  factory Tag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tag(
      creationSequence: serializer.fromJson<int>(json['creation_sequence']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<String?>(json['color']),
      position: serializer.fromJson<String>(json['position']),
      nameKey: serializer.fromJson<String>(json['name_key']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'creation_sequence': serializer.toJson<int>(creationSequence),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<String?>(color),
      'position': serializer.toJson<String>(position),
      'name_key': serializer.toJson<String>(nameKey),
    };
  }

  Tag copyWith({
    int? creationSequence,
    String? id,
    String? name,
    Value<String?> color = const Value.absent(),
    String? position,
    String? nameKey,
  }) => Tag(
    creationSequence: creationSequence ?? this.creationSequence,
    id: id ?? this.id,
    name: name ?? this.name,
    color: color.present ? color.value : this.color,
    position: position ?? this.position,
    nameKey: nameKey ?? this.nameKey,
  );
  @override
  String toString() {
    return (StringBuffer('Tag(')
          ..write('creationSequence: $creationSequence, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('position: $position, ')
          ..write('nameKey: $nameKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(creationSequence, id, name, color, position, nameKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tag &&
          other.creationSequence == this.creationSequence &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color &&
          other.position == this.position &&
          other.nameKey == this.nameKey);
}

class TagsCompanion extends UpdateCompanion<Tag> {
  final Value<int> creationSequence;
  final Value<String> id;
  final Value<String> name;
  final Value<String?> color;
  final Value<String> position;
  const TagsCompanion({
    this.creationSequence = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.position = const Value.absent(),
  });
  TagsCompanion.insert({
    this.creationSequence = const Value.absent(),
    required String id,
    required String name,
    this.color = const Value.absent(),
    required String position,
  }) : id = Value(id),
       name = Value(name),
       position = Value(position);
  static Insertable<Tag> custom({
    Expression<int>? creationSequence,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? color,
    Expression<String>? position,
  }) {
    return RawValuesInsertable({
      if (creationSequence != null) 'creation_sequence': creationSequence,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (position != null) 'position': position,
    });
  }

  TagsCompanion copyWith({
    Value<int>? creationSequence,
    Value<String>? id,
    Value<String>? name,
    Value<String?>? color,
    Value<String>? position,
  }) {
    return TagsCompanion(
      creationSequence: creationSequence ?? this.creationSequence,
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      position: position ?? this.position,
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
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (position.present) {
      map['position'] = Variable<String>(position.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('creationSequence: $creationSequence, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }
}

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
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT \'main\' CHECK (kind IN (\'main\', \'supporting\'))',
    defaultValue: const CustomExpression('\'main\''),
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
    kind,
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
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
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
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
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
  final String kind;
  final bool isArchived;
  final int createdAt;
  final int updatedAt;
  const Intention({
    required this.id,
    required this.title,
    required this.titleSearchKey,
    this.description,
    required this.kind,
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
    map['kind'] = Variable<String>(kind);
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
      kind: Value(kind),
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
      kind: serializer.fromJson<String>(json['kind']),
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
      'kind': serializer.toJson<String>(kind),
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
    String? kind,
    bool? isArchived,
    int? createdAt,
    int? updatedAt,
  }) => Intention(
    id: id ?? this.id,
    title: title ?? this.title,
    titleSearchKey: titleSearchKey ?? this.titleSearchKey,
    description: description.present ? description.value : this.description,
    kind: kind ?? this.kind,
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
          ..write('kind: $kind, ')
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
    kind,
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
          other.kind == this.kind &&
          other.isArchived == this.isArchived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class IntentionsCompanion extends UpdateCompanion<Intention> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> description;
  final Value<String> kind;
  final Value<bool> isArchived;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const IntentionsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.kind = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IntentionsCompanion.insert({
    required String id,
    required String title,
    this.description = const Value.absent(),
    this.kind = const Value.absent(),
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
    Expression<String>? kind,
    Expression<bool>? isArchived,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (kind != null) 'kind': kind,
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
    Value<String>? kind,
    Value<bool>? isArchived,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return IntentionsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      kind: kind ?? this.kind,
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
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
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
          ..write('kind: $kind, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class TagAssignments extends Table
    with TableInfo<TagAssignments, TagAssignment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  TagAssignments(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL REFERENCES tags(id)ON UPDATE RESTRICT ON DELETE CASCADE',
  );
  static const VerificationMeta _intentionIdMeta = const VerificationMeta(
    'intentionId',
  );
  late final GeneratedColumn<String> intentionId = GeneratedColumn<String>(
    'intention_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES intentions(id)ON UPDATE RESTRICT ON DELETE CASCADE',
  );
  @override
  List<GeneratedColumn> get $columns => [creationSequence, tagId, intentionId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tag_assignments';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagAssignment> instance, {
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
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    if (data.containsKey('intention_id')) {
      context.handle(
        _intentionIdMeta,
        intentionId.isAcceptableOrUnknown(
          data['intention_id']!,
          _intentionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_intentionIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {creationSequence};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {tagId, intentionId},
  ];
  @override
  TagAssignment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagAssignment(
      creationSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}creation_sequence'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
      intentionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intention_id'],
      )!,
    );
  }

  @override
  TagAssignments createAlias(String alias) {
    return TagAssignments(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['UNIQUE(tag_id, intention_id)'];
  @override
  bool get dontWriteConstraints => true;
}

class TagAssignment extends DataClass implements Insertable<TagAssignment> {
  final int creationSequence;
  final String tagId;
  final String intentionId;
  const TagAssignment({
    required this.creationSequence,
    required this.tagId,
    required this.intentionId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['creation_sequence'] = Variable<int>(creationSequence);
    map['tag_id'] = Variable<String>(tagId);
    map['intention_id'] = Variable<String>(intentionId);
    return map;
  }

  TagAssignmentsCompanion toCompanion(bool nullToAbsent) {
    return TagAssignmentsCompanion(
      creationSequence: Value(creationSequence),
      tagId: Value(tagId),
      intentionId: Value(intentionId),
    );
  }

  factory TagAssignment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagAssignment(
      creationSequence: serializer.fromJson<int>(json['creation_sequence']),
      tagId: serializer.fromJson<String>(json['tag_id']),
      intentionId: serializer.fromJson<String>(json['intention_id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'creation_sequence': serializer.toJson<int>(creationSequence),
      'tag_id': serializer.toJson<String>(tagId),
      'intention_id': serializer.toJson<String>(intentionId),
    };
  }

  TagAssignment copyWith({
    int? creationSequence,
    String? tagId,
    String? intentionId,
  }) => TagAssignment(
    creationSequence: creationSequence ?? this.creationSequence,
    tagId: tagId ?? this.tagId,
    intentionId: intentionId ?? this.intentionId,
  );
  TagAssignment copyWithCompanion(TagAssignmentsCompanion data) {
    return TagAssignment(
      creationSequence: data.creationSequence.present
          ? data.creationSequence.value
          : this.creationSequence,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      intentionId: data.intentionId.present
          ? data.intentionId.value
          : this.intentionId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagAssignment(')
          ..write('creationSequence: $creationSequence, ')
          ..write('tagId: $tagId, ')
          ..write('intentionId: $intentionId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(creationSequence, tagId, intentionId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagAssignment &&
          other.creationSequence == this.creationSequence &&
          other.tagId == this.tagId &&
          other.intentionId == this.intentionId);
}

class TagAssignmentsCompanion extends UpdateCompanion<TagAssignment> {
  final Value<int> creationSequence;
  final Value<String> tagId;
  final Value<String> intentionId;
  const TagAssignmentsCompanion({
    this.creationSequence = const Value.absent(),
    this.tagId = const Value.absent(),
    this.intentionId = const Value.absent(),
  });
  TagAssignmentsCompanion.insert({
    this.creationSequence = const Value.absent(),
    required String tagId,
    required String intentionId,
  }) : tagId = Value(tagId),
       intentionId = Value(intentionId);
  static Insertable<TagAssignment> custom({
    Expression<int>? creationSequence,
    Expression<String>? tagId,
    Expression<String>? intentionId,
  }) {
    return RawValuesInsertable({
      if (creationSequence != null) 'creation_sequence': creationSequence,
      if (tagId != null) 'tag_id': tagId,
      if (intentionId != null) 'intention_id': intentionId,
    });
  }

  TagAssignmentsCompanion copyWith({
    Value<int>? creationSequence,
    Value<String>? tagId,
    Value<String>? intentionId,
  }) {
    return TagAssignmentsCompanion(
      creationSequence: creationSequence ?? this.creationSequence,
      tagId: tagId ?? this.tagId,
      intentionId: intentionId ?? this.intentionId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (creationSequence.present) {
      map['creation_sequence'] = Variable<int>(creationSequence.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (intentionId.present) {
      map['intention_id'] = Variable<String>(intentionId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagAssignmentsCompanion(')
          ..write('creationSequence: $creationSequence, ')
          ..write('tagId: $tagId, ')
          ..write('intentionId: $intentionId')
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
    creationSequence,
    id,
    sourceIntentionId,
    relatedIntentionId,
    type,
    priority,
    description,
    isArchived,
    createdAt,
    updatedAt,
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
  final int createdAt;
  final int updatedAt;
  const LongTermRelation({
    required this.creationSequence,
    required this.id,
    required this.sourceIntentionId,
    required this.relatedIntentionId,
    required this.type,
    required this.priority,
    this.description,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
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
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
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
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
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
      createdAt: serializer.fromJson<int>(json['created_at']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
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
      'created_at': serializer.toJson<int>(createdAt),
      'updated_at': serializer.toJson<int>(updatedAt),
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
    int? createdAt,
    int? updatedAt,
  }) => LongTermRelation(
    creationSequence: creationSequence ?? this.creationSequence,
    id: id ?? this.id,
    sourceIntentionId: sourceIntentionId ?? this.sourceIntentionId,
    relatedIntentionId: relatedIntentionId ?? this.relatedIntentionId,
    type: type ?? this.type,
    priority: priority ?? this.priority,
    description: description.present ? description.value : this.description,
    isArchived: isArchived ?? this.isArchived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
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
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
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
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
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
    createdAt,
    updatedAt,
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
          other.isArchived == this.isArchived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
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
  final Value<int> createdAt;
  final Value<int> updatedAt;
  const LongTermRelationsCompanion({
    this.creationSequence = const Value.absent(),
    this.id = const Value.absent(),
    this.sourceIntentionId = const Value.absent(),
    this.relatedIntentionId = const Value.absent(),
    this.type = const Value.absent(),
    this.priority = const Value.absent(),
    this.description = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
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
    required int createdAt,
    required int updatedAt,
  }) : id = Value(id),
       sourceIntentionId = Value(sourceIntentionId),
       relatedIntentionId = Value(relatedIntentionId),
       type = Value(type),
       priority = Value(priority),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LongTermRelation> custom({
    Expression<int>? creationSequence,
    Expression<String>? id,
    Expression<String>? sourceIntentionId,
    Expression<String>? relatedIntentionId,
    Expression<String>? type,
    Expression<int>? priority,
    Expression<String>? description,
    Expression<bool>? isArchived,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
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
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
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
    Value<int>? createdAt,
    Value<int>? updatedAt,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
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
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class Actions extends Table with TableInfo<Actions, Action> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Actions(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(title) = \'text\' AND title <> \'\' AND instr(CAST(title AS BLOB), X\'00\') = 0)',
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
    $customConstraints: 'CHECK (description IS NULL OR(typeof(description) = \'text\' AND instr(CAST(description AS BLOB), X\'00\') = 0 AND length(trim(description, char(9) || char(10) || char(11) || char(12) || char(13) || char(32))) > 0))',
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(date) = \'text\' AND length(date) = 10 AND date GLOB \'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\')',
  );
  static const VerificationMeta _scheduledHourMeta = const VerificationMeta(
    'scheduledHour',
  );
  late final GeneratedColumn<int> scheduledHour = GeneratedColumn<int>(
    'scheduled_hour',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (scheduled_hour IS NULL OR(typeof(scheduled_hour) = \'integer\' AND scheduled_hour BETWEEN 0 AND 23))',
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
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(created_at) = \'integer\')',
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
    $customConstraints: 'NOT NULL CHECK (typeof(updated_at) = \'integer\')',
  );
  @override
  List<GeneratedColumn> get $columns => [
    creationSequence,
    id,
    title,
    description,
    date,
    scheduledHour,
    priority,
    isCompleted,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'actions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Action> instance, {
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
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
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
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('scheduled_hour')) {
      context.handle(
        _scheduledHourMeta,
        scheduledHour.isAcceptableOrUnknown(
          data['scheduled_hour']!,
          _scheduledHourMeta,
        ),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    } else if (isInserting) {
      context.missing(_priorityMeta);
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
  Set<GeneratedColumn> get $primaryKey => {creationSequence};
  @override
  Action map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Action(
      creationSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}creation_sequence'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      scheduledHour: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scheduled_hour'],
      ),
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      isCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_completed'],
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
  Actions createAlias(String alias) {
    return Actions(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Action extends DataClass implements Insertable<Action> {
  final int creationSequence;
  final String id;
  final String title;
  final String? description;
  final String date;

  /// NULL — «Весь день».
  final int? scheduledHour;
  final int priority;
  final bool isCompleted;
  final int createdAt;
  final int updatedAt;
  const Action({
    required this.creationSequence,
    required this.id,
    required this.title,
    this.description,
    required this.date,
    this.scheduledHour,
    required this.priority,
    required this.isCompleted,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['creation_sequence'] = Variable<int>(creationSequence);
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['date'] = Variable<String>(date);
    if (!nullToAbsent || scheduledHour != null) {
      map['scheduled_hour'] = Variable<int>(scheduledHour);
    }
    map['priority'] = Variable<int>(priority);
    map['is_completed'] = Variable<bool>(isCompleted);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ActionsCompanion toCompanion(bool nullToAbsent) {
    return ActionsCompanion(
      creationSequence: Value(creationSequence),
      id: Value(id),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      date: Value(date),
      scheduledHour: scheduledHour == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledHour),
      priority: Value(priority),
      isCompleted: Value(isCompleted),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Action.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Action(
      creationSequence: serializer.fromJson<int>(json['creation_sequence']),
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      date: serializer.fromJson<String>(json['date']),
      scheduledHour: serializer.fromJson<int?>(json['scheduled_hour']),
      priority: serializer.fromJson<int>(json['priority']),
      isCompleted: serializer.fromJson<bool>(json['is_completed']),
      createdAt: serializer.fromJson<int>(json['created_at']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'creation_sequence': serializer.toJson<int>(creationSequence),
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'date': serializer.toJson<String>(date),
      'scheduled_hour': serializer.toJson<int?>(scheduledHour),
      'priority': serializer.toJson<int>(priority),
      'is_completed': serializer.toJson<bool>(isCompleted),
      'created_at': serializer.toJson<int>(createdAt),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  Action copyWith({
    int? creationSequence,
    String? id,
    String? title,
    Value<String?> description = const Value.absent(),
    String? date,
    Value<int?> scheduledHour = const Value.absent(),
    int? priority,
    bool? isCompleted,
    int? createdAt,
    int? updatedAt,
  }) => Action(
    creationSequence: creationSequence ?? this.creationSequence,
    id: id ?? this.id,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    date: date ?? this.date,
    scheduledHour: scheduledHour.present
        ? scheduledHour.value
        : this.scheduledHour,
    priority: priority ?? this.priority,
    isCompleted: isCompleted ?? this.isCompleted,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Action copyWithCompanion(ActionsCompanion data) {
    return Action(
      creationSequence: data.creationSequence.present
          ? data.creationSequence.value
          : this.creationSequence,
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      date: data.date.present ? data.date.value : this.date,
      scheduledHour: data.scheduledHour.present
          ? data.scheduledHour.value
          : this.scheduledHour,
      priority: data.priority.present ? data.priority.value : this.priority,
      isCompleted: data.isCompleted.present
          ? data.isCompleted.value
          : this.isCompleted,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Action(')
          ..write('creationSequence: $creationSequence, ')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('date: $date, ')
          ..write('scheduledHour: $scheduledHour, ')
          ..write('priority: $priority, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    creationSequence,
    id,
    title,
    description,
    date,
    scheduledHour,
    priority,
    isCompleted,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Action &&
          other.creationSequence == this.creationSequence &&
          other.id == this.id &&
          other.title == this.title &&
          other.description == this.description &&
          other.date == this.date &&
          other.scheduledHour == this.scheduledHour &&
          other.priority == this.priority &&
          other.isCompleted == this.isCompleted &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ActionsCompanion extends UpdateCompanion<Action> {
  final Value<int> creationSequence;
  final Value<String> id;
  final Value<String> title;
  final Value<String?> description;
  final Value<String> date;
  final Value<int?> scheduledHour;
  final Value<int> priority;
  final Value<bool> isCompleted;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  const ActionsCompanion({
    this.creationSequence = const Value.absent(),
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.date = const Value.absent(),
    this.scheduledHour = const Value.absent(),
    this.priority = const Value.absent(),
    this.isCompleted = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ActionsCompanion.insert({
    this.creationSequence = const Value.absent(),
    required String id,
    required String title,
    this.description = const Value.absent(),
    required String date,
    this.scheduledHour = const Value.absent(),
    required int priority,
    required bool isCompleted,
    required int createdAt,
    required int updatedAt,
  }) : id = Value(id),
       title = Value(title),
       date = Value(date),
       priority = Value(priority),
       isCompleted = Value(isCompleted),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Action> custom({
    Expression<int>? creationSequence,
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? date,
    Expression<int>? scheduledHour,
    Expression<int>? priority,
    Expression<bool>? isCompleted,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (creationSequence != null) 'creation_sequence': creationSequence,
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (date != null) 'date': date,
      if (scheduledHour != null) 'scheduled_hour': scheduledHour,
      if (priority != null) 'priority': priority,
      if (isCompleted != null) 'is_completed': isCompleted,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ActionsCompanion copyWith({
    Value<int>? creationSequence,
    Value<String>? id,
    Value<String>? title,
    Value<String?>? description,
    Value<String>? date,
    Value<int?>? scheduledHour,
    Value<int>? priority,
    Value<bool>? isCompleted,
    Value<int>? createdAt,
    Value<int>? updatedAt,
  }) {
    return ActionsCompanion(
      creationSequence: creationSequence ?? this.creationSequence,
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      date: date ?? this.date,
      scheduledHour: scheduledHour ?? this.scheduledHour,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (scheduledHour.present) {
      map['scheduled_hour'] = Variable<int>(scheduledHour.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (isCompleted.present) {
      map['is_completed'] = Variable<bool>(isCompleted.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionsCompanion(')
          ..write('creationSequence: $creationSequence, ')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('date: $date, ')
          ..write('scheduledHour: $scheduledHour, ')
          ..write('priority: $priority, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class ActionPathItems extends Table
    with TableInfo<ActionPathItems, ActionPathItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ActionPathItems(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _actionIdMeta = const VerificationMeta(
    'actionId',
  );
  late final GeneratedColumn<String> actionId = GeneratedColumn<String>(
    'action_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL REFERENCES actions(id)ON UPDATE RESTRICT ON DELETE CASCADE',
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (typeof(position) = \'integer\' AND position >= 0)',
  );
  static const VerificationMeta _intentionIdMeta = const VerificationMeta(
    'intentionId',
  );
  late final GeneratedColumn<String> intentionId = GeneratedColumn<String>(
    'intention_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(intention_id) = \'text\')',
  );
  static const VerificationMeta _previousIntentionIdMeta =
      const VerificationMeta('previousIntentionId');
  late final GeneratedColumn<String> previousIntentionId =
      GeneratedColumn<String>(
        'previous_intention_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        $customConstraints: '',
      );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(role) = \'text\' AND role IN (\'root\', \'intermediate\', \'terminal\', \'single\'))',
  );
  static const VerificationMeta _orderDateMeta = const VerificationMeta(
    'orderDate',
  );
  late final GeneratedColumn<String> orderDate = GeneratedColumn<String>(
    'order_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _orderHourMeta = const VerificationMeta(
    'orderHour',
  );
  late final GeneratedColumn<int> orderHour = GeneratedColumn<int>(
    'order_hour',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _orderSequenceMeta = const VerificationMeta(
    'orderSequence',
  );
  late final GeneratedColumn<int> orderSequence = GeneratedColumn<int>(
    'order_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    actionId,
    position,
    intentionId,
    previousIntentionId,
    role,
    orderDate,
    orderHour,
    orderSequence,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'action_path_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActionPathItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('action_id')) {
      context.handle(
        _actionIdMeta,
        actionId.isAcceptableOrUnknown(data['action_id']!, _actionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actionIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('intention_id')) {
      context.handle(
        _intentionIdMeta,
        intentionId.isAcceptableOrUnknown(
          data['intention_id']!,
          _intentionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_intentionIdMeta);
    }
    if (data.containsKey('previous_intention_id')) {
      context.handle(
        _previousIntentionIdMeta,
        previousIntentionId.isAcceptableOrUnknown(
          data['previous_intention_id']!,
          _previousIntentionIdMeta,
        ),
      );
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('order_date')) {
      context.handle(
        _orderDateMeta,
        orderDate.isAcceptableOrUnknown(data['order_date']!, _orderDateMeta),
      );
    } else if (isInserting) {
      context.missing(_orderDateMeta);
    }
    if (data.containsKey('order_hour')) {
      context.handle(
        _orderHourMeta,
        orderHour.isAcceptableOrUnknown(data['order_hour']!, _orderHourMeta),
      );
    } else if (isInserting) {
      context.missing(_orderHourMeta);
    }
    if (data.containsKey('order_sequence')) {
      context.handle(
        _orderSequenceMeta,
        orderSequence.isAcceptableOrUnknown(
          data['order_sequence']!,
          _orderSequenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_orderSequenceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {actionId, position};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {actionId, intentionId},
  ];
  @override
  ActionPathItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionPathItem(
      actionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      intentionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intention_id'],
      )!,
      previousIntentionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}previous_intention_id'],
      ),
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      orderDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_date'],
      )!,
      orderHour: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_hour'],
      )!,
      orderSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_sequence'],
      )!,
    );
  }

  @override
  ActionPathItems createAlias(String alias) {
    return ActionPathItems(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(action_id, position)',
    'UNIQUE(action_id, intention_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ActionPathItem extends DataClass implements Insertable<ActionPathItem> {
  final String actionId;
  final int position;
  final String intentionId;
  final String? previousIntentionId;
  final String role;
  final String orderDate;

  /// -1 — «Весь день».
  final int orderHour;
  final int orderSequence;
  const ActionPathItem({
    required this.actionId,
    required this.position,
    required this.intentionId,
    this.previousIntentionId,
    required this.role,
    required this.orderDate,
    required this.orderHour,
    required this.orderSequence,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['action_id'] = Variable<String>(actionId);
    map['position'] = Variable<int>(position);
    map['intention_id'] = Variable<String>(intentionId);
    if (!nullToAbsent || previousIntentionId != null) {
      map['previous_intention_id'] = Variable<String>(previousIntentionId);
    }
    map['role'] = Variable<String>(role);
    map['order_date'] = Variable<String>(orderDate);
    map['order_hour'] = Variable<int>(orderHour);
    map['order_sequence'] = Variable<int>(orderSequence);
    return map;
  }

  ActionPathItemsCompanion toCompanion(bool nullToAbsent) {
    return ActionPathItemsCompanion(
      actionId: Value(actionId),
      position: Value(position),
      intentionId: Value(intentionId),
      previousIntentionId: previousIntentionId == null && nullToAbsent
          ? const Value.absent()
          : Value(previousIntentionId),
      role: Value(role),
      orderDate: Value(orderDate),
      orderHour: Value(orderHour),
      orderSequence: Value(orderSequence),
    );
  }

  factory ActionPathItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionPathItem(
      actionId: serializer.fromJson<String>(json['action_id']),
      position: serializer.fromJson<int>(json['position']),
      intentionId: serializer.fromJson<String>(json['intention_id']),
      previousIntentionId: serializer.fromJson<String?>(
        json['previous_intention_id'],
      ),
      role: serializer.fromJson<String>(json['role']),
      orderDate: serializer.fromJson<String>(json['order_date']),
      orderHour: serializer.fromJson<int>(json['order_hour']),
      orderSequence: serializer.fromJson<int>(json['order_sequence']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'action_id': serializer.toJson<String>(actionId),
      'position': serializer.toJson<int>(position),
      'intention_id': serializer.toJson<String>(intentionId),
      'previous_intention_id': serializer.toJson<String?>(previousIntentionId),
      'role': serializer.toJson<String>(role),
      'order_date': serializer.toJson<String>(orderDate),
      'order_hour': serializer.toJson<int>(orderHour),
      'order_sequence': serializer.toJson<int>(orderSequence),
    };
  }

  ActionPathItem copyWith({
    String? actionId,
    int? position,
    String? intentionId,
    Value<String?> previousIntentionId = const Value.absent(),
    String? role,
    String? orderDate,
    int? orderHour,
    int? orderSequence,
  }) => ActionPathItem(
    actionId: actionId ?? this.actionId,
    position: position ?? this.position,
    intentionId: intentionId ?? this.intentionId,
    previousIntentionId: previousIntentionId.present
        ? previousIntentionId.value
        : this.previousIntentionId,
    role: role ?? this.role,
    orderDate: orderDate ?? this.orderDate,
    orderHour: orderHour ?? this.orderHour,
    orderSequence: orderSequence ?? this.orderSequence,
  );
  ActionPathItem copyWithCompanion(ActionPathItemsCompanion data) {
    return ActionPathItem(
      actionId: data.actionId.present ? data.actionId.value : this.actionId,
      position: data.position.present ? data.position.value : this.position,
      intentionId: data.intentionId.present
          ? data.intentionId.value
          : this.intentionId,
      previousIntentionId: data.previousIntentionId.present
          ? data.previousIntentionId.value
          : this.previousIntentionId,
      role: data.role.present ? data.role.value : this.role,
      orderDate: data.orderDate.present ? data.orderDate.value : this.orderDate,
      orderHour: data.orderHour.present ? data.orderHour.value : this.orderHour,
      orderSequence: data.orderSequence.present
          ? data.orderSequence.value
          : this.orderSequence,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionPathItem(')
          ..write('actionId: $actionId, ')
          ..write('position: $position, ')
          ..write('intentionId: $intentionId, ')
          ..write('previousIntentionId: $previousIntentionId, ')
          ..write('role: $role, ')
          ..write('orderDate: $orderDate, ')
          ..write('orderHour: $orderHour, ')
          ..write('orderSequence: $orderSequence')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    actionId,
    position,
    intentionId,
    previousIntentionId,
    role,
    orderDate,
    orderHour,
    orderSequence,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionPathItem &&
          other.actionId == this.actionId &&
          other.position == this.position &&
          other.intentionId == this.intentionId &&
          other.previousIntentionId == this.previousIntentionId &&
          other.role == this.role &&
          other.orderDate == this.orderDate &&
          other.orderHour == this.orderHour &&
          other.orderSequence == this.orderSequence);
}

class ActionPathItemsCompanion extends UpdateCompanion<ActionPathItem> {
  final Value<String> actionId;
  final Value<int> position;
  final Value<String> intentionId;
  final Value<String?> previousIntentionId;
  final Value<String> role;
  final Value<String> orderDate;
  final Value<int> orderHour;
  final Value<int> orderSequence;
  final Value<int> rowid;
  const ActionPathItemsCompanion({
    this.actionId = const Value.absent(),
    this.position = const Value.absent(),
    this.intentionId = const Value.absent(),
    this.previousIntentionId = const Value.absent(),
    this.role = const Value.absent(),
    this.orderDate = const Value.absent(),
    this.orderHour = const Value.absent(),
    this.orderSequence = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionPathItemsCompanion.insert({
    required String actionId,
    required int position,
    required String intentionId,
    this.previousIntentionId = const Value.absent(),
    required String role,
    required String orderDate,
    required int orderHour,
    required int orderSequence,
    this.rowid = const Value.absent(),
  }) : actionId = Value(actionId),
       position = Value(position),
       intentionId = Value(intentionId),
       role = Value(role),
       orderDate = Value(orderDate),
       orderHour = Value(orderHour),
       orderSequence = Value(orderSequence);
  static Insertable<ActionPathItem> custom({
    Expression<String>? actionId,
    Expression<int>? position,
    Expression<String>? intentionId,
    Expression<String>? previousIntentionId,
    Expression<String>? role,
    Expression<String>? orderDate,
    Expression<int>? orderHour,
    Expression<int>? orderSequence,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (actionId != null) 'action_id': actionId,
      if (position != null) 'position': position,
      if (intentionId != null) 'intention_id': intentionId,
      if (previousIntentionId != null)
        'previous_intention_id': previousIntentionId,
      if (role != null) 'role': role,
      if (orderDate != null) 'order_date': orderDate,
      if (orderHour != null) 'order_hour': orderHour,
      if (orderSequence != null) 'order_sequence': orderSequence,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionPathItemsCompanion copyWith({
    Value<String>? actionId,
    Value<int>? position,
    Value<String>? intentionId,
    Value<String?>? previousIntentionId,
    Value<String>? role,
    Value<String>? orderDate,
    Value<int>? orderHour,
    Value<int>? orderSequence,
    Value<int>? rowid,
  }) {
    return ActionPathItemsCompanion(
      actionId: actionId ?? this.actionId,
      position: position ?? this.position,
      intentionId: intentionId ?? this.intentionId,
      previousIntentionId: previousIntentionId ?? this.previousIntentionId,
      role: role ?? this.role,
      orderDate: orderDate ?? this.orderDate,
      orderHour: orderHour ?? this.orderHour,
      orderSequence: orderSequence ?? this.orderSequence,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (actionId.present) {
      map['action_id'] = Variable<String>(actionId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (intentionId.present) {
      map['intention_id'] = Variable<String>(intentionId.value);
    }
    if (previousIntentionId.present) {
      map['previous_intention_id'] = Variable<String>(
        previousIntentionId.value,
      );
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (orderDate.present) {
      map['order_date'] = Variable<String>(orderDate.value);
    }
    if (orderHour.present) {
      map['order_hour'] = Variable<int>(orderHour.value);
    }
    if (orderSequence.present) {
      map['order_sequence'] = Variable<int>(orderSequence.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionPathItemsCompanion(')
          ..write('actionId: $actionId, ')
          ..write('position: $position, ')
          ..write('intentionId: $intentionId, ')
          ..write('previousIntentionId: $previousIntentionId, ')
          ..write('role: $role, ')
          ..write('orderDate: $orderDate, ')
          ..write('orderHour: $orderHour, ')
          ..write('orderSequence: $orderSequence, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class DeletedIntentions extends Table
    with TableInfo<DeletedIntentions, DeletedIntention> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DeletedIntentions(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _intentionIdMeta = const VerificationMeta(
    'intentionId',
  );
  late final GeneratedColumn<String> intentionId = GeneratedColumn<String>(
    'intention_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL PRIMARY KEY CHECK (typeof(intention_id) = \'text\')',
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(title) = \'text\' AND title <> \'\' AND instr(CAST(title AS BLOB), X\'00\') = 0)',
  );
  @override
  List<GeneratedColumn> get $columns => [intentionId, title];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'deleted_intentions';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeletedIntention> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('intention_id')) {
      context.handle(
        _intentionIdMeta,
        intentionId.isAcceptableOrUnknown(
          data['intention_id']!,
          _intentionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_intentionIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {intentionId};
  @override
  DeletedIntention map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeletedIntention(
      intentionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intention_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
    );
  }

  @override
  DeletedIntentions createAlias(String alias) {
    return DeletedIntentions(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class DeletedIntention extends DataClass
    implements Insertable<DeletedIntention> {
  final String intentionId;
  final String title;
  const DeletedIntention({required this.intentionId, required this.title});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['intention_id'] = Variable<String>(intentionId);
    map['title'] = Variable<String>(title);
    return map;
  }

  DeletedIntentionsCompanion toCompanion(bool nullToAbsent) {
    return DeletedIntentionsCompanion(
      intentionId: Value(intentionId),
      title: Value(title),
    );
  }

  factory DeletedIntention.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeletedIntention(
      intentionId: serializer.fromJson<String>(json['intention_id']),
      title: serializer.fromJson<String>(json['title']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'intention_id': serializer.toJson<String>(intentionId),
      'title': serializer.toJson<String>(title),
    };
  }

  DeletedIntention copyWith({String? intentionId, String? title}) =>
      DeletedIntention(
        intentionId: intentionId ?? this.intentionId,
        title: title ?? this.title,
      );
  DeletedIntention copyWithCompanion(DeletedIntentionsCompanion data) {
    return DeletedIntention(
      intentionId: data.intentionId.present
          ? data.intentionId.value
          : this.intentionId,
      title: data.title.present ? data.title.value : this.title,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeletedIntention(')
          ..write('intentionId: $intentionId, ')
          ..write('title: $title')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(intentionId, title);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeletedIntention &&
          other.intentionId == this.intentionId &&
          other.title == this.title);
}

class DeletedIntentionsCompanion extends UpdateCompanion<DeletedIntention> {
  final Value<String> intentionId;
  final Value<String> title;
  final Value<int> rowid;
  const DeletedIntentionsCompanion({
    this.intentionId = const Value.absent(),
    this.title = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeletedIntentionsCompanion.insert({
    required String intentionId,
    required String title,
    this.rowid = const Value.absent(),
  }) : intentionId = Value(intentionId),
       title = Value(title);
  static Insertable<DeletedIntention> custom({
    Expression<String>? intentionId,
    Expression<String>? title,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (intentionId != null) 'intention_id': intentionId,
      if (title != null) 'title': title,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeletedIntentionsCompanion copyWith({
    Value<String>? intentionId,
    Value<String>? title,
    Value<int>? rowid,
  }) {
    return DeletedIntentionsCompanion(
      intentionId: intentionId ?? this.intentionId,
      title: title ?? this.title,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (intentionId.present) {
      map['intention_id'] = Variable<String>(intentionId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeletedIntentionsCompanion(')
          ..write('intentionId: $intentionId, ')
          ..write('title: $title, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class DeletedRelationPairs extends Table
    with TableInfo<DeletedRelationPairs, DeletedRelationPair> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DeletedRelationPairs(this.attachedDatabase, [this._alias]);
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
        $customConstraints:
            'NOT NULL CHECK (typeof(source_intention_id) = \'text\')',
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
        $customConstraints:
            'NOT NULL CHECK (typeof(related_intention_id) = \'text\')',
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
  @override
  List<GeneratedColumn> get $columns => [
    sourceIntentionId,
    relatedIntentionId,
    type,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'deleted_relation_pairs';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeletedRelationPair> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    sourceIntentionId,
    relatedIntentionId,
  };
  @override
  DeletedRelationPair map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeletedRelationPair(
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
    );
  }

  @override
  DeletedRelationPairs createAlias(String alias) {
    return DeletedRelationPairs(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(source_intention_id, related_intention_id)',
    'CHECK(source_intention_id <> related_intention_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class DeletedRelationPair extends DataClass
    implements Insertable<DeletedRelationPair> {
  final String sourceIntentionId;
  final String relatedIntentionId;
  final String type;
  const DeletedRelationPair({
    required this.sourceIntentionId,
    required this.relatedIntentionId,
    required this.type,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_intention_id'] = Variable<String>(sourceIntentionId);
    map['related_intention_id'] = Variable<String>(relatedIntentionId);
    map['type'] = Variable<String>(type);
    return map;
  }

  DeletedRelationPairsCompanion toCompanion(bool nullToAbsent) {
    return DeletedRelationPairsCompanion(
      sourceIntentionId: Value(sourceIntentionId),
      relatedIntentionId: Value(relatedIntentionId),
      type: Value(type),
    );
  }

  factory DeletedRelationPair.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeletedRelationPair(
      sourceIntentionId: serializer.fromJson<String>(
        json['source_intention_id'],
      ),
      relatedIntentionId: serializer.fromJson<String>(
        json['related_intention_id'],
      ),
      type: serializer.fromJson<String>(json['type']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source_intention_id': serializer.toJson<String>(sourceIntentionId),
      'related_intention_id': serializer.toJson<String>(relatedIntentionId),
      'type': serializer.toJson<String>(type),
    };
  }

  DeletedRelationPair copyWith({
    String? sourceIntentionId,
    String? relatedIntentionId,
    String? type,
  }) => DeletedRelationPair(
    sourceIntentionId: sourceIntentionId ?? this.sourceIntentionId,
    relatedIntentionId: relatedIntentionId ?? this.relatedIntentionId,
    type: type ?? this.type,
  );
  DeletedRelationPair copyWithCompanion(DeletedRelationPairsCompanion data) {
    return DeletedRelationPair(
      sourceIntentionId: data.sourceIntentionId.present
          ? data.sourceIntentionId.value
          : this.sourceIntentionId,
      relatedIntentionId: data.relatedIntentionId.present
          ? data.relatedIntentionId.value
          : this.relatedIntentionId,
      type: data.type.present ? data.type.value : this.type,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeletedRelationPair(')
          ..write('sourceIntentionId: $sourceIntentionId, ')
          ..write('relatedIntentionId: $relatedIntentionId, ')
          ..write('type: $type')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceIntentionId, relatedIntentionId, type);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeletedRelationPair &&
          other.sourceIntentionId == this.sourceIntentionId &&
          other.relatedIntentionId == this.relatedIntentionId &&
          other.type == this.type);
}

class DeletedRelationPairsCompanion
    extends UpdateCompanion<DeletedRelationPair> {
  final Value<String> sourceIntentionId;
  final Value<String> relatedIntentionId;
  final Value<String> type;
  final Value<int> rowid;
  const DeletedRelationPairsCompanion({
    this.sourceIntentionId = const Value.absent(),
    this.relatedIntentionId = const Value.absent(),
    this.type = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeletedRelationPairsCompanion.insert({
    required String sourceIntentionId,
    required String relatedIntentionId,
    required String type,
    this.rowid = const Value.absent(),
  }) : sourceIntentionId = Value(sourceIntentionId),
       relatedIntentionId = Value(relatedIntentionId),
       type = Value(type);
  static Insertable<DeletedRelationPair> custom({
    Expression<String>? sourceIntentionId,
    Expression<String>? relatedIntentionId,
    Expression<String>? type,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceIntentionId != null) 'source_intention_id': sourceIntentionId,
      if (relatedIntentionId != null)
        'related_intention_id': relatedIntentionId,
      if (type != null) 'type': type,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeletedRelationPairsCompanion copyWith({
    Value<String>? sourceIntentionId,
    Value<String>? relatedIntentionId,
    Value<String>? type,
    Value<int>? rowid,
  }) {
    return DeletedRelationPairsCompanion(
      sourceIntentionId: sourceIntentionId ?? this.sourceIntentionId,
      relatedIntentionId: relatedIntentionId ?? this.relatedIntentionId,
      type: type ?? this.type,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceIntentionId.present) {
      map['source_intention_id'] = Variable<String>(sourceIntentionId.value);
    }
    if (relatedIntentionId.present) {
      map['related_intention_id'] = Variable<String>(relatedIntentionId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeletedRelationPairsCompanion(')
          ..write('sourceIntentionId: $sourceIntentionId, ')
          ..write('relatedIntentionId: $relatedIntentionId, ')
          ..write('type: $type, ')
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
  late final GraphLogControl graphLogControl = GraphLogControl(this);
  late final GraphLogTagMarks graphLogTagMarks = GraphLogTagMarks(this);
  late final GraphLogIntentionMarks graphLogIntentionMarks =
      GraphLogIntentionMarks(this);
  late final GraphLogTagAssignmentMarks graphLogTagAssignmentMarks =
      GraphLogTagAssignmentMarks(this);
  late final GraphLogLongTermRelationMarks graphLogLongTermRelationMarks =
      GraphLogLongTermRelationMarks(this);
  late final GraphLogActionMarks graphLogActionMarks = GraphLogActionMarks(
    this,
  );
  late final GraphLogDeletedIntentionMarks graphLogDeletedIntentionMarks =
      GraphLogDeletedIntentionMarks(this);
  late final GraphLogDeletedRelationPairMarks graphLogDeletedRelationPairMarks =
      GraphLogDeletedRelationPairMarks(this);
  late final GraphSnapshots graphSnapshots = GraphSnapshots(this);
  late final GraphLogPackages graphLogPackages = GraphLogPackages(this);
  late final GraphBackups graphBackups = GraphBackups(this);
  late final Tags tags = Tags(this);
  late final Trigger graphLogMarkTagInsert = Trigger(
    'CREATE TRIGGER graph_log_mark_tag_insert AFTER INSERT ON tags WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_tag_marks (tag_id, first_operation) VALUES (new.id, \'insert\');END',
    'graph_log_mark_tag_insert',
  );
  late final Trigger graphLogMarkTagUpdate = Trigger(
    'CREATE TRIGGER graph_log_mark_tag_update AFTER UPDATE ON tags WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_tag_marks (tag_id, first_operation) VALUES (new.id, \'update\');END',
    'graph_log_mark_tag_update',
  );
  late final Trigger graphLogMarkTagDelete = Trigger(
    'CREATE TRIGGER graph_log_mark_tag_delete AFTER DELETE ON tags WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_tag_marks (tag_id, first_operation) VALUES (old.id, \'delete\');END',
    'graph_log_mark_tag_delete',
  );
  late final Intentions intentions = Intentions(this);
  late final Trigger graphLogMarkIntentionInsert = Trigger(
    'CREATE TRIGGER graph_log_mark_intention_insert AFTER INSERT ON intentions WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_intention_marks (intention_id, first_operation) VALUES (new.id, \'insert\');END',
    'graph_log_mark_intention_insert',
  );
  late final Trigger graphLogMarkIntentionUpdate = Trigger(
    'CREATE TRIGGER graph_log_mark_intention_update AFTER UPDATE ON intentions WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_intention_marks (intention_id, first_operation) VALUES (new.id, \'update\');END',
    'graph_log_mark_intention_update',
  );
  late final Trigger graphLogMarkIntentionDelete = Trigger(
    'CREATE TRIGGER graph_log_mark_intention_delete AFTER DELETE ON intentions WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_intention_marks (intention_id, first_operation) VALUES (old.id, \'delete\');END',
    'graph_log_mark_intention_delete',
  );
  late final TagAssignments tagAssignments = TagAssignments(this);
  late final Trigger graphLogMarkTagAssignmentInsert = Trigger(
    'CREATE TRIGGER graph_log_mark_tag_assignment_insert AFTER INSERT ON tag_assignments WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_tag_assignment_marks (tag_id, intention_id, first_operation) VALUES (new.tag_id, new.intention_id, \'insert\');END',
    'graph_log_mark_tag_assignment_insert',
  );
  late final Trigger graphLogMarkTagAssignmentUpdate = Trigger(
    'CREATE TRIGGER graph_log_mark_tag_assignment_update AFTER UPDATE ON tag_assignments WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_tag_assignment_marks (tag_id, intention_id, first_operation) VALUES (new.tag_id, new.intention_id, \'update\');END',
    'graph_log_mark_tag_assignment_update',
  );
  late final Trigger graphLogMarkTagAssignmentDelete = Trigger(
    'CREATE TRIGGER graph_log_mark_tag_assignment_delete AFTER DELETE ON tag_assignments WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_tag_assignment_marks (tag_id, intention_id, first_operation) VALUES (old.tag_id, old.intention_id, \'delete\');END',
    'graph_log_mark_tag_assignment_delete',
  );
  late final LongTermRelations longTermRelations = LongTermRelations(this);
  late final Trigger graphLogMarkLongTermRelationInsert = Trigger(
    'CREATE TRIGGER graph_log_mark_long_term_relation_insert AFTER INSERT ON long_term_relations WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_long_term_relation_marks (long_term_relation_id, first_operation) VALUES (new.id, \'insert\');END',
    'graph_log_mark_long_term_relation_insert',
  );
  late final Trigger graphLogMarkLongTermRelationUpdate = Trigger(
    'CREATE TRIGGER graph_log_mark_long_term_relation_update AFTER UPDATE ON long_term_relations WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_long_term_relation_marks (long_term_relation_id, first_operation) VALUES (new.id, \'update\');END',
    'graph_log_mark_long_term_relation_update',
  );
  late final Trigger graphLogMarkLongTermRelationDelete = Trigger(
    'CREATE TRIGGER graph_log_mark_long_term_relation_delete AFTER DELETE ON long_term_relations WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_long_term_relation_marks (long_term_relation_id, first_operation) VALUES (old.id, \'delete\');END',
    'graph_log_mark_long_term_relation_delete',
  );
  late final Actions actions = Actions(this);
  late final Trigger graphLogMarkActionInsert = Trigger(
    'CREATE TRIGGER graph_log_mark_action_insert AFTER INSERT ON actions WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_action_marks (action_id, first_operation) VALUES (new.id, \'insert\');END',
    'graph_log_mark_action_insert',
  );
  late final Trigger graphLogMarkActionUpdate = Trigger(
    'CREATE TRIGGER graph_log_mark_action_update AFTER UPDATE ON actions WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_action_marks (action_id, first_operation) VALUES (new.id, \'update\');END',
    'graph_log_mark_action_update',
  );
  late final Trigger graphLogMarkActionDelete = Trigger(
    'CREATE TRIGGER graph_log_mark_action_delete AFTER DELETE ON actions WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_action_marks (action_id, first_operation) VALUES (old.id, \'delete\');END',
    'graph_log_mark_action_delete',
  );
  late final ActionPathItems actionPathItems = ActionPathItems(this);
  late final Trigger graphLogMarkActionPathItemInsert = Trigger(
    'CREATE TRIGGER graph_log_mark_action_path_item_insert AFTER INSERT ON action_path_items WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_action_marks (action_id, first_operation) VALUES (new.action_id, \'update\');END',
    'graph_log_mark_action_path_item_insert',
  );
  late final Trigger graphLogMarkActionPathItemDelete = Trigger(
    'CREATE TRIGGER graph_log_mark_action_path_item_delete AFTER DELETE ON action_path_items WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_action_marks (action_id, first_operation) VALUES (old.action_id, \'update\');END',
    'graph_log_mark_action_path_item_delete',
  );
  late final DeletedIntentions deletedIntentions = DeletedIntentions(this);
  late final Trigger graphLogMarkDeletedIntentionInsert = Trigger(
    'CREATE TRIGGER graph_log_mark_deleted_intention_insert AFTER INSERT ON deleted_intentions WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_deleted_intention_marks (intention_id, first_operation) VALUES (new.intention_id, \'insert\');END',
    'graph_log_mark_deleted_intention_insert',
  );
  late final Trigger graphLogMarkDeletedIntentionDelete = Trigger(
    'CREATE TRIGGER graph_log_mark_deleted_intention_delete AFTER DELETE ON deleted_intentions WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_deleted_intention_marks (intention_id, first_operation) VALUES (old.intention_id, \'delete\');END',
    'graph_log_mark_deleted_intention_delete',
  );
  late final DeletedRelationPairs deletedRelationPairs = DeletedRelationPairs(
    this,
  );
  late final Trigger graphLogMarkDeletedRelationPairInsert = Trigger(
    'CREATE TRIGGER graph_log_mark_deleted_relation_pair_insert AFTER INSERT ON deleted_relation_pairs WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_deleted_relation_pair_marks (source_intention_id, related_intention_id, first_operation) VALUES (new.source_intention_id, new.related_intention_id, \'insert\');END',
    'graph_log_mark_deleted_relation_pair_insert',
  );
  late final Trigger graphLogMarkDeletedRelationPairDelete = Trigger(
    'CREATE TRIGGER graph_log_mark_deleted_relation_pair_delete AFTER DELETE ON deleted_relation_pairs WHEN (SELECT capture FROM graph_log_control) = 1 BEGIN SELECT RAISE (ABORT, \'graph write outside the graph write path\') FROM graph_log_control WHERE writing = 0;INSERT OR IGNORE INTO graph_log_deleted_relation_pair_marks (source_intention_id, related_intention_id, first_operation) VALUES (old.source_intention_id, old.related_intention_id, \'delete\');END',
    'graph_log_mark_deleted_relation_pair_delete',
  );
  late final Index actionsDateCompletionScheduleOrder = Index(
    'actions_date_completion_schedule_order',
    'CREATE INDEX actions_date_completion_schedule_order ON actions (date, is_completed, COALESCE(scheduled_hour, -1), priority, creation_sequence)',
  );
  late final Trigger actionsImmutableIdentity = Trigger(
    'CREATE TRIGGER actions_immutable_identity AFTER UPDATE OF creation_sequence, id ON actions WHEN new.creation_sequence <> old.creation_sequence OR new.id <> old.id BEGIN SELECT RAISE (ABORT, \'action identity is immutable\');END',
    'actions_immutable_identity',
  );
  late final Index actionPathItemsIntentionAction = Index(
    'action_path_items_intention_action',
    'CREATE INDEX action_path_items_intention_action ON action_path_items (intention_id, action_id)',
  );
  late final Index actionPathItemsIntentionRoleOrder = Index(
    'action_path_items_intention_role_order',
    'CREATE INDEX action_path_items_intention_role_order ON action_path_items (intention_id, role, order_date DESC, order_hour DESC, order_sequence DESC)',
  );
  late final Index actionPathItemsLink = Index(
    'action_path_items_link',
    'CREATE INDEX action_path_items_link ON action_path_items (previous_intention_id, intention_id)',
  );
  late final Trigger actionPathItemsContinuePreviousPosition = Trigger(
    'CREATE TRIGGER action_path_items_continue_previous_position AFTER INSERT ON action_path_items WHEN new.previous_intention_id IS NOT (SELECT intention_id FROM action_path_items WHERE action_id = new.action_id AND position = new.position - 1) BEGIN SELECT RAISE (ABORT, \'action path item must continue the previous position\');END',
    'action_path_items_continue_previous_position',
  );
  late final Trigger actionPathItemsRoleFollowsPosition = Trigger(
    'CREATE TRIGGER action_path_items_role_follows_position AFTER INSERT ON action_path_items WHEN CASE WHEN new.position = 0 THEN new.role NOT IN (\'root\', \'single\') ELSE new.role NOT IN (\'intermediate\', \'terminal\') OR NOT EXISTS (SELECT 1 FROM action_path_items WHERE action_id = new.action_id AND position = new.position - 1 AND role IN (\'root\', \'intermediate\')) END BEGIN SELECT RAISE (ABORT, \'action path item role must follow its position\');END',
    'action_path_items_role_follows_position',
  );
  late final Trigger actionPathItemsOrderKeyMatchesAction = Trigger(
    'CREATE TRIGGER action_path_items_order_key_matches_action AFTER INSERT ON action_path_items WHEN NOT EXISTS (SELECT 1 FROM actions WHERE id = new.action_id AND date = new.order_date AND COALESCE(scheduled_hour, -1) = new.order_hour AND creation_sequence = new.order_sequence) BEGIN SELECT RAISE (ABORT, \'action path item order key must match its action\');END',
    'action_path_items_order_key_matches_action',
  );
  late final Trigger actionsCopyOrderKeyToPath = Trigger(
    'CREATE TRIGGER actions_copy_order_key_to_path AFTER UPDATE OF date, scheduled_hour ON actions WHEN new.date IS NOT old.date OR new.scheduled_hour IS NOT old.scheduled_hour BEGIN UPDATE action_path_items SET order_date = new.date, order_hour = COALESCE(new.scheduled_hour, -1) WHERE action_id = new.id;END',
    'actions_copy_order_key_to_path',
  );
  late final Trigger actionPathItemsKnownIntention = Trigger(
    'CREATE TRIGGER action_path_items_known_intention AFTER INSERT ON action_path_items WHEN NOT EXISTS (SELECT 1 FROM intentions WHERE id = new.intention_id) AND NOT EXISTS (SELECT 1 FROM deleted_intentions WHERE intention_id = new.intention_id) BEGIN SELECT RAISE (ABORT, \'action path item requires a known intention\');END',
    'action_path_items_known_intention',
  );
  late final Trigger actionPathItemsImmutable = Trigger(
    'CREATE TRIGGER action_path_items_immutable BEFORE UPDATE ON action_path_items WHEN new.action_id IS NOT old.action_id OR new.position IS NOT old.position OR new.intention_id IS NOT old.intention_id OR new.previous_intention_id IS NOT old.previous_intention_id OR new.role IS NOT old.role OR new.order_sequence IS NOT old.order_sequence BEGIN SELECT RAISE (ABORT, \'action path items are immutable\');END',
    'action_path_items_immutable',
  );
  late final Trigger deletedIntentionsRejectExisting = Trigger(
    'CREATE TRIGGER deleted_intentions_reject_existing BEFORE INSERT ON deleted_intentions WHEN EXISTS (SELECT 1 FROM intentions WHERE id = new.intention_id) BEGIN SELECT RAISE (ABORT, \'tombstone of an existing intention\');END',
    'deleted_intentions_reject_existing',
  );
  late final Trigger intentionsRejectTombstoned = Trigger(
    'CREATE TRIGGER intentions_reject_tombstoned AFTER INSERT ON intentions WHEN EXISTS (SELECT 1 FROM deleted_intentions WHERE intention_id = new.id) BEGIN SELECT RAISE (ABORT, \'tombstone of an existing intention\');END',
    'intentions_reject_tombstoned',
  );
  late final Trigger deletedRelationPairsRejectExisting = Trigger(
    'CREATE TRIGGER deleted_relation_pairs_reject_existing BEFORE INSERT ON deleted_relation_pairs WHEN EXISTS (SELECT 1 FROM long_term_relations WHERE source_intention_id = new.source_intention_id AND related_intention_id = new.related_intention_id) BEGIN SELECT RAISE (ABORT, \'tombstone of an existing relation pair\');END',
    'deleted_relation_pairs_reject_existing',
  );
  late final Trigger deletedIntentionsImmutable = Trigger(
    'CREATE TRIGGER deleted_intentions_immutable BEFORE UPDATE ON deleted_intentions BEGIN SELECT RAISE (ABORT, \'tombstones are immutable\');END',
    'deleted_intentions_immutable',
  );
  late final Trigger deletedRelationPairsImmutable = Trigger(
    'CREATE TRIGGER deleted_relation_pairs_immutable BEFORE UPDATE ON deleted_relation_pairs BEGIN SELECT RAISE (ABORT, \'tombstones are immutable\');END',
    'deleted_relation_pairs_immutable',
  );
  late final Trigger intentionsTombstoneAfterDelete = Trigger(
    'CREATE TRIGGER intentions_tombstone_after_delete AFTER DELETE ON intentions WHEN EXISTS (SELECT 1 FROM action_path_items WHERE intention_id = old.id) BEGIN INSERT INTO deleted_intentions (intention_id, title) VALUES (old.id, old.title);END',
    'intentions_tombstone_after_delete',
  );
  late final Trigger longTermRelationsTombstoneAfterDelete = Trigger(
    'CREATE TRIGGER long_term_relations_tombstone_after_delete AFTER DELETE ON long_term_relations WHEN EXISTS (SELECT 1 FROM action_path_items WHERE previous_intention_id = old.source_intention_id AND intention_id = old.related_intention_id) BEGIN INSERT INTO deleted_relation_pairs (source_intention_id, related_intention_id, type) VALUES (old.source_intention_id, old.related_intention_id, old.type);END',
    'long_term_relations_tombstone_after_delete',
  );
  late final Trigger longTermRelationsUntombstoneAfterInsert = Trigger(
    'CREATE TRIGGER long_term_relations_untombstone_after_insert AFTER INSERT ON long_term_relations BEGIN DELETE FROM deleted_relation_pairs WHERE source_intention_id = new.source_intention_id AND related_intention_id = new.related_intention_id;END',
    'long_term_relations_untombstone_after_insert',
  );
  late final Trigger actionPathItemsReleaseTombstonesAfterDelete = Trigger(
    'CREATE TRIGGER action_path_items_release_tombstones_after_delete AFTER DELETE ON action_path_items BEGIN DELETE FROM deleted_intentions WHERE intention_id = old.intention_id AND NOT EXISTS (SELECT 1 FROM action_path_items WHERE intention_id = old.intention_id);DELETE FROM deleted_relation_pairs WHERE source_intention_id = old.previous_intention_id AND related_intention_id = old.intention_id AND NOT EXISTS (SELECT 1 FROM action_path_items WHERE previous_intention_id = old.previous_intention_id AND intention_id = old.intention_id);END',
    'action_path_items_release_tombstones_after_delete',
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
    'CREATE TRIGGER long_term_relations_immutable_identity AFTER UPDATE OF creation_sequence, id, source_intention_id, related_intention_id ON long_term_relations WHEN new.creation_sequence <> old.creation_sequence OR new.id <> old.id OR new.source_intention_id <> old.source_intention_id OR new.related_intention_id <> old.related_intention_id BEGIN SELECT RAISE (ABORT, \'long-term relation identity is immutable\');END',
    'long_term_relations_immutable_identity',
  );
  late final Trigger longTermRelationsActiveParticipantsAfterInsert = Trigger(
    'CREATE TRIGGER long_term_relations_active_participants_after_insert AFTER INSERT ON long_term_relations WHEN new.is_archived = 0 AND(NOT EXISTS (SELECT 1 FROM intentions WHERE id = new.source_intention_id AND is_archived = 0) OR NOT EXISTS (SELECT 1 FROM intentions WHERE id = new.related_intention_id AND is_archived = 0))BEGIN SELECT RAISE (ABORT, \'active relation requires active intentions\');END',
    'long_term_relations_active_participants_after_insert',
  );
  late final Trigger longTermRelationsActiveParticipantsAfterUpdate = Trigger(
    'CREATE TRIGGER long_term_relations_active_participants_after_update AFTER UPDATE OF is_archived ON long_term_relations WHEN new.is_archived = 0 AND(NOT EXISTS (SELECT 1 FROM intentions WHERE id = new.source_intention_id AND is_archived = 0) OR NOT EXISTS (SELECT 1 FROM intentions WHERE id = new.related_intention_id AND is_archived = 0))BEGIN SELECT RAISE (ABORT, \'active relation requires active intentions\');END',
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
    'CREATE TRIGGER intentions_fts_after_update_search_content AFTER UPDATE OF title ON intentions BEGIN INSERT INTO intention_titles_fts (intention_titles_fts, "rowid", title_search_key) VALUES (\'delete\', old."rowid", old.title_search_key);INSERT INTO intention_titles_fts ("rowid", title_search_key) VALUES (new."rowid", new.title_search_key);END',
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
  late final Index intentionsActiveTitleSearchKeyAscIdAsc = Index(
    'intentions_active_title_search_key_asc_id_asc',
    'CREATE INDEX intentions_active_title_search_key_asc_id_asc ON intentions (title_search_key ASC, id ASC) WHERE is_archived = 0',
  );
  late final Index intentionsActiveTitleSearchKeyDescIdAsc = Index(
    'intentions_active_title_search_key_desc_id_asc',
    'CREATE INDEX intentions_active_title_search_key_desc_id_asc ON intentions (title_search_key DESC, id ASC) WHERE is_archived = 0',
  );
  late final Index intentionsArchivedTitleSearchKeyAscIdAsc = Index(
    'intentions_archived_title_search_key_asc_id_asc',
    'CREATE INDEX intentions_archived_title_search_key_asc_id_asc ON intentions (title_search_key ASC, id ASC) WHERE is_archived = 1',
  );
  late final Index intentionsArchivedTitleSearchKeyDescIdAsc = Index(
    'intentions_archived_title_search_key_desc_id_asc',
    'CREATE INDEX intentions_archived_title_search_key_desc_id_asc ON intentions (title_search_key DESC, id ASC) WHERE is_archived = 1',
  );
  late final Index intentionsAllTitleSearchKeyAscIdAsc = Index(
    'intentions_all_title_search_key_asc_id_asc',
    'CREATE INDEX intentions_all_title_search_key_asc_id_asc ON intentions (title_search_key ASC, id ASC)',
  );
  late final Index intentionsAllTitleSearchKeyDescIdAsc = Index(
    'intentions_all_title_search_key_desc_id_asc',
    'CREATE INDEX intentions_all_title_search_key_desc_id_asc ON intentions (title_search_key DESC, id ASC)',
  );
  late final Trigger tagsImmutableIdentity = Trigger(
    'CREATE TRIGGER tags_immutable_identity AFTER UPDATE OF creation_sequence, id ON tags WHEN new.creation_sequence <> old.creation_sequence OR new.id <> old.id BEGIN SELECT RAISE (ABORT, \'tag identity is immutable\');END',
    'tags_immutable_identity',
  );
  late final Index tagAssignmentsIntention = Index(
    'tag_assignments_intention',
    'CREATE INDEX tag_assignments_intention ON tag_assignments (intention_id, tag_id)',
  );
  late final Trigger tagAssignmentsImmutableIdentity = Trigger(
    'CREATE TRIGGER tag_assignments_immutable_identity AFTER UPDATE OF creation_sequence, tag_id, intention_id ON tag_assignments WHEN new.creation_sequence <> old.creation_sequence OR new.tag_id <> old.tag_id OR new.intention_id <> old.intention_id BEGIN SELECT RAISE (ABORT, \'tag assignment identity is immutable\');END',
    'tag_assignments_immutable_identity',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    graphLogControl,
    OnCreateQuery(
      'INSERT INTO graph_log_control (id, capture, writing) VALUES (1, 1, 0)',
    ),
    graphLogTagMarks,
    graphLogIntentionMarks,
    graphLogTagAssignmentMarks,
    graphLogLongTermRelationMarks,
    graphLogActionMarks,
    graphLogDeletedIntentionMarks,
    graphLogDeletedRelationPairMarks,
    graphSnapshots,
    graphLogPackages,
    graphBackups,
    tags,
    graphLogMarkTagInsert,
    graphLogMarkTagUpdate,
    graphLogMarkTagDelete,
    intentions,
    graphLogMarkIntentionInsert,
    graphLogMarkIntentionUpdate,
    graphLogMarkIntentionDelete,
    tagAssignments,
    graphLogMarkTagAssignmentInsert,
    graphLogMarkTagAssignmentUpdate,
    graphLogMarkTagAssignmentDelete,
    longTermRelations,
    graphLogMarkLongTermRelationInsert,
    graphLogMarkLongTermRelationUpdate,
    graphLogMarkLongTermRelationDelete,
    actions,
    graphLogMarkActionInsert,
    graphLogMarkActionUpdate,
    graphLogMarkActionDelete,
    actionPathItems,
    graphLogMarkActionPathItemInsert,
    graphLogMarkActionPathItemDelete,
    deletedIntentions,
    graphLogMarkDeletedIntentionInsert,
    graphLogMarkDeletedIntentionDelete,
    deletedRelationPairs,
    graphLogMarkDeletedRelationPairInsert,
    graphLogMarkDeletedRelationPairDelete,
    actionsDateCompletionScheduleOrder,
    actionsImmutableIdentity,
    actionPathItemsIntentionAction,
    actionPathItemsIntentionRoleOrder,
    actionPathItemsLink,
    actionPathItemsContinuePreviousPosition,
    actionPathItemsRoleFollowsPosition,
    actionPathItemsOrderKeyMatchesAction,
    actionsCopyOrderKeyToPath,
    actionPathItemsKnownIntention,
    actionPathItemsImmutable,
    deletedIntentionsRejectExisting,
    intentionsRejectTombstoned,
    deletedRelationPairsRejectExisting,
    deletedIntentionsImmutable,
    deletedRelationPairsImmutable,
    intentionsTombstoneAfterDelete,
    longTermRelationsTombstoneAfterDelete,
    longTermRelationsUntombstoneAfterInsert,
    actionPathItemsReleaseTombstonesAfterDelete,
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
    intentionsActiveTitleSearchKeyAscIdAsc,
    intentionsActiveTitleSearchKeyDescIdAsc,
    intentionsArchivedTitleSearchKeyAscIdAsc,
    intentionsArchivedTitleSearchKeyDescIdAsc,
    intentionsAllTitleSearchKeyAscIdAsc,
    intentionsAllTitleSearchKeyDescIdAsc,
    tagsImmutableIdentity,
    tagAssignmentsIntention,
    tagAssignmentsImmutableIdentity,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tags',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [TableUpdate('graph_log_tag_marks', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tags',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [TableUpdate('graph_log_tag_marks', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tags',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('graph_log_tag_marks', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'intentions',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [
        TableUpdate('graph_log_intention_marks', kind: UpdateKind.insert),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'intentions',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [
        TableUpdate('graph_log_intention_marks', kind: UpdateKind.insert),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'intentions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('graph_log_intention_marks', kind: UpdateKind.insert),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tags',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tag_assignments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'intentions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tag_assignments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tag_assignments',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [
        TableUpdate('graph_log_tag_assignment_marks', kind: UpdateKind.insert),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tag_assignments',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [
        TableUpdate('graph_log_tag_assignment_marks', kind: UpdateKind.insert),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tag_assignments',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('graph_log_tag_assignment_marks', kind: UpdateKind.insert),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'long_term_relations',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [
        TableUpdate(
          'graph_log_long_term_relation_marks',
          kind: UpdateKind.insert,
        ),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'long_term_relations',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [
        TableUpdate(
          'graph_log_long_term_relation_marks',
          kind: UpdateKind.insert,
        ),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'long_term_relations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate(
          'graph_log_long_term_relation_marks',
          kind: UpdateKind.insert,
        ),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [TableUpdate('graph_log_action_marks', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [TableUpdate('graph_log_action_marks', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('graph_log_action_marks', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('action_path_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'action_path_items',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [TableUpdate('graph_log_action_marks', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'action_path_items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('graph_log_action_marks', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'deleted_intentions',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [
        TableUpdate(
          'graph_log_deleted_intention_marks',
          kind: UpdateKind.insert,
        ),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'deleted_intentions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate(
          'graph_log_deleted_intention_marks',
          kind: UpdateKind.insert,
        ),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'deleted_relation_pairs',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [
        TableUpdate(
          'graph_log_deleted_relation_pair_marks',
          kind: UpdateKind.insert,
        ),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'deleted_relation_pairs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate(
          'graph_log_deleted_relation_pair_marks',
          kind: UpdateKind.insert,
        ),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'action_path_items',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'action_path_items',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'action_path_items',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [TableUpdate('action_path_items', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'action_path_items',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'action_path_items',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'deleted_intentions',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'intentions',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'deleted_relation_pairs',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'deleted_intentions',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'deleted_relation_pairs',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'intentions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('deleted_intentions', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'long_term_relations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('deleted_relation_pairs', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'long_term_relations',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [TableUpdate('deleted_relation_pairs', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'action_path_items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('deleted_intentions', kind: UpdateKind.delete),
        TableUpdate('deleted_relation_pairs', kind: UpdateKind.delete),
      ],
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
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tags',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tag_assignments',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
  ]);
}

typedef $GraphLogControlCreateCompanionBuilder =
    GraphLogControlCompanion Function({
      Value<int> id,
      required bool capture,
      required bool writing,
    });
typedef $GraphLogControlUpdateCompanionBuilder =
    GraphLogControlCompanion Function({
      Value<int> id,
      Value<bool> capture,
      Value<bool> writing,
    });

class $GraphLogControlFilterComposer
    extends Composer<_$AppDatabase, GraphLogControl> {
  $GraphLogControlFilterComposer({
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

  ColumnFilters<bool> get capture => $composableBuilder(
    column: $table.capture,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get writing => $composableBuilder(
    column: $table.writing,
    builder: (column) => ColumnFilters(column),
  );
}

class $GraphLogControlOrderingComposer
    extends Composer<_$AppDatabase, GraphLogControl> {
  $GraphLogControlOrderingComposer({
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

  ColumnOrderings<bool> get capture => $composableBuilder(
    column: $table.capture,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get writing => $composableBuilder(
    column: $table.writing,
    builder: (column) => ColumnOrderings(column),
  );
}

class $GraphLogControlAnnotationComposer
    extends Composer<_$AppDatabase, GraphLogControl> {
  $GraphLogControlAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get capture =>
      $composableBuilder(column: $table.capture, builder: (column) => column);

  GeneratedColumn<bool> get writing =>
      $composableBuilder(column: $table.writing, builder: (column) => column);
}

class $GraphLogControlTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          GraphLogControl,
          GraphLogControlData,
          $GraphLogControlFilterComposer,
          $GraphLogControlOrderingComposer,
          $GraphLogControlAnnotationComposer,
          $GraphLogControlCreateCompanionBuilder,
          $GraphLogControlUpdateCompanionBuilder,
          (
            GraphLogControlData,
            BaseReferences<_$AppDatabase, GraphLogControl, GraphLogControlData>,
          ),
          GraphLogControlData,
          PrefetchHooks Function()
        > {
  $GraphLogControlTableManager(_$AppDatabase db, GraphLogControl table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $GraphLogControlFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $GraphLogControlOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $GraphLogControlAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> capture = const Value.absent(),
                Value<bool> writing = const Value.absent(),
              }) => GraphLogControlCompanion(
                id: id,
                capture: capture,
                writing: writing,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required bool capture,
                required bool writing,
              }) => GraphLogControlCompanion.insert(
                id: id,
                capture: capture,
                writing: writing,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $GraphLogControlProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      GraphLogControl,
      GraphLogControlData,
      $GraphLogControlFilterComposer,
      $GraphLogControlOrderingComposer,
      $GraphLogControlAnnotationComposer,
      $GraphLogControlCreateCompanionBuilder,
      $GraphLogControlUpdateCompanionBuilder,
      (
        GraphLogControlData,
        BaseReferences<_$AppDatabase, GraphLogControl, GraphLogControlData>,
      ),
      GraphLogControlData,
      PrefetchHooks Function()
    >;
typedef $GraphLogTagMarksCreateCompanionBuilder =
    GraphLogTagMarksCompanion Function({
      required String tagId,
      required String firstOperation,
      Value<int> rowid,
    });
typedef $GraphLogTagMarksUpdateCompanionBuilder =
    GraphLogTagMarksCompanion Function({
      Value<String> tagId,
      Value<String> firstOperation,
      Value<int> rowid,
    });

class $GraphLogTagMarksFilterComposer
    extends Composer<_$AppDatabase, GraphLogTagMarks> {
  $GraphLogTagMarksFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnFilters(column),
  );
}

class $GraphLogTagMarksOrderingComposer
    extends Composer<_$AppDatabase, GraphLogTagMarks> {
  $GraphLogTagMarksOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnOrderings(column),
  );
}

class $GraphLogTagMarksAnnotationComposer
    extends Composer<_$AppDatabase, GraphLogTagMarks> {
  $GraphLogTagMarksAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);

  GeneratedColumn<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => column,
  );
}

class $GraphLogTagMarksTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          GraphLogTagMarks,
          GraphLogTagMark,
          $GraphLogTagMarksFilterComposer,
          $GraphLogTagMarksOrderingComposer,
          $GraphLogTagMarksAnnotationComposer,
          $GraphLogTagMarksCreateCompanionBuilder,
          $GraphLogTagMarksUpdateCompanionBuilder,
          (
            GraphLogTagMark,
            BaseReferences<_$AppDatabase, GraphLogTagMarks, GraphLogTagMark>,
          ),
          GraphLogTagMark,
          PrefetchHooks Function()
        > {
  $GraphLogTagMarksTableManager(_$AppDatabase db, GraphLogTagMarks table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $GraphLogTagMarksFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $GraphLogTagMarksOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $GraphLogTagMarksAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tagId = const Value.absent(),
                Value<String> firstOperation = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GraphLogTagMarksCompanion(
                tagId: tagId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tagId,
                required String firstOperation,
                Value<int> rowid = const Value.absent(),
              }) => GraphLogTagMarksCompanion.insert(
                tagId: tagId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $GraphLogTagMarksProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      GraphLogTagMarks,
      GraphLogTagMark,
      $GraphLogTagMarksFilterComposer,
      $GraphLogTagMarksOrderingComposer,
      $GraphLogTagMarksAnnotationComposer,
      $GraphLogTagMarksCreateCompanionBuilder,
      $GraphLogTagMarksUpdateCompanionBuilder,
      (
        GraphLogTagMark,
        BaseReferences<_$AppDatabase, GraphLogTagMarks, GraphLogTagMark>,
      ),
      GraphLogTagMark,
      PrefetchHooks Function()
    >;
typedef $GraphLogIntentionMarksCreateCompanionBuilder =
    GraphLogIntentionMarksCompanion Function({
      required String intentionId,
      required String firstOperation,
      Value<int> rowid,
    });
typedef $GraphLogIntentionMarksUpdateCompanionBuilder =
    GraphLogIntentionMarksCompanion Function({
      Value<String> intentionId,
      Value<String> firstOperation,
      Value<int> rowid,
    });

class $GraphLogIntentionMarksFilterComposer
    extends Composer<_$AppDatabase, GraphLogIntentionMarks> {
  $GraphLogIntentionMarksFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnFilters(column),
  );
}

class $GraphLogIntentionMarksOrderingComposer
    extends Composer<_$AppDatabase, GraphLogIntentionMarks> {
  $GraphLogIntentionMarksOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnOrderings(column),
  );
}

class $GraphLogIntentionMarksAnnotationComposer
    extends Composer<_$AppDatabase, GraphLogIntentionMarks> {
  $GraphLogIntentionMarksAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => column,
  );
}

class $GraphLogIntentionMarksTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          GraphLogIntentionMarks,
          GraphLogIntentionMark,
          $GraphLogIntentionMarksFilterComposer,
          $GraphLogIntentionMarksOrderingComposer,
          $GraphLogIntentionMarksAnnotationComposer,
          $GraphLogIntentionMarksCreateCompanionBuilder,
          $GraphLogIntentionMarksUpdateCompanionBuilder,
          (
            GraphLogIntentionMark,
            BaseReferences<
              _$AppDatabase,
              GraphLogIntentionMarks,
              GraphLogIntentionMark
            >,
          ),
          GraphLogIntentionMark,
          PrefetchHooks Function()
        > {
  $GraphLogIntentionMarksTableManager(
    _$AppDatabase db,
    GraphLogIntentionMarks table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $GraphLogIntentionMarksFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $GraphLogIntentionMarksOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $GraphLogIntentionMarksAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> intentionId = const Value.absent(),
                Value<String> firstOperation = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GraphLogIntentionMarksCompanion(
                intentionId: intentionId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String intentionId,
                required String firstOperation,
                Value<int> rowid = const Value.absent(),
              }) => GraphLogIntentionMarksCompanion.insert(
                intentionId: intentionId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $GraphLogIntentionMarksProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      GraphLogIntentionMarks,
      GraphLogIntentionMark,
      $GraphLogIntentionMarksFilterComposer,
      $GraphLogIntentionMarksOrderingComposer,
      $GraphLogIntentionMarksAnnotationComposer,
      $GraphLogIntentionMarksCreateCompanionBuilder,
      $GraphLogIntentionMarksUpdateCompanionBuilder,
      (
        GraphLogIntentionMark,
        BaseReferences<
          _$AppDatabase,
          GraphLogIntentionMarks,
          GraphLogIntentionMark
        >,
      ),
      GraphLogIntentionMark,
      PrefetchHooks Function()
    >;
typedef $GraphLogTagAssignmentMarksCreateCompanionBuilder =
    GraphLogTagAssignmentMarksCompanion Function({
      required String tagId,
      required String intentionId,
      required String firstOperation,
      Value<int> rowid,
    });
typedef $GraphLogTagAssignmentMarksUpdateCompanionBuilder =
    GraphLogTagAssignmentMarksCompanion Function({
      Value<String> tagId,
      Value<String> intentionId,
      Value<String> firstOperation,
      Value<int> rowid,
    });

class $GraphLogTagAssignmentMarksFilterComposer
    extends Composer<_$AppDatabase, GraphLogTagAssignmentMarks> {
  $GraphLogTagAssignmentMarksFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnFilters(column),
  );
}

class $GraphLogTagAssignmentMarksOrderingComposer
    extends Composer<_$AppDatabase, GraphLogTagAssignmentMarks> {
  $GraphLogTagAssignmentMarksOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnOrderings(column),
  );
}

class $GraphLogTagAssignmentMarksAnnotationComposer
    extends Composer<_$AppDatabase, GraphLogTagAssignmentMarks> {
  $GraphLogTagAssignmentMarksAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);

  GeneratedColumn<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => column,
  );
}

class $GraphLogTagAssignmentMarksTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          GraphLogTagAssignmentMarks,
          GraphLogTagAssignmentMark,
          $GraphLogTagAssignmentMarksFilterComposer,
          $GraphLogTagAssignmentMarksOrderingComposer,
          $GraphLogTagAssignmentMarksAnnotationComposer,
          $GraphLogTagAssignmentMarksCreateCompanionBuilder,
          $GraphLogTagAssignmentMarksUpdateCompanionBuilder,
          (
            GraphLogTagAssignmentMark,
            BaseReferences<
              _$AppDatabase,
              GraphLogTagAssignmentMarks,
              GraphLogTagAssignmentMark
            >,
          ),
          GraphLogTagAssignmentMark,
          PrefetchHooks Function()
        > {
  $GraphLogTagAssignmentMarksTableManager(
    _$AppDatabase db,
    GraphLogTagAssignmentMarks table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $GraphLogTagAssignmentMarksFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $GraphLogTagAssignmentMarksOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $GraphLogTagAssignmentMarksAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> tagId = const Value.absent(),
                Value<String> intentionId = const Value.absent(),
                Value<String> firstOperation = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GraphLogTagAssignmentMarksCompanion(
                tagId: tagId,
                intentionId: intentionId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tagId,
                required String intentionId,
                required String firstOperation,
                Value<int> rowid = const Value.absent(),
              }) => GraphLogTagAssignmentMarksCompanion.insert(
                tagId: tagId,
                intentionId: intentionId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $GraphLogTagAssignmentMarksProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      GraphLogTagAssignmentMarks,
      GraphLogTagAssignmentMark,
      $GraphLogTagAssignmentMarksFilterComposer,
      $GraphLogTagAssignmentMarksOrderingComposer,
      $GraphLogTagAssignmentMarksAnnotationComposer,
      $GraphLogTagAssignmentMarksCreateCompanionBuilder,
      $GraphLogTagAssignmentMarksUpdateCompanionBuilder,
      (
        GraphLogTagAssignmentMark,
        BaseReferences<
          _$AppDatabase,
          GraphLogTagAssignmentMarks,
          GraphLogTagAssignmentMark
        >,
      ),
      GraphLogTagAssignmentMark,
      PrefetchHooks Function()
    >;
typedef $GraphLogLongTermRelationMarksCreateCompanionBuilder =
    GraphLogLongTermRelationMarksCompanion Function({
      required String longTermRelationId,
      required String firstOperation,
      Value<int> rowid,
    });
typedef $GraphLogLongTermRelationMarksUpdateCompanionBuilder =
    GraphLogLongTermRelationMarksCompanion Function({
      Value<String> longTermRelationId,
      Value<String> firstOperation,
      Value<int> rowid,
    });

class $GraphLogLongTermRelationMarksFilterComposer
    extends Composer<_$AppDatabase, GraphLogLongTermRelationMarks> {
  $GraphLogLongTermRelationMarksFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get longTermRelationId => $composableBuilder(
    column: $table.longTermRelationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnFilters(column),
  );
}

class $GraphLogLongTermRelationMarksOrderingComposer
    extends Composer<_$AppDatabase, GraphLogLongTermRelationMarks> {
  $GraphLogLongTermRelationMarksOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get longTermRelationId => $composableBuilder(
    column: $table.longTermRelationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnOrderings(column),
  );
}

class $GraphLogLongTermRelationMarksAnnotationComposer
    extends Composer<_$AppDatabase, GraphLogLongTermRelationMarks> {
  $GraphLogLongTermRelationMarksAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get longTermRelationId => $composableBuilder(
    column: $table.longTermRelationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => column,
  );
}

class $GraphLogLongTermRelationMarksTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          GraphLogLongTermRelationMarks,
          GraphLogLongTermRelationMark,
          $GraphLogLongTermRelationMarksFilterComposer,
          $GraphLogLongTermRelationMarksOrderingComposer,
          $GraphLogLongTermRelationMarksAnnotationComposer,
          $GraphLogLongTermRelationMarksCreateCompanionBuilder,
          $GraphLogLongTermRelationMarksUpdateCompanionBuilder,
          (
            GraphLogLongTermRelationMark,
            BaseReferences<
              _$AppDatabase,
              GraphLogLongTermRelationMarks,
              GraphLogLongTermRelationMark
            >,
          ),
          GraphLogLongTermRelationMark,
          PrefetchHooks Function()
        > {
  $GraphLogLongTermRelationMarksTableManager(
    _$AppDatabase db,
    GraphLogLongTermRelationMarks table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $GraphLogLongTermRelationMarksFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $GraphLogLongTermRelationMarksOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $GraphLogLongTermRelationMarksAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> longTermRelationId = const Value.absent(),
                Value<String> firstOperation = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GraphLogLongTermRelationMarksCompanion(
                longTermRelationId: longTermRelationId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String longTermRelationId,
                required String firstOperation,
                Value<int> rowid = const Value.absent(),
              }) => GraphLogLongTermRelationMarksCompanion.insert(
                longTermRelationId: longTermRelationId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $GraphLogLongTermRelationMarksProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      GraphLogLongTermRelationMarks,
      GraphLogLongTermRelationMark,
      $GraphLogLongTermRelationMarksFilterComposer,
      $GraphLogLongTermRelationMarksOrderingComposer,
      $GraphLogLongTermRelationMarksAnnotationComposer,
      $GraphLogLongTermRelationMarksCreateCompanionBuilder,
      $GraphLogLongTermRelationMarksUpdateCompanionBuilder,
      (
        GraphLogLongTermRelationMark,
        BaseReferences<
          _$AppDatabase,
          GraphLogLongTermRelationMarks,
          GraphLogLongTermRelationMark
        >,
      ),
      GraphLogLongTermRelationMark,
      PrefetchHooks Function()
    >;
typedef $GraphLogActionMarksCreateCompanionBuilder =
    GraphLogActionMarksCompanion Function({
      required String actionId,
      required String firstOperation,
      Value<int> rowid,
    });
typedef $GraphLogActionMarksUpdateCompanionBuilder =
    GraphLogActionMarksCompanion Function({
      Value<String> actionId,
      Value<String> firstOperation,
      Value<int> rowid,
    });

class $GraphLogActionMarksFilterComposer
    extends Composer<_$AppDatabase, GraphLogActionMarks> {
  $GraphLogActionMarksFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get actionId => $composableBuilder(
    column: $table.actionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnFilters(column),
  );
}

class $GraphLogActionMarksOrderingComposer
    extends Composer<_$AppDatabase, GraphLogActionMarks> {
  $GraphLogActionMarksOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get actionId => $composableBuilder(
    column: $table.actionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnOrderings(column),
  );
}

class $GraphLogActionMarksAnnotationComposer
    extends Composer<_$AppDatabase, GraphLogActionMarks> {
  $GraphLogActionMarksAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get actionId =>
      $composableBuilder(column: $table.actionId, builder: (column) => column);

  GeneratedColumn<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => column,
  );
}

class $GraphLogActionMarksTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          GraphLogActionMarks,
          GraphLogActionMark,
          $GraphLogActionMarksFilterComposer,
          $GraphLogActionMarksOrderingComposer,
          $GraphLogActionMarksAnnotationComposer,
          $GraphLogActionMarksCreateCompanionBuilder,
          $GraphLogActionMarksUpdateCompanionBuilder,
          (
            GraphLogActionMark,
            BaseReferences<
              _$AppDatabase,
              GraphLogActionMarks,
              GraphLogActionMark
            >,
          ),
          GraphLogActionMark,
          PrefetchHooks Function()
        > {
  $GraphLogActionMarksTableManager(_$AppDatabase db, GraphLogActionMarks table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $GraphLogActionMarksFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $GraphLogActionMarksOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $GraphLogActionMarksAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> actionId = const Value.absent(),
                Value<String> firstOperation = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GraphLogActionMarksCompanion(
                actionId: actionId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String actionId,
                required String firstOperation,
                Value<int> rowid = const Value.absent(),
              }) => GraphLogActionMarksCompanion.insert(
                actionId: actionId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $GraphLogActionMarksProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      GraphLogActionMarks,
      GraphLogActionMark,
      $GraphLogActionMarksFilterComposer,
      $GraphLogActionMarksOrderingComposer,
      $GraphLogActionMarksAnnotationComposer,
      $GraphLogActionMarksCreateCompanionBuilder,
      $GraphLogActionMarksUpdateCompanionBuilder,
      (
        GraphLogActionMark,
        BaseReferences<_$AppDatabase, GraphLogActionMarks, GraphLogActionMark>,
      ),
      GraphLogActionMark,
      PrefetchHooks Function()
    >;
typedef $GraphLogDeletedIntentionMarksCreateCompanionBuilder =
    GraphLogDeletedIntentionMarksCompanion Function({
      required String intentionId,
      required String firstOperation,
      Value<int> rowid,
    });
typedef $GraphLogDeletedIntentionMarksUpdateCompanionBuilder =
    GraphLogDeletedIntentionMarksCompanion Function({
      Value<String> intentionId,
      Value<String> firstOperation,
      Value<int> rowid,
    });

class $GraphLogDeletedIntentionMarksFilterComposer
    extends Composer<_$AppDatabase, GraphLogDeletedIntentionMarks> {
  $GraphLogDeletedIntentionMarksFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnFilters(column),
  );
}

class $GraphLogDeletedIntentionMarksOrderingComposer
    extends Composer<_$AppDatabase, GraphLogDeletedIntentionMarks> {
  $GraphLogDeletedIntentionMarksOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnOrderings(column),
  );
}

class $GraphLogDeletedIntentionMarksAnnotationComposer
    extends Composer<_$AppDatabase, GraphLogDeletedIntentionMarks> {
  $GraphLogDeletedIntentionMarksAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => column,
  );
}

class $GraphLogDeletedIntentionMarksTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          GraphLogDeletedIntentionMarks,
          GraphLogDeletedIntentionMark,
          $GraphLogDeletedIntentionMarksFilterComposer,
          $GraphLogDeletedIntentionMarksOrderingComposer,
          $GraphLogDeletedIntentionMarksAnnotationComposer,
          $GraphLogDeletedIntentionMarksCreateCompanionBuilder,
          $GraphLogDeletedIntentionMarksUpdateCompanionBuilder,
          (
            GraphLogDeletedIntentionMark,
            BaseReferences<
              _$AppDatabase,
              GraphLogDeletedIntentionMarks,
              GraphLogDeletedIntentionMark
            >,
          ),
          GraphLogDeletedIntentionMark,
          PrefetchHooks Function()
        > {
  $GraphLogDeletedIntentionMarksTableManager(
    _$AppDatabase db,
    GraphLogDeletedIntentionMarks table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $GraphLogDeletedIntentionMarksFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $GraphLogDeletedIntentionMarksOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $GraphLogDeletedIntentionMarksAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> intentionId = const Value.absent(),
                Value<String> firstOperation = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GraphLogDeletedIntentionMarksCompanion(
                intentionId: intentionId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String intentionId,
                required String firstOperation,
                Value<int> rowid = const Value.absent(),
              }) => GraphLogDeletedIntentionMarksCompanion.insert(
                intentionId: intentionId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $GraphLogDeletedIntentionMarksProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      GraphLogDeletedIntentionMarks,
      GraphLogDeletedIntentionMark,
      $GraphLogDeletedIntentionMarksFilterComposer,
      $GraphLogDeletedIntentionMarksOrderingComposer,
      $GraphLogDeletedIntentionMarksAnnotationComposer,
      $GraphLogDeletedIntentionMarksCreateCompanionBuilder,
      $GraphLogDeletedIntentionMarksUpdateCompanionBuilder,
      (
        GraphLogDeletedIntentionMark,
        BaseReferences<
          _$AppDatabase,
          GraphLogDeletedIntentionMarks,
          GraphLogDeletedIntentionMark
        >,
      ),
      GraphLogDeletedIntentionMark,
      PrefetchHooks Function()
    >;
typedef $GraphLogDeletedRelationPairMarksCreateCompanionBuilder =
    GraphLogDeletedRelationPairMarksCompanion Function({
      required String sourceIntentionId,
      required String relatedIntentionId,
      required String firstOperation,
      Value<int> rowid,
    });
typedef $GraphLogDeletedRelationPairMarksUpdateCompanionBuilder =
    GraphLogDeletedRelationPairMarksCompanion Function({
      Value<String> sourceIntentionId,
      Value<String> relatedIntentionId,
      Value<String> firstOperation,
      Value<int> rowid,
    });

class $GraphLogDeletedRelationPairMarksFilterComposer
    extends Composer<_$AppDatabase, GraphLogDeletedRelationPairMarks> {
  $GraphLogDeletedRelationPairMarksFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceIntentionId => $composableBuilder(
    column: $table.sourceIntentionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relatedIntentionId => $composableBuilder(
    column: $table.relatedIntentionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnFilters(column),
  );
}

class $GraphLogDeletedRelationPairMarksOrderingComposer
    extends Composer<_$AppDatabase, GraphLogDeletedRelationPairMarks> {
  $GraphLogDeletedRelationPairMarksOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceIntentionId => $composableBuilder(
    column: $table.sourceIntentionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relatedIntentionId => $composableBuilder(
    column: $table.relatedIntentionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => ColumnOrderings(column),
  );
}

class $GraphLogDeletedRelationPairMarksAnnotationComposer
    extends Composer<_$AppDatabase, GraphLogDeletedRelationPairMarks> {
  $GraphLogDeletedRelationPairMarksAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceIntentionId => $composableBuilder(
    column: $table.sourceIntentionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relatedIntentionId => $composableBuilder(
    column: $table.relatedIntentionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firstOperation => $composableBuilder(
    column: $table.firstOperation,
    builder: (column) => column,
  );
}

class $GraphLogDeletedRelationPairMarksTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          GraphLogDeletedRelationPairMarks,
          GraphLogDeletedRelationPairMark,
          $GraphLogDeletedRelationPairMarksFilterComposer,
          $GraphLogDeletedRelationPairMarksOrderingComposer,
          $GraphLogDeletedRelationPairMarksAnnotationComposer,
          $GraphLogDeletedRelationPairMarksCreateCompanionBuilder,
          $GraphLogDeletedRelationPairMarksUpdateCompanionBuilder,
          (
            GraphLogDeletedRelationPairMark,
            BaseReferences<
              _$AppDatabase,
              GraphLogDeletedRelationPairMarks,
              GraphLogDeletedRelationPairMark
            >,
          ),
          GraphLogDeletedRelationPairMark,
          PrefetchHooks Function()
        > {
  $GraphLogDeletedRelationPairMarksTableManager(
    _$AppDatabase db,
    GraphLogDeletedRelationPairMarks table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $GraphLogDeletedRelationPairMarksFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $GraphLogDeletedRelationPairMarksOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $GraphLogDeletedRelationPairMarksAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> sourceIntentionId = const Value.absent(),
                Value<String> relatedIntentionId = const Value.absent(),
                Value<String> firstOperation = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GraphLogDeletedRelationPairMarksCompanion(
                sourceIntentionId: sourceIntentionId,
                relatedIntentionId: relatedIntentionId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceIntentionId,
                required String relatedIntentionId,
                required String firstOperation,
                Value<int> rowid = const Value.absent(),
              }) => GraphLogDeletedRelationPairMarksCompanion.insert(
                sourceIntentionId: sourceIntentionId,
                relatedIntentionId: relatedIntentionId,
                firstOperation: firstOperation,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $GraphLogDeletedRelationPairMarksProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      GraphLogDeletedRelationPairMarks,
      GraphLogDeletedRelationPairMark,
      $GraphLogDeletedRelationPairMarksFilterComposer,
      $GraphLogDeletedRelationPairMarksOrderingComposer,
      $GraphLogDeletedRelationPairMarksAnnotationComposer,
      $GraphLogDeletedRelationPairMarksCreateCompanionBuilder,
      $GraphLogDeletedRelationPairMarksUpdateCompanionBuilder,
      (
        GraphLogDeletedRelationPairMark,
        BaseReferences<
          _$AppDatabase,
          GraphLogDeletedRelationPairMarks,
          GraphLogDeletedRelationPairMark
        >,
      ),
      GraphLogDeletedRelationPairMark,
      PrefetchHooks Function()
    >;
typedef $GraphSnapshotsCreateCompanionBuilder =
    GraphSnapshotsCompanion Function({
      Value<int> id,
      required int position,
      required String fileName,
      required int byteSize,
      required Uint8List checksum,
    });
typedef $GraphSnapshotsUpdateCompanionBuilder =
    GraphSnapshotsCompanion Function({
      Value<int> id,
      Value<int> position,
      Value<String> fileName,
      Value<int> byteSize,
      Value<Uint8List> checksum,
    });

final class $GraphSnapshotsReferences
    extends
        BaseReferences<_$AppDatabase, GraphSnapshots, RegisteredGraphSnapshot> {
  $GraphSnapshotsReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<GraphLogPackages, List<GraphLogPackage>>
  _graphLogPackagesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.graphLogPackages,
    aliasName: 'graph_snapshots__id__graph_log_packages__snapshot_id',
  );

  $GraphLogPackagesProcessedTableManager get graphLogPackagesRefs {
    final manager = $GraphLogPackagesTableManager(
      $_db,
      $_db.graphLogPackages,
    ).filter((f) => f.snapshotId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _graphLogPackagesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $GraphSnapshotsFilterComposer
    extends Composer<_$AppDatabase, GraphSnapshots> {
  $GraphSnapshotsFilterComposer({
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

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> graphLogPackagesRefs(
    Expression<bool> Function($GraphLogPackagesFilterComposer f) f,
  ) {
    final $GraphLogPackagesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.graphLogPackages,
      getReferencedColumn: (t) => t.snapshotId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $GraphLogPackagesFilterComposer(
            $db: $db,
            $table: $db.graphLogPackages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $GraphSnapshotsOrderingComposer
    extends Composer<_$AppDatabase, GraphSnapshots> {
  $GraphSnapshotsOrderingComposer({
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

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnOrderings(column),
  );
}

class $GraphSnapshotsAnnotationComposer
    extends Composer<_$AppDatabase, GraphSnapshots> {
  $GraphSnapshotsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<Uint8List> get checksum =>
      $composableBuilder(column: $table.checksum, builder: (column) => column);

  Expression<T> graphLogPackagesRefs<T extends Object>(
    Expression<T> Function($GraphLogPackagesAnnotationComposer a) f,
  ) {
    final $GraphLogPackagesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.graphLogPackages,
      getReferencedColumn: (t) => t.snapshotId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $GraphLogPackagesAnnotationComposer(
            $db: $db,
            $table: $db.graphLogPackages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $GraphSnapshotsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          GraphSnapshots,
          RegisteredGraphSnapshot,
          $GraphSnapshotsFilterComposer,
          $GraphSnapshotsOrderingComposer,
          $GraphSnapshotsAnnotationComposer,
          $GraphSnapshotsCreateCompanionBuilder,
          $GraphSnapshotsUpdateCompanionBuilder,
          (RegisteredGraphSnapshot, $GraphSnapshotsReferences),
          RegisteredGraphSnapshot,
          PrefetchHooks Function({bool graphLogPackagesRefs})
        > {
  $GraphSnapshotsTableManager(_$AppDatabase db, GraphSnapshots table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $GraphSnapshotsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $GraphSnapshotsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $GraphSnapshotsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<Uint8List> checksum = const Value.absent(),
              }) => GraphSnapshotsCompanion(
                id: id,
                position: position,
                fileName: fileName,
                byteSize: byteSize,
                checksum: checksum,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int position,
                required String fileName,
                required int byteSize,
                required Uint8List checksum,
              }) => GraphSnapshotsCompanion.insert(
                id: id,
                position: position,
                fileName: fileName,
                byteSize: byteSize,
                checksum: checksum,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $GraphSnapshotsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({graphLogPackagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (graphLogPackagesRefs) db.graphLogPackages,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (graphLogPackagesRefs)
                    await $_getPrefetchedData<
                      RegisteredGraphSnapshot,
                      GraphSnapshots,
                      GraphLogPackage
                    >(
                      currentTable: table,
                      referencedTable: $GraphSnapshotsReferences
                          ._graphLogPackagesRefsTable(db),
                      managerFromTypedResult: (p0) => $GraphSnapshotsReferences(
                        db,
                        table,
                        p0,
                      ).graphLogPackagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.snapshotId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $GraphSnapshotsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      GraphSnapshots,
      RegisteredGraphSnapshot,
      $GraphSnapshotsFilterComposer,
      $GraphSnapshotsOrderingComposer,
      $GraphSnapshotsAnnotationComposer,
      $GraphSnapshotsCreateCompanionBuilder,
      $GraphSnapshotsUpdateCompanionBuilder,
      (RegisteredGraphSnapshot, $GraphSnapshotsReferences),
      RegisteredGraphSnapshot,
      PrefetchHooks Function({bool graphLogPackagesRefs})
    >;
typedef $GraphLogPackagesCreateCompanionBuilder =
    GraphLogPackagesCompanion Function({
      Value<int> position,
      required int recordedAt,
      required String kind,
      Value<int?> formatVersion,
      Value<Uint8List?> facts,
      Value<int?> snapshotId,
    });
typedef $GraphLogPackagesUpdateCompanionBuilder =
    GraphLogPackagesCompanion Function({
      Value<int> position,
      Value<int> recordedAt,
      Value<String> kind,
      Value<int?> formatVersion,
      Value<Uint8List?> facts,
      Value<int?> snapshotId,
    });

final class $GraphLogPackagesReferences
    extends BaseReferences<_$AppDatabase, GraphLogPackages, GraphLogPackage> {
  $GraphLogPackagesReferences(super.$_db, super.$_table, super.$_typedResult);

  static GraphSnapshots _snapshotIdTable(_$AppDatabase db) => db.graphSnapshots
      .createAlias('graph_log_packages__snapshot_id__graph_snapshots__id');

  $GraphSnapshotsProcessedTableManager? get snapshotId {
    final $_column = $_itemColumn<int>('snapshot_id');
    if ($_column == null) return null;
    final manager = $GraphSnapshotsTableManager(
      $_db,
      $_db.graphSnapshots,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_snapshotIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $GraphLogPackagesFilterComposer
    extends Composer<_$AppDatabase, GraphLogPackages> {
  $GraphLogPackagesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get formatVersion => $composableBuilder(
    column: $table.formatVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get facts => $composableBuilder(
    column: $table.facts,
    builder: (column) => ColumnFilters(column),
  );

  $GraphSnapshotsFilterComposer get snapshotId {
    final $GraphSnapshotsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotId,
      referencedTable: $db.graphSnapshots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $GraphSnapshotsFilterComposer(
            $db: $db,
            $table: $db.graphSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $GraphLogPackagesOrderingComposer
    extends Composer<_$AppDatabase, GraphLogPackages> {
  $GraphLogPackagesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get formatVersion => $composableBuilder(
    column: $table.formatVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get facts => $composableBuilder(
    column: $table.facts,
    builder: (column) => ColumnOrderings(column),
  );

  $GraphSnapshotsOrderingComposer get snapshotId {
    final $GraphSnapshotsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotId,
      referencedTable: $db.graphSnapshots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $GraphSnapshotsOrderingComposer(
            $db: $db,
            $table: $db.graphSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $GraphLogPackagesAnnotationComposer
    extends Composer<_$AppDatabase, GraphLogPackages> {
  $GraphLogPackagesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<int> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get formatVersion => $composableBuilder(
    column: $table.formatVersion,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get facts =>
      $composableBuilder(column: $table.facts, builder: (column) => column);

  $GraphSnapshotsAnnotationComposer get snapshotId {
    final $GraphSnapshotsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotId,
      referencedTable: $db.graphSnapshots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $GraphSnapshotsAnnotationComposer(
            $db: $db,
            $table: $db.graphSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $GraphLogPackagesTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          GraphLogPackages,
          GraphLogPackage,
          $GraphLogPackagesFilterComposer,
          $GraphLogPackagesOrderingComposer,
          $GraphLogPackagesAnnotationComposer,
          $GraphLogPackagesCreateCompanionBuilder,
          $GraphLogPackagesUpdateCompanionBuilder,
          (GraphLogPackage, $GraphLogPackagesReferences),
          GraphLogPackage,
          PrefetchHooks Function({bool snapshotId})
        > {
  $GraphLogPackagesTableManager(_$AppDatabase db, GraphLogPackages table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $GraphLogPackagesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $GraphLogPackagesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $GraphLogPackagesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> position = const Value.absent(),
                Value<int> recordedAt = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int?> formatVersion = const Value.absent(),
                Value<Uint8List?> facts = const Value.absent(),
                Value<int?> snapshotId = const Value.absent(),
              }) => GraphLogPackagesCompanion(
                position: position,
                recordedAt: recordedAt,
                kind: kind,
                formatVersion: formatVersion,
                facts: facts,
                snapshotId: snapshotId,
              ),
          createCompanionCallback:
              ({
                Value<int> position = const Value.absent(),
                required int recordedAt,
                required String kind,
                Value<int?> formatVersion = const Value.absent(),
                Value<Uint8List?> facts = const Value.absent(),
                Value<int?> snapshotId = const Value.absent(),
              }) => GraphLogPackagesCompanion.insert(
                position: position,
                recordedAt: recordedAt,
                kind: kind,
                formatVersion: formatVersion,
                facts: facts,
                snapshotId: snapshotId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $GraphLogPackagesReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({snapshotId = false}) {
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
                    if (snapshotId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.snapshotId,
                        referencedTable: $GraphLogPackagesReferences
                            ._snapshotIdTable(db),
                        referencedColumn: $GraphLogPackagesReferences
                            ._snapshotIdTable(db)
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

typedef $GraphLogPackagesProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      GraphLogPackages,
      GraphLogPackage,
      $GraphLogPackagesFilterComposer,
      $GraphLogPackagesOrderingComposer,
      $GraphLogPackagesAnnotationComposer,
      $GraphLogPackagesCreateCompanionBuilder,
      $GraphLogPackagesUpdateCompanionBuilder,
      (GraphLogPackage, $GraphLogPackagesReferences),
      GraphLogPackage,
      PrefetchHooks Function({bool snapshotId})
    >;
typedef $GraphBackupsCreateCompanionBuilder = GraphBackupsCompanion Function({
  Value<int> id,
  required int position,
  required String kind,
  required int madeAt,
  required bool graphReplaced,
  Value<int?> addedCount,
  Value<int?> changedCount,
  Value<int?> deletedCount,
});
typedef $GraphBackupsUpdateCompanionBuilder = GraphBackupsCompanion Function({
  Value<int> id,
  Value<int> position,
  Value<String> kind,
  Value<int> madeAt,
  Value<bool> graphReplaced,
  Value<int?> addedCount,
  Value<int?> changedCount,
  Value<int?> deletedCount,
});

class $GraphBackupsFilterComposer
    extends Composer<_$AppDatabase, GraphBackups> {
  $GraphBackupsFilterComposer({
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

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get madeAt => $composableBuilder(
    column: $table.madeAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get graphReplaced => $composableBuilder(
    column: $table.graphReplaced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedCount => $composableBuilder(
    column: $table.addedCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get changedCount => $composableBuilder(
    column: $table.changedCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedCount => $composableBuilder(
    column: $table.deletedCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $GraphBackupsOrderingComposer
    extends Composer<_$AppDatabase, GraphBackups> {
  $GraphBackupsOrderingComposer({
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

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get madeAt => $composableBuilder(
    column: $table.madeAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get graphReplaced => $composableBuilder(
    column: $table.graphReplaced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedCount => $composableBuilder(
    column: $table.addedCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get changedCount => $composableBuilder(
    column: $table.changedCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedCount => $composableBuilder(
    column: $table.deletedCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $GraphBackupsAnnotationComposer
    extends Composer<_$AppDatabase, GraphBackups> {
  $GraphBackupsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get madeAt =>
      $composableBuilder(column: $table.madeAt, builder: (column) => column);

  GeneratedColumn<bool> get graphReplaced => $composableBuilder(
    column: $table.graphReplaced,
    builder: (column) => column,
  );

  GeneratedColumn<int> get addedCount => $composableBuilder(
    column: $table.addedCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get changedCount => $composableBuilder(
    column: $table.changedCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedCount => $composableBuilder(
    column: $table.deletedCount,
    builder: (column) => column,
  );
}

class $GraphBackupsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          GraphBackups,
          GraphBackup,
          $GraphBackupsFilterComposer,
          $GraphBackupsOrderingComposer,
          $GraphBackupsAnnotationComposer,
          $GraphBackupsCreateCompanionBuilder,
          $GraphBackupsUpdateCompanionBuilder,
          (
            GraphBackup,
            BaseReferences<_$AppDatabase, GraphBackups, GraphBackup>,
          ),
          GraphBackup,
          PrefetchHooks Function()
        > {
  $GraphBackupsTableManager(_$AppDatabase db, GraphBackups table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $GraphBackupsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $GraphBackupsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $GraphBackupsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> madeAt = const Value.absent(),
                Value<bool> graphReplaced = const Value.absent(),
                Value<int?> addedCount = const Value.absent(),
                Value<int?> changedCount = const Value.absent(),
                Value<int?> deletedCount = const Value.absent(),
              }) => GraphBackupsCompanion(
                id: id,
                position: position,
                kind: kind,
                madeAt: madeAt,
                graphReplaced: graphReplaced,
                addedCount: addedCount,
                changedCount: changedCount,
                deletedCount: deletedCount,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int position,
                required String kind,
                required int madeAt,
                required bool graphReplaced,
                Value<int?> addedCount = const Value.absent(),
                Value<int?> changedCount = const Value.absent(),
                Value<int?> deletedCount = const Value.absent(),
              }) => GraphBackupsCompanion.insert(
                id: id,
                position: position,
                kind: kind,
                madeAt: madeAt,
                graphReplaced: graphReplaced,
                addedCount: addedCount,
                changedCount: changedCount,
                deletedCount: deletedCount,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $GraphBackupsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      GraphBackups,
      GraphBackup,
      $GraphBackupsFilterComposer,
      $GraphBackupsOrderingComposer,
      $GraphBackupsAnnotationComposer,
      $GraphBackupsCreateCompanionBuilder,
      $GraphBackupsUpdateCompanionBuilder,
      (GraphBackup, BaseReferences<_$AppDatabase, GraphBackups, GraphBackup>),
      GraphBackup,
      PrefetchHooks Function()
    >;
typedef $TagsCreateCompanionBuilder = TagsCompanion Function({
  Value<int> creationSequence,
  required String id,
  required String name,
  Value<String?> color,
  required String position,
});
typedef $TagsUpdateCompanionBuilder = TagsCompanion Function({
  Value<int> creationSequence,
  Value<String> id,
  Value<String> name,
  Value<String?> color,
  Value<String> position,
});

final class $TagsReferences extends BaseReferences<_$AppDatabase, Tags, Tag> {
  $TagsReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<TagAssignments, List<TagAssignment>>
  _tagAssignmentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.tagAssignments,
    aliasName: 'tags__id__tag_assignments__tag_id',
  );

  $TagAssignmentsProcessedTableManager get tagAssignmentsRefs {
    final manager = $TagAssignmentsTableManager(
      $_db,
      $_db.tagAssignments,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_tagAssignmentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $TagsFilterComposer extends Composer<_$AppDatabase, Tags> {
  $TagsFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameKey => $composableBuilder(
    column: $table.nameKey,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> tagAssignmentsRefs(
    Expression<bool> Function($TagAssignmentsFilterComposer f) f,
  ) {
    final $TagAssignmentsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tagAssignments,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $TagAssignmentsFilterComposer(
            $db: $db,
            $table: $db.tagAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $TagsOrderingComposer extends Composer<_$AppDatabase, Tags> {
  $TagsOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameKey => $composableBuilder(
    column: $table.nameKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $TagsAnnotationComposer extends Composer<_$AppDatabase, Tags> {
  $TagsAnnotationComposer({
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

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get nameKey =>
      $composableBuilder(column: $table.nameKey, builder: (column) => column);

  Expression<T> tagAssignmentsRefs<T extends Object>(
    Expression<T> Function($TagAssignmentsAnnotationComposer a) f,
  ) {
    final $TagAssignmentsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tagAssignments,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $TagAssignmentsAnnotationComposer(
            $db: $db,
            $table: $db.tagAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $TagsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Tags,
          Tag,
          $TagsFilterComposer,
          $TagsOrderingComposer,
          $TagsAnnotationComposer,
          $TagsCreateCompanionBuilder,
          $TagsUpdateCompanionBuilder,
          (Tag, $TagsReferences),
          Tag,
          PrefetchHooks Function({bool tagAssignmentsRefs})
        > {
  $TagsTableManager(_$AppDatabase db, Tags table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $TagsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $TagsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $TagsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> creationSequence = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<String> position = const Value.absent(),
              }) => TagsCompanion(
                creationSequence: creationSequence,
                id: id,
                name: name,
                color: color,
                position: position,
              ),
          createCompanionCallback:
              ({
                Value<int> creationSequence = const Value.absent(),
                required String id,
                required String name,
                Value<String?> color = const Value.absent(),
                required String position,
              }) => TagsCompanion.insert(
                creationSequence: creationSequence,
                id: id,
                name: name,
                color: color,
                position: position,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), $TagsReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({tagAssignmentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (tagAssignmentsRefs) db.tagAssignments,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (tagAssignmentsRefs)
                    await $_getPrefetchedData<Tag, Tags, TagAssignment>(
                      currentTable: table,
                      referencedTable: $TagsReferences._tagAssignmentsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $TagsReferences(db, table, p0).tagAssignmentsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.tagId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $TagsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Tags,
      Tag,
      $TagsFilterComposer,
      $TagsOrderingComposer,
      $TagsAnnotationComposer,
      $TagsCreateCompanionBuilder,
      $TagsUpdateCompanionBuilder,
      (Tag, $TagsReferences),
      Tag,
      PrefetchHooks Function({bool tagAssignmentsRefs})
    >;
typedef $IntentionsCreateCompanionBuilder = IntentionsCompanion Function({
  required String id,
  required String title,
  Value<String?> description,
  Value<String> kind,
  Value<bool> isArchived,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $IntentionsUpdateCompanionBuilder = IntentionsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String?> description,
  Value<String> kind,
  Value<bool> isArchived,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $IntentionsReferences
    extends BaseReferences<_$AppDatabase, Intentions, Intention> {
  $IntentionsReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<TagAssignments, List<TagAssignment>>
  _tagAssignmentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.tagAssignments,
    aliasName: 'intentions__id__tag_assignments__intention_id',
  );

  $TagAssignmentsProcessedTableManager get tagAssignmentsRefs {
    final manager = $TagAssignmentsTableManager(
      $_db,
      $_db.tagAssignments,
    ).filter((f) => f.intentionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_tagAssignmentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

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

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
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

  Expression<bool> tagAssignmentsRefs(
    Expression<bool> Function($TagAssignmentsFilterComposer f) f,
  ) {
    final $TagAssignmentsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tagAssignments,
      getReferencedColumn: (t) => t.intentionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $TagAssignmentsFilterComposer(
            $db: $db,
            $table: $db.tagAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
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

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> tagAssignmentsRefs<T extends Object>(
    Expression<T> Function($TagAssignmentsAnnotationComposer a) f,
  ) {
    final $TagAssignmentsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tagAssignments,
      getReferencedColumn: (t) => t.intentionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $TagAssignmentsAnnotationComposer(
            $db: $db,
            $table: $db.tagAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
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
          (Intention, $IntentionsReferences),
          Intention,
          PrefetchHooks Function({bool tagAssignmentsRefs})
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
                Value<String> kind = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IntentionsCompanion(
                id: id,
                title: title,
                description: description,
                kind: kind,
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
                Value<String> kind = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => IntentionsCompanion.insert(
                id: id,
                title: title,
                description: description,
                kind: kind,
                isArchived: isArchived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $IntentionsReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({tagAssignmentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (tagAssignmentsRefs) db.tagAssignments,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (tagAssignmentsRefs)
                    await $_getPrefetchedData<
                      Intention,
                      Intentions,
                      TagAssignment
                    >(
                      currentTable: table,
                      referencedTable: $IntentionsReferences
                          ._tagAssignmentsRefsTable(db),
                      managerFromTypedResult: (p0) => $IntentionsReferences(
                        db,
                        table,
                        p0,
                      ).tagAssignmentsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.intentionId == item.id,
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
      (Intention, $IntentionsReferences),
      Intention,
      PrefetchHooks Function({bool tagAssignmentsRefs})
    >;
typedef $TagAssignmentsCreateCompanionBuilder =
    TagAssignmentsCompanion Function({
      Value<int> creationSequence,
      required String tagId,
      required String intentionId,
    });
typedef $TagAssignmentsUpdateCompanionBuilder =
    TagAssignmentsCompanion Function({
      Value<int> creationSequence,
      Value<String> tagId,
      Value<String> intentionId,
    });

final class $TagAssignmentsReferences
    extends BaseReferences<_$AppDatabase, TagAssignments, TagAssignment> {
  $TagAssignmentsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Tags _tagIdTable(_$AppDatabase db) =>
      db.tags.createAlias('tag_assignments__tag_id__tags__id');

  $TagsProcessedTableManager get tagId {
    final $_column = $_itemColumn<String>('tag_id')!;

    final manager = $TagsTableManager(
      $_db,
      $_db.tags,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static Intentions _intentionIdTable(_$AppDatabase db) => db.intentions
      .createAlias('tag_assignments__intention_id__intentions__id');

  $IntentionsProcessedTableManager get intentionId {
    final $_column = $_itemColumn<String>('intention_id')!;

    final manager = $IntentionsTableManager(
      $_db,
      $_db.intentions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_intentionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $TagAssignmentsFilterComposer
    extends Composer<_$AppDatabase, TagAssignments> {
  $TagAssignmentsFilterComposer({
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

  $TagsFilterComposer get tagId {
    final $TagsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $TagsFilterComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $IntentionsFilterComposer get intentionId {
    final $IntentionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.intentionId,
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
}

class $TagAssignmentsOrderingComposer
    extends Composer<_$AppDatabase, TagAssignments> {
  $TagAssignmentsOrderingComposer({
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

  $TagsOrderingComposer get tagId {
    final $TagsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $TagsOrderingComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $IntentionsOrderingComposer get intentionId {
    final $IntentionsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.intentionId,
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

class $TagAssignmentsAnnotationComposer
    extends Composer<_$AppDatabase, TagAssignments> {
  $TagAssignmentsAnnotationComposer({
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

  $TagsAnnotationComposer get tagId {
    final $TagsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $TagsAnnotationComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $IntentionsAnnotationComposer get intentionId {
    final $IntentionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.intentionId,
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
}

class $TagAssignmentsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          TagAssignments,
          TagAssignment,
          $TagAssignmentsFilterComposer,
          $TagAssignmentsOrderingComposer,
          $TagAssignmentsAnnotationComposer,
          $TagAssignmentsCreateCompanionBuilder,
          $TagAssignmentsUpdateCompanionBuilder,
          (TagAssignment, $TagAssignmentsReferences),
          TagAssignment,
          PrefetchHooks Function({bool tagId, bool intentionId})
        > {
  $TagAssignmentsTableManager(_$AppDatabase db, TagAssignments table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $TagAssignmentsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $TagAssignmentsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $TagAssignmentsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> creationSequence = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<String> intentionId = const Value.absent(),
              }) => TagAssignmentsCompanion(
                creationSequence: creationSequence,
                tagId: tagId,
                intentionId: intentionId,
              ),
          createCompanionCallback:
              ({
                Value<int> creationSequence = const Value.absent(),
                required String tagId,
                required String intentionId,
              }) => TagAssignmentsCompanion.insert(
                creationSequence: creationSequence,
                tagId: tagId,
                intentionId: intentionId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $TagAssignmentsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({tagId = false, intentionId = false}) {
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
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.tagId,
                        referencedTable: $TagAssignmentsReferences._tagIdTable(
                          db,
                        ),
                        referencedColumn: $TagAssignmentsReferences
                            ._tagIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (intentionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.intentionId,
                        referencedTable: $TagAssignmentsReferences
                            ._intentionIdTable(db),
                        referencedColumn: $TagAssignmentsReferences
                            ._intentionIdTable(db)
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

typedef $TagAssignmentsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      TagAssignments,
      TagAssignment,
      $TagAssignmentsFilterComposer,
      $TagAssignmentsOrderingComposer,
      $TagAssignmentsAnnotationComposer,
      $TagAssignmentsCreateCompanionBuilder,
      $TagAssignmentsUpdateCompanionBuilder,
      (TagAssignment, $TagAssignmentsReferences),
      TagAssignment,
      PrefetchHooks Function({bool tagId, bool intentionId})
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
      required int createdAt,
      required int updatedAt,
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
      Value<int> createdAt,
      Value<int> updatedAt,
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

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
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

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
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

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

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
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => LongTermRelationsCompanion(
                creationSequence: creationSequence,
                id: id,
                sourceIntentionId: sourceIntentionId,
                relatedIntentionId: relatedIntentionId,
                type: type,
                priority: priority,
                description: description,
                isArchived: isArchived,
                createdAt: createdAt,
                updatedAt: updatedAt,
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
                required int createdAt,
                required int updatedAt,
              }) => LongTermRelationsCompanion.insert(
                creationSequence: creationSequence,
                id: id,
                sourceIntentionId: sourceIntentionId,
                relatedIntentionId: relatedIntentionId,
                type: type,
                priority: priority,
                description: description,
                isArchived: isArchived,
                createdAt: createdAt,
                updatedAt: updatedAt,
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
              ({sourceIntentionId = false, relatedIntentionId = false}) {
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
                    return [];
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
      PrefetchHooks Function({bool sourceIntentionId, bool relatedIntentionId})
    >;
typedef $ActionsCreateCompanionBuilder = ActionsCompanion Function({
  Value<int> creationSequence,
  required String id,
  required String title,
  Value<String?> description,
  required String date,
  Value<int?> scheduledHour,
  required int priority,
  required bool isCompleted,
  required int createdAt,
  required int updatedAt,
});
typedef $ActionsUpdateCompanionBuilder = ActionsCompanion Function({
  Value<int> creationSequence,
  Value<String> id,
  Value<String> title,
  Value<String?> description,
  Value<String> date,
  Value<int?> scheduledHour,
  Value<int> priority,
  Value<bool> isCompleted,
  Value<int> createdAt,
  Value<int> updatedAt,
});

final class $ActionsReferences
    extends BaseReferences<_$AppDatabase, Actions, Action> {
  $ActionsReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<ActionPathItems, List<ActionPathItem>>
  _actionPathItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.actionPathItems,
    aliasName: 'actions__id__action_path_items__action_id',
  );

  $ActionPathItemsProcessedTableManager get actionPathItemsRefs {
    final manager = $ActionPathItemsTableManager(
      $_db,
      $_db.actionPathItems,
    ).filter((f) => f.actionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _actionPathItemsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $ActionsFilterComposer extends Composer<_$AppDatabase, Actions> {
  $ActionsFilterComposer({
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scheduledHour => $composableBuilder(
    column: $table.scheduledHour,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
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

  Expression<bool> actionPathItemsRefs(
    Expression<bool> Function($ActionPathItemsFilterComposer f) f,
  ) {
    final $ActionPathItemsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.actionPathItems,
      getReferencedColumn: (t) => t.actionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ActionPathItemsFilterComposer(
            $db: $db,
            $table: $db.actionPathItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $ActionsOrderingComposer extends Composer<_$AppDatabase, Actions> {
  $ActionsOrderingComposer({
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scheduledHour => $composableBuilder(
    column: $table.scheduledHour,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
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

class $ActionsAnnotationComposer extends Composer<_$AppDatabase, Actions> {
  $ActionsAnnotationComposer({
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

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get scheduledHour => $composableBuilder(
    column: $table.scheduledHour,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> actionPathItemsRefs<T extends Object>(
    Expression<T> Function($ActionPathItemsAnnotationComposer a) f,
  ) {
    final $ActionPathItemsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.actionPathItems,
      getReferencedColumn: (t) => t.actionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ActionPathItemsAnnotationComposer(
            $db: $db,
            $table: $db.actionPathItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $ActionsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Actions,
          Action,
          $ActionsFilterComposer,
          $ActionsOrderingComposer,
          $ActionsAnnotationComposer,
          $ActionsCreateCompanionBuilder,
          $ActionsUpdateCompanionBuilder,
          (Action, $ActionsReferences),
          Action,
          PrefetchHooks Function({bool actionPathItemsRefs})
        > {
  $ActionsTableManager(_$AppDatabase db, Actions table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ActionsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ActionsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ActionsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> creationSequence = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int?> scheduledHour = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<bool> isCompleted = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => ActionsCompanion(
                creationSequence: creationSequence,
                id: id,
                title: title,
                description: description,
                date: date,
                scheduledHour: scheduledHour,
                priority: priority,
                isCompleted: isCompleted,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> creationSequence = const Value.absent(),
                required String id,
                required String title,
                Value<String?> description = const Value.absent(),
                required String date,
                Value<int?> scheduledHour = const Value.absent(),
                required int priority,
                required bool isCompleted,
                required int createdAt,
                required int updatedAt,
              }) => ActionsCompanion.insert(
                creationSequence: creationSequence,
                id: id,
                title: title,
                description: description,
                date: date,
                scheduledHour: scheduledHour,
                priority: priority,
                isCompleted: isCompleted,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (e.readTable(table), $ActionsReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({actionPathItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (actionPathItemsRefs) db.actionPathItems,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (actionPathItemsRefs)
                    await $_getPrefetchedData<Action, Actions, ActionPathItem>(
                      currentTable: table,
                      referencedTable: $ActionsReferences
                          ._actionPathItemsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $ActionsReferences(db, table, p0).actionPathItemsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.actionId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $ActionsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Actions,
      Action,
      $ActionsFilterComposer,
      $ActionsOrderingComposer,
      $ActionsAnnotationComposer,
      $ActionsCreateCompanionBuilder,
      $ActionsUpdateCompanionBuilder,
      (Action, $ActionsReferences),
      Action,
      PrefetchHooks Function({bool actionPathItemsRefs})
    >;
typedef $ActionPathItemsCreateCompanionBuilder =
    ActionPathItemsCompanion Function({
      required String actionId,
      required int position,
      required String intentionId,
      Value<String?> previousIntentionId,
      required String role,
      required String orderDate,
      required int orderHour,
      required int orderSequence,
      Value<int> rowid,
    });
typedef $ActionPathItemsUpdateCompanionBuilder =
    ActionPathItemsCompanion Function({
      Value<String> actionId,
      Value<int> position,
      Value<String> intentionId,
      Value<String?> previousIntentionId,
      Value<String> role,
      Value<String> orderDate,
      Value<int> orderHour,
      Value<int> orderSequence,
      Value<int> rowid,
    });

final class $ActionPathItemsReferences
    extends BaseReferences<_$AppDatabase, ActionPathItems, ActionPathItem> {
  $ActionPathItemsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Actions _actionIdTable(_$AppDatabase db) =>
      db.actions.createAlias('action_path_items__action_id__actions__id');

  $ActionsProcessedTableManager get actionId {
    final $_column = $_itemColumn<String>('action_id')!;

    final manager = $ActionsTableManager(
      $_db,
      $_db.actions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_actionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $ActionPathItemsFilterComposer
    extends Composer<_$AppDatabase, ActionPathItems> {
  $ActionPathItemsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get previousIntentionId => $composableBuilder(
    column: $table.previousIntentionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderDate => $composableBuilder(
    column: $table.orderDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderHour => $composableBuilder(
    column: $table.orderHour,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderSequence => $composableBuilder(
    column: $table.orderSequence,
    builder: (column) => ColumnFilters(column),
  );

  $ActionsFilterComposer get actionId {
    final $ActionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ActionsFilterComposer(
            $db: $db,
            $table: $db.actions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ActionPathItemsOrderingComposer
    extends Composer<_$AppDatabase, ActionPathItems> {
  $ActionPathItemsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get previousIntentionId => $composableBuilder(
    column: $table.previousIntentionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderDate => $composableBuilder(
    column: $table.orderDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderHour => $composableBuilder(
    column: $table.orderHour,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderSequence => $composableBuilder(
    column: $table.orderSequence,
    builder: (column) => ColumnOrderings(column),
  );

  $ActionsOrderingComposer get actionId {
    final $ActionsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ActionsOrderingComposer(
            $db: $db,
            $table: $db.actions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ActionPathItemsAnnotationComposer
    extends Composer<_$AppDatabase, ActionPathItems> {
  $ActionPathItemsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get previousIntentionId => $composableBuilder(
    column: $table.previousIntentionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get orderDate =>
      $composableBuilder(column: $table.orderDate, builder: (column) => column);

  GeneratedColumn<int> get orderHour =>
      $composableBuilder(column: $table.orderHour, builder: (column) => column);

  GeneratedColumn<int> get orderSequence => $composableBuilder(
    column: $table.orderSequence,
    builder: (column) => column,
  );

  $ActionsAnnotationComposer get actionId {
    final $ActionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ActionsAnnotationComposer(
            $db: $db,
            $table: $db.actions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ActionPathItemsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          ActionPathItems,
          ActionPathItem,
          $ActionPathItemsFilterComposer,
          $ActionPathItemsOrderingComposer,
          $ActionPathItemsAnnotationComposer,
          $ActionPathItemsCreateCompanionBuilder,
          $ActionPathItemsUpdateCompanionBuilder,
          (ActionPathItem, $ActionPathItemsReferences),
          ActionPathItem,
          PrefetchHooks Function({bool actionId})
        > {
  $ActionPathItemsTableManager(_$AppDatabase db, ActionPathItems table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ActionPathItemsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ActionPathItemsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ActionPathItemsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> actionId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> intentionId = const Value.absent(),
                Value<String?> previousIntentionId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> orderDate = const Value.absent(),
                Value<int> orderHour = const Value.absent(),
                Value<int> orderSequence = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionPathItemsCompanion(
                actionId: actionId,
                position: position,
                intentionId: intentionId,
                previousIntentionId: previousIntentionId,
                role: role,
                orderDate: orderDate,
                orderHour: orderHour,
                orderSequence: orderSequence,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String actionId,
                required int position,
                required String intentionId,
                Value<String?> previousIntentionId = const Value.absent(),
                required String role,
                required String orderDate,
                required int orderHour,
                required int orderSequence,
                Value<int> rowid = const Value.absent(),
              }) => ActionPathItemsCompanion.insert(
                actionId: actionId,
                position: position,
                intentionId: intentionId,
                previousIntentionId: previousIntentionId,
                role: role,
                orderDate: orderDate,
                orderHour: orderHour,
                orderSequence: orderSequence,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $ActionPathItemsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({actionId = false}) {
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
                    if (actionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.actionId,
                        referencedTable: $ActionPathItemsReferences
                            ._actionIdTable(db),
                        referencedColumn: $ActionPathItemsReferences
                            ._actionIdTable(db)
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

typedef $ActionPathItemsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      ActionPathItems,
      ActionPathItem,
      $ActionPathItemsFilterComposer,
      $ActionPathItemsOrderingComposer,
      $ActionPathItemsAnnotationComposer,
      $ActionPathItemsCreateCompanionBuilder,
      $ActionPathItemsUpdateCompanionBuilder,
      (ActionPathItem, $ActionPathItemsReferences),
      ActionPathItem,
      PrefetchHooks Function({bool actionId})
    >;
typedef $DeletedIntentionsCreateCompanionBuilder =
    DeletedIntentionsCompanion Function({
      required String intentionId,
      required String title,
      Value<int> rowid,
    });
typedef $DeletedIntentionsUpdateCompanionBuilder =
    DeletedIntentionsCompanion Function({
      Value<String> intentionId,
      Value<String> title,
      Value<int> rowid,
    });

class $DeletedIntentionsFilterComposer
    extends Composer<_$AppDatabase, DeletedIntentions> {
  $DeletedIntentionsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );
}

class $DeletedIntentionsOrderingComposer
    extends Composer<_$AppDatabase, DeletedIntentions> {
  $DeletedIntentionsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );
}

class $DeletedIntentionsAnnotationComposer
    extends Composer<_$AppDatabase, DeletedIntentions> {
  $DeletedIntentionsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get intentionId => $composableBuilder(
    column: $table.intentionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);
}

class $DeletedIntentionsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          DeletedIntentions,
          DeletedIntention,
          $DeletedIntentionsFilterComposer,
          $DeletedIntentionsOrderingComposer,
          $DeletedIntentionsAnnotationComposer,
          $DeletedIntentionsCreateCompanionBuilder,
          $DeletedIntentionsUpdateCompanionBuilder,
          (
            DeletedIntention,
            BaseReferences<_$AppDatabase, DeletedIntentions, DeletedIntention>,
          ),
          DeletedIntention,
          PrefetchHooks Function()
        > {
  $DeletedIntentionsTableManager(_$AppDatabase db, DeletedIntentions table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $DeletedIntentionsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $DeletedIntentionsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $DeletedIntentionsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> intentionId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeletedIntentionsCompanion(
                intentionId: intentionId,
                title: title,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String intentionId,
                required String title,
                Value<int> rowid = const Value.absent(),
              }) => DeletedIntentionsCompanion.insert(
                intentionId: intentionId,
                title: title,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $DeletedIntentionsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      DeletedIntentions,
      DeletedIntention,
      $DeletedIntentionsFilterComposer,
      $DeletedIntentionsOrderingComposer,
      $DeletedIntentionsAnnotationComposer,
      $DeletedIntentionsCreateCompanionBuilder,
      $DeletedIntentionsUpdateCompanionBuilder,
      (
        DeletedIntention,
        BaseReferences<_$AppDatabase, DeletedIntentions, DeletedIntention>,
      ),
      DeletedIntention,
      PrefetchHooks Function()
    >;
typedef $DeletedRelationPairsCreateCompanionBuilder =
    DeletedRelationPairsCompanion Function({
      required String sourceIntentionId,
      required String relatedIntentionId,
      required String type,
      Value<int> rowid,
    });
typedef $DeletedRelationPairsUpdateCompanionBuilder =
    DeletedRelationPairsCompanion Function({
      Value<String> sourceIntentionId,
      Value<String> relatedIntentionId,
      Value<String> type,
      Value<int> rowid,
    });

class $DeletedRelationPairsFilterComposer
    extends Composer<_$AppDatabase, DeletedRelationPairs> {
  $DeletedRelationPairsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceIntentionId => $composableBuilder(
    column: $table.sourceIntentionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relatedIntentionId => $composableBuilder(
    column: $table.relatedIntentionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );
}

class $DeletedRelationPairsOrderingComposer
    extends Composer<_$AppDatabase, DeletedRelationPairs> {
  $DeletedRelationPairsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceIntentionId => $composableBuilder(
    column: $table.sourceIntentionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relatedIntentionId => $composableBuilder(
    column: $table.relatedIntentionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );
}

class $DeletedRelationPairsAnnotationComposer
    extends Composer<_$AppDatabase, DeletedRelationPairs> {
  $DeletedRelationPairsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceIntentionId => $composableBuilder(
    column: $table.sourceIntentionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relatedIntentionId => $composableBuilder(
    column: $table.relatedIntentionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);
}

class $DeletedRelationPairsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          DeletedRelationPairs,
          DeletedRelationPair,
          $DeletedRelationPairsFilterComposer,
          $DeletedRelationPairsOrderingComposer,
          $DeletedRelationPairsAnnotationComposer,
          $DeletedRelationPairsCreateCompanionBuilder,
          $DeletedRelationPairsUpdateCompanionBuilder,
          (
            DeletedRelationPair,
            BaseReferences<
              _$AppDatabase,
              DeletedRelationPairs,
              DeletedRelationPair
            >,
          ),
          DeletedRelationPair,
          PrefetchHooks Function()
        > {
  $DeletedRelationPairsTableManager(
    _$AppDatabase db,
    DeletedRelationPairs table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $DeletedRelationPairsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $DeletedRelationPairsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $DeletedRelationPairsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceIntentionId = const Value.absent(),
                Value<String> relatedIntentionId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeletedRelationPairsCompanion(
                sourceIntentionId: sourceIntentionId,
                relatedIntentionId: relatedIntentionId,
                type: type,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceIntentionId,
                required String relatedIntentionId,
                required String type,
                Value<int> rowid = const Value.absent(),
              }) => DeletedRelationPairsCompanion.insert(
                sourceIntentionId: sourceIntentionId,
                relatedIntentionId: relatedIntentionId,
                type: type,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $DeletedRelationPairsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      DeletedRelationPairs,
      DeletedRelationPair,
      $DeletedRelationPairsFilterComposer,
      $DeletedRelationPairsOrderingComposer,
      $DeletedRelationPairsAnnotationComposer,
      $DeletedRelationPairsCreateCompanionBuilder,
      $DeletedRelationPairsUpdateCompanionBuilder,
      (
        DeletedRelationPair,
        BaseReferences<
          _$AppDatabase,
          DeletedRelationPairs,
          DeletedRelationPair
        >,
      ),
      DeletedRelationPair,
      PrefetchHooks Function()
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
  $GraphLogControlTableManager get graphLogControl =>
      $GraphLogControlTableManager(_db, _db.graphLogControl);
  $GraphLogTagMarksTableManager get graphLogTagMarks =>
      $GraphLogTagMarksTableManager(_db, _db.graphLogTagMarks);
  $GraphLogIntentionMarksTableManager get graphLogIntentionMarks =>
      $GraphLogIntentionMarksTableManager(_db, _db.graphLogIntentionMarks);
  $GraphLogTagAssignmentMarksTableManager get graphLogTagAssignmentMarks =>
      $GraphLogTagAssignmentMarksTableManager(
        _db,
        _db.graphLogTagAssignmentMarks,
      );
  $GraphLogLongTermRelationMarksTableManager
  get graphLogLongTermRelationMarks =>
      $GraphLogLongTermRelationMarksTableManager(
        _db,
        _db.graphLogLongTermRelationMarks,
      );
  $GraphLogActionMarksTableManager get graphLogActionMarks =>
      $GraphLogActionMarksTableManager(_db, _db.graphLogActionMarks);
  $GraphLogDeletedIntentionMarksTableManager
  get graphLogDeletedIntentionMarks =>
      $GraphLogDeletedIntentionMarksTableManager(
        _db,
        _db.graphLogDeletedIntentionMarks,
      );
  $GraphLogDeletedRelationPairMarksTableManager
  get graphLogDeletedRelationPairMarks =>
      $GraphLogDeletedRelationPairMarksTableManager(
        _db,
        _db.graphLogDeletedRelationPairMarks,
      );
  $GraphSnapshotsTableManager get graphSnapshots =>
      $GraphSnapshotsTableManager(_db, _db.graphSnapshots);
  $GraphLogPackagesTableManager get graphLogPackages =>
      $GraphLogPackagesTableManager(_db, _db.graphLogPackages);
  $GraphBackupsTableManager get graphBackups =>
      $GraphBackupsTableManager(_db, _db.graphBackups);
  $TagsTableManager get tags => $TagsTableManager(_db, _db.tags);
  $IntentionsTableManager get intentions =>
      $IntentionsTableManager(_db, _db.intentions);
  $TagAssignmentsTableManager get tagAssignments =>
      $TagAssignmentsTableManager(_db, _db.tagAssignments);
  $LongTermRelationsTableManager get longTermRelations =>
      $LongTermRelationsTableManager(_db, _db.longTermRelations);
  $ActionsTableManager get actions => $ActionsTableManager(_db, _db.actions);
  $ActionPathItemsTableManager get actionPathItems =>
      $ActionPathItemsTableManager(_db, _db.actionPathItems);
  $DeletedIntentionsTableManager get deletedIntentions =>
      $DeletedIntentionsTableManager(_db, _db.deletedIntentions);
  $DeletedRelationPairsTableManager get deletedRelationPairs =>
      $DeletedRelationPairsTableManager(_db, _db.deletedRelationPairs);
  $IntentionTitlesFtsTableManager get intentionTitlesFts =>
      $IntentionTitlesFtsTableManager(_db, _db.intentionTitlesFts);
}
