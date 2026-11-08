import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/application/relation_pair_probe.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

final _participant = SelectRelationParticipant(
  session: IntentionSearchSession(),
  pairProbe: RelationPairProbe(
    counterpartId: testSummary(index: 999).id,
    candidateRole: RelationParticipantRole.related,
  ),
);

void main() {
  test(
    'пакет только с количествами связей продвигает ревизию и сохраняет выдачу',
    () async {
      final repository = ControlledCatalogRepository();
      final container = reconciliationCatalogContainer(repository);
      addTearDown(container.dispose);
      final subscription = container.listen(
        intentionCatalogViewModelProvider(_participant),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final action = testSummary(index: 1);
      final neighbour = testSummary(index: 2);
      repository.complete(
        0,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: [action],
            totalCount: 1,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await container.read(
        intentionCatalogViewModelProvider(_participant).future,
      );

      const revision = TestCatalogRevision(2);
      final relation = testRelation(
        sourceIntentionId: action.id,
        relatedIntentionId: neighbour.id,
        priority: RelationPriority.p4,
      );
      await completeRelationCommand(
        container,
        repository,
        AddLongTermRelations(
          pageIntentionId: action.id,
          candidateIds: [neighbour.id],
          group: IntentionRelationGroup.needs,
        ),
        relationCreationSuccess(
          revision: revision,
          success: LongTermRelationsAdded(
            relations: [relation],
            changes: [
              IntentionRelationCountsChanged(
                revision: revision,
                intentionId: action.id,
                counts: testRelationCounts(activeNeedOutgoing: 1),
              ),
              IntentionRelationCountsChanged(
                revision: revision,
                intentionId: neighbour.id,
                counts: testRelationCounts(activeNeedIncoming: 1),
              ),
              LongTermRelationCreatedChange(
                revision: revision,
                relation: relation,
              ),
            ],
          ),
        ),
      );

      final current =
          container
                  .read(intentionCatalogViewModelProvider(_participant))
                  .requireValue
              as IntentionCatalogLoaded;
      expect(current.items.single, same(action));
      expect(current.totalCount, 1);
      expect(current.nextCursor, isNull);
      expect(current.revision.compareTo(revision), GraphRevisionOrder.same);
      expect(repository.queries, hasLength(1));
    },
  );

  test('освобождение режима отменяет отложенный фильтр', () async {
    final repository = ControlledCatalogRepository();
    final container = reconciliationCatalogContainer(
      repository,
      filterDebounce: const Duration(milliseconds: 20),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      intentionCatalogViewModelProvider(_participant),
      (_, _) {},
      fireImmediately: true,
    );
    repository.complete(
      0,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await container.read(
      intentionCatalogViewModelProvider(_participant).future,
    );
    container
        .read(intentionCatalogViewModelProvider(_participant).notifier)
        .changeTitleFilter('позже');
    subscription.close();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(repository.queries, hasLength(1));
  });
}
