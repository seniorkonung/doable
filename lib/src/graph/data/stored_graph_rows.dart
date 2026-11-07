import '../../action/domain/action.dart';
import '../../action/domain/action_id.dart';
import '../../action/domain/action_path.dart';
import '../../action/domain/action_priority.dart';
import '../../action/domain/action_schedule.dart';
import '../../action/domain/action_text.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../intention/domain/intention_text.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../../long_term_relation/domain/long_term_relation_description.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import '../../shared/domain/calendar_date.dart';
import '../../tag/domain/tag.dart';
import '../../tag/domain/tag_assignment.dart';
import '../../tag/domain/tag_color.dart';
import '../../tag/domain/tag_id.dart';
import '../../tag/domain/tag_name.dart';
import '../../tag/domain/tag_position.dart';

// Разбор строк таблиц графа в значения предметной модели. Чтения и команды
// репозитория, захват фактов и чтение записей порциями разбирают столбцы
// таблиц графа только здесь, поэтому строка вне формы хранения везде даёт
// один отказ StoredGraphCorruption. Строка передаётся словарём значений
// столбцов, как его выдаёт запрос.

/// Сохранённые данные графа не соответствуют форме хранения или
/// согласованности, которую обеспечивают схема и единый путь записи:
/// например, идентификатор, который схема не проверяет, хранится вне своей
/// формы.
///
/// Чтения и команды графа относят этот отказ к повреждению данных. Отказ не
/// несёт прочитанных данных: в них пользовательский текст.
final class StoredGraphCorruption implements Exception {
  const StoredGraphCorruption();
}

String requiredStoredString(Map<String, Object?> data, String column) {
  final value = data[column];
  if (value is String) return value;
  throw const StoredGraphCorruption();
}

int requiredStoredInteger(Map<String, Object?> data, String column) {
  final value = data[column];
  if (value is int) return value;
  throw const StoredGraphCorruption();
}

String? _nullableStoredString(Map<String, Object?> data, String column) {
  final value = data[column];
  if (value is String?) return value;
  throw const StoredGraphCorruption();
}

// Идентификаторы сущностей схема хранит текстом и не проверяет.

TagId decodeStoredTagId(String value) => switch (TagId.decode(value)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw const StoredGraphCorruption(),
};

IntentionId decodeStoredIntentionId(String value) =>
    switch (IntentionId.decode(value)) {
      IntentionIdDecodingSuccess(:final id) => id,
      InvalidIntentionIdDecoding() => throw const StoredGraphCorruption(),
    };

LongTermRelationId decodeStoredRelationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() =>
        throw const StoredGraphCorruption(),
    };

ActionId decodeStoredActionId(String value) => switch (ActionId.decode(value)) {
  ActionIdDecodingSuccess(:final id) => id,
  InvalidActionIdDecoding() => throw const StoredGraphCorruption(),
};

/// Тег из столбцов `id`, `name`, `color` и `position`. Название проверяет
/// `CHECK` схемы той же функцией [TagName.fromStored], поэтому здесь оно
/// только преобразуется в тип.
Tag decodeStoredTag(Map<String, Object?> data) => Tag(
  id: decodeStoredTagId(requiredStoredString(data, 'id')),
  name: TagName.fromStored(requiredStoredString(data, 'name')),
  color: _decodeStoredTagColor(data),
  position: decodeStoredTagPosition(requiredStoredString(data, 'position')),
);

/// `CHECK` схемы проверяет только алфавит ключа, поэтому каноническую форму
/// проверяет разбор.
TagPosition decodeStoredTagPosition(String value) =>
    switch (TagPosition.decode(value)) {
      TagPositionDecodingSuccess(:final position) => position,
      NonCanonicalTagPositionDecoding() => throw const StoredGraphCorruption(),
    };

/// SQL `NULL` — тег без цвета. Строка без столбца `color` — проекция,
/// забывшая цвет, а не тег без цвета, поэтому она тоже даёт отказ.
TagColor? _decodeStoredTagColor(Map<String, Object?> data) {
  if (!data.containsKey('color')) throw const StoredGraphCorruption();
  return switch (data['color']) {
    null => null,
    final String code => switch (TagColor.decode(code)) {
      TagColorDecodingSuccess(:final color) => color,
      UnknownTagColorDecoding() => throw const StoredGraphCorruption(),
    },
    _ => throw const StoredGraphCorruption(),
  };
}

/// Намерение из столбцов таблицы `intentions`, имена которых в строке
/// начинаются с [prefix]. Название и описание хранятся в той форме, к
/// которой их приводит ввод. Фабрика [Intention] нормализует текст так же,
/// как ввод, поэтому текст в другой форме отличается от прочитанного.
Intention decodeStoredIntention(
  Map<String, Object?> data, [
  String prefix = '',
]) {
  final title = requiredStoredString(data, '${prefix}title');
  final description = _nullableStoredString(data, '${prefix}description');
  final Intention intention;
  try {
    intention = Intention(
      id: decodeStoredIntentionId(requiredStoredString(data, '${prefix}id')),
      title: title,
      description: description,
      readiness: decodeStoredIntentionReadiness(
        data,
        '${prefix}is_action_ready',
      ),
      archiveState: decodeStoredIntentionArchiveState(
        data,
        '${prefix}is_archived',
      ),
      createdAt: _decodeStoredIntentionTimestamp(data, '${prefix}created_at'),
      updatedAt: _decodeStoredIntentionTimestamp(data, '${prefix}updated_at'),
    );
  } on IntentionTextValidationException {
    throw const StoredGraphCorruption();
  }
  if (intention.title != title || intention.description != description) {
    throw const StoredGraphCorruption();
  }
  return intention;
}

/// Название намерения из столбца [column]. Оно хранится в той форме, к
/// которой его приводит ввод.
String decodeStoredIntentionTitle(Map<String, Object?> data, String column) {
  final stored = requiredStoredString(data, column);
  final String normalized;
  try {
    normalized = IntentionText.normalizeTitle(stored);
  } on IntentionTextValidationException {
    throw const StoredGraphCorruption();
  }
  if (normalized != stored) throw const StoredGraphCorruption();
  return stored;
}

IntentionReadiness decodeStoredIntentionReadiness(
  Map<String, Object?> data,
  String column,
) => switch (requiredStoredInteger(data, column)) {
  0 => IntentionReadiness.notReady,
  1 => IntentionReadiness.ready,
  _ => throw const StoredGraphCorruption(),
};

IntentionArchiveState decodeStoredIntentionArchiveState(
  Map<String, Object?> data,
  String column,
) => switch (requiredStoredInteger(data, column)) {
  0 => IntentionArchiveState.active,
  1 => IntentionArchiveState.archived,
  _ => throw const StoredGraphCorruption(),
};

IntentionTimestamp _decodeStoredIntentionTimestamp(
  Map<String, Object?> data,
  String column,
) => IntentionTimestamp(_decodeStoredInstant(data, column));

RelationTimestamp _decodeStoredRelationTimestamp(
  Map<String, Object?> data,
  String column,
) => RelationTimestamp(_decodeStoredInstant(data, column));

/// Момент из столбца [column], который хранит микросекунды эпохи.
DateTime _decodeStoredInstant(Map<String, Object?> data, String column) {
  final microseconds = requiredStoredInteger(data, column);
  try {
    return DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
  } on ArgumentError {
    throw const StoredGraphCorruption();
  }
}

/// Ключ поиска из столбца `title_search_key`, который схема вычисляет из
/// названия намерения. Имя столбца в строке начинается с [prefix].
String decodeStoredTitleSearchKey(
  Map<String, Object?> data, [
  String prefix = '',
]) {
  final key = requiredStoredString(data, '${prefix}title_search_key');
  try {
    IntentionText.ensureValidUnicodeRepertoire(
      key,
      field: IntentionTextField.title,
    );
  } on IntentionTextValidationException {
    throw const StoredGraphCorruption();
  }
  if (key.isEmpty) throw const StoredGraphCorruption();
  return key;
}

/// Назначение тега из столбцов `tag_id` и `intention_id`.
TagAssignment decodeStoredTagAssignment(Map<String, Object?> data) =>
    TagAssignment(
      tagId: decodeStoredTagId(requiredStoredString(data, 'tag_id')),
      intentionId: decodeStoredIntentionId(
        requiredStoredString(data, 'intention_id'),
      ),
    );

/// Долговременная связь из столбцов таблицы `long_term_relations`: значения
/// связи модели, показания времени и описание, которого модель связи не
/// несёт.
final class StoredLongTermRelation {
  factory StoredLongTermRelation.decode(Map<String, Object?> data) {
    final creationSequence = requiredStoredInteger(data, 'creation_sequence');
    if (creationSequence <= 0) throw const StoredGraphCorruption();
    final id = decodeStoredRelationId(requiredStoredString(data, 'id'));
    final ends = decodeStoredRelationEnds(data);
    final type = decodeStoredRelationType(data);
    final priority = switch (requiredStoredInteger(data, 'priority')) {
      1 => RelationPriority.p1,
      2 => RelationPriority.p2,
      3 => RelationPriority.p3,
      4 => RelationPriority.p4,
      _ => throw const StoredGraphCorruption(),
    };
    final scope = decodeStoredRelationScope(data);
    final description = _nullableStoredString(data, 'description');
    final createdAt = _decodeStoredRelationTimestamp(data, 'created_at');
    final updatedAt = _decodeStoredRelationTimestamp(data, 'updated_at');
    LongTermRelationDescription? verifiedDescription;
    if (description != null) {
      try {
        verifiedDescription =
            LongTermRelationDescription.fromInput(description) ??
            (throw const StoredGraphCorruption());
      } on LongTermRelationTextValidationException {
        throw const StoredGraphCorruption();
      }
    }

    return StoredLongTermRelation._(
      creationSequence: creationSequence,
      id: id,
      sourceIntentionId: ends.source,
      relatedIntentionId: ends.related,
      type: type,
      priority: priority,
      scope: scope,
      description: verifiedDescription,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  const StoredLongTermRelation._({
    required this.creationSequence,
    required this.id,
    required this.sourceIntentionId,
    required this.relatedIntentionId,
    required this.type,
    required this.priority,
    required this.scope,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  final int creationSequence;
  final LongTermRelationId id;
  final IntentionId sourceIntentionId;
  final IntentionId relatedIntentionId;
  final LongTermRelationType type;
  final RelationPriority priority;
  final RelationScope scope;
  final LongTermRelationDescription? description;
  final RelationTimestamp createdAt;
  final RelationTimestamp updatedAt;

  bool get hasDescription => description != null;

  LongTermRelation toDomain() {
    try {
      return LongTermRelation(
        id: id,
        sourceIntentionId: sourceIntentionId,
        relatedIntentionId: relatedIntentionId,
        type: type,
        priority: priority,
        scope: scope,
        creationSequence: RelationCreationSequence(creationSequence),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } on LongTermRelationValidationException {
      throw const StoredGraphCorruption();
    } on RelationCreationSequenceValidationException {
      throw const StoredGraphCorruption();
    }
  }
}

/// Концы связи из столбцов `source_intention_id` и `related_intention_id`.
({IntentionId source, IntentionId related}) decodeStoredRelationEnds(
  Map<String, Object?> data,
) => (
  source: decodeStoredIntentionId(
    requiredStoredString(data, 'source_intention_id'),
  ),
  related: decodeStoredIntentionId(
    requiredStoredString(data, 'related_intention_id'),
  ),
);

/// Тип связи из столбца `type`.
LongTermRelationType decodeStoredRelationType(Map<String, Object?> data) =>
    switch (requiredStoredString(data, 'type')) {
      'need' => LongTermRelationType.need,
      'can' => LongTermRelationType.can,
      _ => throw const StoredGraphCorruption(),
    };

/// Охват связи из столбца `is_archived`.
RelationScope decodeStoredRelationScope(Map<String, Object?> data) =>
    switch (requiredStoredInteger(data, 'is_archived')) {
      0 => RelationScope.active,
      1 => RelationScope.archived,
      _ => throw const StoredGraphCorruption(),
    };

/// Поля действия из столбцов таблицы `actions`, общие для полного действия и
/// строки выдачи дня.
typedef StoredActionFields = ({
  ActionId id,
  ActionTitle title,
  ActionDescription? description,
  CalendarDate date,
  ActionSchedule schedule,
  ActionPriority priority,
  bool isCompleted,
});

/// Название и описание хранятся в той форме, к которой их приводит ввод.
StoredActionFields decodeStoredActionFields(Map<String, Object?> data) {
  final title = requiredStoredString(data, 'title');
  final description = _nullableStoredString(data, 'description');
  try {
    final fields = (
      id: decodeStoredActionId(requiredStoredString(data, 'id')),
      title: ActionTitle(title),
      description: description == null
          ? null
          : ActionDescription.fromInput(description) ??
                (throw const StoredGraphCorruption()),
      date: CalendarDate.parseCanonical(requiredStoredString(data, 'date')),
      schedule: switch (data['scheduled_hour']) {
        null => const ActionAllDay(),
        final int hour => ActionAtHour(hour),
        _ => throw const StoredGraphCorruption(),
      },
      priority: switch (requiredStoredInteger(data, 'priority')) {
        1 => ActionPriority.p1,
        2 => ActionPriority.p2,
        3 => ActionPriority.p3,
        4 => ActionPriority.p4,
        _ => throw const StoredGraphCorruption(),
      },
      isCompleted: decodeStoredActionCompletion(data),
    );
    if (fields.title.value != title ||
        fields.description?.value != description) {
      throw const StoredGraphCorruption();
    }
    return fields;
  } on IntentionTextValidationException {
    throw const StoredGraphCorruption();
  } on CalendarDateValidationException {
    throw const StoredGraphCorruption();
  } on ArgumentError {
    throw const StoredGraphCorruption();
  }
}

/// Действие из столбцов таблицы `actions` и строк его пути из
/// `action_path_items` в порядке позиций. Путь непуст, позиции идут подряд с
/// нуля, а `previous_intention_id` повторяет намерение предыдущей позиции.
Action decodeStoredAction(
  Map<String, Object?> data,
  Iterable<Map<String, Object?>> pathRows,
) {
  final fields = decodeStoredActionFields(data);
  try {
    return Action(
      id: fields.id,
      title: fields.title,
      description: fields.description,
      path: _decodeStoredActionPath(pathRows),
      date: fields.date,
      schedule: fields.schedule,
      priority: fields.priority,
      isCompleted: fields.isCompleted,
      creationSequence: ActionCreationSequence(
        requiredStoredInteger(data, 'creation_sequence'),
      ),
      createdAt: ActionTimestamp(_decodeStoredInstant(data, 'created_at')),
      updatedAt: ActionTimestamp(_decodeStoredInstant(data, 'updated_at')),
    );
  } on ArgumentError {
    throw const StoredGraphCorruption();
  }
}

ActionPath _decodeStoredActionPath(Iterable<Map<String, Object?>> rows) {
  final intentions = <IntentionId>[];
  for (final row in rows) {
    final previous = _nullableStoredString(row, 'previous_intention_id');
    if (requiredStoredInteger(row, 'position') != intentions.length ||
        previous != intentions.lastOrNull?.toCanonicalString()) {
      throw const StoredGraphCorruption();
    }
    intentions.add(
      decodeStoredIntentionId(requiredStoredString(row, 'intention_id')),
    );
  }
  return ActionPath(intentions);
}

/// Дата действия из столбца `date`.
CalendarDate decodeStoredActionDate(Map<String, Object?> data) {
  final value = requiredStoredString(data, 'date');
  try {
    return CalendarDate.parseCanonical(value);
  } on CalendarDateValidationException {
    throw const StoredGraphCorruption();
  }
}

/// Выполнение действия из столбца `is_completed`.
bool decodeStoredActionCompletion(Map<String, Object?> data) =>
    switch (requiredStoredInteger(data, 'is_completed')) {
      0 => false,
      1 => true,
      _ => throw const StoredGraphCorruption(),
    };
