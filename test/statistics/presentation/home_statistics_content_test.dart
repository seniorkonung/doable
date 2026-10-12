import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/home_statistics_content.dart';
import 'package:doable/src/statistics/presentation/home_statistics_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('сводка показывает 4 из 21, каталог — порядок и доли периода', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _Harness(
      _data([
        _item(1, 'Высыпаться', 3, 7),
        _item(2, 'Быть в форме', 1, 5),
        _item(3, 'Учить испанский', 0, 5),
        _item(4, 'Читать книги', 0, 2),
      ]),
    );
    await harness.pump(tester);
    final texts = harness.texts(tester);

    expect(find.text(texts.statisticsPeriodSummary), findsOneWidget);
    expect(find.text(texts.statisticsPlannedContribution(21)), findsOneWidget);
    expect(find.text(texts.statisticsContribution(4)), findsOneWidget);
    expect(find.text(texts.statisticsMissed(10)), findsOneWidget);
    expect(find.text(texts.statisticsUpcoming(7)), findsOneWidget);
    expect(find.text(texts.statisticsTotalItems(4)), findsOneWidget);
    expect(find.text(texts.statisticsContributionCounts(3, 7)), findsOneWidget);
    expect(find.text(texts.statisticsContributionShare(.75)), findsOneWidget);
    expect(find.text(texts.statisticsContributionShare(.25)), findsOneWidget);
    expect(find.text(texts.statisticsContributionShare(0)), findsNWidgets(2));
    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data);
    expect(
      titles.where(
        (t) => [
          'Высыпаться',
          'Быть в форме',
          'Учить испанский',
          'Читать книги',
        ].contains(t),
      ),
      ['Высыпаться', 'Быть в форме', 'Учить испанский', 'Читать книги'],
    );
    expect(find.text('Через связи'), findsNothing);

    await tester.tap(find.text(texts.statisticsIntermediateIntentions));
    await tester.pump();
    expect(harness.selectedViews, [StatisticsView.intermediateIntentions]);
  });

  testWidgets('нулевой вклад скрывает доли и объясняет их отсутствие диктору', (
    tester,
  ) async {
    final harness = _Harness(
      _data([_item(1, 'Читать книги', 0, 2)], summary: _summary(0, 2, 0, 2)),
    );
    await harness.pump(tester);
    final texts = harness.texts(tester);

    expect(find.text(texts.statisticsContributionCounts(0, 2)), findsOneWidget);
    expect(find.textContaining('Доля'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp(texts.statisticsNoContributionShare)),
      findsOneWidget,
    );
  });

  testWidgets(
    'промежуточные намерения получают полный вклад без нормализации',
    (tester) async {
      final harness = _Harness(
        _data([
          _item(1, 'Вечерний ритуал', 1, 1),
          _item(2, 'Высыпаться', 1, 1),
        ], summary: _summary(1, 1, 0, 0)),
        view: StatisticsView.intermediateIntentions,
      );
      await harness.pump(tester);
      final texts = harness.texts(tester);
      expect(
        find.text(texts.statisticsContributionCounts(1, 1)),
        findsNWidgets(2),
      );
      expect(find.text(texts.statisticsContributionShare(1)), findsNWidgets(2));
    },
  );
}

final _revision = _Revision();

final class _Revision implements GraphRevision {
  @override
  GraphRevisionOrder compareTo(GraphRevision other) => identical(this, other)
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}

StatisticsPeriodSummary _summary(
  int contribution,
  int planned,
  int missed,
  int upcoming,
) => StatisticsPeriodSummary(
  counts: ContributionCounts(planned: planned, contribution: contribution),
  uncompleted: UncompletedSplit(missed: missed, upcoming: upcoming),
);

StatisticsItem _item(
  int id,
  String title,
  int contribution,
  int planned, {
  bool archived = false,
}) => StatisticsItem(
  id: switch (IntentionId.decode(
    '00000000-0000-4000-8000-${id.toString().padLeft(12, '0')}',
  )) {
    IntentionIdDecodingSuccess(:final id) => id,
    InvalidIntentionIdDecoding() => throw StateError(
      'Некорректный идентификатор фикстуры',
    ),
  },
  title: title,
  archiveState: archived
      ? IntentionArchiveState.archived
      : IntentionArchiveState.active,
  counts: ContributionCounts(planned: planned, contribution: contribution),
);

HomeStatisticsData _data(
  List<StatisticsItem> items, {
  StatisticsPeriodSummary? summary,
  int? totalItems,
  StatisticsCursor? cursor,
  HomeStatisticsPageStatus pageStatus = const HomeStatisticsPageIdle(),
  HomeStatisticsRefreshStatus refreshStatus = const HomeStatisticsRefreshIdle(),
}) => HomeStatisticsData(
  summary: summary ?? _summary(4, 21, 10, 7),
  totalItems: totalItems ?? items.length,
  items: items,
  revision: _revision,
  nextCursor: cursor,
  pageStatus: pageStatus,
  refreshStatus: refreshStatus,
);

final class _Harness {
  _Harness(
    HomeStatisticsReadState read, {
    StatisticsView view = StatisticsView.sourceIntentions,
  }) : state = ValueNotifier(
         HomeStatisticsState(
           selection: HomeStatisticsSelection.initial(
             CalendarDate.fromParts(2026, 10, 12),
           ).copyWith(view: view),
           read: read,
         ),
       ) {
    addTearDown(state.dispose);
  }

  final ValueNotifier<HomeStatisticsState> state;
  final selectedViews = <StatisticsView>[];

  AppLocalizations texts(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(HomeStatisticsContent)));

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: state,
            builder: (context, value, _) => HomeStatisticsContent(
              state: value,
              periodSelector: const SizedBox.shrink(),
              onViewSelected: selectedViews.add,
              onLoadMoreIfNeeded: (_) {},
              onRetryFirstPage: () {},
              onRetryRefresh: () {},
              onRetryLoadMore: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }
}
