import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_target.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'intention_statistics_test_support.dart';

void main() {
  test(
    'обычное открытие задаёт местные периоды и вид до первого чтения',
    () async {
      final harness = IntentionStatisticsHarness();
      addTearDown(harness.dispose);
      final page = harness.open();
      expect(page.state.selection.period, StatisticsMonth(2026, 10));
      expect(page.state.selection.year, StatisticsYear(2026));
      expect(page.state.selection.view, StatisticsView.throughRelations);
      expect(page.state.read, isA<IntentionStatisticsInitialLoad>());
      await pumpEventQueue();
      final query = harness.reader.queries.single;
      expect(query.intentionId, statisticsId(1));
      expect(query.period, StatisticsMonth(2026, 10));
      expect(query.view, StatisticsView.throughRelations);
      expect(query.localDate, statisticsToday);
      expect(query.pageSize, 100);
    },
  );

  for (final (name, period) in [
    ('месяца', StatisticsMonth(2025, 3)),
    ('года', StatisticsYear(2024)),
  ]) {
    test(
      'цель $name применяется до первого чтения без промежуточного запроса',
      () async {
        final harness = IntentionStatisticsHarness();
        addTearDown(harness.dispose);
        final page = harness.open(
          target: IntentionStatisticsTarget(
            view: StatisticsView.intermediateIntentions,
            period: period,
          ),
        );
        await pumpEventQueue();
        expect(page.state.selection.period, period);
        expect(harness.reader.queries.single.period, period);
        expect(
          harness.reader.queries.single.view,
          StatisticsView.intermediateIntentions,
        );
        expect(
          page.state.selection.month,
          period is StatisticsMonth ? period : StatisticsMonth(2026, 10),
        );
        expect(
          page.state.selection.year,
          period is StatisticsYear ? period : StatisticsYear(2026),
        );
      },
    );
  }

  test(
    'режимы сохраняют периоды и общий вид, столбик выбирает месяц своего года',
    () async {
      final harness = IntentionStatisticsHarness();
      addTearDown(harness.dispose);
      final page = harness.open();
      await pumpEventQueue();
      page.model.selectPeriod(StatisticsMonth(2025, 3));
      page.model.selectMode(IntentionStatisticsMode.year);
      page.model.selectPeriod(StatisticsYear(2024));
      page.model.selectView(StatisticsView.sourceIntentions);
      page.model.selectMode(IntentionStatisticsMode.month);
      expect(page.state.selection.period, StatisticsMonth(2025, 3));
      page.model.selectMode(IntentionStatisticsMode.year);
      expect(page.state.selection.period, StatisticsYear(2024));
      page.model.selectMonth(7);
      expect(page.state.selection.period, StatisticsMonth(2024, 7));
      expect(page.state.selection.view, StatisticsView.sourceIntentions);
      page.model.selectMode(IntentionStatisticsMode.year);
      expect(page.state.selection.period, StatisticsYear(2024));
      final count = harness.reader.queries.length;
      page.model.selectMode(IntentionStatisticsMode.year);
      page.model.selectPeriod(StatisticsYear(2024));
      page.model.selectView(StatisticsView.sourceIntentions);
      expect(harness.reader.queries, hasLength(count));
    },
  );

  test(
    'стрелки переходят через год и останавливаются на границах календаря',
    () async {
      final harness = IntentionStatisticsHarness();
      addTearDown(harness.dispose);
      final page = harness.open();
      await pumpEventQueue();
      page.model.selectPeriod(StatisticsMonth(2026, 1));
      page.model.selectPreviousPeriod();
      expect(page.state.selection.period, StatisticsMonth(2025, 12));
      page.model.selectNextPeriod();
      expect(page.state.selection.period, StatisticsMonth(2026, 1));
      for (final period in [
        StatisticsMonth(CalendarDate.earliest.year, 1),
        StatisticsYear(CalendarDate.earliest.year),
      ]) {
        page.model.selectPeriod(period);
        final count = harness.reader.queries.length;
        page.model.selectPreviousPeriod();
        expect(harness.reader.queries, hasLength(count));
        expect(page.state.selection.period, period);
      }
      for (final period in [
        StatisticsMonth(CalendarDate.latest.year, 12),
        StatisticsYear(CalendarDate.latest.year),
      ]) {
        page.model.selectPeriod(period);
        final count = harness.reader.queries.length;
        page.model.selectNextPeriod();
        expect(harness.reader.queries, hasLength(count));
        expect(page.state.selection.period, period);
      }
    },
  );

  test('два экземпляра намерения независимо хранят условия и данные', () async {
    final harness = IntentionStatisticsHarness();
    addTearDown(harness.dispose);
    final first = harness.open();
    final second = harness.open();
    await pumpEventQueue();
    harness.reader.section(0, marker: 11);
    harness.reader.section(1, marker: 22);
    await pumpEventQueue();
    first.model.selectPeriod(StatisticsMonth(2025, 3));
    first.model.selectView(StatisticsView.intermediateIntentions);
    harness.reader.section(3, marker: 33);
    await pumpEventQueue();
    expect(
      first.loaded.breakdowns.sourceIntentions!.items.single.id,
      statisticsId(33),
    );
    expect(second.state.selection.period, StatisticsMonth(2026, 10));
    expect(second.state.selection.view, StatisticsView.throughRelations);
    expect(
      second.loaded.breakdowns.selectedActions!.items.single.id,
      statisticsId(22),
    );
    first.close();
    await harness.container.pump();
    expect(second.loaded.section.selectedCounts.planned, 1);
    final reopened = harness.open();
    await pumpEventQueue();
    expect(reopened.state.selection.period, StatisticsMonth(2026, 10));
    expect(reopened.state.selection.view, StatisticsView.throughRelations);
  });

  test('смена условий отбрасывает поздние успех и отказ раздела', () async {
    final harness = IntentionStatisticsHarness();
    addTearDown(harness.dispose);
    final page = harness.open();
    await pumpEventQueue();
    page.model.selectPeriod(StatisticsYear(2025));
    page.model.selectView(StatisticsView.intermediateIntentions);
    harness.reader.section(2, marker: 3);
    await pumpEventQueue();
    harness.reader.section(0, marker: 1);
    harness.reader.fail(1, const StatisticsReadUnavailableFailure());
    await pumpEventQueue();
    expect(
      page.loaded.breakdowns.sourceIntentions!.items.single.id,
      statisticsId(3),
    );
    expect(page.loaded.section.query.period, StatisticsYear(2025));
    expect(
      page.loaded.section.query.view,
      StatisticsView.intermediateIntentions,
    );
  });

  test(
    'пустой выбранный вид сохраняет карточки и ненулевой вклад периода',
    () async {
      final harness = IntentionStatisticsHarness();
      addTearDown(harness.dispose);
      final page = harness.open(
        target: IntentionStatisticsTarget(
          view: StatisticsView.intermediateIntentions,
          period: StatisticsMonth(2026, 10),
        ),
      );
      await pumpEventQueue();
      harness.reader.section(0, empty: true);
      await pumpEventQueue();
      expect(page.state.read, isA<IntentionStatisticsEmpty>());
      expect(page.loaded.section.selectedCounts.planned, 0);
      expect(page.loaded.section.periodCounts.contribution, 20);
      expect(page.loaded.section.cards.sourceIntentions.planned, 1);
    },
  );

  test('разбивки независимо подгружаются за 30 строк, завершение одной не стирает другую', () async {
    final harness = IntentionStatisticsHarness();
    addTearDown(harness.dispose);
    final page = harness.open();
    await pumpEventQueue();
    final relationCursor = StatisticsTestCursor<StatisticsRelationItem>();
    final actionCursor = StatisticsTestCursor<StatisticsItem>();
    harness.reader.section(
      0,
      marker: 106,
      count: 100,
      total: 205,
      relationsTotal: 101,
      relationsCursor: relationCursor,
      actionsCursor: actionCursor,
    );
    await pumpEventQueue();
    await page.model.loadMoreIfNeeded(StatisticsBreakdown.relations, 68);
    expect(harness.reader.continuations, isEmpty);
    final relationsLoad = page.model.loadMoreIfNeeded(
      StatisticsBreakdown.relations,
      69,
    );
    final actionsLoad = page.model.loadMoreIfNeeded(
      StatisticsBreakdown.selectedActions,
      69,
    );
    await page.model.loadMoreIfNeeded(StatisticsBreakdown.relations, 99);
    expect(harness.reader.continuations, hasLength(2));
    expect(page.loaded.breakdowns.relations!.items, hasLength(100));
    final lastCursor = StatisticsTestCursor<StatisticsItem>();
    harness.reader.more(
      1,
      List.generate(100, (i) => statisticsItem(105 - i)),
      cursor: lastCursor,
    );
    await actionsLoad;
    harness.reader.more<StatisticsRelationItem>(0, [
      statisticsRelation(105, planned: 3),
    ]);
    await relationsLoad;
    expect(page.loaded.breakdowns.relations!.items, hasLength(101));
    expect(page.loaded.breakdowns.selectedActions!.items, hasLength(200));
    expect(page.loaded.breakdowns.selectedActions!.totalItems, 205);
    await page.model.loadMoreIfNeeded(StatisticsBreakdown.selectedActions, 168);
    expect(harness.reader.continuations, hasLength(2));
    final lastLoad = page.model.loadMoreIfNeeded(
      StatisticsBreakdown.selectedActions,
      169,
    );
    harness.reader.more(2, List.generate(5, (i) => statisticsItem(5 - i)));
    await lastLoad;
    expect(
      page.loaded.breakdowns.selectedActions!.items.map((item) => item.id),
      List.generate(205, (i) => statisticsId(205 - i)),
    );
    await page.model.loadMoreIfNeeded(StatisticsBreakdown.selectedActions, 204);
    await page.model.loadMoreIfNeeded(StatisticsBreakdown.sourceIntentions, 0);
    expect(harness.reader.continuations, hasLength(3));
  });

  test(
    'смена вида начинает новые разбивки и отбрасывает старое продолжение',
    () async {
      final harness = IntentionStatisticsHarness();
      addTearDown(harness.dispose);
      final page = harness.open();
      await pumpEventQueue();
      harness.reader.section(
        0,
        total: 2,
        actionsCursor: StatisticsTestCursor<StatisticsItem>(),
      );
      await pumpEventQueue();
      final oldLoad = page.model.loadMore(StatisticsBreakdown.selectedActions);
      page.model.selectView(StatisticsView.selectedActions);
      expect(page.state.read, isA<IntentionStatisticsInitialLoad>());
      harness.reader.section(1, marker: 9);
      await pumpEventQueue();
      harness.reader.more(0, [statisticsItem(2)]);
      await oldLoad;
      expect(
        page.loaded.breakdowns.sourceIntentions!.items.single.id,
        statisticsId(9),
      );
      expect(page.loaded.breakdowns.selectedActions, isNull);
    },
  );

  test(
    'разбивка по исходным намерениям продолжает выбранные действия',
    () async {
      final harness = IntentionStatisticsHarness();
      addTearDown(harness.dispose);
      final page = harness.open(
        target: IntentionStatisticsTarget(
          view: StatisticsView.selectedActions,
          period: StatisticsMonth(2026, 10),
        ),
      );
      await pumpEventQueue();
      harness.reader.section(
        0,
        marker: 2,
        total: 2,
        sourcesCursor: StatisticsTestCursor<StatisticsItem>(),
      );
      await pumpEventQueue();
      final load = page.model.loadMore(StatisticsBreakdown.sourceIntentions);
      harness.reader.more(0, [statisticsItem(1)]);
      await load;
      expect(
        page.loaded.breakdowns.sourceIntentions!.items.map((item) => item.id),
        [statisticsId(2), statisticsId(1)],
      );
      expect(page.loaded.breakdowns.selectedActions, isNull);
    },
  );

  test(
    'отсутствие намерения отличается от пустой статистики и не повторяется',
    () async {
      final harness = IntentionStatisticsHarness();
      addTearDown(harness.dispose);
      final page = harness.open();
      await pumpEventQueue();
      harness.reader.fail(0, const StatisticsIntentionNotFoundFailure());
      await pumpEventQueue();
      expect(page.state.read, isA<IntentionStatisticsNotFound>());
      await page.model.retry();
      expect(harness.reader.queries, hasLength(1));
    },
  );

  for (final (name, failure, canRetry) in [
    ('недоступность', const StatisticsReadUnavailableFailure(), true),
    ('повреждение', const StatisticsReadCorruptionFailure(), false),
    ('неизвестный отказ', const StatisticsReadUnexpectedFailure(), false),
  ]) {
    test('$name раздела допускает только разрешённый повтор', () async {
      final harness = IntentionStatisticsHarness();
      addTearDown(harness.dispose);
      final page = harness.open();
      await pumpEventQueue();
      harness.reader.fail(0, failure);
      await pumpEventQueue();
      expect(
        (page.state.read as IntentionStatisticsFailure).canRetry,
        canRetry,
      );
      final retry = page.model.retry();
      if (canRetry) {
        await page.model.retry();
        expect(harness.reader.queries, hasLength(2));
        expect(harness.reader.queries.last.period, StatisticsMonth(2026, 10));
        expect(
          harness.reader.queries.last.view,
          StatisticsView.throughRelations,
        );
        harness.reader.section(1);
      }
      await retry;
      expect(harness.reader.queries, hasLength(canRetry ? 2 : 1));
    });

    test(
      '$name продолжения сохраняет строки и относится только к своей разбивке',
      () async {
        final harness = IntentionStatisticsHarness();
        addTearDown(harness.dispose);
        final page = harness.open();
        await pumpEventQueue();
        harness.reader.section(
          0,
          total: 2,
          actionsCursor: StatisticsTestCursor<StatisticsItem>(),
        );
        await pumpEventQueue();
        final load = page.model.loadMore(StatisticsBreakdown.selectedActions);
        harness.reader.failMore<StatisticsItem>(0, failure);
        await load;
        expect(
          page.loaded.breakdowns.selectedActions!.items.single.id,
          statisticsId(1),
        );
        final status =
            page.loaded.breakdowns.selectedActions!.pageStatus
                as IntentionStatisticsPageFailure;
        expect(status.failure, failure);
        expect(status.canRetry, canRetry);
        expect(
          page.loaded.breakdowns.relations!.pageStatus,
          isA<IntentionStatisticsPageIdle>(),
        );
        await page.model.loadMoreIfNeeded(
          StatisticsBreakdown.selectedActions,
          0,
        );
        expect(harness.reader.continuations, hasLength(1));
        final retry = page.model.retryLoadMore(
          StatisticsBreakdown.selectedActions,
        );
        if (canRetry) {
          await page.model.retryLoadMore(StatisticsBreakdown.selectedActions);
          expect(harness.reader.continuations, hasLength(2));
          harness.reader.more(1, [statisticsItem(2)]);
        }
        await retry;
        expect(
          page.loaded.breakdowns.selectedActions!.items,
          hasLength(canRetry ? 2 : 1),
        );
      },
    );
  }

  test(
    'исключение адаптера становится безопасным отказом без повтора',
    () async {
      final harness = IntentionStatisticsHarness();
      addTearDown(harness.dispose);
      final page = harness.open();
      await pumpEventQueue();
      harness.reader.responses.single.completeError(
        StateError('Внутренние данные'),
      );
      await pumpEventQueue();
      final failure = page.state.read as IntentionStatisticsFailure;
      expect(failure.failure, isA<StatisticsReadUnexpectedFailure>());
      expect(failure.canRetry, isFalse);
    },
  );

  test(
    'освобождение страницы пресекает поздний сигнал и новое чтение',
    () async {
      final harness = IntentionStatisticsHarness();
      addTearDown(harness.dispose);
      final page = harness.open();
      await pumpEventQueue();
      page.close();
      await harness.container.pump();
      harness.reader.fail(0, const StatisticsSnapshotExpired());
      await pumpEventQueue();
      expect(harness.reader.queries, hasLength(1));
    },
  );
}
