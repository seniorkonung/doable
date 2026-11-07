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
import '../tag/domain/tag_id.dart';

/// Заголовок файла или снимка: момент записи и количества записей каждого
/// вида.
final class GraphFormatHeader {
  GraphFormatHeader({required DateTime writtenAt, required this.counts})
    : writtenAt = writtenAt.toUtc();

  /// Показание часов устройства в момент записи.
  final DateTime writtenAt;
  final GraphRecordCounts counts;
}

/// Количества записей каждого вида — размеры секций файла.
final class GraphRecordCounts {
  GraphRecordCounts({
    required this.tags,
    required this.intentions,
    required this.deletedIntentions,
    required this.tagAssignments,
    required this.longTermRelations,
    required this.deletedRelationPairs,
    required this.actions,
  }) {
    RangeError.checkNotNegative(tags, 'tags');
    RangeError.checkNotNegative(intentions, 'intentions');
    RangeError.checkNotNegative(deletedIntentions, 'deletedIntentions');
    RangeError.checkNotNegative(tagAssignments, 'tagAssignments');
    RangeError.checkNotNegative(longTermRelations, 'longTermRelations');
    RangeError.checkNotNegative(deletedRelationPairs, 'deletedRelationPairs');
    RangeError.checkNotNegative(actions, 'actions');
  }

  final int tags;
  final int intentions;

  /// Надгробия удалённых намерений, на которые ссылаются пути действий.
  final int deletedIntentions;
  final int tagAssignments;
  final int longTermRelations;

  /// Надгробия удалённых связей пар, соседствующих в путях действий.
  final int deletedRelationPairs;
  final int actions;
}

/// Факт пакета лога: вид изменения сущности транзакцией.
sealed class GraphFact {
  const GraphFact();
}

/// Сущность создана транзакцией; [record] — её состояние после транзакции.
final class GraphEntityCreated extends GraphFact {
  const GraphEntityCreated(this.record);

  final GraphEntityRecord record;
}

/// Сущность была до транзакции и есть после неё; [record] — её состояние
/// после транзакции.
final class GraphEntityChanged extends GraphFact {
  const GraphEntityChanged(this.record);

  final GraphEntityRecord record;
}

/// Сущность была до транзакции и удалена ею. Удаление бывает только в пакете
/// фактов: файл и снимок содержат одно состояние графа.
final class GraphEntityDeleted extends GraphFact {
  const GraphEntityDeleted(this.entity);

  final GraphEntityKey entity;
}

/// Запись сущности графа: строка файла экспорта или снимка либо состояние
/// сущности в факте пакета.
sealed class GraphEntityRecord {
  const GraphEntityRecord();

  /// Ключ сущности, состояние которой несёт запись.
  GraphEntityKey get key => switch (this) {
    TagRecord(:final tag) => TagKey(tag.id),
    IntentionRecord(:final intention) => IntentionKey(intention.id),
    DeletedIntentionRecord(:final id) => DeletedIntentionKey(id),
    TagAssignmentRecord(:final assignment) => TagAssignmentKey(assignment),
    LongTermRelationRecord(:final id) => LongTermRelationKey(id),
    DeletedRelationPairRecord(
      :final sourceIntentionId,
      :final relatedIntentionId,
    ) =>
      DeletedRelationPairKey(
        sourceIntentionId: sourceIntentionId,
        relatedIntentionId: relatedIntentionId,
      ),
    ActionRecord(:final id) => ActionKey(id),
  };
}

final class TagRecord extends GraphEntityRecord {
  const TagRecord(this.tag);

  final Tag tag;
}

final class IntentionRecord extends GraphEntityRecord {
  const IntentionRecord(this.intention);

  final Intention intention;
}

/// Канонический порядок намерений в секции файла формата — тот же, в каком
/// их перечисляет база: по времени создания, затем по идентификатору. Время
/// создания — показание часов устройства, поэтому созданное позже намерение
/// может встать перед прежними.
int compareIntentionsInFormatOrder(Intention first, Intention second) {
  final byCreation = first.createdAt.value.compareTo(second.createdAt.value);
  return byCreation != 0 ? byCreation : first.id.compareTo(second.id);
}

/// Надгробие удалённого намерения: его название, которое показывают пути
/// действий. Другие данные удалённого не хранятся.
final class DeletedIntentionRecord extends GraphEntityRecord {
  /// Название приводится к форме, в которой его хранит намерение.
  factory DeletedIntentionRecord({
    required IntentionId id,
    required String title,
  }) => DeletedIntentionRecord._(id, IntentionText.normalizeTitle(title));

  const DeletedIntentionRecord._(this.id, this.title);

  final IntentionId id;
  final String title;
}

final class TagAssignmentRecord extends GraphEntityRecord {
  const TagAssignmentRecord(this.assignment);

  final TagAssignment assignment;
}

/// Порядок создания связи передаёт место записи в секции, а не поле.
final class LongTermRelationRecord extends GraphEntityRecord {
  const LongTermRelationRecord({
    required this.id,
    required this.sourceIntentionId,
    required this.relatedIntentionId,
    required this.type,
    required this.priority,
    required this.description,
    required this.scope,
    required this.createdAt,
    required this.updatedAt,
  });

  final LongTermRelationId id;
  final IntentionId sourceIntentionId;
  final IntentionId relatedIntentionId;
  final LongTermRelationType type;
  final RelationPriority priority;
  final LongTermRelationDescription? description;
  final RelationScope scope;
  final RelationTimestamp createdAt;
  final RelationTimestamp updatedAt;
}

/// Надгробие удалённой связи: тип, который имела связь направленной пары
/// намерений на момент удаления.
final class DeletedRelationPairRecord extends GraphEntityRecord {
  /// Пара состоит из двух разных намерений.
  factory DeletedRelationPairRecord({
    required IntentionId sourceIntentionId,
    required IntentionId relatedIntentionId,
    required LongTermRelationType type,
  }) {
    if (sourceIntentionId == relatedIntentionId) {
      throw ArgumentError.value(relatedIntentionId, 'relatedIntentionId');
    }
    return DeletedRelationPairRecord._(
      sourceIntentionId,
      relatedIntentionId,
      type,
    );
  }

  const DeletedRelationPairRecord._(
    this.sourceIntentionId,
    this.relatedIntentionId,
    this.type,
  );

  final IntentionId sourceIntentionId;
  final IntentionId relatedIntentionId;
  final LongTermRelationType type;
}

/// Действие с путём. Порядок создания действия передаёт место записи в
/// секции, а не поле.
final class ActionRecord extends GraphEntityRecord {
  const ActionRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.path,
    required this.date,
    required this.schedule,
    required this.priority,
    required this.isCompleted,
    required this.createdAt,
    required this.updatedAt,
  });

  final ActionId id;
  final ActionTitle title;
  final ActionDescription? description;
  final ActionPath path;
  final CalendarDate date;
  final ActionSchedule schedule;
  final ActionPriority priority;
  final bool isCompleted;
  final ActionTimestamp createdAt;
  final ActionTimestamp updatedAt;
}

/// Ключ сущности графа. Ключи равны, когда указывают на одну сущность.
sealed class GraphEntityKey {
  const GraphEntityKey();
}

final class TagKey extends GraphEntityKey {
  const TagKey(this.id);

  final TagId id;

  @override
  bool operator ==(Object other) => other is TagKey && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final class IntentionKey extends GraphEntityKey {
  const IntentionKey(this.id);

  final IntentionId id;

  @override
  bool operator ==(Object other) => other is IntentionKey && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Ключ надгробия удалённого намерения: не равен ключу намерения.
final class DeletedIntentionKey extends GraphEntityKey {
  const DeletedIntentionKey(this.id);

  final IntentionId id;

  @override
  bool operator ==(Object other) =>
      other is DeletedIntentionKey && other.id == id;

  @override
  int get hashCode => Object.hash(DeletedIntentionKey, id);
}

final class TagAssignmentKey extends GraphEntityKey {
  const TagAssignmentKey(this.assignment);

  final TagAssignment assignment;

  @override
  bool operator ==(Object other) =>
      other is TagAssignmentKey && other.assignment == assignment;

  @override
  int get hashCode => assignment.hashCode;
}

final class LongTermRelationKey extends GraphEntityKey {
  const LongTermRelationKey(this.id);

  final LongTermRelationId id;

  @override
  bool operator ==(Object other) =>
      other is LongTermRelationKey && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Ключ надгробия удалённой связи: не равен ключу связи.
final class DeletedRelationPairKey extends GraphEntityKey {
  const DeletedRelationPairKey({
    required this.sourceIntentionId,
    required this.relatedIntentionId,
  });

  final IntentionId sourceIntentionId;
  final IntentionId relatedIntentionId;

  @override
  bool operator ==(Object other) =>
      other is DeletedRelationPairKey &&
      other.sourceIntentionId == sourceIntentionId &&
      other.relatedIntentionId == relatedIntentionId;

  @override
  int get hashCode => Object.hash(
    DeletedRelationPairKey,
    sourceIntentionId,
    relatedIntentionId,
  );
}

final class ActionKey extends GraphEntityKey {
  const ActionKey(this.id);

  final ActionId id;

  @override
  bool operator ==(Object other) => other is ActionKey && other.id == id;

  @override
  int get hashCode => Object.hash(ActionKey, id);
}
