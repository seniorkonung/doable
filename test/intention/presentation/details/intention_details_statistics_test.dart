import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_calendar.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/intention_statistics_target.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/ordinary_page_test_app.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import 'details_test_support.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });
  testWidgets(
    'обычное открытие показывает статистику между тегами и связями для обоих состояний намерения',
    (tester) async {
      for (final archiveState in IntentionArchiveState.values) {
        final repository = ControlledDetailsRepository()
          ..onStatisticsSection = _emptySection;
        final intention = testDetailsIntention(archiveState: archiveState);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              personalGraphRepositoryProvider.overrideWithValue(repository),
              dailyChoiceLocalDateSourceProvider.overrideWithValue(
                () => DailyChoiceLocalDay(
                  date: CalendarDate.fromParts(2026, 10, 12),
                  untilNextDate: const Duration(hours: 12),
                ),
              ),
            ],
            child: OrdinaryPageTestApp(
              locale: const Locale('ru'),
              home: IntentionDetailsPage(intentionId: intention.id),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        repository.detailRequests.single.add(ResultSuccess(intention));
        await tester.pumpAndSettle();

        expect(find.text(intention.title).hitTestable(), findsOneWidget);
        final query = repository.statisticsQueries.single;
        expect(query.intentionId, intention.id);
        expect(query.period, StatisticsMonth(2026, 10));
        expect(query.view, StatisticsView.throughRelations);
        expect(query.localDate, CalendarDate.fromParts(2026, 10, 12));
        final initialGroup = repository.relationGroupQueries.single;
        expect(initialGroup.direction, RelationDirection.outgoing);
        expect(initialGroup.type, LongTermRelationType.need);
        expect(initialGroup.scope, RelationScope.active);

        final tags = find.byType(TagAssignmentsSection, skipOffstage: false);
        final statistics = find.text('Статистика', skipOffstage: false);
        expect(statistics, findsOneWidget);
        expect(
          tester.getTopLeft(tags).dy,
          lessThan(tester.getTopLeft(statistics).dy),
        );
        expect(
          tester.getTopLeft(statistics).dy,
          lessThan(
            tester.getTopLeft(find.text('Связи', skipOffstage: false)).dy,
          ),
        );
        await tester.ensureVisible(statistics);
        await tester.pumpAndSettle();
        expect(statistics.hitTestable(), findsOneWidget);
        expect(find.textContaining('октябрь 2026'), findsOneWidget);
        expect(find.text('Через связи'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'цель маршрута применяется до чтения и прокручивает раздел только при первом получении намерения',
    (tester) async {
      final repository = ControlledDetailsRepository()
        ..onStatisticsSection = _emptySection;
      final intention = testDetailsIntention();
      final router = AppRouter();
      final container = ProviderContainer(
        overrides: [
          inMemoryQuickCreationModeOverride,
          personalGraphRepositoryProvider.overrideWithValue(repository),
          dailyChoiceLocalDateSourceProvider.overrideWithValue(
            () => DailyChoiceLocalDay(
              date: CalendarDate.fromParts(2026, 10, 12),
              untilNextDate: const Duration(hours: 12),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(container.dispose);
      Future<void> pumpApp(Locale locale) => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router.config(),
          ),
        ),
      );
      await pumpApp(const Locale('ru'));
      await tester.pumpAndSettle();
      unawaited(
        router.push(
          IntentionDetailsRoute(
            intentionId: intention.id,
            statisticsTarget: IntentionStatisticsTarget(
              view: StatisticsView.intermediateIntentions,
              period: StatisticsYear(2025),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.statisticsQueries.single.period, StatisticsYear(2025));
      expect(
        repository.statisticsQueries.single.view,
        StatisticsView.intermediateIntentions,
      );
      repository.detailRequests.single.add(ResultSuccess(intention));
      await tester.pumpAndSettle();
      expect(find.text('Статистика').hitTestable(), findsOneWidget);
      expect(find.text('2025'), findsOneWidget);
      expect(repository.relationGroupQueries, hasLength(1));

      await tester.tap(find.text('Месяц'));
      await tester.pumpAndSettle();
      final title = find.byKey(
        const ValueKey('intention-details-title'),
        skipOffstage: false,
      );
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      expect(title.hitTestable(), findsOneWidget);

      repository.detailRequests.single.add(
        ResultSuccess(testDetailsIntention(title: 'Новое название')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Новое название').hitTestable(), findsOneWidget);
      await pumpApp(const Locale('en'));
      await tester.pumpAndSettle();
      expect(find.text('Новое название').hitTestable(), findsOneWidget);
      expect(repository.statisticsQueries, hasLength(2));
      expect(
        repository.statisticsQueries.last.period,
        StatisticsMonth(2026, 10),
      );

      unawaited(
        router.push(
          IntentionDetailsRoute(
            intentionId: intention.id,
            statisticsTarget: IntentionStatisticsTarget(
              view: StatisticsView.sourceIntentions,
              period: StatisticsYear(2020),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2020'), findsOneWidget);
      expect(repository.statisticsQueries, hasLength(3));
      await tester.tap(find.byTooltip('Previous year'));
      await tester.pumpAndSettle();
      expect(find.text('2019'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Новое название').hitTestable(), findsOneWidget);
      expect(repository.statisticsQueries, hasLength(4));
      await tester.ensureVisible(find.text('Statistics', skipOffstage: false));
      await tester.pumpAndSettle();
      expect(find.textContaining('October 2026'), findsOneWidget);
      expect(repository.statisticsQueries.last.period, StatisticsYear(2019));
    },
  );

  testWidgets(
    'полночь и возврат приложения обновляют только видимую статистику без смены условий',
    (tester) async {
      var date = CalendarDate.fromParts(2026, 10, 12);
      final repository = ControlledDetailsRepository()
        ..onStatisticsSection = _emptySection;
      final intention = testDetailsIntention();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalGraphRepositoryProvider.overrideWithValue(repository),
            dailyChoiceLocalDateSourceProvider.overrideWithValue(
              () => DailyChoiceLocalDay(
                date: date,
                untilNextDate: const Duration(hours: 1),
              ),
            ),
          ],
          child: OrdinaryPageTestApp(
            locale: const Locale('ru'),
            home: IntentionDetailsPage(intentionId: intention.id),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      repository.detailRequests.single.add(ResultSuccess(intention));
      await tester.pumpAndSettle();
      date = CalendarDate.fromParts(2026, 10, 13);
      await tester.pump(const Duration(hours: 1));
      await tester.pumpAndSettle();
      expect(repository.statisticsQueries, hasLength(2));
      expect(repository.statisticsQueries.last.localDate, date);
      expect(
        repository.statisticsQueries.last.period,
        StatisticsMonth(2026, 10),
      );

      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(IntentionDetailsPage)),
          builder: (context) => AlertDialog(
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      date = CalendarDate.fromParts(2026, 10, 14);
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await tester.pumpAndSettle();
      expect(repository.statisticsQueries, hasLength(2));
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(repository.statisticsQueries, hasLength(3));
      expect(repository.statisticsQueries.last.localDate, date);
      expect(
        repository.statisticsQueries.last.period,
        StatisticsMonth(2026, 10),
      );
      expect(
        repository.statisticsQueries.last.view,
        StatisticsView.throughRelations,
      );
    },
  );
}

IntentionStatisticsSectionResult _emptySection(IntentionStatisticsQuery query) {
  final zero = ContributionCounts(planned: 0, contribution: 0);
  final intentions = StatisticsBreakdownFirstPage<StatisticsItem>(
    items: const [],
    totalItems: 0,
    nextCursor: null,
  );
  final split = UncompletedSplit(missed: 0, upcoming: 0);
  return IntentionStatisticsSectionSuccess(
    IntentionStatisticsSection(
      query: query,
      revision: const TestDetailsRevision(0),
      cards: IntentionStatisticsCards(
        sourceIntentions: zero,
        intermediateIntentions: zero,
        selectedActions: zero,
        throughRelations: zero,
      ),
      periodCounts: zero,
      details: switch (query.view) {
        StatisticsView.sourceIntentions => IntentionStatisticsSourceDetails(
          uncompleted: split,
          selectedActions: intentions,
        ),
        StatisticsView.intermediateIntentions =>
          IntentionStatisticsIntermediateDetails(
            uncompleted: split,
            sourceIntentions: intentions,
            selectedActions: intentions,
          ),
        StatisticsView.selectedActions => IntentionStatisticsSelectedDetails(
          uncompleted: split,
          sourceIntentions: intentions,
        ),
        StatisticsView.throughRelations =>
          IntentionStatisticsThroughRelationsDetails(
            uncompleted: split,
            explicitPathChoices: 0,
            relations: StatisticsBreakdownFirstPage(
              items: const [],
              totalItems: 0,
              nextCursor: null,
            ),
            selectedActions: intentions,
          ),
      },
      calendar: switch (query.period) {
        final StatisticsMonth month => IntentionStatisticsMonthCalendar(
          period: month,
          statuses: const {},
        ),
        final StatisticsYear year => IntentionStatisticsYearCalendar(
          period: year,
          months: List.filled(12, zero),
        ),
      },
    ),
  );
}
