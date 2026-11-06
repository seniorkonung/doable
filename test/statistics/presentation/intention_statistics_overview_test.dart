import 'dart:ui' show CheckedState;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_calendar.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_calendar.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_overview.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'intention_statistics_test_support.dart';

void main() {
  testWidgets('четыре плитки показывают число действий периода по порядку, '
      'под ними стоит пояснение вида, а сводка — выполнено, долю и явные '
      'основания', (tester) async {
    await _pump(tester, _overview());
    final texts = AppLocalizations.of(
      tester.element(find.byType(IntentionStatisticsOverview)),
    );
    final period = texts.statisticsMonthPeriod(DateTime.utc(2026, 10));
    final tiles = [
      (texts.statisticsTileRoot, 7, CheckedState.isFalse),
      (texts.statisticsTileIntermediate, 0, CheckedState.isFalse),
      (texts.statisticsTileTerminal, 0, CheckedState.isFalse),
      (texts.statisticsTileThroughRelations, 8, CheckedState.isTrue),
    ];
    final nodes = tester.semantics
        .simulatedAccessibilityTraversal()
        .map((node) => node.getSemanticsData())
        .where((node) => tiles.any((tile) => node.label.startsWith(tile.$1)))
        .toList();
    expect(nodes.map((node) => node.label), [
      for (final (name, count, _) in tiles)
        texts.statisticsTileSemantics(
          name,
          texts.statisticsPeriodActions(count),
          period,
        ),
    ]);
    expect(nodes.map((node) => node.flagsCollection.isChecked), [
      for (final (_, _, selected) in tiles) selected,
    ]);
    expect(
      find.text(texts.statisticsIntentionThroughRelationsHint),
      findsOneWidget,
    );
    expect(find.text(texts.statisticsPeriodCompleted(3, 8)), findsOneWidget);
    expect(
      find.text(texts.statisticsPeriodActionsShare(8 / 21)),
      findsOneWidget,
    );
    expect(
      find.text(texts.statisticsExplicitPathActions(7, 8)),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(texts.statisticsCurrentPeriod)),
      findsWidgets,
    );
  });

  testWidgets('пояснение под плитками следует выбранному виду', (tester) async {
    await _pump(tester, _overview(view: StatisticsView.rootIntentions));
    final texts = AppLocalizations.of(
      tester.element(find.byType(IntentionStatisticsOverview)),
    );
    expect(find.text(texts.statisticsIntentionRootHint), findsOneWidget);
    expect(
      find.text(texts.statisticsIntentionThroughRelationsHint),
      findsNothing,
    );
  });

  testWidgets('вид без действий сохраняет плитки и вместо сводки, календаря и '
      'пояснения о связях показывает сообщение о том, что здесь посчитают', (
    tester,
  ) async {
    await _pump(tester, _overview(view: StatisticsView.terminalIntentions));
    final texts = AppLocalizations.of(
      tester.element(find.byType(IntentionStatisticsOverview)),
    );
    final period = texts.statisticsMonthPeriod(DateTime.utc(2026, 10));
    expect(find.text(texts.statisticsTileRoot), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(
      find.text(texts.statisticsIntentionEmptyTerminalTitle(period)),
      findsOneWidget,
    );
    expect(
      find.text(texts.statisticsIntentionEmptyTerminalText),
      findsOneWidget,
    );
    expect(find.textContaining('7 из'), findsNothing);
    expect(find.byType(IntentionStatisticsCalendarView), findsNothing);
    expect(find.byType(Table), findsNothing);
    expect(
      find.textContaining(texts.statisticsPeriodCompleted(0, 0)),
      findsNothing,
    );
  });

  testWidgets('нулевой вклад не скрывает долю действий периода', (
    tester,
  ) async {
    await _pump(tester, _overview(zero: true));
    final texts = AppLocalizations.of(
      tester.element(find.byType(IntentionStatisticsOverview)),
    );
    expect(
      find.text(texts.statisticsPeriodActionsShare(8 / 21)),
      findsOneWidget,
    );
    expect(find.text(texts.statisticsPeriodCompleted(0, 8)), findsOneWidget);
  });

  testWidgets(
    'клавиатура переключает режим, период и вид через события модели',
    (tester) async {
      final harness = IntentionStatisticsHarness();
      addTearDown(harness.dispose);
      final page = harness.open();
      harness.reader.section(0, count: 1);
      final content = UncontrolledProviderScope(
        container: harness.container,
        child: Consumer(
          builder: (context, ref, _) => IntentionStatisticsOverview(
            state: ref.watch(page.provider),
            onModeSelected: page.model.selectMode,
            onPreviousPeriod: page.model.selectPreviousPeriod,
            onNextPeriod: page.model.selectNextPeriod,
            onViewSelected: page.model.selectView,
            onMonthSelected: page.model.selectMonth,
            onDaySelected: (_) {},
          ),
        ),
      );
      await _pump(tester, content);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(harness.reader.queries.last.period, StatisticsYear(2026));
      harness.reader.section(1, count: 1);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(harness.reader.queries.last.period, StatisticsYear(2025));
      harness.reader.section(2, count: 1);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(harness.reader.queries.last.view, StatisticsView.rootIntentions);
      harness.reader.section(3, count: 1);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Месяц'));
      await tester.pump();
      expect(harness.reader.queries.last.period, StatisticsMonth(2026, 10));
      expect(harness.reader.queries.last.view, StatisticsView.rootIntentions);
      harness.reader.section(4, count: 1);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Год'));
      await tester.pump();
      expect(harness.reader.queries.last.period, StatisticsYear(2025));
      harness.reader.section(5, count: 1);
      await tester.pumpAndSettle();
      final texts = AppLocalizations.of(
        tester.element(find.byType(IntentionStatisticsOverview)),
      );
      final march = find.text(texts.statisticsMonthName(DateTime.utc(2025, 3)));
      await tester.ensureVisible(march);
      await tester.tap(march);
      await tester.pump();
      expect(harness.reader.queries.last.period, StatisticsMonth(2025, 3));
      expect(harness.reader.queries.last.view, StatisticsView.rootIntentions);
      harness.reader.section(6, count: 1);
      await tester.pumpAndSettle();
      await _pump(tester, content, locale: 'en');
      final english = AppLocalizations.of(
        tester.element(find.byType(IntentionStatisticsOverview)),
      );
      expect(
        find.text(english.statisticsMonthPeriod(DateTime.utc(2025, 3))),
        findsOneWidget,
      );
      final rootTile = tester.semantics
          .simulatedAccessibilityTraversal()
          .map((node) => node.getSemanticsData())
          .singleWhere(
            (node) => node.label.startsWith(english.statisticsTileRoot),
          );
      expect(rootTile.flagsCollection.isChecked, CheckedState.isTrue);
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String locale = 'ru',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: doableTheme(Brightness.light),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Плитки: 7, 0, 0 и 8 действий; вид без действий — «Конечное» или
/// «Промежуточное».
Widget _overview({
  bool zero = false,
  StatisticsView view = StatisticsView.throughRelations,
}) {
  final period = StatisticsMonth(2026, 10);
  final counts = ContributionCounts(planned: 8, contribution: zero ? 0 : 3);
  final cards = IntentionStatisticsCards(
    rootIntentions: ContributionCounts(planned: 7, contribution: zero ? 0 : 3),
    intermediateIntentions: ContributionCounts(planned: 0, contribution: 0),
    terminalIntentions: ContributionCounts(planned: 0, contribution: 0),
    throughRelations: counts,
  );
  final action = StatisticsItem(
    id: statisticsId(2),
    title: 'Лечь до полуночи',
    archiveState: IntentionArchiveState.active,
    counts: counts,
  );
  StatisticsBreakdownFirstPage<StatisticsItem> intentions(
    List<StatisticsItem> items,
  ) => StatisticsBreakdownFirstPage(
    items: items,
    totalItems: items.length,
    nextCursor: null,
  );
  final section = IntentionStatisticsSection(
    query: IntentionStatisticsQuery(
      intentionId: statisticsId(1),
      period: period,
      view: view,
      pageSize: 100,
    ),
    revision: const StatisticsTestRevision(0),
    cards: cards,
    periodCounts: ContributionCounts(planned: 21, contribution: zero ? 0 : 4),
    details: switch (view) {
      StatisticsView.rootIntentions => IntentionStatisticsRootDetails(
        terminalIntentions: intentions([action]),
      ),
      StatisticsView.intermediateIntentions =>
        IntentionStatisticsIntermediateDetails(
          rootIntentions: intentions([]),
          terminalIntentions: intentions([]),
        ),
      StatisticsView.terminalIntentions => IntentionStatisticsTerminalDetails(
        rootIntentions: intentions([]),
      ),
      StatisticsView.throughRelations =>
        IntentionStatisticsThroughRelationsDetails(
          explicitPathActions: 7,
          relations: StatisticsBreakdownFirstPage(
            items: [
              StatisticsRelationItem(
                id: statisticsRelation(1).id,
                scope: statisticsRelation(1).scope,
                relatedIntention: action,
              ),
            ],
            totalItems: 1,
            nextCursor: null,
          ),
          terminalIntentions: intentions([action]),
        ),
    },
    calendar: IntentionStatisticsMonthCalendar(
      period: period,
      statuses: cards[view].planned == 0
          ? {}
          : {
              CalendarDate.fromParts(2026, 10, 7):
                  ActionDayStatus.hasIncomplete,
              CalendarDate.fromParts(2026, 10, 12):
                  ActionDayStatus.hasIncomplete,
              CalendarDate.fromParts(2026, 10, 15): zero
                  ? ActionDayStatus.hasIncomplete
                  : ActionDayStatus.allCompleted,
            },
    ),
  );
  return IntentionStatisticsOverview(
    state: IntentionStatisticsState(
      selection: IntentionStatisticsSelection.initial(statisticsToday, null),
      read: IntentionStatisticsLoaded.first(section),
    ),
    onModeSelected: (_) {},
    onPreviousPeriod: () {},
    onNextPeriod: () {},
    onViewSelected: (_) {},
    onMonthSelected: (_) {},
    onDaySelected: (_) {},
  );
}
