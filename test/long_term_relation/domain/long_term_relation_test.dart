import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('последовательность создания долговременной связи', () {
    test('принимает только положительные значения', () {
      final first = RelationCreationSequence(1);
      final later = RelationCreationSequence(42);

      expect(first.value, 1);
      expect(later.value, 42);
      expect(first.compareTo(later), isNegative);
      expect(RelationCreationSequence(1), first);
    });

    test('отклоняет ноль и отрицательные значения', () {
      for (final value in [0, -1]) {
        expect(
          () => RelationCreationSequence(value),
          throwsA(
            isA<RelationCreationSequenceValidationException>().having(
              (error) => error.failure,
              'failure',
              RelationCreationSequenceValidationFailure.notPositive,
            ),
          ),
        );
      }
    });
  });

  group('модель долговременной связи', () {
    test('сохраняет проверенные идентичность и параметры', () {
      final relation = LongTermRelation(
        id: _relationId('018f0b5d-6b2e-7c80-8000-000000000001'),
        sourceIntentionId: _intentionId('0f8fad5b-d9cb-469f-a165-70867728950e'),
        relatedIntentionId: _intentionId(
          '7c9e6679-7425-40de-944b-e07fc1f90ae7',
        ),
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        scope: RelationScope.archived,
        creationSequence: RelationCreationSequence(7),
      );

      expect(
        relation.id.toCanonicalString(),
        '018f0b5d-6b2e-7c80-8000-000000000001',
      );
      expect(
        relation.sourceIntentionId.toCanonicalString(),
        '0f8fad5b-d9cb-469f-a165-70867728950e',
      );
      expect(
        relation.relatedIntentionId.toCanonicalString(),
        '7c9e6679-7425-40de-944b-e07fc1f90ae7',
      );
      expect(relation.type, LongTermRelationType.need);
      expect(relation.priority, RelationPriority.p2);
      expect(relation.scope, RelationScope.archived);
      expect(relation.creationSequence.value, 7);
    });

    test('не смешивает идентификаторы связи и намерения', () {
      const serialized = '0f8fad5b-d9cb-469f-a165-70867728950e';
      final relationId = _relationId(serialized);
      final intentionId = _intentionId(serialized);

      expect(relationId.toCanonicalString(), intentionId.toCanonicalString());
      expect(relationId, isNot(equals(intentionId)));
    });

    test('отклоняет прямую самосвязь по идентификатору намерения', () {
      final intentionId = _intentionId('0f8fad5b-d9cb-469f-a165-70867728950e');

      expect(
        () => LongTermRelation(
          id: _relationId('018f0b5d-6b2e-7c80-8000-000000000001'),
          sourceIntentionId: intentionId,
          relatedIntentionId: intentionId,
          type: LongTermRelationType.can,
          priority: RelationPriority.p4,
          scope: RelationScope.active,
          creationSequence: RelationCreationSequence(1),
        ),
        throwsA(
          isA<LongTermRelationValidationException>().having(
            (error) => error.failure,
            'failure',
            LongTermRelationValidationFailure.sameIntention,
          ),
        ),
      );
    });
  });

  test('перечисления задают полный закрытый набор вариантов', () {
    expect(LongTermRelationType.values.map(_relationTypeLabel), [
      'need',
      'can',
    ]);
    expect(RelationPriority.values.map(_priorityLabel), [
      'p1',
      'p2',
      'p3',
      'p4',
    ]);
    expect(RelationDirection.values.map(_directionLabel), [
      'incoming',
      'outgoing',
    ]);
    expect(RelationScope.values.map(_scopeLabel), ['active', 'archived']);
  });
}

String _relationTypeLabel(LongTermRelationType type) => switch (type) {
  LongTermRelationType.need => 'need',
  LongTermRelationType.can => 'can',
};

String _priorityLabel(RelationPriority priority) => switch (priority) {
  RelationPriority.p1 => 'p1',
  RelationPriority.p2 => 'p2',
  RelationPriority.p3 => 'p3',
  RelationPriority.p4 => 'p4',
};

String _directionLabel(RelationDirection direction) => switch (direction) {
  RelationDirection.incoming => 'incoming',
  RelationDirection.outgoing => 'outgoing',
};

String _scopeLabel(RelationScope scope) => switch (scope) {
  RelationScope.active => 'active',
  RelationScope.archived => 'archived',
};

LongTermRelationId _relationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Ожидался корректный UUID связи.',
      ),
    };

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError(
    'Ожидался корректный UUID намерения.',
  ),
};
