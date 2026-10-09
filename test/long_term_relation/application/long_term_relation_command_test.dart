import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('команда создания долговременной связи', () {
    test('не допускает прямую самосвязь', () {
      expect(
        () => CreateLongTermRelation(
          sourceIntentionId: _sourceId,
          relatedIntentionId: _sourceId,
          type: LongTermRelationType.can,
          priority: RelationPriority.p4,
          description: null,
        ),
        throwsA(
          isA<CreateLongTermRelationValidationException>().having(
            (error) => error.failure,
            'failure',
            CreateLongTermRelationValidationFailure.sameIntention,
          ),
        ),
      );
    });
  });

  group('типизированный набор частичных правок связи', () {
    test('пробельный ввод явно очищает описание', () {
      final patch = LongTermRelationDescriptionPatch.fromInput(' \n\t ');

      expect(patch, isA<LongTermRelationDescriptionCleared>());
    });
  });

  group('пакет подтверждённого изменения графа', () {
    test('отклоняет сведения об изменении другой ревизии', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 7);
      const newerRevision = _TestGraphRevision(epoch: 'первая', sequence: 8);
      final relation = _relation();

      expect(
        () => ConfirmedGraphResult(
          revision: revision,
          value: LongTermRelationCreated(
            relation: relation,
            description: null,
            changes: [
              LongTermRelationCreatedChange(
                revision: newerRevision,
                relation: relation,
              ),
            ],
          ),
        ),
        throwsA(
          isA<ConfirmedGraphResultValidationException>().having(
            (error) => error.failure,
            'failure',
            ConfirmedGraphResultValidationFailure.revisionMismatch,
          ),
        ),
      );
    });

    test('обновление не смешивает идентичность разных связей', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 10);
      final before = _relation();
      final after = LongTermRelation(
        id: _longTermRelationId('018f0b5d-6b2e-7c80-8000-000000000002'),
        sourceIntentionId: _sourceId,
        relatedIntentionId: _relatedId,
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        scope: RelationScope.active,
        creationSequence: RelationCreationSequence(1),
      );

      expect(
        () => LongTermRelationUpdatedChange(
          revision: revision,
          before: before,
          after: after,
        ),
        throwsA(
          isA<LongTermRelationChangeValidationException>().having(
            (error) => error.failure,
            'failure',
            LongTermRelationChangeValidationFailure.identityMismatch,
          ),
        ),
      );
    });
  });
}

LongTermRelation _relation() => LongTermRelation(
  id: _relationId,
  sourceIntentionId: _sourceId,
  relatedIntentionId: _relatedId,
  type: LongTermRelationType.need,
  priority: RelationPriority.p2,
  scope: RelationScope.active,
  creationSequence: RelationCreationSequence(1),
);

final class _TestGraphRevision implements GraphRevision {
  const _TestGraphRevision({required this.epoch, required this.sequence});

  final String epoch;
  final int sequence;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! _TestGraphRevision || other.epoch != epoch) {
      return GraphRevisionOrder.differentEpoch;
    }
    return switch (sequence.compareTo(other.sequence)) {
      < 0 => GraphRevisionOrder.older,
      > 0 => GraphRevisionOrder.newer,
      _ => GraphRevisionOrder.same,
    };
  }
}

final _sourceId = _intentionId('0f8fad5b-d9cb-469f-a165-70867728950e');
final _relatedId = _intentionId('7c9e6679-7425-40de-944b-e07fc1f90ae7');
final _relationId = _longTermRelationId('018f0b5d-6b2e-7c80-8000-000000000001');

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError(
    'Ожидался корректный UUID намерения.',
  ),
};

LongTermRelationId _longTermRelationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Ожидался корректный UUID связи.',
      ),
    };
