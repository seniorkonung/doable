import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_calendar.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_breakdowns.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'intention_statistics_test_support.dart';

void main() {
  testWidgets(
    'три связи получают по 50%, архивы различимы, строка открывается клавиатурой',
    (tester) async {
      final opened = <(IntentionId, StatisticsBreakdown)>[];
      await _pump(
        tester,
        _state(),
        onOpen: (id, kind) => opened.add((id, kind)),
      );
      final texts = _texts(tester);
      expect(find.text(texts.statisticsBreakdownRelations), findsOneWidget);
      expect(find.text(texts.statisticsTotalItems(3)), findsOneWidget);
      expect(
        find.text(texts.statisticsBreakdownContributionShare(.5)),
        findsNWidgets(3),
      );
      expect(find.text('1 из 1'), findsNWidgets(3));
      final labels = tester.semantics
          .simulatedAccessibilityTraversal()
          .map((node) => node.getSemanticsData())
          .where((data) => data.label.startsWith('Связь '))
          .toList();
      expect(labels, hasLength(3));
      expect(labels[0].label, contains(texts.detailsArchived));
      expect(
        labels[0].label,
        isNot(contains(texts.relationNeighborhoodRelationArchived)),
      );
      expect(
        labels[1].label,
        contains(texts.relationNeighborhoodRelationArchived),
      );
      expect(labels[1].label, isNot(contains(texts.detailsArchived)));
      expect(labels[2].label, contains(texts.detailsArchived));
      expect(
        labels[2].label,
        contains(texts.relationNeighborhoodRelationArchived),
      );
      for (final data in labels) {
        expect(
          data.label,
          contains(texts.statisticsContributionCountsSemantics(1, 1)),
        );
        expect(data.flagsCollection.isButton, isTrue);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(opened, [(statisticsId(2), StatisticsBreakdown.relations)]);
      await tester.scrollUntilVisible(find.text('Действие'), 300);
      await tester.tap(find.text('Действие'));
      expect(opened.last, (
        statisticsId(1000),
        StatisticsBreakdown.selectedActions,
      ));
    },
  );

  testWidgets('нулевой вклад намерения скрывает доли даже при вкладе периода', (
    tester,
  ) async {
    await _pump(tester, _state(zero: true));
    expect(find.textContaining('%'), findsNothing);
    expect(
      find.bySemanticsLabel(
        RegExp(_texts(tester).statisticsBreakdownNoContributionShare),
      ),
      findsWidgets,
    );
    expect(find.text('0 из 1'), findsNWidgets(3));
  });

  testWidgets('вид показывает только свои разбивки и точное число элементов', (
    tester,
  ) async {
    for (final view in StatisticsView.values) {
      await _pump(tester, _state(view: view));
      final texts = _texts(tester);
      for (final kind in StatisticsBreakdown.values) {
        final title = switch (kind) {
          StatisticsBreakdown.sourceIntentions =>
            texts.statisticsBreakdownSourceIntentions,
          StatisticsBreakdown.selectedActions =>
            texts.statisticsBreakdownSelectedActions,
          StatisticsBreakdown.relations => texts.statisticsBreakdownRelations,
        };
        expect(
          find.text(title),
          view.breakdowns.contains(kind) ? findsOneWidget : findsNothing,
        );
      }
    }
  });

  testWidgets('загрузка, пустой вид, отсутствие намерения и отказы различимы', (
    tester,
  ) async {
    var retries = 0;
    final base = _state();
    await _pump(tester, base.withRead(const IntentionStatisticsInitialLoad()));
    final texts = _texts(tester);
    expect(find.text(texts.statisticsLoading), findsOneWidget);
    expect(find.text(texts.statisticsEmpty), findsNothing);
    await _pump(tester, _state(empty: true));
    expect(find.text(texts.statisticsEmpty), findsWidgets);
    expect(find.text(texts.statisticsTotalItems(0)), findsNWidgets(2));
    await _pump(tester, base.withRead(const IntentionStatisticsNotFound()));
    expect(find.text(texts.detailsNotFound), findsOneWidget);
    for (final (failure, message, canRetry) in [
      (
        const StatisticsReadUnavailableFailure(),
        texts.statisticsUnavailable,
        true,
      ),
      (
        const StatisticsReadCorruptionFailure(),
        texts.statisticsCorruption,
        false,
      ),
      (
        const StatisticsReadUnexpectedFailure(),
        texts.statisticsUnexpectedFailure,
        false,
      ),
    ]) {
      await _pump(
        tester,
        base.withRead(IntentionStatisticsFailure(failure)),
        onRetry: () => retries++,
      );
      expect(find.text(message), findsOneWidget);
      expect(find.text(texts.statisticsEmpty), findsNothing);
      expect(
        find.text(texts.commonRetry),
        canRetry ? findsOneWidget : findsNothing,
      );
      if (canRetry) await tester.tap(find.text(texts.commonRetry));
    }
    expect(retries, 1);
  });

  testWidgets(
    'две разбивки подгружаются отдельно и сохраняют строки при отказе одной',
    (tester) async {
      final initial = _state(length: 100, paginate: true);
      final updates = ValueNotifier(initial);
      addTearDown(updates.dispose);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final visible = <(StatisticsBreakdown, int)>[];
      final retries = <StatisticsBreakdown>[];
      await _pump(
        tester,
        initial,
        updates: updates,
        controller: controller,
        onLoadMore: (kind, index) => visible.add((kind, index)),
        onRetryMore: retries.add,
      );
      final texts = _texts(tester);
      expect(find.text(texts.statisticsTotalItems(200)), findsOneWidget);
      expect(find.text('Связь 99'), findsNothing);
      await tester.scrollUntilVisible(find.text('Связь 99'), 500);
      expect(
        visible.any(
          (event) =>
              event.$1 == StatisticsBreakdown.relations && event.$2 >= 70,
        ),
        isTrue,
      );
      final loaded = initial.read as IntentionStatisticsLoaded;
      updates.value = initial.withRead(
        loaded.copyWith(
          breakdowns: loaded.breakdowns.copyWith(
            relations: loaded.breakdowns.relations!.withPageStatus(
              const IntentionStatisticsPageFailure(
                StatisticsReadUnavailableFailure(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(texts.statisticsLoadMoreUnavailable),
        300,
      );
      expect(find.text('Связь 99').hitTestable(), findsOneWidget);
      expect(find.text(texts.commonRetry).hitTestable(), findsOneWidget);
      await tester.tap(find.text(texts.commonRetry));
      expect(retries, [StatisticsBreakdown.relations]);
      final beforeRefresh = updates.value.read as IntentionStatisticsLoaded;
      updates.value = initial.withRead(
        beforeRefresh.copyWith(
          refreshStatus: const IntentionStatisticsRefreshing(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(texts.commonRetry).hitTestable(), findsNothing);
      updates.value = initial.withRead(beforeRefresh);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(texts.statisticsBreakdownSelectedActions),
        300,
      );
      expect(find.text(texts.statisticsTotalItems(200)), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Действие 99'), 500);
      final loading = updates.value.read as IntentionStatisticsLoaded;
      updates.value = initial.withRead(
        loading.copyWith(
          breakdowns: loading.breakdowns.copyWith(
            selectedActions: loading.breakdowns.selectedActions!.withPageStatus(
              const IntentionStatisticsPageLoading(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(texts.statisticsLoadingMore),
        300,
      );
      expect(find.text('Действие 99').hitTestable(), findsOneWidget);
      final beforeFailure = updates.value.read as IntentionStatisticsLoaded;
      updates.value = initial.withRead(
        beforeFailure.copyWith(
          breakdowns: beforeFailure.breakdowns.copyWith(
            selectedActions: loaded.breakdowns.selectedActions!.withPageStatus(
              const IntentionStatisticsPageFailure(
                StatisticsReadCorruptionFailure(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(texts.statisticsLoadMoreCorruption).hitTestable(),
        findsOneWidget,
      );
      expect(find.text(texts.commonRetry).hitTestable(), findsNothing);
      expect(find.text('Действие 99').hitTestable(), findsOneWidget);
      // Успешная замена первой разбивки не сбрасывает отказ второй.
      updates.value = initial.withRead(
        (updates.value.read as IntentionStatisticsLoaded).copyWith(
          breakdowns: beforeFailure.breakdowns.copyWith(
            relations: loaded.breakdowns.relations!.append(
              StatisticsBreakdownContinuationPage(
                items: List.generate(
                  100,
                  (index) => statisticsRelation(200 + index),
                ),
                revision: const StatisticsTestRevision(0),
                nextCursor: null,
              ),
            ),
            selectedActions: loaded.breakdowns.selectedActions!.withPageStatus(
              const IntentionStatisticsPageFailure(
                StatisticsReadCorruptionFailure(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        find.text(texts.statisticsLoadMoreCorruption).hitTestable(),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('Действие 70'), -500);
      expect(
        visible.any(
          (event) =>
              event.$1 == StatisticsBreakdown.selectedActions && event.$2 >= 70,
        ),
        isTrue,
      );
    },
  );

  testWidgets('пересборка во второй разбивке не подгружает скрытую первую', (
    tester,
  ) async {
    final initial = _state(length: 100, paginate: true);
    final updates = ValueNotifier(initial);
    addTearDown(updates.dispose);
    final events = <(StatisticsBreakdown, int)>[];
    await _pump(
      tester,
      initial,
      updates: updates,
      onLoadMore: (kind, index) => events.add((kind, index)),
    );
    await tester.scrollUntilVisible(find.text('Действие 80'), 500);
    final loaded = initial.read as IntentionStatisticsLoaded;
    updates.value = initial.withRead(
      loaded.copyWith(refreshStatus: const IntentionStatisticsRefreshing()),
    );
    await tester.pumpAndSettle();
    events.clear();
    updates.value = initial;
    await tester.pumpAndSettle();
    expect(events, isNotEmpty);
    expect(
      events.every((event) => event.$1 == StatisticsBreakdown.selectedActions),
      isTrue,
    );
  });

  testWidgets(
    'статус обновления и повтор видны при глубокой прокрутке на RU/EN с текстом 3×',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final initial = _state(length: 100);
      final updates = ValueNotifier(initial);
      final controller = ScrollController();
      addTearDown(updates.dispose);
      addTearDown(controller.dispose);
      var retries = 0;
      for (final locale in ['ru', 'en']) {
        updates.value = initial;
        await _pump(
          tester,
          initial,
          updates: updates,
          controller: controller,
          locale: locale,
          scale: 3,
          onRetryRefresh: () => retries++,
        );
        await tester.scrollUntilVisible(
          find.text('Связь 10'),
          500,
          maxScrolls: 100,
        );
        await tester.ensureVisible(find.text('Связь 10'));
        await tester.pumpAndSettle();
        final offset = controller.offset;
        final loaded = initial.read as IntentionStatisticsLoaded;
        updates.value = initial.withRead(
          loaded.copyWith(refreshStatus: const IntentionStatisticsRefreshing()),
        );
        await tester.pumpAndSettle();
        final texts = _texts(tester);
        expect(
          find.text(texts.statisticsRefreshing).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.text(texts.statisticsContributionCounts(1, 1)).hitTestable(),
          findsWidgets,
        );
        expect(controller.offset, offset);
        updates.value = initial.withRead(
          loaded.copyWith(
            refreshStatus: const IntentionStatisticsRefreshFailure(
              StatisticsReadUnavailableFailure(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final message = find.text(texts.statisticsRefreshUnavailableShort);
        final retry = find.text(texts.commonRetry);
        expect(message.hitTestable(), findsOneWidget);
        expect(retry.hitTestable(), findsOneWidget);
        expect(tester.getRect(message).top, greaterThanOrEqualTo(0));
        expect(tester.getRect(retry).bottom, lessThanOrEqualTo(800));
        expect(
          find.text(texts.statisticsContributionCounts(1, 1)).hitTestable(),
          findsWidgets,
        );
        expect(controller.offset, offset);
        final data = tester.getSemantics(message).getSemanticsData();
        expect(data.flagsCollection.isLiveRegion, isTrue);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(retries, locale == 'ru' ? 1 : 2);
        for (final (failure, message) in [
          (
            const StatisticsReadCorruptionFailure(),
            texts.statisticsRefreshCorruptionShort,
          ),
          (
            const StatisticsReadUnexpectedFailure(),
            texts.statisticsRefreshUnexpectedShort,
          ),
        ]) {
          updates.value = initial.withRead(
            loaded.copyWith(
              refreshStatus: IntentionStatisticsRefreshFailure(failure),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(message).hitTestable(), findsOneWidget);
          expect(find.text(texts.commonRetry), findsNothing);
          expect(controller.offset, offset);
        }
        updates.value = initial;
        await tester.pumpAndSettle();
        expect(
          find.text(texts.statisticsRefreshUnavailableShort),
          findsNothing,
        );
        expect(controller.offset, offset);
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final size in [const Size(320, 700), const Size(700, 360)]) {
    testWidgets(
      'окно $size: сообщение, повтор и числа целиком читаемы при тексте 3×',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final initial = _state(length: 100);
        final updates = ValueNotifier(initial);
        final controller = ScrollController();
        addTearDown(updates.dispose);
        addTearDown(controller.dispose);
        var retries = 0;
        for (final locale in ['ru', 'en']) {
          updates.value = initial;
          await _pump(
            tester,
            initial,
            updates: updates,
            controller: controller,
            locale: locale,
            scale: 3,
            chrome: true,
            onRetryRefresh: () => retries++,
          );
          await tester.scrollUntilVisible(
            find.text('Связь 10'),
            500,
            maxScrolls: 100,
          );
          await tester.ensureVisible(find.text('Связь 10'));
          await tester.pumpAndSettle();
          final offset = controller.offset;
          updates.value = initial.withRead(
            (initial.read as IntentionStatisticsLoaded).copyWith(
              refreshStatus: const IntentionStatisticsRefreshFailure(
                StatisticsReadUnavailableFailure(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final texts = _texts(tester);
          final viewport = tester.getRect(find.byType(CustomScrollView));
          final message = find.text(texts.statisticsRefreshUnavailableShort);
          final retry = find.text(texts.commonRetry);
          expect(
            tester.getRect(message).top,
            greaterThanOrEqualTo(viewport.top),
          );
          expect(
            tester.getRect(message).bottom,
            lessThanOrEqualTo(viewport.bottom),
          );
          expect(retry.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(retry).bottom,
            lessThanOrEqualTo(viewport.bottom),
          );
          expect(controller.offset, offset);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(retries, locale == 'ru' ? 1 : 2);
          final counts = find.descendant(
            of: find.bySemanticsLabel(RegExp(r'^Связь 10\n')),
            matching: find.text(texts.statisticsContributionCounts(1, 1)),
          );
          final noticeBottom = tester.getRect(retry).bottom + 8;
          controller.jumpTo(
            controller.offset + tester.getRect(counts).top - noticeBottom,
          );
          await tester.pumpAndSettle();
          expect(counts.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(counts).top,
            greaterThanOrEqualTo(noticeBottom),
          );
          expect(
            tester.getRect(counts).bottom,
            lessThanOrEqualTo(viewport.bottom),
          );
          expect(message.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets(
    'закреплённый статус уходит вместе с разбивками перед группами связей',
    (tester) async {
      final initial = _state();
      final state = initial.withRead(
        (initial.read as IntentionStatisticsLoaded).copyWith(
          refreshStatus: const IntentionStatisticsRefreshing(),
        ),
      );
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        state,
        controller: controller,
        following: const [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 1500,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text('Группы связей'),
              ),
            ),
          ),
        ],
      );
      final texts = _texts(tester);
      expect(
        find.text(texts.statisticsRefreshing).hitTestable(),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('Группы связей'), 300);
      controller.jumpTo(
        controller.offset + tester.getTopLeft(find.text('Группы связей')).dy,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Группы связей'));
      await tester.pumpAndSettle();
      expect(find.text('Группы связей').hitTestable(), findsOneWidget);
      expect(find.text(texts.statisticsRefreshing).hitTestable(), findsNothing);
    },
  );
}

AppLocalizations _texts(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(IntentionStatisticsBreakdownsSliver)),
);

Future<void> _pump(
  WidgetTester tester,
  IntentionStatisticsState state, {
  void Function(IntentionId, StatisticsBreakdown)? onOpen,
  void Function(StatisticsBreakdown, int)? onLoadMore,
  VoidCallback? onRetry,
  VoidCallback? onRetryRefresh,
  ValueChanged<StatisticsBreakdown>? onRetryMore,
  ValueNotifier<IntentionStatisticsState>? updates,
  ScrollController? controller,
  String locale = 'ru',
  double scale = 1,
  bool chrome = false,
  List<Widget> following = const [],
}) async {
  Widget sliver(IntentionStatisticsState current) =>
      IntentionStatisticsBreakdownsSliver(
        state: current,
        onOpenIntention: onOpen ?? (_, _) {},
        onLoadMoreIfNeeded: onLoadMore ?? (_, _) {},
        onRetry: onRetry ?? () {},
        onRetryRefresh: onRetryRefresh ?? () {},
        onRetryLoadMore: onRetryMore ?? (_) {},
      );
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        appBar: chrome ? AppBar(title: const Text('Намерение')) : null,
        bottomNavigationBar: chrome ? const SizedBox(height: 64) : null,
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: CustomScrollView(
            controller: controller,
            slivers: [
              if (updates == null)
                sliver(state)
              else
                ValueListenableBuilder<IntentionStatisticsState>(
                  valueListenable: updates,
                  builder: (context, value, _) => sliver(value),
                ),
              ...following,
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

IntentionStatisticsState _state({
  StatisticsView view = StatisticsView.throughRelations,
  bool zero = false,
  bool empty = false,
  int length = 3,
  bool paginate = false,
}) {
  final period = StatisticsMonth(2026, 10);
  final planned = empty
      ? 0
      : length > 3
      ? (paginate ? length * 2 : length)
      : 2;
  final counts = ContributionCounts(
    planned: planned,
    contribution: zero ? 0 : planned,
  );
  final items = empty
      ? <StatisticsItem>[]
      : List.generate(
          paginate ? length : 1,
          (index) => StatisticsItem(
            id: statisticsId(1000 + index),
            title: index == 0 ? 'Действие' : 'Действие $index',
            archiveState: IntentionArchiveState.active,
            counts: paginate
                ? ContributionCounts(planned: 1, contribution: 1)
                : counts,
          ),
        );
  StatisticsBreakdownFirstPage<StatisticsItem> intentions() =>
      StatisticsBreakdownFirstPage(
        items: items,
        totalItems: empty
            ? 0
            : paginate
            ? length * 2
            : 1,
        nextCursor: paginate ? StatisticsTestCursor<StatisticsItem>() : null,
      );
  final split = UncompletedSplit(missed: zero ? planned : 0, upcoming: 0);
  final section = IntentionStatisticsSection(
    query: IntentionStatisticsQuery(
      intentionId: statisticsId(1),
      period: period,
      view: view,
      localDate: statisticsToday,
      pageSize: 100,
    ),
    revision: const StatisticsTestRevision(0),
    cards: IntentionStatisticsCards(
      sourceIntentions: view == StatisticsView.sourceIntentions
          ? counts
          : ContributionCounts(planned: 0, contribution: 0),
      intermediateIntentions: view == StatisticsView.intermediateIntentions
          ? counts
          : ContributionCounts(planned: 0, contribution: 0),
      selectedActions: view == StatisticsView.selectedActions
          ? counts
          : ContributionCounts(planned: 0, contribution: 0),
      throughRelations: counts,
    ),
    periodCounts: ContributionCounts(
      planned: planned + 10,
      contribution: planned + 10,
    ),
    details: switch (view) {
      StatisticsView.sourceIntentions => IntentionStatisticsSourceDetails(
        uncompleted: split,
        selectedActions: intentions(),
      ),
      StatisticsView.intermediateIntentions =>
        IntentionStatisticsIntermediateDetails(
          uncompleted: split,
          sourceIntentions: intentions(),
          selectedActions: intentions(),
        ),
      StatisticsView.selectedActions => IntentionStatisticsSelectedDetails(
        uncompleted: split,
        sourceIntentions: intentions(),
      ),
      StatisticsView.throughRelations =>
        IntentionStatisticsThroughRelationsDetails(
          uncompleted: split,
          explicitPathChoices: planned,
          relations: StatisticsBreakdownFirstPage(
            items: List.generate(
              empty ? 0 : length,
              (index) => StatisticsRelationItem(
                id: statisticsRelation(index + 2).id,
                scope: index == 1 || index == 2
                    ? RelationScope.archived
                    : RelationScope.active,
                relatedIntention: StatisticsItem(
                  id: statisticsId(index + 2),
                  title: 'Связь $index',
                  archiveState: index == 0 || index == 2
                      ? IntentionArchiveState.archived
                      : IntentionArchiveState.active,
                  counts: ContributionCounts(
                    planned: 1,
                    contribution: zero ? 0 : 1,
                  ),
                ),
              ),
            ),
            totalItems: empty
                ? 0
                : paginate
                ? length * 2
                : length,
            nextCursor: paginate
                ? StatisticsTestCursor<StatisticsRelationItem>()
                : null,
          ),
          selectedActions: intentions(),
        ),
    },
    calendar: IntentionStatisticsMonthCalendar(period: period, statuses: {}),
  );
  return IntentionStatisticsState(
    selection: IntentionStatisticsSelection.initial(
      statisticsToday,
      null,
    ).copyWith(view: view),
    read: IntentionStatisticsLoaded.first(section),
  );
}
