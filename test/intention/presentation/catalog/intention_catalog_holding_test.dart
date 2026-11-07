import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_holding.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_reconciliation_test_support.dart';
import 'catalog_test_support.dart';

const _catalog = BrowseIntentionCatalog();

void main() {
  test('удержание читается только для активных вспомогательных строк, а '
      'отказ чтения оставляет его неизвестным без повторов', () async {
    final repository = ControlledCatalogRepository();
    final container = _container(repository);
    final main = testSummary(index: 3);
    final held = testSummary(index: 2, kind: IntentionKind.supporting);
    final unheld = testSummary(index: 1, kind: IntentionKind.supporting);
    await _loadFirstPage(container, repository, [main, held, unheld]);

    expect(repository.holdingReads, [
      {held.id, unheld.id},
    ]);
    repository.completeHolding(
      0,
      IntentionHoldingRead(
        revision: const TestCatalogRevision(1),
        holdings: {
          held.id: IntentionHolding.held,
          unheld.id: IntentionHolding.notHeld,
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(_loaded(container).holdings, {
      held.id: IntentionHolding.held,
      unheld.id: IntentionHolding.notHeld,
    });

    await _changeHolding(container, repository, held, revision: 2);
    expect(_loaded(container).holdings, isEmpty);
    repository.completeHolding(1, const IntentionHoldingFailed());
    await Future<void>.delayed(Duration.zero);

    expect(_loaded(container).holdings, isEmpty);
    expect(repository.holdingReads, hasLength(2));
  });

  test('после изменения удержания строки остаются на местах, ждут новое '
      'удержание без прежнего и отбрасывают запоздалый ответ', () async {
    final repository = ControlledCatalogRepository();
    final container = _container(repository);
    final warmUp = testSummary(index: 2, kind: IntentionKind.supporting);
    final stretch = testSummary(index: 1, kind: IntentionKind.supporting);
    await _loadFirstPage(container, repository, [warmUp, stretch]);

    await _changeHolding(container, repository, warmUp, revision: 2);
    expect(repository.holdingReads, [
      {warmUp.id, stretch.id},
      {warmUp.id, stretch.id},
    ]);
    repository.completeHolding(
      0,
      IntentionHoldingRead(
        revision: const TestCatalogRevision(1),
        holdings: {
          warmUp.id: IntentionHolding.notHeld,
          stretch.id: IntentionHolding.notHeld,
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(_loaded(container).holdings, isEmpty);

    repository.completeHolding(
      1,
      IntentionHoldingRead(
        revision: const TestCatalogRevision(2),
        holdings: {
          warmUp.id: IntentionHolding.held,
          stretch.id: IntentionHolding.held,
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final current = _loaded(container);
    expect(current.items.map((item) => item.id), [warmUp.id, stretch.id]);
    expect(current.holdings, {
      warmUp.id: IntentionHolding.held,
      stretch.id: IntentionHolding.held,
    });
  });

  test('строки следующей порции читают удержание отдельно, не повторяя '
      'загруженные', () async {
    final repository = ControlledCatalogRepository();
    final container = _container(repository, pageSize: 2);
    final first = testSummary(index: 3, kind: IntentionKind.supporting);
    final next = testSummary(index: 1, kind: IntentionKind.supporting);
    await _loadFirstPage(
      container,
      repository,
      [first, testSummary(index: 2)],
      totalCount: 3,
      nextCursor: const TestCatalogCursor(),
    );

    final load = container
        .read(intentionCatalogViewModelProvider(_catalog).notifier)
        .loadNextPageIfNeeded(visibleIndex: 1);
    await waitForCatalogQueries(repository, 2);
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [next],
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await load;

    expect(repository.holdingReads, [
      {first.id},
      {next.id},
    ]);
  });
}

ProviderContainer _container(
  ControlledCatalogRepository repository, {
  int pageSize = 100,
}) {
  final container = reconciliationCatalogContainer(
    repository,
    pageSize: pageSize,
    prefetchRemaining: 1,
  );
  addTearDown(container.dispose);
  final subscription = container.listen(
    intentionCatalogViewModelProvider(_catalog),
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  return container;
}

Future<void> _loadFirstPage(
  ProviderContainer container,
  ControlledCatalogRepository repository,
  List<IntentionSummary> items, {
  int? totalCount,
  IntentionCatalogCursor? nextCursor,
}) async {
  repository.complete(
    0,
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: items,
        totalCount: totalCount ?? items.length,
        nextCursor: nextCursor,
        revision: const TestCatalogRevision(1),
      ),
    ),
  );
  await container.read(intentionCatalogViewModelProvider(_catalog).future);
  await Future<void>.delayed(Duration.zero);
}

/// Подтверждает добавление связи к [related] с изменением удержания.
Future<void> _changeHolding(
  ProviderContainer container,
  ControlledCatalogRepository repository,
  IntentionSummary related, {
  required int revision,
}) async {
  final graphRevision = TestCatalogRevision(revision);
  final holder = testSummary(index: 50);
  final relation = testRelation(
    sourceIntentionId: holder.id,
    relatedIntentionId: related.id,
  );
  await completeRelationCommand(
    container,
    repository,
    AddLongTermRelations(
      pageIntentionId: holder.id,
      candidateIds: [related.id],
      group: IntentionRelationGroup.needs,
    ),
    relationCreationSuccess(
      revision: graphRevision,
      success: LongTermRelationsAdded(
        relations: [relation],
        changes: [
          LongTermRelationCreatedChange(
            revision: graphRevision,
            relation: relation,
          ),
          IntentionHoldingChanged(revision: graphRevision),
        ],
      ),
    ),
  );
}

IntentionCatalogLoaded _loaded(ProviderContainer container) =>
    container.read(intentionCatalogViewModelProvider(_catalog)).requireValue
        as IntentionCatalogLoaded;
