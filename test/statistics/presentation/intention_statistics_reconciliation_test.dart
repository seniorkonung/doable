import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_target.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'intention_statistics_test_support.dart';

void main() {
  test('скрытый раздел не начинает чтение, подгрузку или повтор', () async {
    final h = IntentionStatisticsHarness();
    addTearDown(h.dispose);
    final page = h.open(visible: false);
    page.model.selectPeriod(StatisticsYear(2025));
    page.model.selectView(StatisticsView.intermediateIntentions);
    page.model.setLocalDate(CalendarDate.fromParts(2026, 10, 13));
    await h.change(1);
    await page.model.loadMore(StatisticsBreakdown.selectedActions);
    await page.model.retryLoadMore(StatisticsBreakdown.selectedActions);
    await page.model.retry();
    await page.model.retryRefresh();
    expect(h.reader.queries, isEmpty);
    expect(h.reader.continuations, isEmpty);
    page.model.setVisible(true);
    page.model.setVisible(true);
    expect(h.reader.queries, hasLength(1));
    expect(h.reader.queries.single.period, StatisticsYear(2025));
    expect(h.reader.queries.single.view, StatisticsView.intermediateIntentions);
    expect(
      h.reader.queries.single.localDate,
      CalendarDate.fromParts(2026, 10, 13),
    );
    h.reader.section(0, revision: 1);
    await pumpEventQueue();
    expect(page.state.read, isA<IntentionStatisticsData>());
  });

  test('несколько скрытых изменений объединяются, другая страница читает независимо', () async {
    final h = IntentionStatisticsHarness();
    addTearDown(h.dispose);
    final page = h.open();
    h.reader.section(0, actionsCursor: StatisticsTestCursor<StatisticsItem>());
    await pumpEventQueue();
    page.model.setVisible(false);
    final top = h.open();
    h.reader.section(1);
    await pumpEventQueue();
    await h.change(1);
    h.reader.section(2, revision: 1, marker: 11);
    await pumpEventQueue();
    await h.change(2);
    h.reader.section(3, revision: 2, marker: 22);
    await pumpEventQueue();
    await page.model.loadMoreIfNeeded(StatisticsBreakdown.selectedActions, 0);
    expect(h.reader.continuations, isEmpty);
    expect(
      page.loaded.breakdowns.selectedActions!.items.single.id,
      statisticsId(1),
    );
    expect(
      top.loaded.breakdowns.selectedActions!.items.single.id,
      statisticsId(22),
    );
    top.model.setVisible(false);
    page.model.setVisible(true);
    expect(h.reader.queries, hasLength(5));
    expect(page.loaded.refreshStatus, isA<IntentionStatisticsRefreshing>());
    h.reader.section(4, revision: 2, marker: 22);
    await pumpEventQueue();
    expect(
      page.loaded.breakdowns.selectedActions!.items.single.id,
      statisticsId(22),
    );
    page.model.setVisible(false);
    page.model.setVisible(true);
    await h.change(2);
    expect(h.reader.queries, hasLength(5));
  });

  for (final (name, view) in [
    ('через связи', StatisticsView.throughRelations),
    ('по промежуточным намерениям', StatisticsView.intermediateIntentions),
  ]) {
    test(
      'раздел и обе разбивки $name заменяются только после всех порций',
      () async {
        final h = IntentionStatisticsHarness();
        addTearDown(h.dispose);
        final page = h.open(
          target: IntentionStatisticsTarget(
            view: view,
            period: StatisticsYear(2025),
          ),
        );
        await _loadBoth(h, page, view);
        await h.change(1);
        h.reader.section(
          1,
          revision: 1,
          marker: 501,
          count: 100,
          total: 350,
          sourcesCursor: StatisticsTestCursor<StatisticsItem>(),
          relationsCursor: StatisticsTestCursor<StatisticsRelationItem>(),
          actionsCursor: StatisticsTestCursor<StatisticsItem>(),
        );
        await pumpEventQueue();
        expect(page.loaded.section.selectedCounts.planned, 300);
        expect(
          page.loaded.breakdowns.selectedActions!.items.first.id,
          statisticsId(100),
        );
        _moreFirst(h, 4, view, revision: 1, cursor: true);
        await pumpEventQueue();
        _moreFirst(h, 5, view, revision: 1);
        await pumpEventQueue();
        expect(page.loaded.section.selectedCounts.planned, 300);
        expect(_firstLength(page, view), 300);
        h.reader.more(
          6,
          List.generate(100, (i) => statisticsItem(700 + i)),
          revision: 1,
          cursor: StatisticsTestCursor<StatisticsItem>(),
        );
        await pumpEventQueue();
        expect(page.loaded.section.selectedCounts.planned, 300);
        await page.model.loadMore(StatisticsBreakdown.selectedActions);
        expect(h.reader.continuations, hasLength(8));
        h.reader.more(
          7,
          List.generate(100, (i) => statisticsItem(800 + i)),
          revision: 1,
        );
        await pumpEventQueue();
        expect(page.loaded.section.selectedCounts.planned, 350);
        expect(page.loaded.breakdowns.selectedActions!.items, hasLength(300));
        expect(_firstLength(page, view), 300);
        expect(
          page.loaded.breakdowns.selectedActions!.items.first.id,
          statisticsId(600),
        );
        expect(
          page.loaded.refreshStatus,
          isA<IntentionStatisticsRefreshIdle>(),
        );
        expect(page.state.selection.period, StatisticsYear(2025));
        expect(h.reader.queries.every((q) => q.pageSize == 100), isTrue);
      },
    );
  }

  test(
    'команда между разбивками отбрасывает всю незавершённую замену',
    () async {
      final h = IntentionStatisticsHarness();
      addTearDown(h.dispose);
      final page = h.open();
      await _loadBoth(h, page, StatisticsView.throughRelations);
      await h.change(1);
      h.reader.section(
        1,
        revision: 1,
        count: 100,
        total: 300,
        relationsCursor: StatisticsTestCursor<StatisticsRelationItem>(),
        actionsCursor: StatisticsTestCursor<StatisticsItem>(),
      );
      await pumpEventQueue();
      _moreFirst(
        h,
        4,
        StatisticsView.throughRelations,
        revision: 1,
        cursor: true,
      );
      await pumpEventQueue();
      _moreFirst(h, 5, StatisticsView.throughRelations, revision: 1);
      await pumpEventQueue();
      expect(h.reader.continuations, hasLength(7));
      await h.change(2);
      h.reader.more(6, [statisticsItem(999)], revision: 1);
      await pumpEventQueue();
      expect(page.loaded.section.selectedCounts.planned, 300);
      expect(
        page.loaded.breakdowns.selectedActions!.items.first.id,
        statisticsId(100),
      );
      expect(h.reader.queries, hasLength(3));
      h.reader.section(2, revision: 2, marker: 22);
      await pumpEventQueue();
      expect(
        page.loaded.breakdowns.selectedActions!.items.single.id,
        statisticsId(22),
      );
      expect(
        page.loaded.breakdowns.relations!.items.single.relatedIntention.id,
        statisticsId(22),
      );
    },
  );

  test(
    'скрытие после ответа останавливает пересборку и позднее истечение снимка',
    () async {
      final h = IntentionStatisticsHarness();
      addTearDown(h.dispose);
      final page = h.open();
      await _loadBoth(h, page, StatisticsView.throughRelations);
      await h.change(1);
      h.reader.section(
        1,
        revision: 1,
        count: 100,
        total: 300,
        relationsCursor: StatisticsTestCursor<StatisticsRelationItem>(),
        actionsCursor: StatisticsTestCursor<StatisticsItem>(),
      );
      await pumpEventQueue();
      page.model.setVisible(false);
      h.reader.failMore<StatisticsRelationItem>(
        4,
        const StatisticsSnapshotExpired(),
      );
      await pumpEventQueue();
      await h.change(2);
      expect(h.reader.continuations, hasLength(5));
      expect(h.reader.queries, hasLength(2));
      expect(page.loaded.breakdowns.selectedActions!.items, hasLength(300));
      page.model.setVisible(true);
      h.reader.section(2, revision: 2, marker: 22);
      await pumpEventQueue();
      expect(
        page.loaded.breakdowns.relations!.items.single.relatedIntention.id,
        statisticsId(22),
      );
    },
  );

  for (final (name, failure) in [
    ('недоступность', const StatisticsReadUnavailableFailure()),
    ('повреждение', const StatisticsReadCorruptionFailure()),
    ('неизвестный отказ', const StatisticsReadUnexpectedFailure()),
  ]) {
    test(
      'отказ обновления: $name сохраняет обе разбивки и допустимость повтора',
      () async {
        final h = IntentionStatisticsHarness();
        addTearDown(h.dispose);
        final page = h.open();
        await _loadBoth(h, page, StatisticsView.throughRelations);
        await h.change(1);
        h.reader.section(
          1,
          revision: 1,
          count: 100,
          total: 300,
          relationsCursor: StatisticsTestCursor<StatisticsRelationItem>(),
          actionsCursor: StatisticsTestCursor<StatisticsItem>(),
        );
        await pumpEventQueue();
        h.reader.failMore<StatisticsRelationItem>(4, failure);
        await pumpEventQueue();
        expect(page.loaded.section.selectedCounts.planned, 300);
        expect(_firstLength(page, StatisticsView.throughRelations), 300);
        expect(page.loaded.breakdowns.selectedActions!.items, hasLength(300));
        final status =
            page.loaded.refreshStatus as IntentionStatisticsRefreshFailure;
        expect(status.failure, failure);
        expect(status.canRetry, failure is StatisticsReadUnavailableFailure);
        await page.model.loadMore(StatisticsBreakdown.selectedActions);
        expect(h.reader.continuations, hasLength(5));
        page.model.setVisible(false);
        await page.model.retryRefresh();
        page.model.setVisible(true);
        expect(h.reader.queries, hasLength(2));
        final retry = page.model.retryRefresh();
        if (status.canRetry) {
          h.reader.section(2, revision: 1, marker: 11);
        }
        await retry;
        expect(h.reader.queries, hasLength(status.canRetry ? 3 : 2));
        if (status.canRetry) {
          expect(
            page.loaded.refreshStatus,
            isA<IntentionStatisticsRefreshIdle>(),
          );
        }
      },
    );
  }

  test(
    'местная дата обновляет невыполненное без смены периодов и вида',
    () async {
      final h = IntentionStatisticsHarness();
      addTearDown(h.dispose);
      final page = h.open();
      h.reader.section(
        0,
        total: 2,
        split: UncompletedSplit(missed: 0, upcoming: 1),
      );
      await pumpEventQueue();
      page.model.setVisible(false);
      final tomorrow = CalendarDate.fromParts(2026, 10, 13);
      page.model.setLocalDate(tomorrow);
      page.model.setLocalDate(tomorrow);
      expect(h.reader.queries, hasLength(1));
      page.model.setVisible(true);
      expect(h.reader.queries.last.localDate, tomorrow);
      expect(page.loaded.section.details.uncompleted.upcoming, 1);
      h.reader.section(
        1,
        total: 2,
        split: UncompletedSplit(missed: 1, upcoming: 0),
      );
      await pumpEventQueue();
      expect(page.loaded.section.details.uncompleted.missed, 1);
      expect(page.state.selection.period, StatisticsMonth(2026, 10));
      expect(page.state.selection.year, StatisticsYear(2026));
      expect(page.state.selection.view, StatisticsView.throughRelations);
    },
  );

  for (final stop in ['скрытие', 'смена условий', 'освобождение']) {
    test(
      'поздний сигнал первой порции после: $stop не запускает старое чтение',
      () async {
        final h = IntentionStatisticsHarness();
        addTearDown(h.dispose);
        final page = h.open();
        switch (stop) {
          case 'скрытие':
            page.model.setVisible(false);
          case 'смена условий':
            page.model.selectView(StatisticsView.selectedActions);
          case 'освобождение':
            page.close();
            await h.container.pump();
        }
        h.reader.fail(0, const StatisticsSnapshotExpired());
        await pumpEventQueue();
        expect(h.reader.queries, hasLength(stop == 'смена условий' ? 2 : 1));
        if (stop == 'скрытие') {
          page.model.setVisible(true);
          h.reader.section(1, marker: 2);
          await pumpEventQueue();
          expect(
            page.loaded.breakdowns.selectedActions!.items.single.id,
            statisticsId(2),
          );
        } else if (stop == 'освобождение') {
          await h.change(1);
          expect(h.reader.queries, hasLength(1));
        }
      },
    );
  }

  test(
    'истечение снимка продолжения пересобирает обе разбивки без ошибки',
    () async {
      final h = IntentionStatisticsHarness();
      addTearDown(h.dispose);
      final page = h.open();
      h.reader.section(
        0,
        total: 300,
        actionsCursor: StatisticsTestCursor<StatisticsItem>(),
      );
      await pumpEventQueue();
      final more = page.model.loadMore(StatisticsBreakdown.selectedActions);
      h.reader.failMore<StatisticsItem>(0, const StatisticsSnapshotExpired());
      await pumpEventQueue();
      expect(page.loaded.refreshStatus, isA<IntentionStatisticsRefreshing>());
      h.reader.section(1, marker: 9);
      await more;
      expect(
        page.loaded.breakdowns.selectedActions!.items.single.id,
        statisticsId(9),
      );
      expect(page.loaded.refreshStatus, isA<IntentionStatisticsRefreshIdle>());
    },
  );

  test('незавершённые подгрузки скрытой страницы не блокируют обе разбивки при возврате', () async {
    final h = IntentionStatisticsHarness();
    addTearDown(h.dispose);
    final page = h.open();
    h.reader.section(
      0,
      total: 2,
      actionsCursor: StatisticsTestCursor<StatisticsItem>(),
      relationsCursor: StatisticsTestCursor<StatisticsRelationItem>(),
    );
    await pumpEventQueue();
    final relations = page.model.loadMore(StatisticsBreakdown.relations);
    final actions = page.model.loadMore(StatisticsBreakdown.selectedActions);
    page.model.setVisible(false);
    h.reader.more(0, [statisticsRelation(2)]);
    h.reader.more(1, [statisticsItem(2)]);
    await Future.wait([relations, actions]);
    expect(page.loaded.breakdowns.selectedActions!.items, hasLength(1));
    page.model.setVisible(true);
    expect(h.reader.queries, hasLength(1));
    final nextRelations = page.model.loadMore(StatisticsBreakdown.relations);
    final nextActions = page.model.loadMore(
      StatisticsBreakdown.selectedActions,
    );
    h.reader.more(2, [statisticsRelation(2)]);
    h.reader.more(3, [statisticsItem(2)]);
    await Future.wait([nextRelations, nextActions]);
    expect(page.loaded.breakdowns.selectedActions!.items, hasLength(2));
    expect(page.loaded.breakdowns.relations!.items, hasLength(2));
  });

  test(
    'показ из завершения команды начинает одно обновление актуальной ревизии',
    () async {
      final h = IntentionStatisticsHarness();
      addTearDown(h.dispose);
      final page = h.open();
      h.reader.section(0);
      await pumpEventQueue();
      page.model.setVisible(false);
      await h.change(1);
      final navigation = h.container
          .read(graphCommandCoordinatorProvider.notifier)
          .completions
          .listen((_) => page.model.setVisible(true));
      addTearDown(navigation.cancel);
      await h.change(2);
      expect(h.reader.queries, hasLength(2));
      h.reader.section(1, revision: 2, marker: 2);
      await pumpEventQueue();
      expect(
        page.loaded.breakdowns.selectedActions!.items.single.id,
        statisticsId(2),
      );
    },
  );
  test(
    'устаревшая первая порция видимого раздела получает новую основу',
    () async {
      final h = IntentionStatisticsHarness();
      addTearDown(h.dispose);
      final page = h.open();
      h.reader.fail(0, const StatisticsSnapshotExpired());
      await pumpEventQueue();
      expect(page.state.read, isA<IntentionStatisticsInitialLoad>());
      h.reader.section(1, marker: 9);
      await pumpEventQueue();
      expect(
        page.loaded.breakdowns.selectedActions!.items.single.id,
        statisticsId(9),
      );
    },
  );

  test(
    'разные ревизии продолжения и новая эпоха требуют новой основы',
    () async {
      final h = IntentionStatisticsHarness();
      addTearDown(h.dispose);
      final page = h.open();
      h.reader.section(
        0,
        total: 2,
        actionsCursor: StatisticsTestCursor<StatisticsItem>(),
      );
      await pumpEventQueue();
      final more = page.model.loadMore(StatisticsBreakdown.selectedActions);
      h.reader.more(0, [statisticsItem(2)], revision: 1);
      await pumpEventQueue();
      expect(
        page.loaded.breakdowns.selectedActions!.items.single.id,
        statisticsId(1),
      );
      h.reader.section(1, revision: 1, marker: 11);
      await more;
      await h.change(2);
      h.reader.section(2, revision: 1, marker: 12);
      await pumpEventQueue();
      expect(
        page.loaded.breakdowns.selectedActions!.items.single.id,
        statisticsId(11),
      );
      h.reader.section(3, revision: 2, marker: 22);
      await pumpEventQueue();
      await h.change(0, epoch: 1);
      h.reader.section(4, revision: 3, marker: 33);
      await pumpEventQueue();
      expect(
        page.loaded.breakdowns.selectedActions!.items.single.id,
        statisticsId(22),
      );
      h.reader.section(5, revision: 0, epoch: 1, marker: 44);
      await pumpEventQueue();
      expect(
        page.loaded.breakdowns.selectedActions!.items.single.id,
        statisticsId(44),
      );
    },
  );

  test(
    'освобождение во время пересборки пресекает остальные порции и подписку',
    () async {
      final h = IntentionStatisticsHarness();
      addTearDown(h.dispose);
      final page = h.open();
      await _loadBoth(h, page, StatisticsView.throughRelations);
      await h.change(1);
      h.reader.section(
        1,
        revision: 1,
        count: 100,
        total: 300,
        relationsCursor: StatisticsTestCursor<StatisticsRelationItem>(),
        actionsCursor: StatisticsTestCursor<StatisticsItem>(),
      );
      await pumpEventQueue();
      page.close();
      await h.container.pump();
      _moreFirst(
        h,
        4,
        StatisticsView.throughRelations,
        revision: 1,
        cursor: true,
      );
      await pumpEventQueue();
      await h.change(2);
      expect(h.reader.continuations, hasLength(5));
      expect(h.reader.queries, hasLength(2));
    },
  );

  test('пустой вид сохраняет данные при отказе, исчезнувшее намерение отличается от отказа', () async {
    final h = IntentionStatisticsHarness();
    addTearDown(h.dispose);
    final page = h.open();
    h.reader.section(0, empty: true);
    await pumpEventQueue();
    await h.change(1);
    h.reader.fail(1, const StatisticsReadUnavailableFailure());
    await pumpEventQueue();
    expect(page.state.read, isA<IntentionStatisticsEmpty>());
    expect(page.loaded.section.periodCounts.contribution, 20);
    expect(page.loaded.refreshStatus, isA<IntentionStatisticsRefreshFailure>());
    final retry = page.model.retryRefresh();
    h.reader.fail(2, const StatisticsIntentionNotFoundFailure());
    await retry;
    expect(page.state.read, isA<IntentionStatisticsNotFound>());
    await page.model.retry();
    expect(h.reader.queries, hasLength(3));
  });
  test(
    'отказ обновления после прерванных подгрузок не оставляет их в загрузке',
    () async {
      final h = IntentionStatisticsHarness();
      addTearDown(h.dispose);
      final page = h.open();
      h.reader.section(
        0,
        total: 2,
        actionsCursor: StatisticsTestCursor<StatisticsItem>(),
        relationsCursor: StatisticsTestCursor<StatisticsRelationItem>(),
      );
      await pumpEventQueue();
      final relations = page.model.loadMore(StatisticsBreakdown.relations);
      final actions = page.model.loadMore(StatisticsBreakdown.selectedActions);
      await h.change(1);
      h.reader.fail(1, const StatisticsReadUnavailableFailure());
      await pumpEventQueue();
      h.reader.failMore<StatisticsRelationItem>(
        0,
        const StatisticsSnapshotExpired(),
      );
      h.reader.more(1, [statisticsItem(2)]);
      await Future.wait([relations, actions]);
      expect(
        page.loaded.refreshStatus,
        isA<IntentionStatisticsRefreshFailure>(),
      );
      expect(
        page.loaded.breakdowns.relations!.pageStatus,
        isA<IntentionStatisticsPageIdle>(),
      );
      expect(
        page.loaded.breakdowns.selectedActions!.pageStatus,
        isA<IntentionStatisticsPageIdle>(),
      );
      expect(page.loaded.breakdowns.selectedActions!.items, hasLength(1));
      expect(h.reader.queries, hasLength(2));
    },
  );
}

Future<void> _loadBoth(
  IntentionStatisticsHarness h,
  IntentionStatisticsTestPage page,
  StatisticsView view,
) async {
  h.reader.section(
    0,
    count: 100,
    total: 300,
    sourcesCursor: StatisticsTestCursor<StatisticsItem>(),
    relationsCursor: StatisticsTestCursor<StatisticsRelationItem>(),
    actionsCursor: StatisticsTestCursor<StatisticsItem>(),
  );
  await pumpEventQueue();
  final breakdown = view == StatisticsView.throughRelations
      ? StatisticsBreakdown.relations
      : StatisticsBreakdown.sourceIntentions;
  for (var i = 0; i < 2; i++) {
    final load = page.model.loadMore(breakdown);
    _moreFirst(h, i, view, cursor: i == 0);
    await load;
  }
  for (var i = 0; i < 2; i++) {
    final load = page.model.loadMore(StatisticsBreakdown.selectedActions);
    h.reader.more(
      2 + i,
      List.generate(100, (j) => statisticsItem(101 + i * 100 + j)),
      cursor: i == 0 ? StatisticsTestCursor<StatisticsItem>() : null,
    );
    await load;
  }
}

void _moreFirst(
  IntentionStatisticsHarness h,
  int index,
  StatisticsView view, {
  int revision = 0,
  bool cursor = false,
}) {
  if (view == StatisticsView.throughRelations) {
    h.reader.more(
      index,
      List.generate(100, (i) => statisticsRelation(700 + index * 100 + i)),
      revision: revision,
      cursor: cursor ? StatisticsTestCursor<StatisticsRelationItem>() : null,
    );
  } else {
    h.reader.more(
      index,
      List.generate(100, (i) => statisticsItem(700 + index * 100 + i)),
      revision: revision,
      cursor: cursor ? StatisticsTestCursor<StatisticsItem>() : null,
    );
  }
}

int _firstLength(IntentionStatisticsTestPage page, StatisticsView view) =>
    view == StatisticsView.throughRelations
    ? page.loaded.breakdowns.relations!.items.length
    : page.loaded.breakdowns.sourceIntentions!.items.length;
