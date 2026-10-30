import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/pair_occupant_reconciliation.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_pair_probe.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_test_support.dart';

void main() {
  const revision = TestCatalogRevision(2);
  final counterpart = testSummary(index: 9).id;
  final otherIntention = testSummary(index: 8).id;
  final row = testSummary(index: 1).id;
  final otherRow = testSummary(index: 2).id;
  final unloaded = testSummary(index: 3).id;

  final choosingRelated = RelationPairProbe(
    counterpartId: counterpart,
    candidateRole: RelationParticipantRole.related,
  );
  final choosingSource = RelationPairProbe(
    counterpartId: counterpart,
    candidateRole: RelationParticipantRole.source,
  );

  LongTermRelation relation({
    required IntentionId source,
    required IntentionId related,
    int index = 1,
    RelationScope scope = RelationScope.active,
  }) => testRelation(
    sourceIntentionId: source,
    relatedIntentionId: related,
    index: index,
    scope: scope,
  );

  PairOccupant occupantOf(LongTermRelation relation) =>
      PairOccupant(relationId: relation.id, scope: relation.scope);

  Map<IntentionId, PairOccupant> reconcile(
    Iterable<LongTermRelationChange> changes, {
    RelationPairProbe? probe,
    Map<IntentionId, PairOccupant> occupants = const {},
  }) => reconcilePairOccupants(
    probe: probe ?? choosingRelated,
    occupants: occupants,
    rowIds: {row, otherRow},
    changes: changes,
  );

  test('созданная связь занимает пару загруженной строки', () {
    final created = relation(source: counterpart, related: row);

    expect(
      reconcile([
        LongTermRelationCreatedChange(revision: revision, relation: created),
      ]),
      {row: occupantOf(created)},
    );
  });

  test('созданная связь не отмечает незагруженную строку', () {
    expect(
      reconcile([
        LongTermRelationCreatedChange(
          revision: revision,
          relation: relation(source: counterpart, related: unloaded),
        ),
      ]),
      isEmpty,
    );
  });

  test('при выборе исходного намерения пару занимает связь к участнику', () {
    final created = relation(source: row, related: counterpart);

    expect(
      reconcile([
        LongTermRelationCreatedChange(revision: revision, relation: created),
      ], probe: choosingSource),
      {row: occupantOf(created)},
    );
  });

  test('связь обратного направления пару не занимает', () {
    expect(
      reconcile([
        LongTermRelationCreatedChange(
          revision: revision,
          relation: relation(source: row, related: counterpart),
        ),
      ]),
      isEmpty,
    );
  });

  test('замена связанного участника переносит отметку на новую строку', () {
    final before = relation(source: counterpart, related: row);
    final after = relation(source: counterpart, related: otherRow);

    expect(
      reconcile(
        [
          LongTermRelationUpdatedChange(
            revision: revision,
            before: before,
            after: after,
          ),
        ],
        occupants: {row: occupantOf(before)},
      ),
      {otherRow: occupantOf(after)},
    );
  });

  test('замена участника другой роли снимает отметку строки', () {
    final before = relation(source: counterpart, related: row);

    expect(
      reconcile(
        [
          LongTermRelationUpdatedChange(
            revision: revision,
            before: before,
            after: relation(source: otherIntention, related: row),
          ),
        ],
        occupants: {row: occupantOf(before)},
      ),
      isEmpty,
    );
  });

  test('архивирование делает отметку архивной', () {
    final before = relation(source: counterpart, related: row);
    final after = relation(
      source: counterpart,
      related: row,
      scope: RelationScope.archived,
    );

    expect(
      reconcile(
        [
          LongTermRelationUpdatedChange(
            revision: revision,
            before: before,
            after: after,
          ),
        ],
        occupants: {row: occupantOf(before)},
      ),
      {row: occupantOf(after)},
    );
  });

  test('восстановление делает отметку активной', () {
    final before = relation(
      source: counterpart,
      related: row,
      scope: RelationScope.archived,
    );
    final after = relation(source: counterpart, related: row);

    expect(
      reconcile(
        [
          LongTermRelationUpdatedChange(
            revision: revision,
            before: before,
            after: after,
          ),
        ],
        occupants: {row: occupantOf(before)},
      ),
      {row: occupantOf(after)},
    );
  });

  test('удаление снимает отметку строки', () {
    final deleted = relation(source: counterpart, related: row);

    expect(
      reconcile(
        [LongTermRelationDeletedChange(revision: revision, relation: deleted)],
        occupants: {row: occupantOf(deleted)},
      ),
      isEmpty,
    );
  });

  test('изменяемая связь пару не занимает', () {
    final edited = relation(source: counterpart, related: row);

    expect(
      reconcile(
        [LongTermRelationCreatedChange(revision: revision, relation: edited)],
        probe: RelationPairProbe(
          counterpartId: counterpart,
          candidateRole: RelationParticipantRole.related,
          ignoredRelationId: edited.id,
        ),
      ),
      isEmpty,
    );
  });

  test('прежнее состояние связи не снимает отметку другой связи', () {
    final moved = relation(source: counterpart, related: row, index: 1);
    final occupying = relation(source: counterpart, related: row, index: 2);

    expect(
      reconcile(
        [
          LongTermRelationUpdatedChange(
            revision: revision,
            before: moved,
            after: relation(source: counterpart, related: otherRow, index: 1),
          ),
        ],
        occupants: {row: occupantOf(occupying)},
      ),
      containsPair(row, occupantOf(occupying)),
    );
  });
}
