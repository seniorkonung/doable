import 'dart:async';

import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/home_statistics_state.dart';
import 'package:doable/src/statistics/presentation/home_statistics_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('новый экземпляр выбирает местные месяц и год до первого чтения', () {
    final harness = _Harness();
    addTearDown(harness.dispose);

    expect(harness.state.selection.tab, HomeStatisticsTab.month);
    expect(harness.state.selection.month, StatisticsMonth(2026, 10));
    expect(harness.state.selection.year, StatisticsYear(2026));
    expect(harness.state.selection.view, StatisticsView.sourceIntentions);
    expect(harness.state.selection.isCurrentPeriod, isTrue);
    expect(harness.state.selection.isPeriodSelectorExpanded, isFalse);
    expect(harness.state.read, isA<HomeStatisticsInitialLoad>());
    final query = harness.reader.queries.single;
    expect(query.period, StatisticsMonth(2026, 10));
    expect(query.view, StatisticsView.sourceIntentions);
    expect(query.localDate, _today);
    expect(query.pageSize, 100);
    expect(query.cursor, isNull);
  });

  test('вкладки сохраняют независимые периоды и общий вид', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    harness.model.selectPeriod(StatisticsMonth(2025, 3));
    harness.model.selectView(StatisticsView.intermediateIntentions);
    harness.model.selectTab(HomeStatisticsTab.year);
    harness.model.selectPeriod(StatisticsYear(2024));
    harness.model.selectTab(HomeStatisticsTab.month);
    expect(harness.state.selection.period, StatisticsMonth(2025, 3));
    expect(harness.state.selection.isCurrentPeriod, isFalse);
    harness.model.selectTab(HomeStatisticsTab.year);
    expect(harness.state.selection.period, StatisticsYear(2024));
    expect(harness.state.selection.view, StatisticsView.intermediateIntentions);
    expect(harness.reader.queries.last.cursor, isNull);

    harness.reader.first(6, [_item(7)]);
    await pumpEventQueue();
    final queryCount = harness.reader.queries.length;
    harness.model.selectTab(HomeStatisticsTab.year);
    harness.model.selectPeriod(StatisticsYear(2024));
    harness.model.selectView(StatisticsView.intermediateIntentions);
    expect(harness.reader.queries, hasLength(queryCount));
    expect(harness.loaded.items.single.id, _id(7));
  });

  test(
    'просмотр года не читает статистику, выбор оставляет его раскрытым',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.reader.first(0, [_item(1)]);
      await pumpEventQueue();

      harness.model.setPeriodSelectorExpanded(true);
      harness.model.browsePreviousYear();
      expect(harness.state.selection.browsedYear, StatisticsYear(2025));
      expect(harness.state.selection.period, StatisticsMonth(2026, 10));
      expect(harness.loaded.items.single.id, _id(1));
      expect(harness.reader.queries, hasLength(1));

      harness.model.selectPeriod(StatisticsMonth(2025, 3));
      expect(harness.state.selection.isPeriodSelectorExpanded, isTrue);
      expect(harness.state.selection.browsedYear, StatisticsYear(2025));
      expect(harness.state.read, isA<HomeStatisticsInitialLoad>());
      expect(harness.reader.queries.last.period, StatisticsMonth(2025, 3));
      harness.model.setPeriodSelectorExpanded(false);
      expect(harness.reader.queries, hasLength(2));

      harness.model.selectTab(HomeStatisticsTab.year);
      harness.model.setPeriodSelectorExpanded(true);
      harness.model.browseNextYear();
      expect(harness.state.selection.browsedYear, StatisticsYear(2027));
      expect(harness.state.selection.period, StatisticsYear(2026));
      expect(harness.reader.queries, hasLength(3));
      harness.model.selectPeriod(StatisticsYear(2027));
      expect(harness.state.selection.isPeriodSelectorExpanded, isTrue);
      expect(harness.reader.queries.last.period, StatisticsYear(2027));
    },
  );

  test(
    'соседние периоды переходят через год и соблюдают границы календаря',
    () {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.model.selectPeriod(StatisticsMonth(2026, 1));
      harness.model.selectPreviousPeriod();
      expect(harness.state.selection.period, StatisticsMonth(2025, 12));
      harness.model.selectNextPeriod();
      expect(harness.state.selection.period, StatisticsMonth(2026, 1));

      harness.model.selectPeriod(
        StatisticsMonth(CalendarDate.earliest.year, 1),
      );
      var queryCount = harness.reader.queries.length;
      harness.model.selectPreviousPeriod();
      harness.model.setPeriodSelectorExpanded(true);
      harness.model.browsePreviousYear();
      expect(harness.reader.queries, hasLength(queryCount));
      expect(
        harness.state.selection.browsedYear.year,
        CalendarDate.earliest.year,
      );

      harness.model.selectPeriod(StatisticsYear(CalendarDate.latest.year));
      queryCount = harness.reader.queries.length;
      harness.model.selectNextPeriod();
      harness.model.browseNextYear();
      expect(harness.reader.queries, hasLength(queryCount));
      expect(
        harness.state.selection.browsedYear.year,
        CalendarDate.latest.year,
      );
    },
  );

  test(
    'смена условий убирает прежние числа и отбрасывает поздние ответы',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.reader.first(0, [_item(1)]);
      await pumpEventQueue();

      harness.model.selectPeriod(StatisticsMonth(2025, 3));
      expect(harness.state.read, isA<HomeStatisticsInitialLoad>());
      harness.model.selectTab(HomeStatisticsTab.year);
      harness.model.selectView(StatisticsView.selectedActions);
      harness.reader.first(3, [_item(4)]);
      await pumpEventQueue();
      harness.reader.first(1, [_item(2)]);
      harness.reader.fail(2, const StatisticsReadUnavailableFailure());
      await pumpEventQueue();

      expect(harness.loaded.items.single.id, _id(4));
      expect(harness.state.selection.period, StatisticsYear(2026));
      expect(harness.state.selection.view, StatisticsView.selectedActions);
    },
  );

  test('пустой вид сохраняет ненулевую сводку периода', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.model.selectView(StatisticsView.intermediateIntentions);
    harness.reader.first(
      1,
      [],
      summary: StatisticsPeriodSummary(
        counts: ContributionCounts(planned: 21, contribution: 4),
        uncompleted: UncompletedSplit(missed: 10, upcoming: 7),
      ),
    );
    await pumpEventQueue();

    expect(harness.state.read, isA<HomeStatisticsEmpty>());
    expect(harness.loaded.summary.counts.planned, 21);
    expect(harness.loaded.summary.counts.contribution, 4);
    expect(harness.loaded.totalItems, 0);
  });

  test('подгрузка за 30 элементов получает последовательные порции по 100 без дублей', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final firstCursor = _Cursor();
    final secondCursor = _Cursor();
    harness.reader.first(
      0,
      List.generate(100, (i) => _item(205 - i)),
      total: 205,
      cursor: firstCursor,
    );
    await pumpEventQueue();

    await harness.model.loadMoreIfNeeded(68);
    expect(harness.reader.queries, hasLength(1));
    final second = harness.model.loadMoreIfNeeded(69);
    expect(harness.loaded.items, hasLength(100));
    expect(harness.loaded.pageStatus, isA<HomeStatisticsPageLoading>());
    await harness.model.loadMoreIfNeeded(99);
    await harness.model.loadMore();
    expect(harness.reader.queries, hasLength(2));
    harness.reader.more(
      1,
      List.generate(100, (i) => _item(105 - i)),
      cursor: secondCursor,
    );
    await second;

    await harness.model.loadMoreIfNeeded(168);
    expect(harness.reader.queries, hasLength(2));
    final third = harness.model.loadMoreIfNeeded(169);
    harness.reader.more(2, List.generate(5, (i) => _item(5 - i)));
    await third;
    await harness.model.loadMoreIfNeeded(204);
    expect(harness.reader.queries, hasLength(3));
    expect(harness.reader.queries.map((q) => q.pageSize), everyElement(100));
    expect(harness.reader.queries.map((q) => q.cursor), [
      null,
      firstCursor,
      secondCursor,
    ]);
    expect(
      harness.loaded.items.map((item) => item.id),
      List.generate(205, (i) => _id(205 - i)),
    );
    expect(harness.loaded.totalItems, 205);
    expect(harness.loaded.summary.counts.planned, 205);
    expect(harness.loaded.pageStatus, isA<HomeStatisticsPageIdle>());
  });

  test(
    'смена вида начинает первую порцию и отбрасывает прежнее продолжение',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.reader.first(0, [_item(2)], total: 2, cursor: _Cursor());
      await pumpEventQueue();
      final oldLoad = harness.model.loadMore();

      harness.model.selectView(StatisticsView.selectedActions);
      expect(harness.state.read, isA<HomeStatisticsInitialLoad>());
      expect(harness.reader.queries.last.cursor, isNull);
      harness.reader.first(2, [_item(3)]);
      await pumpEventQueue();
      harness.reader.more(1, [_item(1)]);
      await oldLoad;
      expect(harness.loaded.items.map((item) => item.id), [_id(3)]);
      expect(harness.loaded.totalItems, 1);
      expect(harness.loaded.pageStatus, isA<HomeStatisticsPageIdle>());
    },
  );

  for (final (name, failure, canRetry) in [
    ('недоступность', const StatisticsReadUnavailableFailure(), true),
    ('повреждение', const StatisticsReadCorruptionFailure(), false),
    ('неизвестный отказ', const StatisticsReadUnexpectedFailure(), false),
  ]) {
    test(
      'первая порция: $name допускает только разрешённый явный повтор',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        harness.reader.fail(0, failure);
        await pumpEventQueue();
        final failed = harness.state.read as HomeStatisticsInitialFailure;
        expect(failed.failure, failure);
        expect(failed.canRetry, canRetry);
        await harness.model.loadMoreIfNeeded(0);
        expect(harness.reader.queries, hasLength(1));

        final retry = harness.model.retryFirstPage();
        if (canRetry) {
          expect(harness.state.read, isA<HomeStatisticsInitialLoad>());
          await harness.model.retryFirstPage();
          expect(harness.reader.queries, hasLength(2));
          final query = harness.reader.queries.last;
          expect(query.period, StatisticsMonth(2026, 10));
          expect(query.view, StatisticsView.sourceIntentions);
          expect(query.localDate, _today);
          expect(query.cursor, isNull);
          harness.reader.first(1, [_item(1)]);
          await retry;
          expect(harness.loaded.items.single.id, _id(1));
        } else {
          await retry;
          expect(harness.reader.queries, hasLength(1));
          expect(harness.state.read, isA<HomeStatisticsInitialFailure>());
        }
      },
    );

    test(
      'продолжение: $name сохраняет элементы и ограничивает повтор',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final cursor = _Cursor();
        harness.reader.first(0, [_item(2)], total: 2, cursor: cursor);
        await pumpEventQueue();
        final load = harness.model.loadMore();
        harness.reader.fail(1, failure);
        await load;
        expect(harness.loaded.items.map((item) => item.id), [_id(2)]);
        expect(harness.loaded.totalItems, 2);
        expect(harness.loaded.summary.counts.contribution, 2);
        final status = harness.loaded.pageStatus as HomeStatisticsPageFailure;
        expect(status.failure, failure);
        expect(status.canRetry, canRetry);
        await harness.model.loadMoreIfNeeded(0);
        expect(harness.reader.queries, hasLength(2));

        final retry = harness.model.retryLoadMore();
        if (canRetry) {
          expect(harness.loaded.pageStatus, isA<HomeStatisticsPageLoading>());
          await harness.model.retryLoadMore();
          expect(harness.reader.queries, hasLength(3));
          expect(harness.reader.queries.last.cursor, cursor);
          harness.reader.more(2, [_item(1)]);
          await retry;
          expect(harness.loaded.items.map((item) => item.id), [_id(2), _id(1)]);
          expect(harness.loaded.pageStatus, isA<HomeStatisticsPageIdle>());
        } else {
          await retry;
          expect(harness.reader.queries, hasLength(2));
          expect(harness.loaded.pageStatus, isA<HomeStatisticsPageFailure>());
        }
      },
    );
  }

  test('исключение чтения становится безопасным отказом без повтора', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.reader.responses[0].completeError(StateError('Внутренние данные'));
    await pumpEventQueue();
    final failed = harness.state.read as HomeStatisticsInitialFailure;
    expect(failed.failure, isA<StatisticsReadUnexpectedFailure>());
    expect(failed.canRetry, isFalse);
  });

  test(
    'ответ чтения сохраняет просмотр периода, изменённый во время загрузки',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.model.setPeriodSelectorExpanded(true);
      harness.model.browseNextYear();
      harness.reader.first(0, [_item(1)]);
      await pumpEventQueue();
      expect(harness.loaded.items.single.id, _id(1));
      expect(harness.state.selection.browsedYear, StatisticsYear(2027));
      expect(harness.state.selection.isPeriodSelectorExpanded, isTrue);
      expect(harness.state.selection.period, StatisticsMonth(2026, 10));
    },
  );

  test('закрытая модель не публикует поздний ответ', () async {
    final harness = _Harness();
    harness.dispose();
    harness.reader.first(0, [_item(1)]);
    await pumpEventQueue();
  });
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
    subscription = container.listen(homeStatisticsViewModelProvider, (_, _) {});
    model = container.read(homeStatisticsViewModelProvider.notifier);
    model.setVisible(true);
  }

  final reader = _Reader();
  late final ProviderContainer container;
  late final ProviderSubscription<HomeStatisticsState> subscription;
  late final HomeStatisticsViewModel model;

  HomeStatisticsState get state =>
      container.read(homeStatisticsViewModelProvider);
  HomeStatisticsLoaded get loaded => state.read as HomeStatisticsLoaded;

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

final class _Reader implements PersonalGraphRepository {
  final queries = <StatisticsQuery>[];
  final responses = <Completer<StatisticsPageResult>>[];

  @override
  Future<StatisticsPageResult> getStatisticsPage(StatisticsQuery query) {
    queries.add(query);
    final response = Completer<StatisticsPageResult>();
    responses.add(response);
    return response.future;
  }

  void first(
    int index,
    List<StatisticsItem> items, {
    int? total,
    StatisticsCursor? cursor,
    StatisticsPeriodSummary? summary,
  }) {
    responses[index].complete(
      StatisticsPageSuccess(
        StatisticsFirstPage(
          summary:
              summary ??
              StatisticsPeriodSummary(
                counts: ContributionCounts(
                  planned: total ?? items.length,
                  contribution: total ?? items.length,
                ),
                uncompleted: UncompletedSplit(missed: 0, upcoming: 0),
              ),
          totalItems: total ?? items.length,
          items: items,
          revision: const _Revision(),
          nextCursor: cursor,
        ),
      ),
    );
  }

  void fail(int index, StatisticsReadFailure failure) =>
      responses[index].complete(StatisticsPageError(failure));

  void more(
    int index,
    List<StatisticsItem> items, {
    StatisticsCursor? cursor,
  }) => responses[index].complete(
    StatisticsPageSuccess(
      StatisticsContinuationPage(
        items: items,
        revision: const _Revision(),
        nextCursor: cursor,
      ),
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'В этой проверке используется только чтение статистики.',
  );
}

StatisticsItem _item(int id) => StatisticsItem(
  id: _id(id),
  title: 'Намерение $id',
  archiveState: IntentionArchiveState.active,
  counts: ContributionCounts(planned: 1, contribution: 1),
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

final class _Cursor implements StatisticsCursor {}
