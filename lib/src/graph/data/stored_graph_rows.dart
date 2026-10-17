import '../../daily_choice/domain/calendar_date.dart';
import '../../daily_choice/domain/choice_path_step_id.dart';
import '../../daily_choice/domain/daily_choice.dart';
import '../../daily_choice/domain/daily_choice_description.dart';
import '../../daily_choice/domain/daily_choice_id.dart';
import '../../daily_choice/domain/daily_choice_priority.dart';
import '../../daily_choice/domain/daily_choice_schedule.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../intention/domain/intention_text.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../../long_term_relation/domain/long_term_relation_description.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import '../../tag/domain/tag.dart';
import '../../tag/domain/tag_assignment.dart';
import '../../tag/domain/tag_id.dart';
import '../../tag/domain/tag_name.dart';

// Разбор строк таблиц графа в значения предметной модели. Чтения и команды
// репозитория, захват фактов и чтение записей порциями разбирают столбцы
// таблиц графа только здесь, поэтому строка вне формы хранения везде даёт
// один отказ StoredGraphCorruption. Строка передаётся словарём значений
// столбцов, как его выдаёт запрос.

/// Сохранённые данные графа вне формы хранения или нарушают согласованность,
/// которую обеспечивают схема и единый путь записи: например, идентификатор,
/// который схема не проверяет, хранится вне своей формы.
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

DailyChoiceId decodeStoredDailyChoiceId(String value) =>
    switch (DailyChoiceId.decode(value)) {
      DailyChoiceIdDecodingSuccess(:final id) => id,
      InvalidDailyChoiceIdDecoding() => throw const StoredGraphCorruption(),
    };

ChoicePathStepId _decodeStoredChoicePathStepId(String value) =>
    switch (ChoicePathStepId.decode(value)) {
      ChoicePathStepIdDecodingSuccess(:final id) => id,
      InvalidChoicePathStepIdDecoding() => throw const StoredGraphCorruption(),
    };

/// Тег из столбцов `id` и `name`. Название проверяет `CHECK` схемы той же
/// функцией [TagName.fromStored], поэтому здесь оно только преобразуется в
/// тип.
Tag decodeStoredTag(Map<String, Object?> data) => Tag(
  id: decodeStoredTagId(requiredStoredString(data, 'id')),
  name: TagName.fromStored(requiredStoredString(data, 'name')),
);

/// Намерение из столбцов таблицы `intentions`, имена которых в строке
/// начинаются с [prefix].
Intention decodeStoredIntention(
  Map<String, Object?> data, [
  String prefix = '',
]) {
  final description = _nullableStoredString(data, '${prefix}description');
  return Intention(
    id: decodeStoredIntentionId(requiredStoredString(data, '${prefix}id')),
    title: decodeStoredIntentionTitle(data, '${prefix}title'),
    description: description == null
        ? null
        : _storedIntentionText(description, IntentionText.normalizeDescription),
    readiness: decodeStoredIntentionReadiness(data, '${prefix}is_action_ready'),
    archiveState: decodeStoredIntentionArchiveState(
      data,
      '${prefix}is_archived',
    ),
    createdAt: _decodeStoredIntentionTimestamp(data, '${prefix}created_at'),
    updatedAt: _decodeStoredIntentionTimestamp(data, '${prefix}updated_at'),
  );
}

/// Название намерения из столбца [column]. Оно хранится в той форме, к
/// которой его приводит ввод.
String decodeStoredIntentionTitle(Map<String, Object?> data, String column) =>
    _storedIntentionText(
      requiredStoredString(data, column),
      IntentionText.normalizeTitle,
    );

/// Текст намерения [stored], который нормализация [normalize] ввода
/// оставляет без изменений.
String _storedIntentionText(
  String stored,
  String? Function(String value) normalize,
) {
  final String? normalized;
  try {
    normalized = normalize(stored);
  } on IntentionTextValidationException {
    throw const StoredGraphCorruption();
  } on ArgumentError {
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
) {
  final microseconds = requiredStoredInteger(data, column);
  try {
    return IntentionTimestamp(
      DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true),
    );
  } on ArgumentError {
    throw const StoredGraphCorruption();
  }
}

/// Ключ поиска из столбца `title_search_key`, который схема вычисляет из
/// названия намерения.
String decodeStoredTitleSearchKey(Map<String, Object?> data) {
  final key = requiredStoredString(data, 'title_search_key');
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
/// связи модели и описание, которого модель связи не несёт.
final class StoredLongTermRelation {
  factory StoredLongTermRelation.decode(Map<String, Object?> data) {
    final creationSequence = requiredStoredInteger(data, 'creation_sequence');
    if (creationSequence <= 0) throw const StoredGraphCorruption();
    final id = decodeStoredRelationId(requiredStoredString(data, 'id'));
    final ends = decodeStoredRelationEnds(data);
    final type = switch (requiredStoredString(data, 'type')) {
      'need' => LongTermRelationType.need,
      'can' => LongTermRelationType.can,
      _ => throw const StoredGraphCorruption(),
    };
    final priority = switch (requiredStoredInteger(data, 'priority')) {
      1 => RelationPriority.p1,
      2 => RelationPriority.p2,
      3 => RelationPriority.p3,
      4 => RelationPriority.p4,
      _ => throw const StoredGraphCorruption(),
    };
    final scope = decodeStoredRelationScope(data);
    final description = _nullableStoredString(data, 'description');
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
  });

  final int creationSequence;
  final LongTermRelationId id;
  final IntentionId sourceIntentionId;
  final IntentionId relatedIntentionId;
  final LongTermRelationType type;
  final RelationPriority priority;
  final RelationScope scope;
  final LongTermRelationDescription? description;

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

/// Охват связи из столбца `is_archived`.
RelationScope decodeStoredRelationScope(Map<String, Object?> data) =>
    switch (requiredStoredInteger(data, 'is_archived')) {
      0 => RelationScope.active,
      1 => RelationScope.archived,
      _ => throw const StoredGraphCorruption(),
    };

/// Дневной выбор из столбцов таблицы `daily_choices`.
DailyChoice decodeStoredDailyChoice(Map<String, Object?> data) {
  if (requiredStoredInteger(data, 'creation_sequence') <= 0) {
    throw const StoredGraphCorruption();
  }
  final id = decodeStoredDailyChoiceId(requiredStoredString(data, 'id'));
  final sourceId = decodeStoredIntentionId(
    requiredStoredString(data, 'source_intention_id'),
  );
  final selectedId = decodeStoredIntentionId(
    requiredStoredString(data, 'selected_intention_id'),
  );
  final description = _nullableStoredString(data, 'description');
  final schedule = switch (data['scheduled_minute']) {
    null => const DailyChoiceAllDay(),
    final int minute when minute >= 0 && minute <= 1439 => DailyChoiceTime(
      hour: minute ~/ 60,
      minute: minute % 60,
    ),
    _ => throw const StoredGraphCorruption(),
  };
  final priority = switch (requiredStoredInteger(data, 'priority')) {
    1 => DailyChoicePriority.p1,
    2 => DailyChoicePriority.p2,
    3 => DailyChoicePriority.p3,
    4 => DailyChoicePriority.p4,
    _ => throw const StoredGraphCorruption(),
  };
  try {
    return DailyChoice(
      id: id,
      sourceIntentionId: sourceId,
      selectedIntentionId: selectedId,
      date: decodeStoredChoiceDate(data),
      description: description == null
          ? null
          : DailyChoiceDescription.fromStored(description),
      isCompleted: decodeStoredChoiceCompletion(data),
      schedule: schedule,
      priority: priority,
    );
  } on DailyChoiceDescriptionValidationException {
    throw const StoredGraphCorruption();
  } on ArgumentError {
    throw const StoredGraphCorruption();
  }
}

/// Дата дневного выбора из столбца `choice_date`.
CalendarDate decodeStoredChoiceDate(Map<String, Object?> data) {
  final value = requiredStoredString(data, 'choice_date');
  try {
    return CalendarDate.parseCanonical(value);
  } on CalendarDateValidationException {
    throw const StoredGraphCorruption();
  }
}

/// Выполнение дневного выбора из столбца `is_completed`.
bool decodeStoredChoiceCompletion(Map<String, Object?> data) =>
    switch (requiredStoredInteger(data, 'is_completed')) {
      0 => false,
      1 => true,
      _ => throw const StoredGraphCorruption(),
    };

/// Шаг пути дневного выбора из столбцов таблицы `daily_choice_path_steps`.
ChoicePathStep decodeStoredChoicePathStep(Map<String, Object?> data) {
  final previous = _nullableStoredString(data, 'previous_step_id');
  return ChoicePathStep(
    id: _decodeStoredChoicePathStepId(requiredStoredString(data, 'id')),
    dailyChoiceId: decodeStoredDailyChoiceId(
      requiredStoredString(data, 'daily_choice_id'),
    ),
    relationId: decodeStoredRelationId(
      requiredStoredString(data, 'long_term_relation_id'),
    ),
    previousStepId: previous == null
        ? null
        : _decodeStoredChoicePathStepId(previous),
  );
}
