import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/intention/domain/intention.dart';
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
    'четыре карточки показывают меры по порядку, сводка — долю и явные основания',
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
              texts.statisticsSourceIntentions,
              texts.statisticsIntermediateIntentions,
              texts.statisticsSelectedActions,
              texts.statisticsThroughRelations,
            ].any((view) => node.label.startsWith('$view.')),
          )
          .where((node) => node.flagsCollection.isButton)
          .toList();
      expect(nodes.map((node) => node.label.split('.').first), [
        texts.statisticsSourceIntentions,
        texts.statisticsIntermediateIntentions,
        texts.statisticsSelectedActions,
        texts.statisticsThroughRelations,
      ]);
      expect(find.text('3 из 7'), findsOneWidget);
      expect(find.text('0 из 0'), findsNWidgets(2));
      expect(find.text('3 из 8'), findsNWidgets(2));
      expect(find.text(texts.statisticsContributionShare(.75)), findsOneWidget);
      expect(find.text(texts.statisticsMissed(2)), findsOneWidget);
      expect(find.text(texts.statisticsUpcoming(3)), findsOneWidget);
      expect(
        find.text(texts.statisticsExplicitPathChoices(7, 8)),
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

  testWidgets(
    'нулевой вклад периода не показывает процент и объясняется диктору',
    (tester) async {
      await _pump(tester, _overview(zero: true));
      final texts = AppLocalizations.of(
        tester.element(find.byType(IntentionStatisticsOverview)),
      );
      expect(find.textContaining('%'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(texts.statisticsNoContributionShare)),
        findsWidgets,
      );
      expect(find.text('0 из 8'), findsNWidgets(2));
    },
  );

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
      expect(harness.reader.queries.last.view, StatisticsView.sourceIntentions);
      harness.reader.section(3, count: 1);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Месяц'));
      await tester.pump();
      expect(harness.reader.queries.last.period, StatisticsMonth(2026, 10));
      expect(harness.reader.queries.last.view, StatisticsView.sourceIntentions);
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
      expect(harness.reader.queries.last.view, StatisticsView.sourceIntentions);
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
                node.label.startsWith('${english.statisticsSourceIntentions}.'),
          );
      expect(sourceCard.flagsCollection.isSelected, Tristate.isTrue);
    },
  );

  testWidgets(
    'русские и английские подписи, числа и команды доступны при тексте 3×',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final locale in ['ru', 'en']) {
        await _pump(tester, _overview(), locale: locale, scale: 3);
        final texts = AppLocalizations.of(
          tester.element(find.byType(IntentionStatisticsOverview)),
        );
        await tester.ensureVisible(
          find.text(texts.statisticsExplicitPathChoices(7, 8)),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(texts.statisticsExplicitPathChoices(7, 8)).hitTestable(),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text(texts.statisticsThroughRelations));
        await tester.pumpAndSettle();
        expect(
          find.text(texts.statisticsThroughRelations).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String locale = 'ru',
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: SingleChildScrollView(child: child),
        ),
      ),
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
      localDate: statisticsToday,
      pageSize: 100,
    ),
    revision: const StatisticsTestRevision(0),
    cards: IntentionStatisticsCards(
      sourceIntentions: ContributionCounts(
        planned: 7,
        contribution: zero ? 0 : 3,
      ),
      intermediateIntentions: ContributionCounts(planned: 0, contribution: 0),
      selectedActions: ContributionCounts(planned: 0, contribution: 0),
      throughRelations: counts,
    ),
    periodCounts: ContributionCounts(planned: 21, contribution: zero ? 0 : 4),
    details: IntentionStatisticsThroughRelationsDetails(
      uncompleted: UncompletedSplit(missed: 2, upcoming: zero ? 6 : 3),
      explicitPathChoices: 7,
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
      selectedActions: StatisticsBreakdownFirstPage(
        items: [action],
        totalItems: 1,
        nextCursor: null,
      ),
    ),
    calendar: IntentionStatisticsMonthCalendar(
      period: period,
      statuses: {
        CalendarDate.fromParts(2026, 10, 7): DailyChoiceDayStatus.hasIncomplete,
        CalendarDate.fromParts(2026, 10, 12):
            DailyChoiceDayStatus.hasIncomplete,
        CalendarDate.fromParts(2026, 10, 15): zero
            ? DailyChoiceDayStatus.hasIncomplete
            : DailyChoiceDayStatus.allCompleted,
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
