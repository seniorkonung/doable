import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_calendar.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/intention_statistics_target.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_state.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'обычное открытие задаёт местные периоды и вид до первого чтения',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final page = harness.open();
      expect(page.state.selection.period, StatisticsMonth(2026, 10));
      expect(page.state.selection.year, StatisticsYear(2026));
      expect(page.state.selection.view, StatisticsView.throughRelations);
      expect(page.state.read, isA<IntentionStatisticsInitialLoad>());
      await pumpEventQueue();
      final query = harness.reader.queries.single;
      expect(query.intentionId, _id(1));
      expect(query.period, StatisticsMonth(2026, 10));
      expect(query.view, StatisticsView.throughRelations);
      expect(query.localDate, _today);
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
        final harness = _Harness();
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
      final harness = _Harness();
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
      final harness = _Harness();
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
    final harness = _Harness();
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
    expect(first.loaded.breakdowns.sourceIntentions!.items.single.id, _id(33));
    expect(second.state.selection.period, StatisticsMonth(2026, 10));
    expect(second.state.selection.view, StatisticsView.throughRelations);
    expect(second.loaded.breakdowns.selectedActions!.items.single.id, _id(22));
    first.close();
    await harness.container.pump();
    expect(second.loaded.section.selectedCounts.planned, 1);
    final reopened = harness.open();
    await pumpEventQueue();
    expect(reopened.state.selection.period, StatisticsMonth(2026, 10));
    expect(reopened.state.selection.view, StatisticsView.throughRelations);
  });

  test('смена условий отбрасывает поздние успех и отказ раздела', () async {
    final harness = _Harness();
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
    expect(page.loaded.breakdowns.sourceIntentions!.items.single.id, _id(3));
    expect(page.loaded.section.query.period, StatisticsYear(2025));
    expect(
      page.loaded.section.query.view,
      StatisticsView.intermediateIntentions,
    );
  });

  test(
    'пустой выбранный вид сохраняет карточки и ненулевой вклад периода',
    () async {
      final harness = _Harness();
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
    final harness = _Harness();
    addTearDown(harness.dispose);
    final page = harness.open();
    await pumpEventQueue();
    final relationCursor = _Cursor<StatisticsRelationItem>();
    final actionCursor = _Cursor<StatisticsItem>();
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
    final lastCursor = _Cursor<StatisticsItem>();
    harness.reader.more(
      1,
      List.generate(100, (i) => _item(105 - i)),
      cursor: lastCursor,
    );
    await actionsLoad;
    harness.reader.more<StatisticsRelationItem>(0, [
      _relation(105, planned: 3),
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
    harness.reader.more(2, List.generate(5, (i) => _item(5 - i)));
    await lastLoad;
    expect(
      page.loaded.breakdowns.selectedActions!.items.map((item) => item.id),
      List.generate(205, (i) => _id(205 - i)),
    );
    await page.model.loadMoreIfNeeded(StatisticsBreakdown.selectedActions, 204);
    await page.model.loadMoreIfNeeded(StatisticsBreakdown.sourceIntentions, 0);
    expect(harness.reader.continuations, hasLength(3));
  });

  test(
    'смена вида начинает новые разбивки и отбрасывает старое продолжение',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final page = harness.open();
      await pumpEventQueue();
      harness.reader.section(
        0,
        total: 2,
        actionsCursor: _Cursor<StatisticsItem>(),
      );
      await pumpEventQueue();
      final oldLoad = page.model.loadMore(StatisticsBreakdown.selectedActions);
      page.model.selectView(StatisticsView.selectedActions);
      expect(page.state.read, isA<IntentionStatisticsInitialLoad>());
      harness.reader.section(1, marker: 9);
      await pumpEventQueue();
      harness.reader.more(0, [_item(2)]);
      await oldLoad;
      expect(page.loaded.breakdowns.sourceIntentions!.items.single.id, _id(9));
      expect(page.loaded.breakdowns.selectedActions, isNull);
    },
  );

  test(
    'разбивка по исходным намерениям продолжает выбранные действия',
    () async {
      final harness = _Harness();
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
        sourcesCursor: _Cursor<StatisticsItem>(),
      );
      await pumpEventQueue();
      final load = page.model.loadMore(StatisticsBreakdown.sourceIntentions);
      harness.reader.more(0, [_item(1)]);
      await load;
      expect(
        page.loaded.breakdowns.sourceIntentions!.items.map((item) => item.id),
        [_id(2), _id(1)],
      );
      expect(page.loaded.breakdowns.selectedActions, isNull);
    },
  );

  test(
    'отсутствие намерения отличается от пустой статистики и не повторяется',
    () async {
      final harness = _Harness();
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
      final harness = _Harness();
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
        final harness = _Harness();
        addTearDown(harness.dispose);
        final page = harness.open();
        await pumpEventQueue();
        harness.reader.section(
          0,
          total: 2,
          actionsCursor: _Cursor<StatisticsItem>(),
        );
        await pumpEventQueue();
        final load = page.model.loadMore(StatisticsBreakdown.selectedActions);
        harness.reader.failMore<StatisticsItem>(0, failure);
        await load;
        expect(page.loaded.breakdowns.selectedActions!.items.single.id, _id(1));
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
          harness.reader.more(1, [_item(2)]);
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
      final harness = _Harness();
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
      final harness = _Harness();
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

final _today = CalendarDate.fromParts(2026, 10, 12);

final class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(reader),
        dailyChoiceLocalDateSourceProvider.overrideWithValue(
          () => DailyChoiceLocalDay(
            date: _today,
            untilNextDate: const Duration(hours: 12),
          ),
        ),
      ],
    );
  }

  final reader = _Reader();
  late final ProviderContainer container;

  _Page open({IntentionStatisticsTarget? target}) => _Page(container, target);
  void dispose() => container.dispose();
}

final class _Page {
  _Page(this.container, IntentionStatisticsTarget? target) {
    provider = intentionStatisticsViewModelProvider(
      _id(1),
      Object(),
      target: target,
    );
    subscription = container.listen(provider, (_, _) {});
    model = container.read(provider.notifier);
  }

  final ProviderContainer container;
  late final IntentionStatisticsViewModelProvider provider;
  late final ProviderSubscription<IntentionStatisticsState> subscription;
  late final IntentionStatisticsViewModel model;
  IntentionStatisticsState get state => container.read(provider);
  IntentionStatisticsLoaded get loaded =>
      state.read as IntentionStatisticsLoaded;
  void close() => subscription.close();
}

final class _Reader implements PersonalGraphRepository {
  final queries = <IntentionStatisticsQuery>[];
  final responses = <Completer<IntentionStatisticsSectionResult>>[];
  final continuations = <_Pending<Object?>>[];

  @override
  Future<IntentionStatisticsSectionResult> getIntentionStatisticsSection(
    IntentionStatisticsQuery query,
  ) {
    queries.add(query);
    final response = Completer<IntentionStatisticsSectionResult>();
    responses.add(response);
    return response.future;
  }

  @override
  Future<IntentionStatisticsBreakdownResult<T>>
  getIntentionStatisticsBreakdown<T>(StatisticsBreakdownCursor<T> cursor) {
    final pending = _Pending<T>();
    continuations.add(pending);
    return pending.response.future;
  }

  void section(
    int index, {
    int marker = 1,
    int count = 1,
    int? total,
    int? relationsTotal,
    bool empty = false,
    StatisticsBreakdownCursor<StatisticsItem>? sourcesCursor,
    StatisticsBreakdownCursor<StatisticsItem>? actionsCursor,
    StatisticsBreakdownCursor<StatisticsRelationItem>? relationsCursor,
  }) {
    final query = queries[index];
    final counts = ContributionCounts(
      planned: empty ? 0 : total ?? count,
      contribution: empty ? 0 : total ?? count,
    );
    final items = empty
        ? <StatisticsItem>[]
        : List.generate(count, (i) => _item(marker + count - 1 - i));
    StatisticsBreakdownFirstPage<StatisticsItem> intentions([
      StatisticsBreakdownCursor<StatisticsItem>? cursor,
    ]) => StatisticsBreakdownFirstPage(
      items: items,
      totalItems: empty ? 0 : total ?? count,
      nextCursor: cursor,
    );
    final uncompleted = UncompletedSplit(missed: 0, upcoming: 0);
    final details = switch (query.view) {
      StatisticsView.sourceIntentions => IntentionStatisticsSourceDetails(
        uncompleted: uncompleted,
        selectedActions: intentions(actionsCursor),
      ),
      StatisticsView.intermediateIntentions =>
        IntentionStatisticsIntermediateDetails(
          uncompleted: uncompleted,
          sourceIntentions: intentions(sourcesCursor),
          selectedActions: intentions(actionsCursor),
        ),
      StatisticsView.selectedActions => IntentionStatisticsSelectedDetails(
        uncompleted: uncompleted,
        sourceIntentions: intentions(sourcesCursor),
      ),
      StatisticsView.throughRelations =>
        IntentionStatisticsThroughRelationsDetails(
          uncompleted: uncompleted,
          explicitPathChoices: 0,
          relations: StatisticsBreakdownFirstPage(
            items: empty
                ? <StatisticsRelationItem>[]
                : List.generate(
                    count,
                    (i) => _relation(
                      marker + count - 1 - i,
                      planned: relationsTotal == null ? 1 : 3,
                    ),
                  ),
            totalItems: empty ? 0 : relationsTotal ?? total ?? count,
            nextCursor: relationsCursor,
          ),
          selectedActions: intentions(actionsCursor),
        ),
    };
    responses[index].complete(
      IntentionStatisticsSectionSuccess(
        IntentionStatisticsSection(
          query: query,
          revision: const _Revision(),
          cards: IntentionStatisticsCards(
            sourceIntentions: empty
                ? ContributionCounts(planned: 1, contribution: 1)
                : query.view == StatisticsView.sourceIntentions
                ? counts
                : ContributionCounts(planned: 0, contribution: 0),
            intermediateIntentions:
                query.view == StatisticsView.intermediateIntentions
                ? counts
                : ContributionCounts(planned: 0, contribution: 0),
            selectedActions: query.view == StatisticsView.selectedActions
                ? counts
                : ContributionCounts(planned: 0, contribution: 0),
            throughRelations: empty
                ? ContributionCounts(planned: 1, contribution: 1)
                : counts,
          ),
          periodCounts: ContributionCounts(
            planned: empty ? 20 : (total ?? count) + 20,
            contribution: empty ? 20 : (total ?? count) + 20,
          ),
          details: details,
          calendar: switch (query.period) {
            final StatisticsMonth period => IntentionStatisticsMonthCalendar(
              period: period,
              statuses: empty
                  ? {}
                  : {period.firstDate: DailyChoiceDayStatus.allCompleted},
            ),
            final StatisticsYear period => IntentionStatisticsYearCalendar(
              period: period,
              months: List.generate(
                12,
                (i) => i == 0
                    ? counts
                    : ContributionCounts(planned: 0, contribution: 0),
              ),
            ),
          },
        ),
      ),
    );
  }

  void fail(int index, StatisticsReadFailure failure) =>
      responses[index].complete(IntentionStatisticsSectionError(failure));
  void more<T>(
    int index,
    List<T> items, {
    StatisticsBreakdownCursor<T>? cursor,
  }) => (continuations[index] as _Pending<T>).response.complete(
    IntentionStatisticsBreakdownSuccess(
      StatisticsBreakdownContinuationPage(
        items: items,
        revision: const _Revision(),
        nextCursor: cursor,
      ),
    ),
  );
  void failMore<T>(int index, StatisticsReadFailure failure) =>
      (continuations[index] as _Pending<T>).response.complete(
        IntentionStatisticsBreakdownError(failure),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'В этой проверке используется только статистика намерения.',
  );
}

final class _Pending<T> {
  final response = Completer<IntentionStatisticsBreakdownResult<T>>();
}

StatisticsItem _item(int id) => StatisticsItem(
  id: _id(id),
  title: 'Намерение $id',
  archiveState: IntentionArchiveState.active,
  counts: ContributionCounts(planned: 1, contribution: 1),
);
StatisticsRelationItem _relation(int id, {int planned = 1}) =>
    StatisticsRelationItem(
      id: switch (LongTermRelationId.decode(_id(id).toCanonicalString())) {
        LongTermRelationIdDecodingSuccess(:final id) => id,
        InvalidLongTermRelationIdDecoding() => throw StateError(
          'Некорректный UUID связи.',
        ),
      },
      scope: RelationScope.active,
      relatedIntention: StatisticsItem(
        id: _id(id),
        title: 'Намерение $id',
        archiveState: IntentionArchiveState.active,
        counts: ContributionCounts(planned: planned, contribution: planned),
      ),
    );
IntentionId _id(int value) => switch (IntentionId.decode(
  '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError(
    'Некорректный UUID фикстуры.',
  ),
};

final class _Revision implements GraphRevision {
  const _Revision();
  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}

final class _Cursor<T> implements StatisticsBreakdownCursor<T> {}
