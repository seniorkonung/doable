import '../daily_choice/domain/daily_choice.dart';
import '../daily_choice/domain/daily_choice_id.dart';
import '../intention/domain/intention.dart';
import '../intention/domain/intention_id.dart';
import '../long_term_relation/domain/long_term_relation.dart';
import '../long_term_relation/domain/long_term_relation_description.dart';
import '../long_term_relation/domain/long_term_relation_id.dart';
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
    required this.tagAssignments,
    required this.longTermRelations,
    required this.dailyChoices,
  }) {
    RangeError.checkNotNegative(tags, 'tags');
    RangeError.checkNotNegative(intentions, 'intentions');
    RangeError.checkNotNegative(tagAssignments, 'tagAssignments');
    RangeError.checkNotNegative(longTermRelations, 'longTermRelations');
    RangeError.checkNotNegative(dailyChoices, 'dailyChoices');
  }

  final int tags;
  final int intentions;
  final int tagAssignments;
  final int longTermRelations;
  final int dailyChoices;
}

/// Факт пакета лога: полное состояние сущности после транзакции или её
/// удаление.
sealed class GraphFact {
  const GraphFact();
}

/// Запись сущности графа: строка файла экспорта или снимка либо факт пакета.
sealed class GraphEntityRecord extends GraphFact {
  const GraphEntityRecord();
}

final class TagRecord extends GraphEntityRecord {
  const TagRecord(this.tag);

  final Tag tag;
}

final class IntentionRecord extends GraphEntityRecord {
  const IntentionRecord(this.intention);

  final Intention intention;
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
  });

  final LongTermRelationId id;
  final IntentionId sourceIntentionId;
  final IntentionId relatedIntentionId;
  final LongTermRelationType type;
  final RelationPriority priority;
  final LongTermRelationDescription? description;
  final RelationScope scope;
}

final class DailyChoiceRecord extends GraphEntityRecord {
  /// Путь выбора принадлежит этому дневному выбору.
  factory DailyChoiceRecord({
    required DailyChoice choice,
    required StoredChoicePath path,
  }) {
    if (path.steps.first.dailyChoiceId != choice.id) {
      throw ArgumentError.value(path, 'path');
    }
    return DailyChoiceRecord._(choice, path);
  }

  const DailyChoiceRecord._(this.choice, this.path);

  final DailyChoice choice;
  final StoredChoicePath path;
}

/// Удаление сущности бывает только в пакете фактов: файл и снимок содержат
/// одно состояние графа.
final class GraphEntityDeletion extends GraphFact {
  const GraphEntityDeletion(this.entity);

  final GraphEntityKey entity;
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

final class DailyChoiceKey extends GraphEntityKey {
  const DailyChoiceKey(this.id);

  final DailyChoiceId id;

  @override
  bool operator ==(Object other) => other is DailyChoiceKey && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
