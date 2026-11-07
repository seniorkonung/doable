import 'dart:convert';
import 'dart:typed_data';

import '../action/domain/action.dart';
import '../action/domain/action_id.dart';
import '../action/domain/action_path.dart';
import '../action/domain/action_priority.dart';
import '../action/domain/action_schedule.dart';
import '../action/domain/action_text.dart';
import '../intention/domain/intention.dart';
import '../intention/domain/intention_id.dart';
import '../intention/domain/intention_text.dart';
import '../long_term_relation/domain/long_term_relation.dart';
import '../long_term_relation/domain/long_term_relation_description.dart';
import '../long_term_relation/domain/long_term_relation_id.dart';
import '../shared/domain/calendar_date.dart';
import '../tag/domain/tag.dart';
import '../tag/domain/tag_assignment.dart';
import '../tag/domain/tag_color.dart';
import '../tag/domain/tag_id.dart';
import '../tag/domain/tag_name.dart';
import '../tag/domain/tag_position.dart';
import 'graph_format_records.dart';

/// Предел записи: наибольшая длина одной записи в байтах UTF-8 без перевода
/// строки.
///
/// 1 МиБ — наименьшее допустимое значение, выбранное бенчмарком лога
/// фактов: файл из записей на пределе читается не большей памятью, чем тот
/// же объём записей по 64 КиБ, а реалистичная запись не длиннее 150 КБ.
/// Строка читается целиком, поэтому больший предел увеличил бы память
/// чтения в худшем случае без пользы. Следующие версии формата предел не
/// снижают, иначе ранее записанные носители перестанут читаться.
const int graphFormatRecordByteLimit = 1024 * 1024;

/// Повышает запись версии N до записей версии N + 1.
typedef _RecordUpgrade = List<Map<String, Object?>> Function(
  Map<String, Object?> record,
);

/// Цепочка повышения, общая для всех носителей: элемент N - 1 повышает
/// версию N. Функции не удаляются, иначе носители прежних версий перестанут
/// читаться.
const List<_RecordUpgrade> _recordUpgrades = [];

/// Версия формата, которую несёт носитель записей: файл, снимок или пакет
/// фактов.
final class GraphFormatVersion {
  const GraphFormatVersion._(this.number);

  /// Проверяет версию, прочитанную из носителя.
  factory GraphFormatVersion.ofCarrier(int number) {
    if (number < 1) throw const GraphFormatCorruption();
    if (number > current.number) throw const GraphFormatVersionTooNew();
    return GraphFormatVersion._(number);
  }

  /// Новая версия появляется вместе с функцией повышения до неё.
  static final GraphFormatVersion current = GraphFormatVersion._(
    _recordUpgrades.length + 1,
  );

  final int number;
}

/// Данные не являются записями формата или повреждены.
///
/// Отказ не несёт прочитанных данных: в них пользовательский текст.
final class GraphFormatCorruption implements Exception {
  const GraphFormatCorruption();
}

/// Носитель записан более новой версией формата, чем текущая.
final class GraphFormatVersionTooNew implements Exception {
  const GraphFormatVersionTooNew();
}

/// Запись длиннее [graphFormatRecordByteLimit].
final class GraphRecordTooLong implements Exception {
  const GraphRecordTooLong();
}

/// Каноническое кодирование «запись ↔ объект JSON»: фиксированный порядок
/// полей, поэтому одно состояние всегда даёт одни байты.
abstract final class GraphFormatCodec {
  static final _jsonFromUtf8 = const Utf8Decoder().fuse(const JsonDecoder());

  /// Отклоняет запись длиннее предела отказом [GraphRecordTooLong].
  static Uint8List encode(GraphEntityRecord record) {
    final bytes = utf8.encode(jsonEncode(_writeRecord(record)));
    if (bytes.length > graphFormatRecordByteLimit) {
      throw const GraphRecordTooLong();
    }
    return bytes;
  }

  /// Пакет фактов — их упорядоченная последовательность, каждый факт на
  /// своей строке.
  ///
  /// Факт «создана» или «изменена» — объект записи сущности с видом факта
  /// первым полем. Предел проверяется у самой записи, поэтому сущность с
  /// записью на пределе сохраняется, а её запись читается из файла формата.
  static Uint8List encodePackage(Iterable<GraphFact> facts) {
    final bytes = BytesBuilder(copy: false);
    for (final fact in facts) {
      switch (fact) {
        case GraphEntityCreated(:final record):
          _addRecordFact(bytes, _createdFactStart, record);
        case GraphEntityChanged(:final record):
          _addRecordFact(bytes, _changedFactStart, record);
        case GraphEntityDeleted(:final entity):
          bytes.add(
            utf8.encode(
              jsonEncode({'fact': _deletedFact, ..._writeEntityKey(entity)}),
            ),
          );
      }
      bytes.addByte(_lineFeed);
    }
    return bytes.takeBytes();
  }

  /// Дописывает к [bytes] начало объекта факта [factStart] и поля записи
  /// [record] без открывающей скобки её объекта.
  static void _addRecordFact(
    BytesBuilder bytes,
    Uint8List factStart,
    GraphEntityRecord record,
  ) {
    final encoded = encode(record);
    bytes
      ..add(factStart)
      ..add(Uint8List.sublistView(encoded, 1));
  }

  /// Заголовок всегда пишется текущей версией формата.
  static Uint8List encodeHeader(GraphFormatHeader header) {
    final counts = header.counts;
    return utf8.encode(
      jsonEncode({
        'format': _formatMarker,
        'version': GraphFormatVersion.current.number,
        'writtenAt': _writeTimestamp(header.writtenAt),
        'counts': {
          'tags': counts.tags,
          'intentions': counts.intentions,
          'deletedIntentions': counts.deletedIntentions,
          'tagAssignments': counts.tagAssignments,
          'longTermRelations': counts.longTermRelations,
          'deletedRelationPairs': counts.deletedRelationPairs,
          'actions': counts.actions,
        },
      }),
    );
  }

  /// Читает заголовок файла или снимка вместе с версией его записей.
  ///
  /// Маркер и версия проверяются раньше остальных полей: заголовок более
  /// новой версии может быть устроен иначе.
  static ({GraphFormatVersion version, GraphFormatHeader header}) decodeHeader(
    List<int> line,
  ) {
    final json = _readJson(line);
    final number = json['version'];
    if (json['format'] != _formatMarker || number is! int) {
      throw const GraphFormatCorruption();
    }
    final version = GraphFormatVersion.ofCarrier(number);
    final header = _readObject(json, (fields) {
      fields
        ..string('format')
        ..integer('version');
      return GraphFormatHeader(
        writtenAt: _readTimestamp(fields.string('writtenAt')),
        counts: _readCounts(fields.object('counts')),
      );
    });
    return (version: version, header: header);
  }

  /// Читает строку файла или снимка версии [version] в записи текущей версии.
  static List<GraphEntityRecord> decodeEntityRecord(
    List<int> line,
    GraphFormatVersion version,
  ) => [
    for (final object in _readCurrentVersion(line, version))
      _readObject(
        object,
        (fields) => _readEntity(fields.string('kind'), fields),
      ),
  ];

  /// Читает факт пакета версии [version] в факты текущей версии.
  static List<GraphFact> decodeFact(
    List<int> line,
    GraphFormatVersion version,
  ) => [
    for (final object in _readCurrentVersion(line, version))
      _readObject(object, _readFact),
  ];

  /// Читает пакет фактов версии [version] в факты текущей версии.
  static List<GraphFact> decodePackage(
    List<int> payload,
    GraphFormatVersion version,
  ) {
    final facts = <GraphFact>[];
    var start = 0;
    while (start < payload.length) {
      final end = payload.indexOf(_lineFeed, start);
      if (end < 0) throw const GraphFormatCorruption();
      facts.addAll(decodeFact(payload.sublist(start, end), version));
      start = end + 1;
    }
    return facts;
  }

  static Map<String, Object?> _readJson(List<int> line) {
    final Object? json;
    try {
      json = _jsonFromUtf8.convert(line);
    } on FormatException {
      throw const GraphFormatCorruption();
    }
    if (json is! Map<String, Object?>) throw const GraphFormatCorruption();
    return json;
  }

  static List<Map<String, Object?>> _readCurrentVersion(
    List<int> line,
    GraphFormatVersion version,
  ) {
    var objects = [_readJson(line)];
    for (
      var number = version.number;
      number < GraphFormatVersion.current.number;
      number++
    ) {
      objects = [
        for (final object in objects) ..._recordUpgrades[number - 1](object),
      ];
    }
    return objects;
  }

  /// Отказы предметных типов означают недопустимое значение поля.
  static T _readObject<T>(
    Map<String, Object?> object,
    T Function(_JsonFields fields) read,
  ) {
    final fields = _JsonFields(object);
    try {
      final value = read(fields);
      fields.ensureAllRead();
      return value;
    } on IntentionTextValidationException {
      throw const GraphFormatCorruption();
    } on TagNameValidationException {
      throw const GraphFormatCorruption();
    } on LongTermRelationTextValidationException {
      throw const GraphFormatCorruption();
    } on CalendarDateValidationException {
      throw const GraphFormatCorruption();
    } on ArgumentError {
      throw const GraphFormatCorruption();
    }
  }
}

const _lineFeed = 0x0a;

const _formatMarker = 'doable-graph';

const _tagKind = 'tag';
const _intentionKind = 'intention';
const _deletedIntentionKind = 'deletedIntention';
const _tagAssignmentKind = 'tagAssignment';
const _relationKind = 'longTermRelation';
const _deletedRelationPairKind = 'deletedRelationPair';
const _actionKind = 'action';

const _createdFact = 'created';
const _changedFact = 'changed';
const _deletedFact = 'deleted';

/// Начала объектов фактов с записью: поле вида факта и разделитель перед
/// полями записи.
final _createdFactStart = utf8.encode('{"fact":"$_createdFact",');
final _changedFactStart = utf8.encode('{"fact":"$_changedFact",');

Map<String, Object?> _writeRecord(GraphEntityRecord record) => switch (record) {
  TagRecord(:final tag) => {
    'kind': _tagKind,
    'id': tag.id.toCanonicalString(),
    'name': tag.name.value,
    'color': tag.color?.code,
    'position': tag.position.value,
  },
  IntentionRecord(:final intention) => {
    'kind': _intentionKind,
    'id': intention.id.toCanonicalString(),
    'title': intention.title,
    'description': intention.description,
    'intentionKind': intention.kind.name,
    'actionReady': switch (intention.readiness) {
      IntentionReadiness.notReady => false,
      IntentionReadiness.ready => true,
    },
    'archived': switch (intention.archiveState) {
      IntentionArchiveState.active => false,
      IntentionArchiveState.archived => true,
    },
    'createdAt': _writeTimestamp(intention.createdAt.value),
    'updatedAt': _writeTimestamp(intention.updatedAt.value),
  },
  DeletedIntentionRecord(:final id, :final title) => {
    'kind': _deletedIntentionKind,
    'id': id.toCanonicalString(),
    'title': title,
  },
  TagAssignmentRecord(:final assignment) => {
    'kind': _tagAssignmentKind,
    ..._writeTagAssignment(assignment),
  },
  final LongTermRelationRecord relation => {
    'kind': _relationKind,
    'id': relation.id.toCanonicalString(),
    'sourceIntentionId': relation.sourceIntentionId.toCanonicalString(),
    'relatedIntentionId': relation.relatedIntentionId.toCanonicalString(),
    'type': _writeRelationType(relation.type),
    'priority': switch (relation.priority) {
      RelationPriority.p1 => 'P1',
      RelationPriority.p2 => 'P2',
      RelationPriority.p3 => 'P3',
      RelationPriority.p4 => 'P4',
    },
    'description': relation.description?.value,
    'archived': switch (relation.scope) {
      RelationScope.active => false,
      RelationScope.archived => true,
    },
    'createdAt': _writeTimestamp(relation.createdAt.value),
    'updatedAt': _writeTimestamp(relation.updatedAt.value),
  },
  DeletedRelationPairRecord(
    :final sourceIntentionId,
    :final relatedIntentionId,
    :final type,
  ) =>
    {
      'kind': _deletedRelationPairKind,
      'sourceIntentionId': sourceIntentionId.toCanonicalString(),
      'relatedIntentionId': relatedIntentionId.toCanonicalString(),
      'type': _writeRelationType(type),
    },
  final ActionRecord action => {
    'kind': _actionKind,
    'id': action.id.toCanonicalString(),
    'title': action.title.value,
    'description': action.description?.value,
    'date': action.date.toCanonicalString(),
    // `null` — «Весь день».
    'hour': switch (action.schedule) {
      ActionAllDay() => null,
      ActionAtHour(:final hour) => hour,
    },
    'priority': switch (action.priority) {
      ActionPriority.p1 => 'P1',
      ActionPriority.p2 => 'P2',
      ActionPriority.p3 => 'P3',
      ActionPriority.p4 => 'P4',
    },
    'completed': action.isCompleted,
    'path': [
      for (final intentionId in action.path.intentions)
        intentionId.toCanonicalString(),
    ],
    'createdAt': _writeTimestamp(action.createdAt.value),
    'updatedAt': _writeTimestamp(action.updatedAt.value),
  },
};

String _writeRelationType(LongTermRelationType type) => switch (type) {
  LongTermRelationType.need => 'need',
  LongTermRelationType.can => 'can',
};

Map<String, Object?> _writeEntityKey(GraphEntityKey entity) => switch (entity) {
  TagKey(:final id) => {'entity': _tagKind, 'id': id.toCanonicalString()},
  IntentionKey(:final id) => {
    'entity': _intentionKind,
    'id': id.toCanonicalString(),
  },
  DeletedIntentionKey(:final id) => {
    'entity': _deletedIntentionKind,
    'id': id.toCanonicalString(),
  },
  TagAssignmentKey(:final assignment) => {
    'entity': _tagAssignmentKind,
    ..._writeTagAssignment(assignment),
  },
  LongTermRelationKey(:final id) => {
    'entity': _relationKind,
    'id': id.toCanonicalString(),
  },
  DeletedRelationPairKey(:final sourceIntentionId, :final relatedIntentionId) =>
    {
      'entity': _deletedRelationPairKind,
      'sourceIntentionId': sourceIntentionId.toCanonicalString(),
      'relatedIntentionId': relatedIntentionId.toCanonicalString(),
    },
  ActionKey(:final id) => {'entity': _actionKind, 'id': id.toCanonicalString()},
};

Map<String, Object?> _writeTagAssignment(TagAssignment assignment) => {
  'tagId': assignment.tagId.toCanonicalString(),
  'intentionId': assignment.intentionId.toCanonicalString(),
};

/// Момент [value] в UTC в ISO-8601 с микросекундами. Показания часов
/// устройства укладываются в четырёхзначный год.
String _writeTimestamp(DateTime value) =>
    '${_digits(value.year, 4)}-${_digits(value.month, 2)}-'
    '${_digits(value.day, 2)}T${_digits(value.hour, 2)}:'
    '${_digits(value.minute, 2)}:${_digits(value.second, 2)}.'
    '${_digits(value.millisecond * 1000 + value.microsecond, 6)}Z';

String _digits(int value, int width) => value.toString().padLeft(width, '0');

GraphFact _readFact(_JsonFields fields) => switch (fields.string('fact')) {
  _createdFact => GraphEntityCreated(
    _readEntity(fields.string('kind'), fields),
  ),
  _changedFact => GraphEntityChanged(
    _readEntity(fields.string('kind'), fields),
  ),
  _deletedFact => GraphEntityDeleted(_readEntityKey(fields)),
  _ => throw const GraphFormatCorruption(),
};

GraphEntityRecord _readEntity(String kind, _JsonFields fields) =>
    switch (kind) {
      _tagKind => TagRecord(
        Tag(
          id: _readTagId(fields.string('id')),
          name: TagName.fromStored(fields.string('name')),
          color: _readTagColor(fields.nullableString('color')),
          position: _readTagPosition(fields.string('position')),
        ),
      ),
      _intentionKind => IntentionRecord(_readIntention(fields)),
      _deletedIntentionKind => DeletedIntentionRecord(
        id: _readIntentionId(fields.string('id')),
        title: _readIntentionTitle(fields.string('title')),
      ),
      _tagAssignmentKind => TagAssignmentRecord(_readTagAssignment(fields)),
      _relationKind => _readRelation(fields),
      _deletedRelationPairKind => DeletedRelationPairRecord(
        sourceIntentionId: _readIntentionId(fields.string('sourceIntentionId')),
        relatedIntentionId: _readIntentionId(
          fields.string('relatedIntentionId'),
        ),
        type: _readRelationType(fields.string('type')),
      ),
      _actionKind => _readAction(fields),
      _ => throw const GraphFormatCorruption(),
    };

GraphEntityKey _readEntityKey(_JsonFields fields) => switch (fields.string(
  'entity',
)) {
  _tagKind => TagKey(_readTagId(fields.string('id'))),
  _intentionKind => IntentionKey(_readIntentionId(fields.string('id'))),
  _deletedIntentionKind => DeletedIntentionKey(
    _readIntentionId(fields.string('id')),
  ),
  _tagAssignmentKind => TagAssignmentKey(_readTagAssignment(fields)),
  _relationKind => LongTermRelationKey(_readRelationId(fields.string('id'))),
  _deletedRelationPairKind => DeletedRelationPairKey(
    sourceIntentionId: _readIntentionId(fields.string('sourceIntentionId')),
    relatedIntentionId: _readIntentionId(fields.string('relatedIntentionId')),
  ),
  _actionKind => ActionKey(_readActionId(fields.string('id'))),
  _ => throw const GraphFormatCorruption(),
};

/// Название и описание хранятся в той форме, к которой их приводит ввод.
Intention _readIntention(_JsonFields fields) {
  final description = fields.nullableString('description');
  if (description != null &&
      IntentionText.normalizeDescription(description) != description) {
    throw const GraphFormatCorruption();
  }
  return Intention(
    id: _readIntentionId(fields.string('id')),
    title: _readIntentionTitle(fields.string('title')),
    description: description,
    kind: switch (fields.string('intentionKind')) {
      'main' => IntentionKind.main,
      'supporting' => IntentionKind.supporting,
      _ => throw const GraphFormatCorruption(),
    },
    readiness: fields.boolean('actionReady')
        ? IntentionReadiness.ready
        : IntentionReadiness.notReady,
    archiveState: fields.boolean('archived')
        ? IntentionArchiveState.archived
        : IntentionArchiveState.active,
    createdAt: IntentionTimestamp(_readTimestamp(fields.string('createdAt'))),
    updatedAt: IntentionTimestamp(_readTimestamp(fields.string('updatedAt'))),
  );
}

String _readIntentionTitle(String title) {
  if (IntentionText.normalizeTitle(title) != title) {
    throw const GraphFormatCorruption();
  }
  return title;
}

TagAssignment _readTagAssignment(_JsonFields fields) => TagAssignment(
  tagId: _readTagId(fields.string('tagId')),
  intentionId: _readIntentionId(fields.string('intentionId')),
);

LongTermRelationRecord _readRelation(_JsonFields fields) {
  final description = fields.nullableString('description');
  return LongTermRelationRecord(
    id: _readRelationId(fields.string('id')),
    sourceIntentionId: _readIntentionId(fields.string('sourceIntentionId')),
    relatedIntentionId: _readIntentionId(fields.string('relatedIntentionId')),
    type: _readRelationType(fields.string('type')),
    priority: switch (fields.string('priority')) {
      'P1' => RelationPriority.p1,
      'P2' => RelationPriority.p2,
      'P3' => RelationPriority.p3,
      'P4' => RelationPriority.p4,
      _ => throw const GraphFormatCorruption(),
    },
    description: description == null
        ? null
        : LongTermRelationDescription.fromInput(description) ??
              (throw const GraphFormatCorruption()),
    scope: fields.boolean('archived')
        ? RelationScope.archived
        : RelationScope.active,
    createdAt: RelationTimestamp(_readTimestamp(fields.string('createdAt'))),
    updatedAt: RelationTimestamp(_readTimestamp(fields.string('updatedAt'))),
  );
}

LongTermRelationType _readRelationType(String text) => switch (text) {
  'need' => LongTermRelationType.need,
  'can' => LongTermRelationType.can,
  _ => throw const GraphFormatCorruption(),
};

/// Название и описание хранятся в той форме, к которой их приводит ввод.
ActionRecord _readAction(_JsonFields fields) {
  final id = _readActionId(fields.string('id'));
  final storedTitle = fields.string('title');
  final title = ActionTitle(storedTitle);
  final storedDescription = fields.nullableString('description');
  final description = storedDescription == null
      ? null
      : ActionDescription.fromInput(storedDescription);
  if (title.value != storedTitle || description?.value != storedDescription) {
    throw const GraphFormatCorruption();
  }
  return ActionRecord(
    id: id,
    title: title,
    description: description,
    date: CalendarDate.parseCanonical(fields.string('date')),
    schedule: switch (fields.nullableInteger('hour')) {
      null => const ActionAllDay(),
      final hour => ActionAtHour(hour),
    },
    priority: switch (fields.string('priority')) {
      'P1' => ActionPriority.p1,
      'P2' => ActionPriority.p2,
      'P3' => ActionPriority.p3,
      'P4' => ActionPriority.p4,
      _ => throw const GraphFormatCorruption(),
    },
    isCompleted: fields.boolean('completed'),
    path: ActionPath([
      for (final intentionId in fields.strings('path'))
        _readIntentionId(intentionId),
    ]),
    createdAt: ActionTimestamp(_readTimestamp(fields.string('createdAt'))),
    updatedAt: ActionTimestamp(_readTimestamp(fields.string('updatedAt'))),
  );
}

final _timestampPattern = RegExp(
  r'^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})\.([0-9]{6})Z$',
);

DateTime _readTimestamp(String text) {
  final match =
      _timestampPattern.firstMatch(text) ??
      (throw const GraphFormatCorruption());
  int part(int group) => int.parse(match.group(group)!);
  final fraction = part(7);
  final timestamp = DateTime.utc(
    part(1),
    part(2),
    part(3),
    part(4),
    part(5),
    part(6),
    fraction ~/ 1000,
    fraction % 1000,
  );
  // DateTime переносит лишние единицы в старшие разряды, поэтому
  // несуществующий момент записывается иначе, чем прочитан.
  if (_writeTimestamp(timestamp) != text) throw const GraphFormatCorruption();
  return timestamp;
}

GraphRecordCounts _readCounts(Map<String, Object?> object) {
  final fields = _JsonFields(object);
  final counts = GraphRecordCounts(
    tags: fields.integer('tags'),
    intentions: fields.integer('intentions'),
    deletedIntentions: fields.integer('deletedIntentions'),
    tagAssignments: fields.integer('tagAssignments'),
    longTermRelations: fields.integer('longTermRelations'),
    deletedRelationPairs: fields.integer('deletedRelationPairs'),
    actions: fields.integer('actions'),
  );
  fields.ensureAllRead();
  return counts;
}

TagId _readTagId(String text) => switch (TagId.decode(text)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw const GraphFormatCorruption(),
};

/// `null` — «Без цвета»; неизвестный код — повреждение.
TagColor? _readTagColor(String? code) {
  if (code == null) return null;
  return switch (TagColor.decode(code)) {
    TagColorDecodingSuccess(:final color) => color,
    UnknownTagColorDecoding() => throw const GraphFormatCorruption(),
  };
}

/// Неканонический ключ — повреждение: формат не исправляет место.
TagPosition _readTagPosition(String text) => switch (TagPosition.decode(text)) {
  TagPositionDecodingSuccess(:final position) => position,
  NonCanonicalTagPositionDecoding() => throw const GraphFormatCorruption(),
};

IntentionId _readIntentionId(String text) => switch (IntentionId.decode(text)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw const GraphFormatCorruption(),
};

LongTermRelationId _readRelationId(String text) =>
    switch (LongTermRelationId.decode(text)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() =>
        throw const GraphFormatCorruption(),
    };

ActionId _readActionId(String text) => switch (ActionId.decode(text)) {
  ActionIdDecodingSuccess(:final id) => id,
  InvalidActionIdDecoding() => throw const GraphFormatCorruption(),
};

/// Поля объекта записи. Каждое поле обязательно и читается один раз, поэтому
/// непрочитанное поле — неизвестное.
final class _JsonFields {
  _JsonFields(Object? object)
    : _object = object is Map<String, Object?>
          ? object
          : throw const GraphFormatCorruption();

  final Map<String, Object?> _object;
  var _readCount = 0;

  String string(String name) => _read<String>(name);

  String? nullableString(String name) => _read<String?>(name);

  bool boolean(String name) => _read<bool>(name);

  int integer(String name) => _read<int>(name);

  int? nullableInteger(String name) => _read<int?>(name);

  Map<String, Object?> object(String name) => _read<Map<String, Object?>>(name);

  List<Object?> list(String name) => _read<List<Object?>>(name);

  /// Список строк; элемент другого типа делает запись повреждённой.
  List<String> strings(String name) => [
    for (final element in list(name))
      element is String ? element : throw const GraphFormatCorruption(),
  ];

  void ensureAllRead() {
    if (_readCount != _object.length) throw const GraphFormatCorruption();
  }

  T _read<T>(String name) {
    final value = _object[name];
    if (value is! T || !_object.containsKey(name)) {
      throw const GraphFormatCorruption();
    }
    _readCount++;
    return value;
  }
}
