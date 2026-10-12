import 'dart:async';

import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
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
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('скрытая модель не начинает чтений даже при смене условий', () async {
    final h = _Harness(visible: false);
    addTearDown(h.dispose);
    h.model.selectPeriod(StatisticsMonth(2025, 3));
    h.model.selectView(StatisticsView.selectedActions);
    await h.change(1);
    await h.model.retryFirstPage();
    await h.model.loadMore();
    expect(h.reader.queries, isEmpty);

    h.model.setVisible(true);
    h.model.setVisible(true);
    expect(h.reader.queries, hasLength(1));
    expect(h.reader.queries.single.period, StatisticsMonth(2025, 3));
    h.reader.first(0, revision: 1);
    await pumpEventQueue();
    expect(h.loaded.items.single.title, 'Версия 1');
  });

  test(
    'несколько скрытых изменений требуют одного обновления при показе',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reader.first(0, cursor: _Cursor());
      await pumpEventQueue();
      h.model.setPeriodSelectorExpanded(true);
      h.model.browsePreviousYear();
      h.model.setVisible(false);
      await h.change(1);
      await h.change(2);
      await h.change(3);
      await h.model.loadMoreIfNeeded(0);
      await h.model.retryLoadMore();
      expect(h.reader.queries, hasLength(1));

      h.model.setVisible(true);
      h.model.setVisible(true);
      expect(h.reader.queries, hasLength(2));
      expect(h.loaded.items.single.title, 'Версия 0');
      expect(h.loaded.refreshStatus, isA<HomeStatisticsRefreshing>());
      h.reader.first(1, revision: 3);
      await pumpEventQueue();
      expect(h.loaded.items.single.title, 'Версия 3');
      expect(h.state.selection.browsedYear, StatisticsYear(2025));
      expect(h.state.selection.isPeriodSelectorExpanded, isTrue);
      h.model.setVisible(false);
      h.model.setVisible(true);
      await h.change(3);
      expect(h.reader.queries, hasLength(2));
    },
  );

  test(
    'показ из завершения команды объединяет все скрытые изменения',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reader.first(0);
      await pumpEventQueue();
      h.model.setVisible(false);
      await h.change(1);
      final navigation = h.container
          .read(graphCommandCoordinatorProvider.notifier)
          .completions
          .listen((_) => h.model.setVisible(true));
      addTearDown(navigation.cancel);
      await h.change(2);
      expect(h.reader.queries, hasLength(2));
      h.reader.first(1, revision: 2);
      await pumpEventQueue();
      expect(h.loaded.items.single.title, 'Версия 2');
    },
  );

  test(
    'сводка и несколько порций заменяются одной согласованной выдачей',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.loadThreePages();
      await h.change(1);
      h.reader.first(3, revision: 1, count: 100, total: 350, cursor: _Cursor());
      await pumpEventQueue();
      expect(h.loaded.items, hasLength(300));
      expect(h.loaded.summary.counts.planned, 300);
      expect(h.loaded.items.first.title, 'Версия 0');
      h.reader.more(4, revision: 1, start: 100, cursor: _Cursor());
      await pumpEventQueue();
      expect(h.loaded.items.first.title, 'Версия 0');
      expect(h.loaded.refreshStatus, isA<HomeStatisticsRefreshing>());
      await h.model.loadMore();
      expect(h.reader.queries, hasLength(6));
      h.reader.more(5, revision: 1, start: 200, cursor: _Cursor());
      await pumpEventQueue();
      expect(h.loaded.items, hasLength(300));
      expect(
        h.loaded.items.map((item) => item.title),
        everyElement('Версия 1'),
      );
      expect(h.loaded.summary.counts.planned, 350);
      expect(h.loaded.totalItems, 350);
      expect(h.loaded.refreshStatus, isA<HomeStatisticsRefreshIdle>());
      expect(h.reader.queries.map((q) => q.pageSize), everyElement(100));
    },
  );

  test(
    'скрытие останавливает пересборку между порциями до следующего показа',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.loadThreePages();
      await h.change(1);
      h.reader.first(3, revision: 1, count: 100, total: 300, cursor: _Cursor());
      await pumpEventQueue();
      h.model.setVisible(false);
      h.reader.more(4, revision: 1, start: 100, cursor: _Cursor());
      await pumpEventQueue();
      expect(h.reader.queries, hasLength(5));
      expect(h.loaded.items.first.title, 'Версия 0');

      h.model.setVisible(true);
      expect(h.reader.queries.last.cursor, isNull);
      h.reader.first(5, revision: 1, count: 100, total: 100);
      await pumpEventQueue();
      expect(h.loaded.items, hasLength(100));
      expect(h.loaded.items.first.title, 'Версия 1');
    },
  );

  test('поздняя первая порция не заменяет результат новой команды', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.change(1);
    h.reader.first(1, revision: 1);
    await pumpEventQueue();
    h.reader.first(0);
    await pumpEventQueue();
    expect(h.loaded.items.single.title, 'Версия 1');
  });

  test('команда между порциями исключает публикацию смешанных чисел', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.loadThreePages();
    await h.change(1);
    h.reader.first(3, revision: 1, count: 100, total: 300, cursor: _Cursor());
    await pumpEventQueue();
    await h.change(2);
    h.reader.more(4, revision: 1, start: 100, cursor: _Cursor());
    await pumpEventQueue();
    expect(h.loaded.items.first.title, 'Версия 0');
    h.reader.first(5, revision: 2);
    await pumpEventQueue();
    expect(h.loaded.items.single.title, 'Версия 2');
    expect(h.loaded.totalItems, 1);
  });

  test(
    'ответ старой эпохи после смены репозитория требует новой основы',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reader.first(0);
      await pumpEventQueue();
      await h.change(1, epoch: 1);
      h.reader.first(1, revision: 10);
      await pumpEventQueue();
      expect(h.loaded.items.single.title, 'Версия 0');
      h.reader.first(2, revision: 1, epoch: 1);
      await pumpEventQueue();
      expect(h.loaded.items.single.title, 'Версия 1');
    },
  );

  test(
    'устаревшее продолжение пересобирает основу вместо повтора курсора',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reader.first(0, cursor: _Cursor());
      await pumpEventQueue();
      final load = h.model.loadMore();
      h.reader.fail(1, const StatisticsSnapshotExpired());
      await pumpEventQueue();
      expect(h.loaded.items.single.title, 'Версия 0');
      expect(h.loaded.refreshStatus, isA<HomeStatisticsRefreshing>());
      expect(h.reader.queries.last.cursor, isNull);
      h.reader.first(2, revision: 1);
      await load;
      expect(h.loaded.items.single.title, 'Версия 1');
    },
  );

  for (final (name, failure, canRetry) in [
    ('недоступность', const StatisticsReadUnavailableFailure(), true),
    ('повреждение', const StatisticsReadCorruptionFailure(), false),
    ('неизвестный отказ', const StatisticsReadUnexpectedFailure(), false),
  ]) {
    test(
      'отказ обновления сохраняет числа и ограничивает повтор: $name',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.loadThreePages();
        await h.change(1);
        h.reader.first(
          3,
          revision: 1,
          count: 100,
          total: 300,
          cursor: _Cursor(),
        );
        await pumpEventQueue();
        h.reader.fail(4, failure);
        await pumpEventQueue();
        expect(h.loaded.items, hasLength(300));
        expect(h.loaded.items.first.title, 'Версия 0');
        expect(h.loaded.summary.counts.planned, 300);
        final status = h.loaded.refreshStatus as HomeStatisticsRefreshFailure;
        expect(status.failure, failure);
        expect(status.canRetry, canRetry);
        await h.model.loadMore();
        h.model.setVisible(false);
        await h.model.retryRefresh();
        expect(h.reader.queries, hasLength(5));
        h.model.setVisible(true);
        final retry = h.model.retryRefresh();
        if (canRetry) {
          expect(h.reader.queries.last.cursor, isNull);
          h.reader.first(5, revision: 1);
          await retry;
          expect(h.loaded.items.single.title, 'Версия 1');
        } else {
          await retry;
          expect(h.reader.queries, hasLength(5));
        }
      },
    );
  }

  test(
    'смена местного дня обновляет деление, сохраняя периоды и вид',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reader.first(0, split: UncompletedSplit(missed: 0, upcoming: 1));
      await pumpEventQueue();
      final tomorrow = CalendarDate.fromParts(2026, 11, 1);
      h.model.setLocalDate(tomorrow);
      h.model.setLocalDate(tomorrow);
      expect(h.reader.queries, hasLength(2));
      expect(h.reader.queries.last.localDate, tomorrow);
      expect(h.state.selection.month, StatisticsMonth(2026, 10));
      expect(h.state.selection.year, StatisticsYear(2026));
      expect(h.state.selection.isCurrentPeriod, isFalse);
      expect(h.loaded.summary.uncompleted.upcoming, 1);
      h.reader.first(1, split: UncompletedSplit(missed: 1, upcoming: 0));
      await pumpEventQueue();
      expect(h.loaded.summary.uncompleted.missed, 1);
      h.model.setVisible(false);
      h.model.setLocalDate(_today);
      expect(h.reader.queries, hasLength(2));
      h.model.setVisible(true);
      expect(h.reader.queries.last.localDate, _today);
      expect(h.reader.queries, hasLength(3));
    },
  );

  test(
    'незавершённая подгрузка скрытой страницы не блокирует следующую',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.reader.first(0, cursor: _Cursor());
      await pumpEventQueue();
      final interrupted = h.model.loadMore();
      h.model.setVisible(false);
      h.reader.more(1);
      await interrupted;
      expect(h.loaded.items, hasLength(1));
      h.model.setVisible(true);
      expect(h.reader.queries, hasLength(2));
      final next = h.model.loadMore();
      h.reader.more(2);
      await next;
      expect(h.loaded.items, hasLength(101));
    },
  );

  test('пустой вид обновляет сводку с теми же признаками обновления', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.reader.first(0, count: 0);
    await pumpEventQueue();
    await h.change(1);
    expect(h.state.read, isA<HomeStatisticsEmpty>());
    expect(h.loaded.refreshStatus, isA<HomeStatisticsRefreshing>());
    h.reader.fail(1, const StatisticsReadUnavailableFailure());
    await pumpEventQueue();
    expect(h.state.read, isA<HomeStatisticsEmpty>());
    expect(h.loaded.refreshStatus, isA<HomeStatisticsRefreshFailure>());
    final retry = h.model.retryRefresh();
    h.reader.first(2, revision: 1);
    await retry;
    expect(h.loaded.items.single.title, 'Версия 1');
  });

  test(
    'истечение снимка во время пересборки заново получает всю основу',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.loadThreePages();
      await h.change(1);
      h.reader.first(3, revision: 1, count: 100, total: 300, cursor: _Cursor());
      await pumpEventQueue();
      h.reader.fail(4, const StatisticsSnapshotExpired());
      await pumpEventQueue();
      expect(h.reader.queries.last.cursor, isNull);
      expect(h.loaded.items, hasLength(300));
      expect(h.loaded.items.first.title, 'Версия 0');
      h.reader.first(5, revision: 2);
      await pumpEventQueue();
      expect(h.loaded.items.single.title, 'Версия 2');
    },
  );

  test(
    'закрытие модели освобождает подписку и останавливает пересборку',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.loadThreePages();
      await h.change(1);
      h.subscription.close();
      await h.container.pump();
      h.reader.first(3, revision: 1, count: 100, total: 300, cursor: _Cursor());
      await h.change(2);
      expect(h.reader.queries, hasLength(4));
    },
  );
}

final _today = CalendarDate.fromParts(2026, 10, 12);

final class _Harness {
  _Harness({bool visible = true}) {
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
    if (visible) model.setVisible(true);
  }

  final reader = _Reader();
  var _tag = Tag(
    id: (TagId.decode(
      '00000000-0000-4000-8000-000000000001',
    ) as TagIdDecodingSuccess).id,
    name: TagName.fromInput('Тег'),
  );
  late final ProviderContainer container;
  late final ProviderSubscription<HomeStatisticsState> subscription;
  HomeStatisticsViewModel get model =>
      container.read(homeStatisticsViewModelProvider.notifier);
  HomeStatisticsState get state =>
      container.read(homeStatisticsViewModelProvider);
  HomeStatisticsLoaded get loaded => state.read as HomeStatisticsLoaded;

  Future<void> loadThreePages() async {
    reader.first(0, count: 100, total: 300, cursor: _Cursor());
    await pumpEventQueue();
    final second = model.loadMore();
    reader.more(1, start: 100, cursor: _Cursor());
    await second;
    final third = model.loadMore();
    reader.more(2, start: 200);
    await third;
  }

  Future<void> change(int revision, {int epoch = 0}) async {
    final next = Tag(id: _tag.id, name: TagName.fromInput('Тег $revision'));
    final stamp = _Revision(revision, epoch);
    reader.commandResult = TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: stamp,
        value: next.name == _tag.name
            ? TagUnchanged(TagUnchangedChange(revision: stamp, tag: _tag))
            : TagRenamed(
                TagRenamedChange(revision: stamp, before: _tag, after: next),
              ),
      ),
    );
    final accepted =
        container
                .read(graphCommandCoordinatorProvider.notifier)
                .acceptTagRename(RenameTag(tagId: _tag.id, name: next.name))
            as TagCommandAccepted;
    await accepted.future;
    _tag = next;
    await pumpEventQueue();
  }

  void dispose() => container.dispose();
}

final class _Reader implements PersonalGraphRepository {
  final queries = <StatisticsQuery>[];
  final responses = <Completer<StatisticsPageResult>>[];
  late TagCommandResult commandResult;

  @override
  Future<StatisticsPageResult> getStatisticsPage(StatisticsQuery query) {
    queries.add(query);
    final response = Completer<StatisticsPageResult>();
    responses.add(response);
    return response.future;
  }

  void first(
    int index, {
    int revision = 0,
    int epoch = 0,
    int count = 1,
    int? total,
    StatisticsCursor? cursor,
    UncompletedSplit? split,
  }) {
    final totalItems = total ?? count + (cursor == null ? 0 : 100);
    responses[index].complete(
      StatisticsPageSuccess(
        StatisticsFirstPage(
          summary: StatisticsPeriodSummary(
            counts: ContributionCounts(
              planned: totalItems,
              contribution: split == null ? totalItems : 0,
            ),
            uncompleted: split ?? UncompletedSplit(missed: 0, upcoming: 0),
          ),
          totalItems: totalItems,
          items: _items(revision, 0, count, completed: split == null),
          revision: _Revision(revision, epoch),
          nextCursor: cursor,
        ),
      ),
    );
  }

  void more(
    int index, {
    int revision = 0,
    int start = 1,
    StatisticsCursor? cursor,
  }) => responses[index].complete(
    StatisticsPageSuccess(
      StatisticsContinuationPage(
        items: _items(revision, start, 100),
        revision: _Revision(revision),
        nextCursor: cursor,
      ),
    ),
  );

  void fail(int index, StatisticsReadFailure failure) =>
      responses[index].complete(StatisticsPageError(failure));

  @override
  Future<GraphCommandResult<T, F>>
  execute<T extends GraphCommandOutcome, F extends GraphCommandFailure>(
    GraphCommand<T, F> command,
  ) async => commandResult as GraphCommandResult<T, F>;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Неиспользуемая операция.');
}

List<StatisticsItem> _items(
  int revision,
  int start,
  int count, {
  bool completed = true,
}) => List.generate(
  count,
  (i) => StatisticsItem(
    id: (IntentionId.decode(
      '00000000-0000-4000-8000-${(10000 - start - i).toString().padLeft(12, '0')}',
    ) as IntentionIdDecodingSuccess).id,
    title: 'Версия $revision',
    archiveState: IntentionArchiveState.active,
    counts: ContributionCounts(planned: 1, contribution: completed ? 1 : 0),
  ),
);

final class _Revision implements GraphRevision {
  const _Revision(this.value, [this.epoch = 0]);
  final int value;
  final int epoch;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) =>
      other is! _Revision || epoch != other.epoch
      ? GraphRevisionOrder.differentEpoch
      : value < other.value
      ? GraphRevisionOrder.older
      : value > other.value
      ? GraphRevisionOrder.newer
      : GraphRevisionOrder.same;
}

final class _Cursor implements StatisticsCursor {}
