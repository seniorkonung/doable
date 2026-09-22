import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final owner = _intentionId(1);
  final firstNeighbor = _intentionId(2);
  final secondNeighbor = _intentionId(3);
  final firstId = _relationId(101);
  final secondId = _relationId(102);

  test('пустой и повторяющийся выбор не создаёт команду', () {
    expect(
      () => DeleteBlockingRelations(
        intentionId: owner,
        relationIds: <LongTermRelationId>[],
      ),
      throwsA(
        isA<DeleteBlockingRelationsValidationException>().having(
          (error) => error.failure,
          'failure',
          DeleteBlockingRelationsValidationFailure.emptySelection,
        ),
      ),
    );
    expect(
      () => DeleteBlockingRelations(
        intentionId: owner,
        relationIds: [firstId, firstId],
      ),
      throwsA(
        isA<DeleteBlockingRelationsValidationException>().having(
          (error) => error.failure,
          'failure',
          DeleteBlockingRelationsValidationFailure.duplicateRelation,
        ),
      ),
    );
  });

  test('подтверждённый набор не меняется вместе с исходным выбором', () {
    final selection = <LongTermRelationId>{firstId, secondId};
    final command = DeleteBlockingRelations(
      intentionId: owner,
      relationIds: selection,
    );

    selection
      ..clear()
      ..add(_relationId(103));

    expect(command.intentionId, owner);
    expect(command.relationIds, unorderedEquals([firstId, secondId]));
    expect(
      () => command.relationIds.add(_relationId(104)),
      throwsUnsupportedError,
    );
  });

  test('типизированные отказы сохраняют категории и идентификаторы', () {
    const unavailable = DeleteBlockingRelationsUnavailableFailure();
    const corruption = DeleteBlockingRelationsCorruptionFailure();
    const unexpected = DeleteBlockingRelationsUnexpectedFailure();
    final notFound = DeleteBlockingRelationsIntentionNotFoundFailure(owner);
    final stale = DeleteBlockingRelationsSelectionConflictFailure(
      relationId: firstId,
      reason: BlockingRelationConflictReason.noLongerBlocking,
    );
    final DeleteBlockingRelationsResult failed = GraphResultFailure(stale);

    expect(notFound.intentionId, owner);
    expect(notFound.category, GraphFailureCategory.notFound);
    expect(stale.relationId, firstId);
    expect(stale.category, GraphFailureCategory.conflict);
    expect((failed as GraphResultFailure).failure, same(stale));
    expect(unavailable.category, GraphFailureCategory.unavailable);
    expect(corruption.category, GraphFailureCategory.corruption);
    expect(unexpected.category, GraphFailureCategory.unexpected);
  });

  test('единый результат содержит ровно удаления и счётчики участников', () {
    final command = DeleteBlockingRelations(
      intentionId: owner,
      relationIds: [firstId, secondId],
    );
    final revision = _TestRevision(1);
    final outgoing = _relation(firstId, owner, firstNeighbor);
    final incoming = _relation(secondId, secondNeighbor, owner);
    final outcome = BlockingRelationsDeleted(
      command: command,
      revision: revision,
      deletedRelations: [outgoing, incoming],
      counts: {
        owner: _counts(0),
        firstNeighbor: _counts(1),
        secondNeighbor: _counts(2),
      },
    );
    final DeleteBlockingRelationsResult result = GraphResultSuccess(
      ConfirmedGraphResult(revision: revision, value: outcome),
    );

    final confirmed =
        (result as GraphResultSuccess).value
            as ConfirmedGraphResult<BlockingRelationsDeleted>;
    final deletions = confirmed.changes
        .whereType<LongTermRelationDeletedChange>()
        .toList();
    final changedCounts = confirmed.changes
        .whereType<IntentionRelationCountsChanged>()
        .toList();
    expect(confirmed.revision, same(revision));
    expect(
      deletions.map((change) => change.id),
      unorderedEquals([firstId, secondId]),
    );
    expect(
      deletions.map((change) => change.before),
      containsAll([outgoing, incoming]),
    );
    expect(
      changedCounts.map((change) => change.intentionId),
      unorderedEquals([owner, firstNeighbor, secondNeighbor]),
    );
    expect(
      changedCounts.singleWhere((change) => change.intentionId == owner).counts,
      _counts(0),
    );
    expect(confirmed.changes, hasLength(5));
  });

  test('результат отклоняет неполное удаление и неполные счётчики', () {
    final command = DeleteBlockingRelations(
      intentionId: owner,
      relationIds: [firstId, secondId],
    );
    final relation = _relation(firstId, owner, firstNeighbor);
    final revision = _TestRevision(1);
    expect(
      () => BlockingRelationsDeleted(
        command: command,
        revision: revision,
        deletedRelations: [relation],
        counts: {owner: _counts(0), firstNeighbor: _counts(0)},
      ),
      throwsA(isA<BlockingRelationsDeletedValidationException>()),
    );
    expect(
      () => BlockingRelationsDeleted(
        command: DeleteBlockingRelations(
          intentionId: owner,
          relationIds: [firstId],
        ),
        revision: revision,
        deletedRelations: [relation],
        counts: {owner: _counts(0)},
      ),
      throwsA(isA<BlockingRelationsDeletedValidationException>()),
    );
  });
}

IntentionId _intentionId(int value) =>
    switch (IntentionId.decode(_uuid(value))) {
      IntentionIdDecodingSuccess(:final id) => id,
      InvalidIntentionIdDecoding() => throw StateError(
        'Недопустимый идентификатор',
      ),
    };

LongTermRelationId _relationId(int value) =>
    switch (LongTermRelationId.decode(_uuid(value))) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Недопустимый идентификатор',
      ),
    };

String _uuid(int value) =>
    '00000000-0000-4000-8000-${value.toRadixString(16).padLeft(12, '0')}';

LongTermRelation _relation(
  LongTermRelationId id,
  IntentionId source,
  IntentionId related,
) => LongTermRelation(
  id: id,
  sourceIntentionId: source,
  relatedIntentionId: related,
  type: LongTermRelationType.need,
  priority: RelationPriority.p1,
  scope: RelationScope.archived,
  creationSequence: RelationCreationSequence(1),
);

RelationCounts _counts(int count) => RelationCounts(
  activeNeedIncoming: count,
  activeNeedOutgoing: 0,
  activeCanIncoming: 0,
  activeCanOutgoing: 0,
  archivedNeedIncoming: 0,
  archivedNeedOutgoing: 0,
  archivedCanIncoming: 0,
  archivedCanOutgoing: 0,
);

final class _TestRevision implements GraphRevision {
  const _TestRevision(this.value);

  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    _TestRevision(:final value) when value < this.value =>
      GraphRevisionOrder.newer,
    _TestRevision(:final value) when value == this.value =>
      GraphRevisionOrder.same,
    _TestRevision() => GraphRevisionOrder.older,
    _ => GraphRevisionOrder.differentEpoch,
  };
}
