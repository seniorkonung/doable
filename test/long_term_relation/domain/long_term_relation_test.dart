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
}

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
