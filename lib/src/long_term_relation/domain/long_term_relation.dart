import '../../intention/domain/intention_id.dart';
import 'long_term_relation_id.dart';

enum LongTermRelationType { need, can }

enum RelationPriority { p1, p2, p3, p4 }

enum RelationDirection { incoming, outgoing }

enum RelationScope { active, archived }

enum RelationCreationSequenceValidationFailure { notPositive }

final class RelationCreationSequenceValidationException implements Exception {
  const RelationCreationSequenceValidationException(this.failure);

  final RelationCreationSequenceValidationFailure failure;
}

final class RelationCreationSequence
    implements Comparable<RelationCreationSequence> {
  factory RelationCreationSequence(int value) {
    if (value <= 0) {
      throw const RelationCreationSequenceValidationException(
        RelationCreationSequenceValidationFailure.notPositive,
      );
    }
    return RelationCreationSequence._(value);
  }

  const RelationCreationSequence._(this.value);

  final int value;

  @override
  int compareTo(RelationCreationSequence other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      other is RelationCreationSequence && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'RelationCreationSequence';
}

/// Показание часов устройства о создании или последнем изменении связи.
/// Служит только для показа и не задаёт порядок связей.
final class RelationTimestamp {
  RelationTimestamp(DateTime value) : value = value.toUtc();

  final DateTime value;

  @override
  bool operator ==(Object other) =>
      other is RelationTimestamp && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

enum LongTermRelationValidationFailure { sameIntention }

final class LongTermRelationValidationException implements Exception {
  const LongTermRelationValidationException(this.failure);

  final LongTermRelationValidationFailure failure;
}

final class LongTermRelation {
  factory LongTermRelation({
    required LongTermRelationId id,
    required IntentionId sourceIntentionId,
    required IntentionId relatedIntentionId,
    required LongTermRelationType type,
    required RelationPriority priority,
    required RelationScope scope,
    required RelationCreationSequence creationSequence,
    required RelationTimestamp createdAt,
    required RelationTimestamp updatedAt,
  }) {
    if (sourceIntentionId == relatedIntentionId) {
      throw const LongTermRelationValidationException(
        LongTermRelationValidationFailure.sameIntention,
      );
    }
    return LongTermRelation._(
      id: id,
      sourceIntentionId: sourceIntentionId,
      relatedIntentionId: relatedIntentionId,
      type: type,
      priority: priority,
      scope: scope,
      creationSequence: creationSequence,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  const LongTermRelation._({
    required this.id,
    required this.sourceIntentionId,
    required this.relatedIntentionId,
    required this.type,
    required this.priority,
    required this.scope,
    required this.creationSequence,
    required this.createdAt,
    required this.updatedAt,
  });

  final LongTermRelationId id;
  final IntentionId sourceIntentionId;
  final IntentionId relatedIntentionId;
  final LongTermRelationType type;
  final RelationPriority priority;
  final RelationScope scope;
  final RelationCreationSequence creationSequence;
  final RelationTimestamp createdAt;
  final RelationTimestamp updatedAt;
}
