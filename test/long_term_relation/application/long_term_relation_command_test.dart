import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('команда создания долговременной связи', () {
    test('содержит проверенные параметры и разных участников', () {
      final description = LongTermRelationDescription.fromInput(
        '  Ходить не меньше часа  ',
      );
      final command = CreateLongTermRelation(
        sourceIntentionId: _sourceId,
        relatedIntentionId: _relatedId,
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        description: description,
      );

      expect(command.sourceIntentionId, _sourceId);
      expect(command.relatedIntentionId, _relatedId);
      expect(command.type, LongTermRelationType.need);
      expect(command.priority, RelationPriority.p2);
      expect(command.description, same(description));
    });

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

    test('разделяет команды сущностей на общей границе графа', () {
      final commands = <GraphCommand<GraphCommandOutcome, GraphCommandFailure>>[
        const CreateIntention(title: 'Быть здоровым', description: null),
        CreateLongTermRelation(
          sourceIntentionId: _sourceId,
          relatedIntentionId: _relatedId,
          type: LongTermRelationType.can,
          priority: RelationPriority.p3,
          description: null,
        ),
      ];

      expect(commands[0], isA<IntentionCommand>());
      expect(commands[1], isA<LongTermRelationCommand>());
      expect(
        const IntentionUnavailableFailure().category,
        GraphFailureCategory.unavailable,
      );
    });
  });

  group('типизированные отказы создания связи', () {
    test('занятая пара ссылается на существующую связь', () {
      final failure = LongTermRelationPairOccupiedFailure(_relationId);

      expect(failure.category, GraphFailureCategory.conflict);
      expect(failure.existingRelationId, _relationId);
    });

    test('отсутствующий и архивный участники сохраняют роль', () {
      final failures = <LongTermRelationCommandFailure>[
        LongTermRelationParticipantNotFoundFailure(
          role: RelationParticipantRole.source,
          intentionId: _sourceId,
        ),
        LongTermRelationParticipantArchivedFailure(
          role: RelationParticipantRole.related,
          intentionId: _relatedId,
        ),
      ];

      expect(failures.map((failure) => failure.category), [
        GraphFailureCategory.notFound,
        GraphFailureCategory.conflict,
      ]);
      expect(
        (failures[0] as LongTermRelationParticipantNotFoundFailure).role,
        RelationParticipantRole.source,
      );
      expect(
        (failures[1] as LongTermRelationParticipantArchivedFailure).role,
        RelationParticipantRole.related,
      );
    });

    test('закрытый набор охватывает все общие категории', () {
      const failures = <LongTermRelationCommandFailure>[
        LongTermRelationCommandValidationFailure(
          CreateLongTermRelationValidationFailure.sameIntention,
        ),
        LongTermRelationUnavailableFailure(),
        LongTermRelationCorruptionFailure(),
        LongTermRelationUnexpectedFailure(),
      ];

      expect(failures.map((failure) => failure.category), [
        GraphFailureCategory.validation,
        GraphFailureCategory.unavailable,
        GraphFailureCategory.corruption,
        GraphFailureCategory.unexpected,
      ]);
      expect(failures.map(_failureDescription), [
        'validation',
        'unavailable',
        'corruption',
        'unexpected',
      ]);
      expect(
        (failures.first as LongTermRelationCommandValidationFailure).reason,
        CreateLongTermRelationValidationFailure.sameIntention,
      );
    });
  });

  group('пакет подтверждённого изменения графа', () {
    test('объединяет точные изменения одной ревизии', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 7);
      final relation = _relation();
      final sourceCounts = _counts(activeNeedOutgoing: 1);
      final relatedCounts = _counts(activeNeedIncoming: 1);
      final catalogMutation = IntentionCatalogUpdated(
        revision: revision,
        before: _catalogEntry(_sourceId, activeRelationCount: 0),
        after: _catalogEntry(_sourceId, activeRelationCount: 1),
      );
      final changes = <GraphChange>[
        catalogMutation,
        IntentionRelationCountsChanged(
          revision: revision,
          intentionId: _sourceId,
          counts: sourceCounts,
        ),
        IntentionRelationCountsChanged(
          revision: revision,
          intentionId: _relatedId,
          counts: relatedCounts,
        ),
        LongTermRelationCreatedChange(revision: revision, relation: relation),
      ];
      final success = LongTermRelationCreated(
        relation: relation,
        description: null,
        changes: changes,
      );
      final result = ConfirmedGraphResult(revision: revision, value: success);

      expect(result.changes, hasLength(4));
      expect(
        result.changes.whereType<IntentionCatalogMutation>(),
        contains(same(catalogMutation)),
      );
      expect(
        result.changes.whereType<IntentionRelationCountsChanged>().map(
          (change) => (change.intentionId, change.counts),
        ),
        containsAll([(_sourceId, sourceCounts), (_relatedId, relatedCounts)]),
      );
      expect(
        result.changes
            .singleWhereType<LongTermRelationCreatedChange>()
            .relation,
        same(relation),
      );
      expect(
        () => result.changes.add(
          LongTermRelationDeletedChange(revision: revision, relation: relation),
        ),
        throwsUnsupportedError,
      );

      final LongTermRelationCommandResult commandResult = GraphCommandSucceeded(
        result,
      );
      expect(commandResult, isA<GraphCommandSucceeded>());
    });

    test('результат команды сохраняет типизированный отказ', () {
      final LongTermRelationCommandResult result = GraphCommandFailed(
        LongTermRelationParticipantArchivedFailure(
          role: RelationParticipantRole.related,
          intentionId: _relatedId,
        ),
      );

      expect(
        result,
        isA<
              GraphCommandFailed<
                LongTermRelationCommandSuccess,
                LongTermRelationCommandFailure
              >
            >()
            .having(
              (failed) => failed.failure.category,
              'category',
              GraphFailureCategory.conflict,
            ),
      );
    });

    test('изменение только счётчика не изображает изменение намерения', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 8);
      final relation = _relation();
      final success = LongTermRelationCreated(
        relation: relation,
        description: null,
        changes: [
          IntentionRelationCountsChanged(
            revision: revision,
            intentionId: _sourceId,
            counts: _counts(activeNeedOutgoing: 1),
          ),
          LongTermRelationCreatedChange(revision: revision, relation: relation),
        ],
      );
      final result = ConfirmedGraphResult(revision: revision, value: success);

      expect(result.changes.whereType<IntentionCatalogMutation>(), isEmpty);
      expect(
        result.changes.whereType<IntentionRelationCountsChanged>(),
        hasLength(1),
      );
    });

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

    test('обновление и удаление несут прежних и новых участников', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 9);
      final before = _relation();
      final after = _relation(relatedIntentionId: _replacementId);
      final updated = LongTermRelationUpdatedChange(
        revision: revision,
        before: before,
        after: after,
      );
      final deleted = LongTermRelationDeletedChange(
        revision: revision,
        relation: after,
      );

      expect(updated.before.relatedIntentionId, _relatedId);
      expect(updated.after.relatedIntentionId, _replacementId);
      expect(deleted.id, _relationId);
      expect(deleted.before.relatedIntentionId, _replacementId);
      expect(deleted.after, isNull);
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

String _failureDescription(LongTermRelationCommandFailure failure) =>
    switch (failure) {
      LongTermRelationCommandValidationFailure() => 'validation',
      LongTermRelationPairOccupiedFailure() => 'pairOccupied',
      LongTermRelationParticipantNotFoundFailure() => 'participantNotFound',
      LongTermRelationParticipantArchivedFailure() => 'participantArchived',
      LongTermRelationUnavailableFailure() => 'unavailable',
      LongTermRelationCorruptionFailure() => 'corruption',
      LongTermRelationUnexpectedFailure() => 'unexpected',
    };

LongTermRelation _relation({IntentionId? relatedIntentionId}) =>
    LongTermRelation(
      id: _relationId,
      sourceIntentionId: _sourceId,
      relatedIntentionId: relatedIntentionId ?? _relatedId,
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      scope: RelationScope.active,
      creationSequence: RelationCreationSequence(1),
    );

RelationCounts _counts({
  int activeNeedIncoming = 0,
  int activeNeedOutgoing = 0,
}) => RelationCounts(
  activeNeedIncoming: activeNeedIncoming,
  activeNeedOutgoing: activeNeedOutgoing,
  activeCanIncoming: 0,
  activeCanOutgoing: 0,
  archivedNeedIncoming: 0,
  archivedNeedOutgoing: 0,
  archivedCanIncoming: 0,
  archivedCanOutgoing: 0,
);

_TestCatalogEntry _catalogEntry(
  IntentionId id, {
  required int activeRelationCount,
}) => _TestCatalogEntry(
  IntentionSummary(
    id: id,
    title: 'Намерение',
    hasDescription: false,
    readiness: IntentionReadiness.notReady,
    archiveState: IntentionArchiveState.active,
    activeRelationCount: activeRelationCount,
    createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 19)),
    updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 19)),
  ),
);

final class _TestCatalogEntry implements IntentionCatalogEntrySnapshot {
  const _TestCatalogEntry(this.summary);

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}

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

extension _SingleWhereType on Iterable<GraphChange> {
  T singleWhereType<T extends GraphChange>() => whereType<T>().single;
}

final _sourceId = _intentionId('0f8fad5b-d9cb-469f-a165-70867728950e');
final _relatedId = _intentionId('7c9e6679-7425-40de-944b-e07fc1f90ae7');
final _replacementId = _intentionId('00000000-0000-4000-8000-000000000003');
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
