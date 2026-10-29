import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/intention_choices/intention_choices_state.dart';
import 'package:doable/src/daily_choice/presentation/intention_choices/intention_choices_view_model.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_page_target.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/presentation/relation_group_paging_policy.dart';
import 'package:doable/src/long_term_relation/presentation/relation_list_reconciliation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../long_term_relation/presentation/neighborhood/neighborhood_test_support.dart';
import '../../../support/daily_choice_reconciliation_fixture.dart';

void main() {
  test(
    'без сохранённого выбора вкладка начинает с первой порции роли «исходное»',
    () async {
      final repository = ControlledNeighborhoodRepository();
      final harness = _ChoicesHarness(repository);
      addTearDown(harness.dispose);

      expect(harness.state, isA<IntentionChoicesInitialLoad>());
      expect(harness.state.role, DailyChoiceRelationRole.source);
      expect(repository.requestCount, 1);
      final query = repository.pageQueryAt(0) as DailyChoiceGroupQuery;
      expect(query.role, DailyChoiceRelationRole.source);
      expect(query.cursor, isNull);
    },
  );

  test(
    'смена роли записывается в экземпляр, и новая модель начинает с неё заново',
    () async {
      final repository = ControlledNeighborhoodRepository();
      final harness = _ChoicesHarness(repository, pageSize: 1);
      addTearDown(harness.dispose);
      repository.completePage(
        0,
        DailyChoiceGroupFirstPage(
          items: [
            testDailyCatalogItem(
              source: harness.intentionId,
              selected: testIntentionId(2),
            ),
          ],
          counts: testRelationCounts(dailySource: 1, dailySelected: 2),
          nextCursor: null,
          revision: const TestGraphRevision(1),
        ),
      );
      await pumpEventQueue();

      harness.viewModel.selectRole(DailyChoiceRelationRole.selected);
      expect(
        harness.pageInstance.choicesRole,
        DailyChoiceRelationRole.selected,
      );
      expect(harness.state, isA<IntentionChoicesInitialLoad>());
      expect(
        (repository.pageQueryAt(1) as DailyChoiceGroupQuery).role,
        DailyChoiceRelationRole.selected,
      );
      repository.completePage(
        1,
        DailyChoiceGroupFirstPage(
          items: [
            testDailyCatalogItem(
              source: testIntentionId(2),
              selected: harness.intentionId,
            ),
          ],
          counts: testRelationCounts(dailySource: 1, dailySelected: 2),
          nextCursor: const TestRelationGroupCursor(1),
          revision: const TestGraphRevision(1),
        ),
      );
      await pumpEventQueue();
      harness.scrollTo(0);
      expect(repository.requestCount, 3);

      await harness.release();
      harness.retain();
      expect(harness.state, isA<IntentionChoicesInitialLoad>());
      expect(harness.state.role, DailyChoiceRelationRole.selected);
      final query = repository.pageQueryAt(3) as DailyChoiceGroupQuery;
      expect(query.role, DailyChoiceRelationRole.selected);
      expect(query.cursor, isNull);
    },
  );

  test('две страницы одного намерения не делят роль и порции', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _ChoicesHarness(repository);
    addTearDown(harness.dispose);
    final other = IntentionPageInstance(target: const OverviewTarget());
    final otherSubscription = harness.container.listen(
      intentionChoicesViewModelProvider(harness.intentionId, other),
      (_, _) {},
    );
    addTearDown(otherSubscription.close);
    IntentionChoicesState otherState() => harness.container.read(
      intentionChoicesViewModelProvider(harness.intentionId, other),
    );

    harness.viewModel.selectRole(DailyChoiceRelationRole.selected);
    expect(
      (repository.pageQueryAt(2) as DailyChoiceGroupQuery).role,
      DailyChoiceRelationRole.selected,
    );
    expect(other.choicesRole, DailyChoiceRelationRole.source);
    expect(otherState().role, DailyChoiceRelationRole.source);

    repository.completePage(
      1,
      DailyChoiceGroupFirstPage(
        items: [
          testDailyCatalogItem(
            source: harness.intentionId,
            selected: testIntentionId(2),
          ),
        ],
        counts: testRelationCounts(dailySource: 1, dailySelected: 1),
        nextCursor: null,
        revision: const TestGraphRevision(1),
      ),
    );
    await pumpEventQueue();
    expect(otherState(), isA<IntentionChoicesLoaded>());
    expect(harness.state, isA<IntentionChoicesInitialLoad>());

    repository.completePage(
      2,
      DailyChoiceGroupFirstPage(
        items: [
          testDailyCatalogItem(
            source: testIntentionId(3),
            selected: harness.intentionId,
          ),
        ],
        counts: testRelationCounts(dailySource: 1, dailySelected: 1),
        nextCursor: null,
        revision: const TestGraphRevision(1),
      ),
    );
    await pumpEventQueue();
    expect(harness.loaded.items.single.source.id, testIntentionId(3));
    final otherLoaded = otherState() as IntentionChoicesLoaded;
    expect(otherLoaded.role, DailyChoiceRelationRole.source);
    expect(otherLoaded.items.single.selected.id, testIntentionId(2));
  });

  test('освобождённая модель не читает и не публикует поздний ответ', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _ChoicesHarness(repository);
    addTearDown(harness.dispose);

    await harness.release();
    repository.emitIntention(
      testNeighborhoodIntention(id: harness.intentionId),
      counts: testRelationCounts(dailySource: 1),
      revision: const TestGraphRevision(2),
    );
    repository.completePage(
      0,
      DailyChoiceGroupFirstPage(
        items: [
          testDailyCatalogItem(
            source: harness.intentionId,
            selected: testIntentionId(2),
          ),
        ],
        counts: testRelationCounts(dailySource: 1),
        nextCursor: null,
        revision: const TestGraphRevision(1),
      ),
    );
    await pumpEventQueue();
    expect(repository.requestCount, 1);

    harness.retain();
    await pumpEventQueue();
    expect(harness.state, isA<IntentionChoicesInitialLoad>());
    expect(repository.requestCount, 2);
  });

  test('поздний ответ прежней роли не заменяет новую выбранную роль', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _ChoicesHarness(repository);
    addTearDown(harness.dispose);
    harness.viewModel.selectRole(DailyChoiceRelationRole.selected);
    expect(
      (repository.pageQueryAt(1) as DailyChoiceGroupQuery).role,
      DailyChoiceRelationRole.selected,
    );
    repository.completePage(
      1,
      DailyChoiceGroupFirstPage(
        items: [
          testDailyCatalogItem(
            source: testIntentionId(2),
            selected: harness.intentionId,
          ),
        ],
        counts: testRelationCounts(dailySource: 1, dailySelected: 1),
        nextCursor: null,
        revision: const TestGraphRevision(2),
      ),
    );
    await pumpEventQueue();
    repository.completePage(
      0,
      DailyChoiceGroupFirstPage(
        items: [
          testDailyCatalogItem(
            source: harness.intentionId,
            selected: testIntentionId(2),
          ),
        ],
        counts: testRelationCounts(dailySource: 1, dailySelected: 1),
        nextCursor: null,
        revision: const TestGraphRevision(1),
      ),
    );
    await pumpEventQueue();
    expect(harness.loaded.role, DailyChoiceRelationRole.selected);
    expect(harness.loaded.items.single.selected.id, harness.intentionId);
  });

  test(
    'изменение показанного дневного выбора сохраняет старую пару до замены',
    () async {
      final repository = ControlledNeighborhoodRepository();
      final harness = _ChoicesHarness(repository);
      addTearDown(harness.dispose);
      repository.completePage(
        0,
        DailyChoiceGroupFirstPage(
          items: [
            testDailyCatalogItem(
              source: harness.intentionId,
              selected: testIntentionId(2),
            ),
          ],
          counts: testRelationCounts(dailySource: 1),
          nextCursor: null,
          revision: const TestGraphRevision(1),
        ),
      );
      await pumpEventQueue();
      repository.emitIntention(
        testNeighborhoodIntention(id: harness.intentionId),
        counts: testRelationCounts(dailySource: 1),
        revision: const TestGraphRevision(2),
      );
      await pumpEventQueue();
      final refreshing = harness.loaded;
      expect(refreshing.items.single.isCompleted, isFalse);
      expect(refreshing.summaryStatus, isA<RelationListSummaryRefreshing>());
      repository.completePage(
        1,
        DailyChoiceGroupFirstPage(
          items: [
            testDailyCatalogItem(
              source: harness.intentionId,
              selected: testIntentionId(2),
              isCompleted: true,
            ),
          ],
          counts: testRelationCounts(dailySource: 1),
          nextCursor: null,
          revision: const TestGraphRevision(2),
        ),
      );
      await pumpEventQueue();
      final updated = harness.loaded;
      expect(updated.items.single.isCompleted, isTrue);
      expect(updated.summaryStatus, isA<RelationListSummaryCurrent>());
    },
  );

  test(
    'ошибка замены дневной роли оставляет согласованные строки и числа',
    () async {
      final repository = ControlledNeighborhoodRepository();
      final harness = _ChoicesHarness(repository);
      addTearDown(harness.dispose);
      repository.completePage(
        0,
        DailyChoiceGroupFirstPage(
          items: [
            testDailyCatalogItem(
              source: harness.intentionId,
              selected: testIntentionId(2),
            ),
          ],
          counts: testRelationCounts(dailySource: 1),
          nextCursor: null,
          revision: const TestGraphRevision(1),
        ),
      );
      await pumpEventQueue();
      repository.emitIntention(
        testNeighborhoodIntention(id: harness.intentionId),
        counts: testRelationCounts(),
        revision: const TestGraphRevision(2),
      );
      await pumpEventQueue();
      repository.failRead(1, const RelationGroupUnavailableFailure());
      await pumpEventQueue();
      final stale = harness.loaded;
      expect(stale.items, hasLength(1));
      expect(stale.counts.dailySource, 1);
      expect(
        stale.summaryStatus,
        isA<RelationListSummaryRefreshFailure>().having(
          (status) => status.canRetry,
          'canRetry',
          isTrue,
        ),
      );
    },
  );

  test(
    'подтверждённое изменение даты и выполнения пересобирает дневную строку',
    () async {
      final repository = ControlledNeighborhoodRepository();
      final harness = _ChoicesHarness(repository);
      addTearDown(harness.dispose);
      final choice = reconciliationChoice(
        source: harness.intentionId,
        selected: testIntentionId(2),
      );
      repository.completePage(
        0,
        DailyChoiceGroupFirstPage(
          items: [
            testDailyCatalogItem(
              source: harness.intentionId,
              selected: testIntentionId(2),
            ),
          ],
          counts: testRelationCounts(dailySource: 1),
          nextCursor: null,
          revision: const TestGraphRevision(1),
        ),
      );
      await pumpEventQueue();

      final start = harness.coordinator.acceptDailyChoiceUpdate(
        UpdateDailyChoiceFields(
          choiceId: choice.id,
          patch: DailyChoiceFieldsPatch(
            date: DailyChoiceFieldSet(CalendarDate.fromParts(2026, 9, 24)),
            isCompleted: const DailyChoiceFieldSet(true),
          ),
        ),
      ) as DailyChoiceCommandAccepted;
      repository.completeDailyChoiceCommand(
        0,
        testDailyFieldsUpdatedResult(
          before: choice,
          after: DailyChoice(
            id: choice.id,
            sourceIntentionId: choice.sourceIntentionId,
            selectedIntentionId: choice.selectedIntentionId,
            date: CalendarDate.fromParts(2026, 9, 24),
            description: choice.description,
            isCompleted: true,
          ),
          counts: {
            harness.intentionId: testRelationCounts(dailySource: 1),
            testIntentionId(2): testRelationCounts(dailySelected: 1),
          },
        ),
      );
      await start.future;
      await pumpEventQueue();
      expect(
        harness.loaded.summaryStatus,
        isA<RelationListSummaryRefreshing>(),
      );
      repository.completePage(
        1,
        DailyChoiceGroupFirstPage(
          items: [
            testDailyCatalogItem(
              source: harness.intentionId,
              selected: testIntentionId(2),
              date: CalendarDate.fromParts(2026, 9, 24),
              isCompleted: true,
            ),
          ],
          counts: testRelationCounts(dailySource: 1),
          nextCursor: null,
          revision: const TestGraphRevision(2),
        ),
      );
      await pumpEventQueue();
      final item = harness.loaded.items.single;
      expect(item.isCompleted, isTrue);
      expect(item.date, CalendarDate.fromParts(2026, 9, 24));
    },
  );

  test(
    'удаление последнего выбора заменяет роль пустой на новой ревизии',
    () async {
      final repository = ControlledNeighborhoodRepository();
      final harness = _ChoicesHarness(repository);
      addTearDown(harness.dispose);
      final choice = reconciliationChoice(
        source: harness.intentionId,
        selected: testIntentionId(2),
      );
      repository.completePage(
        0,
        DailyChoiceGroupFirstPage(
          items: [
            testDailyCatalogItem(
              source: harness.intentionId,
              selected: testIntentionId(2),
            ),
          ],
          counts: testRelationCounts(dailySource: 1),
          nextCursor: null,
          revision: const TestGraphRevision(1),
        ),
      );
      await pumpEventQueue();
      final start = harness.coordinator.acceptDailyChoiceDelete(
        DeleteDailyChoice(choice.id),
      ) as DailyChoiceCommandAccepted;
      repository.completeDailyChoiceCommand(
        0,
        reconciliationChoiceDeleted(
          choice: choice,
          pathRelationId: testRelationId(1),
          revision: const TestGraphRevision(2),
          counts: {
            harness.intentionId: testRelationCounts(),
            testIntentionId(2): testRelationCounts(),
          },
        ),
      );
      await start.future;
      await pumpEventQueue();
      expect(
        harness.loaded.summaryStatus,
        isA<RelationListSummaryRefreshing>(),
      );
      repository.completePage(
        1,
        DailyChoiceGroupFirstPage(
          items: const [],
          counts: testRelationCounts(),
          nextCursor: null,
          revision: const TestGraphRevision(2),
        ),
      );
      await pumpEventQueue();
      final empty = harness.state as IntentionChoicesEmpty;
      expect(empty.role, DailyChoiceRelationRole.source);
      expect(empty.counts.total, 0);
    },
  );

  test('поздняя порция роли уступает новой основе перед подгрузкой', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _ChoicesHarness(repository, pageSize: 1);
    addTearDown(harness.dispose);
    repository.completePage(
      0,
      DailyChoiceGroupFirstPage(
        items: [
          testDailyCatalogItem(
            source: harness.intentionId,
            selected: testIntentionId(2),
          ),
        ],
        counts: testRelationCounts(dailySource: 2),
        nextCursor: const TestRelationGroupCursor(1),
        revision: const TestGraphRevision(1),
      ),
    );
    await pumpEventQueue();
    harness.scrollTo(0);
    expect(repository.pageQueryAt(1).cursor, const TestRelationGroupCursor(1));
    repository.emitIntention(
      testNeighborhoodIntention(id: harness.intentionId),
      counts: testRelationCounts(dailySource: 1),
      revision: const TestGraphRevision(2),
    );
    await pumpEventQueue();
    expect(harness.loaded.summaryStatus, isA<RelationListSummaryRefreshing>());
    repository.completePage(
      1,
      DailyChoiceGroupContinuationPage(
        items: const [],
        nextCursor: null,
        revision: const TestGraphRevision(1),
      ),
    );
    await pumpEventQueue();
    repository.completePage(
      2,
      DailyChoiceGroupFirstPage(
        items: [
          testDailyCatalogItem(
            source: harness.intentionId,
            selected: testIntentionId(2),
          ),
        ],
        counts: testRelationCounts(dailySource: 1),
        nextCursor: null,
        revision: const TestGraphRevision(2),
      ),
    );
    await pumpEventQueue();
    final current = harness.loaded;
    expect(current.items, hasLength(1));
    expect(current.counts.dailySource, 1);
    expect(current.hasConfirmedEnd, isTrue);
  });

  test('посторонняя ревизия требует новой основы роли', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _ChoicesHarness(repository, pageSize: 1);
    addTearDown(harness.dispose);
    repository.completePage(
      0,
      DailyChoiceGroupFirstPage(
        items: [
          testDailyCatalogItem(
            source: harness.intentionId,
            selected: testIntentionId(2),
          ),
        ],
        counts: testRelationCounts(dailySource: 2),
        nextCursor: const TestRelationGroupCursor(1),
        revision: const TestGraphRevision(1),
      ),
    );
    await pumpEventQueue();
    harness.scrollTo(0);
    repository.failRead(1, const RelationGroupSnapshotExpired());
    await pumpEventQueue();
    expect(repository.pageQueryAt(2).cursor, isNull);
    expect(harness.loaded.summaryStatus, isA<RelationListSummaryRefreshing>());
    repository.completePage(
      2,
      DailyChoiceGroupFirstPage(
        items: [
          testDailyCatalogItem(
            source: harness.intentionId,
            selected: testIntentionId(2),
          ),
        ],
        counts: testRelationCounts(dailySource: 1),
        nextCursor: null,
        revision: const TestGraphRevision(2),
      ),
    );
    await pumpEventQueue();
    final current = harness.loaded;
    expect(current.counts.dailySource, 1);
    expect(current.hasConfirmedEnd, isTrue);
  });

  test(
    'новая дата незагруженного выбора перестраивает видимую часть роли',
    () async {
      final repository = ControlledNeighborhoodRepository();
      final harness = _ChoicesHarness(repository, pageSize: 1);
      addTearDown(harness.dispose);
      final unseenId = _choiceId(2);
      repository.completePage(
        0,
        DailyChoiceGroupFirstPage(
          items: [
            testDailyCatalogItem(
              source: harness.intentionId,
              selected: testIntentionId(2),
            ),
          ],
          counts: testRelationCounts(dailySource: 2),
          nextCursor: const TestRelationGroupCursor(1),
          revision: const TestGraphRevision(1),
        ),
      );
      await pumpEventQueue();
      final before = DailyChoice(
        id: unseenId,
        sourceIntentionId: harness.intentionId,
        selectedIntentionId: testIntentionId(3),
        date: CalendarDate.fromParts(2026, 9, 22),
        description: null,
        isCompleted: false,
      );
      final after = DailyChoice(
        id: unseenId,
        sourceIntentionId: harness.intentionId,
        selectedIntentionId: testIntentionId(3),
        date: CalendarDate.fromParts(2026, 9, 24),
        description: null,
        isCompleted: false,
      );
      final start = harness.coordinator.acceptDailyChoiceUpdate(
        UpdateDailyChoiceFields(
          choiceId: unseenId,
          patch: DailyChoiceFieldsPatch(date: DailyChoiceFieldSet(after.date)),
        ),
      ) as DailyChoiceCommandAccepted;
      repository.completeDailyChoiceCommand(
        0,
        testDailyFieldsUpdatedResult(
          before: before,
          after: after,
          counts: {
            harness.intentionId: testRelationCounts(dailySource: 2),
            testIntentionId(3): testRelationCounts(dailySelected: 1),
          },
        ),
      );
      await start.future;
      await pumpEventQueue();
      expect(
        harness.loaded.summaryStatus,
        isA<RelationListSummaryRefreshing>(),
      );
      repository.completePage(
        1,
        DailyChoiceGroupFirstPage(
          items: [
            testDailyCatalogItem(
              id: unseenId,
              source: harness.intentionId,
              selected: testIntentionId(3),
              date: after.date,
            ),
          ],
          counts: testRelationCounts(dailySource: 2),
          nextCursor: const TestRelationGroupCursor(1),
          revision: const TestGraphRevision(2),
        ),
      );
      await pumpEventQueue();
      final visible = harness.loaded;
      expect(visible.items.single.id, unseenId);
      expect(visible.counts.dailySource, 2);
    },
  );

  test('переименование показанного участника пересобирает роль', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _ChoicesHarness(repository);
    addTearDown(harness.dispose);
    final participantId = testIntentionId(2);
    repository.completePage(
      0,
      DailyChoiceGroupFirstPage(
        items: [
          testDailyCatalogItem(
            source: harness.intentionId,
            selected: participantId,
          ),
        ],
        counts: testRelationCounts(dailySource: 1),
        nextCursor: null,
        revision: const TestGraphRevision(1),
      ),
    );
    await pumpEventQueue();
    final before = testNeighborhoodIntention(
      id: participantId,
      title: 'Действие',
    );
    final after = testNeighborhoodIntention(
      id: participantId,
      title: 'Новое действие',
    );
    final start = harness.coordinator.acceptExisting(
      UpdateIntention(
        id: participantId,
        title: after.title,
        description: after.description,
      ),
      presentationTitle: before.title,
    ) as IntentionCommandAccepted;
    repository.completeIntentionCommand(
      0,
      testNeighborhoodSavedResult(
        before: before,
        after: after,
        revision: const TestGraphRevision(2),
      ),
    );
    await start.future;
    await pumpEventQueue();
    expect(harness.loaded.summaryStatus, isA<RelationListSummaryRefreshing>());
    expect(harness.loaded.items.single.selected.title, 'Действие');
    repository.completePage(
      1,
      DailyChoiceGroupFirstPage(
        items: [
          testDailyCatalogItem(
            source: harness.intentionId,
            selected: participantId,
            selectedTitle: 'Новое действие',
          ),
        ],
        counts: testRelationCounts(dailySource: 1),
        nextCursor: null,
        revision: const TestGraphRevision(2),
      ),
    );
    await pumpEventQueue();
    expect(harness.loaded.items.single.selected.title, 'Новое действие');
  });

  test('устранимый отказ первого чтения роли повторяется', () async {
    final repository = ControlledNeighborhoodRepository();
    final harness = _ChoicesHarness(repository);
    addTearDown(harness.dispose);
    repository.failRead(0, const RelationGroupUnavailableFailure());
    await pumpEventQueue();
    final failure = harness.state as IntentionChoicesInitialFailure;
    expect(failure.canRetry, isTrue);

    harness.retryFirstPage();
    expect(harness.state, isA<IntentionChoicesInitialLoad>());
    expect(
      (repository.pageQueryAt(1) as DailyChoiceGroupQuery).role,
      DailyChoiceRelationRole.source,
    );
    repository.completePage(
      1,
      DailyChoiceGroupFirstPage(
        items: [
          testDailyCatalogItem(
            source: harness.intentionId,
            selected: testIntentionId(2),
          ),
        ],
        counts: testRelationCounts(dailySource: 1),
        nextCursor: null,
        revision: const TestGraphRevision(1),
      ),
    );
    await pumpEventQueue();
    expect(harness.loaded.items, hasLength(1));
  });

  test(
    'отказ подгрузки сохраняет строки, а повтор продолжает список один раз',
    () async {
      final repository = ControlledNeighborhoodRepository();
      final harness = _ChoicesHarness(repository, pageSize: 1);
      addTearDown(harness.dispose);
      repository.completePage(
        0,
        DailyChoiceGroupFirstPage(
          items: [
            testDailyCatalogItem(
              source: harness.intentionId,
              selected: testIntentionId(2),
            ),
          ],
          counts: testRelationCounts(dailySource: 2),
          nextCursor: const TestRelationGroupCursor(1),
          revision: const TestGraphRevision(1),
        ),
      );
      await pumpEventQueue();
      harness.scrollTo(0);
      repository.failRead(1, const RelationGroupUnavailableFailure());
      await pumpEventQueue();
      expect(harness.loaded.items, hasLength(1));
      expect(
        harness.loaded.progress,
        isA<RelationListLoadMoreFailure>().having(
          (progress) => progress.canRetry,
          'canRetry',
          isTrue,
        ),
      );

      harness.retryLoadMore();
      harness.retryLoadMore();
      expect(repository.requestCount, 3);
      expect(
        repository.pageQueryAt(2).cursor,
        const TestRelationGroupCursor(1),
      );
      repository.completePage(
        2,
        DailyChoiceGroupContinuationPage(
          items: [
            testDailyCatalogItem(
              id: _choiceId(2),
              source: harness.intentionId,
              selected: testIntentionId(3),
            ),
          ],
          nextCursor: null,
          revision: const TestGraphRevision(1),
        ),
      );
      await pumpEventQueue();
      expect(harness.loaded.items, hasLength(2));
      expect(harness.loaded.hasConfirmedEnd, isTrue);
    },
  );

  test(
    'подтверждённое отсутствие намерения завершает вкладку без новых чтений',
    () async {
      final repository = ControlledNeighborhoodRepository();
      final harness = _ChoicesHarness(repository);
      addTearDown(harness.dispose);
      repository.completePage(
        0,
        DailyChoiceGroupFirstPage(
          items: [
            testDailyCatalogItem(
              source: harness.intentionId,
              selected: testIntentionId(2),
            ),
          ],
          counts: testRelationCounts(dailySource: 1),
          nextCursor: null,
          revision: const TestGraphRevision(1),
        ),
      );
      await pumpEventQueue();

      repository.emitIntentionNotFound(revision: const TestGraphRevision(2));
      await pumpEventQueue();
      expect(harness.state, isA<IntentionChoicesIntentionNotFound>());

      harness.viewModel.selectRole(DailyChoiceRelationRole.selected);
      repository.emitIntention(
        testNeighborhoodIntention(id: harness.intentionId),
        counts: testRelationCounts(dailySource: 1),
        revision: const TestGraphRevision(3),
      );
      await pumpEventQueue();
      expect(harness.state, isA<IntentionChoicesIntentionNotFound>());
      expect(repository.requestCount, 1);
    },
  );
}

DailyChoiceId _choiceId(int index) => switch (DailyChoiceId.decode(
  '018f0002-0000-7000-8000-${index.toString().padLeft(12, '0')}',
)) {
  DailyChoiceIdDecodingSuccess(:final id) => id,
  InvalidDailyChoiceIdDecoding() => throw StateError('Некорректный ID.'),
};

final class _ChoicesHarness {
  _ChoicesHarness(this.repository, {int pageSize = 50})
    : intentionId = testIntentionId(1) {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        relationGroupPagingPolicyProvider.overrideWithValue(
          RelationGroupPagingPolicy(
            pageSize: pageSize,
            prefetchRemaining: pageSize - 1,
          ),
        ),
      ],
      retry: (retryCount, error) => null,
    );
    retain();
  }

  final ControlledNeighborhoodRepository repository;
  final IntentionId intentionId;
  final pageInstance = IntentionPageInstance(target: const OverviewTarget());
  late final ProviderContainer container;
  ProviderSubscription<IntentionChoicesState>? _subscription;

  IntentionChoicesViewModelProvider get _provider =>
      intentionChoicesViewModelProvider(intentionId, pageInstance);

  IntentionChoicesViewModel get viewModel => container.read(_provider.notifier);

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  IntentionChoicesState get state => container.read(_provider);

  IntentionChoicesLoaded get loaded => state as IntentionChoicesLoaded;

  /// Слушатель удерживает модель, как выбранная вкладка страницы.
  void retain() {
    _subscription = container.listen(_provider, (_, _) {});
  }

  /// Снимает слушателя и ждёт автоматического освобождения модели.
  Future<void> release() async {
    _subscription?.close();
    _subscription = null;
    await container.pump();
    expect(container.exists(_provider), isFalse);
  }

  /// Прокрутка не ожидает ответа: порция приходит по команде теста.
  void scrollTo(int visibleIndex) =>
      unawaited(viewModel.loadMoreIfNeeded(visibleIndex: visibleIndex));

  void retryFirstPage() => unawaited(viewModel.retryFirstPage());

  void retryLoadMore() => unawaited(viewModel.retryLoadMore());

  void dispose() {
    _subscription?.close();
    container.dispose();
    unawaited(repository.dispose());
  }
}
