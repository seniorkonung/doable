import 'dart:convert';
import 'dart:typed_data';

import '../daily_choice/domain/calendar_date.dart';
import '../daily_choice/domain/choice_path_step_id.dart';
import '../daily_choice/domain/daily_choice.dart';
import '../daily_choice/domain/daily_choice_description.dart';
import '../daily_choice/domain/daily_choice_id.dart';
import '../daily_choice/domain/daily_choice_priority.dart';
import '../daily_choice/domain/daily_choice_schedule.dart';
import '../intention/domain/intention.dart';
import '../intention/domain/intention_id.dart';
import '../intention/domain/intention_text.dart';
import '../long_term_relation/domain/long_term_relation.dart';
import '../long_term_relation/domain/long_term_relation_description.dart';
import '../long_term_relation/domain/long_term_relation_id.dart';
import '../tag/domain/tag.dart';
import '../tag/domain/tag_assignment.dart';
import '../tag/domain/tag_id.dart';
import '../tag/domain/tag_name.dart';
import 'graph_format_records.dart';

/// Предел записи: наибольшая длина одной записи в байтах UTF-8 без перевода
/// строки.
///
/// Не ниже 1 МиБ; значение выбирается замером памяти чтения. Следующие версии
/// формата предел не снижают, иначе ранее записанные носители перестанут
/// читаться.
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
  static Uint8List encode(GraphFact fact) {
    final bytes = utf8.encode(jsonEncode(_writeFact(fact)));
    if (bytes.length > graphFormatRecordByteLimit) {
      throw const GraphRecordTooLong();
    }
    return bytes;
  }

  /// Пакет фактов — их упорядоченная последовательность, каждый факт на
  /// своей строке.
  static Uint8List encodePackage(Iterable<GraphFact> facts) {
    final bytes = BytesBuilder(copy: false);
    for (final fact in facts) {
      bytes
        ..add(encode(fact))
        ..addByte(_lineFeed);
    }
    return bytes.takeBytes();
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

  static List<Map<String, Object?>> _readCurrentVersion(
    List<int> line,
    GraphFormatVersion version,
  ) {
    final Object? json;
    try {
      json = _jsonFromUtf8.convert(line);
    } on FormatException {
      throw const GraphFormatCorruption();
    }
    if (json is! Map<String, Object?>) throw const GraphFormatCorruption();
    var objects = [json];
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
    } on DailyChoiceDescriptionValidationException {
      throw const GraphFormatCorruption();
    } on CalendarDateValidationException {
      throw const GraphFormatCorruption();
    } on ArgumentError {
      throw const GraphFormatCorruption();
    }
  }
}

const _lineFeed = 0x0a;

const _tagKind = 'tag';
const _intentionKind = 'intention';
const _tagAssignmentKind = 'tagAssignment';
const _relationKind = 'longTermRelation';
const _dailyChoiceKind = 'dailyChoice';
const _deletionKind = 'deletion';

Map<String, Object?> _writeFact(GraphFact fact) => switch (fact) {
  TagRecord(:final tag) => {
    'kind': _tagKind,
    'id': tag.id.toCanonicalString(),
    'name': tag.name.value,
  },
  IntentionRecord(:final intention) => {
    'kind': _intentionKind,
    'id': intention.id.toCanonicalString(),
    'title': intention.title,
    'description': intention.description,
    'actionReady': switch (intention.readiness) {
      IntentionReadiness.notReady => false,
      IntentionReadiness.ready => true,
    },
    'archived': switch (intention.archiveState) {
      IntentionArchiveState.active => false,
      IntentionArchiveState.archived => true,
    },
    'createdAt': _writeTimestamp(intention.createdAt),
    'updatedAt': _writeTimestamp(intention.updatedAt),
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
    'type': switch (relation.type) {
      LongTermRelationType.need => 'need',
      LongTermRelationType.can => 'can',
    },
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
  },
  DailyChoiceRecord(:final choice, :final path) => {
    'kind': _dailyChoiceKind,
    'id': choice.id.toCanonicalString(),
    'sourceIntentionId': choice.sourceIntentionId.toCanonicalString(),
    'selectedIntentionId': choice.selectedIntentionId.toCanonicalString(),
    'date': choice.date.toCanonicalString(),
    'time': switch (choice.schedule) {
      DailyChoiceAllDay() => null,
      DailyChoiceTime(:final hour, :final minute) =>
        '${_digits(hour, 2)}:${_digits(minute, 2)}',
    },
    'priority': switch (choice.priority) {
      DailyChoicePriority.p1 => 'P1',
      DailyChoicePriority.p2 => 'P2',
      DailyChoicePriority.p3 => 'P3',
      DailyChoicePriority.p4 => 'P4',
    },
    'completed': choice.isCompleted,
    'description': choice.description?.value,
    'path': [
      for (final step in path.steps)
        {
          'id': step.id.toCanonicalString(),
          'relationId': step.relationId.toCanonicalString(),
        },
    ],
  },
  GraphEntityDeletion(:final entity) => {
    'kind': _deletionKind,
    ...switch (entity) {
      TagKey(:final id) => {'entity': _tagKind, 'id': id.toCanonicalString()},
      IntentionKey(:final id) => {
        'entity': _intentionKind,
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
      DailyChoiceKey(:final id) => {
        'entity': _dailyChoiceKind,
        'id': id.toCanonicalString(),
      },
    },
  },
};

Map<String, Object?> _writeTagAssignment(TagAssignment assignment) => {
  'tagId': assignment.tagId.toCanonicalString(),
  'intentionId': assignment.intentionId.toCanonicalString(),
};

/// Момент в UTC в ISO-8601 с микросекундами. Показания часов устройства
/// укладываются в четырёхзначный год.
String _writeTimestamp(IntentionTimestamp timestamp) {
  final value = timestamp.value;
  return '${_digits(value.year, 4)}-${_digits(value.month, 2)}-'
      '${_digits(value.day, 2)}T${_digits(value.hour, 2)}:'
      '${_digits(value.minute, 2)}:${_digits(value.second, 2)}.'
      '${_digits(value.millisecond * 1000 + value.microsecond, 6)}Z';
}

String _digits(int value, int width) => value.toString().padLeft(width, '0');

GraphFact _readFact(_JsonFields fields) {
  final kind = fields.string('kind');
  return kind == _deletionKind
      ? GraphEntityDeletion(_readEntityKey(fields))
      : _readEntity(kind, fields);
}

GraphEntityRecord _readEntity(String kind, _JsonFields fields) =>
    switch (kind) {
      _tagKind => TagRecord(
        Tag(
          id: _readTagId(fields.string('id')),
          name: TagName.fromStored(fields.string('name')),
        ),
      ),
      _intentionKind => IntentionRecord(_readIntention(fields)),
      _tagAssignmentKind => TagAssignmentRecord(_readTagAssignment(fields)),
      _relationKind => _readRelation(fields),
      _dailyChoiceKind => _readDailyChoice(fields),
      _ => throw const GraphFormatCorruption(),
    };

GraphEntityKey _readEntityKey(_JsonFields fields) => switch (fields.string(
  'entity',
)) {
  _tagKind => TagKey(_readTagId(fields.string('id'))),
  _intentionKind => IntentionKey(_readIntentionId(fields.string('id'))),
  _tagAssignmentKind => TagAssignmentKey(_readTagAssignment(fields)),
  _relationKind => LongTermRelationKey(_readRelationId(fields.string('id'))),
  _dailyChoiceKind => DailyChoiceKey(_readDailyChoiceId(fields.string('id'))),
  _ => throw const GraphFormatCorruption(),
};

/// Название и описание хранятся в той форме, к которой их приводит ввод.
Intention _readIntention(_JsonFields fields) {
  final title = fields.string('title');
  final description = fields.nullableString('description');
  if (IntentionText.normalizeTitle(title) != title ||
      (description != null &&
          IntentionText.normalizeDescription(description) != description)) {
    throw const GraphFormatCorruption();
  }
  return Intention(
    id: _readIntentionId(fields.string('id')),
    title: title,
    description: description,
    readiness: fields.boolean('actionReady')
        ? IntentionReadiness.ready
        : IntentionReadiness.notReady,
    archiveState: fields.boolean('archived')
        ? IntentionArchiveState.archived
        : IntentionArchiveState.active,
    createdAt: _readTimestamp(fields.string('createdAt')),
    updatedAt: _readTimestamp(fields.string('updatedAt')),
  );
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
    type: switch (fields.string('type')) {
      'need' => LongTermRelationType.need,
      'can' => LongTermRelationType.can,
      _ => throw const GraphFormatCorruption(),
    },
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
  );
}

DailyChoiceRecord _readDailyChoice(_JsonFields fields) {
  final id = _readDailyChoiceId(fields.string('id'));
  final description = fields.nullableString('description');
  final steps = <ChoicePathStep>[];
  ChoicePathStepId? previousStepId;
  for (final element in fields.list('path')) {
    final step = _JsonFields(element);
    final stepId = _readStepId(step.string('id'));
    steps.add(
      ChoicePathStep(
        id: stepId,
        dailyChoiceId: id,
        relationId: _readRelationId(step.string('relationId')),
        previousStepId: previousStepId,
      ),
    );
    step.ensureAllRead();
    previousStepId = stepId;
  }
  return DailyChoiceRecord(
    choice: DailyChoice(
      id: id,
      sourceIntentionId: _readIntentionId(fields.string('sourceIntentionId')),
      selectedIntentionId: _readIntentionId(
        fields.string('selectedIntentionId'),
      ),
      date: CalendarDate.parseCanonical(fields.string('date')),
      description: description == null
          ? null
          : DailyChoiceDescription.fromStored(description),
      isCompleted: fields.boolean('completed'),
      schedule: _readSchedule(fields.nullableString('time')),
      priority: switch (fields.string('priority')) {
        'P1' => DailyChoicePriority.p1,
        'P2' => DailyChoicePriority.p2,
        'P3' => DailyChoicePriority.p3,
        'P4' => DailyChoicePriority.p4,
        _ => throw const GraphFormatCorruption(),
      },
    ),
    path: StoredChoicePath(steps),
  );
}

final _timestampPattern = RegExp(
  r'^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})\.([0-9]{6})Z$',
);

IntentionTimestamp _readTimestamp(String text) {
  final match =
      _timestampPattern.firstMatch(text) ??
      (throw const GraphFormatCorruption());
  int part(int group) => int.parse(match.group(group)!);
  final fraction = part(7);
  final timestamp = IntentionTimestamp(
    DateTime.utc(
      part(1),
      part(2),
      part(3),
      part(4),
      part(5),
      part(6),
      fraction ~/ 1000,
      fraction % 1000,
    ),
  );
  // DateTime переносит лишние единицы в старшие разряды, поэтому
  // несуществующий момент записывается иначе, чем прочитан.
  if (_writeTimestamp(timestamp) != text) throw const GraphFormatCorruption();
  return timestamp;
}

final _timeOfDayPattern = RegExp(r'^([0-9]{2}):([0-9]{2})$');

DailyChoiceSchedule _readSchedule(String? text) {
  if (text == null) return const DailyChoiceAllDay();
  final match =
      _timeOfDayPattern.firstMatch(text) ??
      (throw const GraphFormatCorruption());
  return DailyChoiceTime(
    hour: int.parse(match.group(1)!),
    minute: int.parse(match.group(2)!),
  );
}

TagId _readTagId(String text) => switch (TagId.decode(text)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw const GraphFormatCorruption(),
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

DailyChoiceId _readDailyChoiceId(String text) =>
    switch (DailyChoiceId.decode(text)) {
      DailyChoiceIdDecodingSuccess(:final id) => id,
      InvalidDailyChoiceIdDecoding() => throw const GraphFormatCorruption(),
    };

ChoicePathStepId _readStepId(String text) =>
    switch (ChoicePathStepId.decode(text)) {
      ChoicePathStepIdDecodingSuccess(:final id) => id,
      InvalidChoicePathStepIdDecoding() => throw const GraphFormatCorruption(),
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

  List<Object?> list(String name) => _read<List<Object?>>(name);

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
