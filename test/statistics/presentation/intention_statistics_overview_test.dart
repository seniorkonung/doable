import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_calendar.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_overview.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'intention_statistics_test_support.dart';

void main() {
  testWidgets(
    'четыре карточки показывают меры по порядку, сводка — выполнено, долю и явные основания',
    (tester) async {
      await _pump(tester, _overview());
      final texts = AppLocalizations.of(
        tester.element(find.byType(IntentionStatisticsOverview)),
      );
      final nodes = tester.semantics
          .simulatedAccessibilityTraversal()
          .map((node) => node.getSemanticsData())
          .where(
            (node) => [
              texts.statisticsRootIntentions,
              texts.statisticsIntermediateIntentions,
              texts.statisticsTerminalIntentions,
              texts.statisticsThroughRelations,
            ].any((view) => node.label.startsWith('$view.')),
          )
          .where((node) => node.flagsCollection.isButton)
          .toList();
      expect(nodes.map((node) => node.label.split('.').first), [
        texts.statisticsRootIntentions,
        texts.statisticsIntermediateIntentions,
        texts.statisticsTerminalIntentions,
        texts.statisticsThroughRelations,
      ]);
      expect(find.text('3 из 7'), findsOneWidget);
      expect(find.text('0 из 0'), findsNWidgets(2));
      expect(find.text('3 из 8'), findsOneWidget);
      expect(find.text(texts.statisticsPeriodCompleted(3, 8)), findsOneWidget);
      expect(
        find.text(texts.statisticsPeriodActionsShare(8 / 21)),
        findsOneWidget,
      );
      expect(
        find.text(texts.statisticsExplicitPathActions(7, 8)),
        findsOneWidget,
      );
      expect(nodes.map((node) => node.flagsCollection.isSelected), [
        Tristate.isFalse,
        Tristate.isFalse,
        Tristate.isFalse,
        Tristate.isTrue,
      ]);
      expect(
        find.bySemanticsLabel(RegExp(texts.statisticsCurrentPeriod)),
        findsWidgets,
      );
    },
  );

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
    expect(find.text('0 из 8'), findsOneWidget);
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
      final sourceCard = tester.semantics
          .simulatedAccessibilityTraversal()
          .map((node) => node.getSemanticsData())
          .singleWhere(
            (node) =>
                node.label.startsWith('${english.statisticsRootIntentions}.'),
          );
      expect(sourceCard.flagsCollection.isSelected, Tristate.isTrue);
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
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _overview({bool zero = false}) {
  final period = StatisticsMonth(2026, 10);
  final counts = ContributionCounts(planned: 8, contribution: zero ? 0 : 3);
  final action = StatisticsItem(
    id: statisticsId(2),
    title: 'Лечь до полуночи',
    archiveState: IntentionArchiveState.active,
    counts: counts,
  );
  final section = IntentionStatisticsSection(
    query: IntentionStatisticsQuery(
      intentionId: statisticsId(1),
      period: period,
      view: StatisticsView.throughRelations,
      pageSize: 100,
    ),
    revision: const StatisticsTestRevision(0),
    cards: IntentionStatisticsCards(
      rootIntentions: ContributionCounts(
        planned: 7,
        contribution: zero ? 0 : 3,
      ),
      intermediateIntentions: ContributionCounts(planned: 0, contribution: 0),
      terminalIntentions: ContributionCounts(planned: 0, contribution: 0),
      throughRelations: counts,
    ),
    periodCounts: ContributionCounts(planned: 21, contribution: zero ? 0 : 4),
    details: IntentionStatisticsThroughRelationsDetails(
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
      terminalIntentions: StatisticsBreakdownFirstPage(
        items: [action],
        totalItems: 1,
        nextCursor: null,
      ),
    ),
    calendar: IntentionStatisticsMonthCalendar(
      period: period,
      statuses: {
        CalendarDate.fromParts(2026, 10, 7): ActionDayStatus.hasIncomplete,
        CalendarDate.fromParts(2026, 10, 12): ActionDayStatus.hasIncomplete,
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
