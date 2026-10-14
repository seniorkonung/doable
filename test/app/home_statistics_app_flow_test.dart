import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart' hide LongTermRelation;
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/daily_choice_durability_fixture.dart';
import '../support/daily_choice_local_date.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/local_database_harness.dart';

final _today = CalendarDate.fromParts(2026, 10, 12);

void main() {
  testWidgets('команды связей меняют вклад через связи за прошлый месяц', (
    tester,
  ) async {
    final gate = _StatisticsRefreshGate();
    final app = await _start(tester, reachabilityRunner: gate.compute);
    addTearDown(gate.releaseComputation);
    await _until(tester, find.text(app.texts.statisticsEmpty));
    await app.choice(tester, durabilityCreate());
    await _tap(tester, find.byTooltip(app.texts.statisticsPreviousMonth));
    await _until(tester, find.text(app.texts.statisticsContribution(1)));
    await _tap(tester, find.text(app.texts.statisticsThroughRelations));
    await _until(tester, find.text(app.texts.statisticsTotalItems(3)));

    final relation = await app.relation(
      tester,
      CreateLongTermRelation(
        sourceIntentionId: durabilityIntention(5),
        relatedIntentionId: durabilityIntention(3),
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        description: null,
      ),
    );
    await _until(tester, find.text(app.texts.statisticsTotalItems(4)));
    expect(find.text('Намерение 5'), findsOneWidget);
    expect(
      find.text(app.texts.statisticsContributionCounts(1, 1)),
      findsNWidgets(4),
    );

    await app.relation(tester, ArchiveLongTermRelation(relation.id));
    await _until(tester, find.text(app.texts.statisticsTotalItems(3)));
    expect(find.text('Намерение 5'), findsNothing);
    await app.relation(tester, RestoreLongTermRelation(relation.id));
    await _until(tester, find.text(app.texts.statisticsTotalItems(4)));
    expect(find.text('Намерение 5'), findsOneWidget);

    await app.relation(
      tester,
      UpdateLongTermRelation(
        relationId: relation.id,
        patch: LongTermRelationPatch(
          sourceIntentionId: LongTermRelationFieldSet(durabilityIntention(4)),
        ),
      ),
    );
    await _until(tester, find.text('Намерение 4'));
    expect(find.text('Намерение 5'), findsNothing);
    await app.relation(
      tester,
      UpdateLongTermRelation(
        relationId: relation.id,
        patch: LongTermRelationPatch(
          relatedIntentionId: LongTermRelationFieldSet(durabilityIntention(5)),
        ),
      ),
    );
    await _until(tester, find.text(app.texts.statisticsTotalItems(3)));
    expect(find.text('Намерение 4'), findsNothing);
    await app.relation(
      tester,
      UpdateLongTermRelation(
        relationId: relation.id,
        patch: LongTermRelationPatch(
          relatedIntentionId: LongTermRelationFieldSet(durabilityIntention(2)),
        ),
      ),
    );
    await _until(tester, find.text(app.texts.statisticsTotalItems(4)));
    expect(find.text('Намерение 4'), findsOneWidget);
    await app.relation(tester, DeleteLongTermRelation(relation.id));
    await _until(tester, find.text(app.texts.statisticsTotalItems(3)));
    expect(find.text('Намерение 4'), findsNothing);
    await app.relation(
      tester,
      CreateLongTermRelation(
        sourceIntentionId: durabilityIntention(5),
        relatedIntentionId: durabilityIntention(2),
        type: LongTermRelationType.can,
        priority: RelationPriority.p2,
        description: null,
      ),
    );
    await _until(tester, find.text(app.texts.statisticsTotalItems(4)));
    await app.intention(tester, ArchiveIntention(durabilityIntention(2)));
    await _until(tester, find.text(app.texts.statisticsTotalItems(3)));
    for (final number in [1, 2, 3]) {
      expect(find.text('Намерение $number'), findsOneWidget);
    }
    expect(find.text('Намерение 5'), findsNothing);
    expect(find.text(app.texts.detailsArchived), findsOneWidget);
    expect(
      find.text(app.texts.statisticsContributionCounts(1, 1)),
      findsNWidgets(3),
    );

    await app.coverHome(tester);
    final reads = app.reads;
    await app.intention(
      tester,
      UpdateIntention(
        id: durabilityIntention(2),
        title: 'Сохранённое основание',
        description: null,
      ),
    );
    await app.choice(
      tester,
      UpdateDailyChoiceFields(
        choiceId: durabilityChoice(201),
        patch: const DailyChoiceFieldsPatch(
          isCompleted: DailyChoiceFieldSet(false),
        ),
      ),
    );
    expect(app.reads, reads);
    await app.back(tester);
    await _until(tester, find.text('Сохранённое основание'));
    expect(app.reads, reads + 1);
    expect(find.text(app.texts.statisticsContribution(0)), findsOneWidget);
    expect(
      find.text(app.texts.statisticsContributionCounts(0, 1)),
      findsNWidgets(3),
    );
    expect(
      find.text(app.texts.statisticsMonthPeriod(DateTime.utc(2026, 9))),
      findsOneWidget,
    );

    gate.holdNextComputation();
    await _tap(tester, find.text(app.texts.statisticsYearTab));
    await _untilCondition(
      tester,
      () => gate.computationStarted.isCompleted,
      'Подсчёт года не начался',
    );
    await _tap(tester, find.text(app.texts.statisticsSourceIntentions));
    await _until(tester, find.text(app.texts.statisticsTotalItems(1)));
    final readsAfterViewChange = app.reads;
    final pagesBeforeOldResponse = app.completedPages;
    gate.releaseComputation();
    await _untilCondition(
      tester,
      () => app.completedPages == pagesBeforeOldResponse + 1,
      'Ответ прежнего вида не получен',
    );
    await tester.pumpAndSettle();
    expect(app.reads, readsAfterViewChange);
    expect(find.text(app.texts.statisticsTotalItems(1)), findsOneWidget);
    expect(find.text('Намерение 1'), findsOneWidget);
    expect(find.text('Сохранённое основание'), findsNothing);
    expect(find.text('2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'периоды, вид, раскрытие, порции и прокрутка сохраняются при навигации и смене языка',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await _start(tester, seedMore: _seedCatalog);
      await _until(tester, find.text(app.texts.statisticsEmpty));
      await _tap(tester, find.byTooltip(app.texts.statisticsPreviousMonth));
      await _until(tester, find.text(app.texts.statisticsEmpty));
      await _tap(tester, find.text(app.texts.statisticsYearTab));
      await _tap(tester, find.byTooltip(app.texts.statisticsPreviousYear));
      await _until(
        tester,
        find.text(app.texts.statisticsPlannedContribution(220)),
      );
      await _tap(tester, find.text(app.texts.statisticsIntermediateIntentions));
      await _until(tester, find.text(app.texts.statisticsTotalItems(220)));
      await _tap(
        tester,
        find.byTooltip(app.texts.statisticsExpandPeriodSelector),
      );
      await _tap(tester, find.byTooltip(app.texts.statisticsPreviousYear).last);

      await _scrollTo(tester, find.text('Промежуточное 071'));
      final offset = _homeScroll(tester).position.pixels;
      var reads = app.reads;
      expect(offset, greaterThan(0));
      expect(reads, greaterThan(4));
      await openIntentionGraph(tester);
      await openHome(tester);
      await tester.pumpAndSettle();
      expect(_homeScroll(tester).position.pixels, offset);
      expect(find.text('Промежуточное 071'), findsOneWidget);
      await openHome(tester);
      await tester.pumpAndSettle();
      expect(_homeScroll(tester).position.pixels, offset);
      await app.coverHome(tester);
      await app.back(tester);
      expect(_homeScroll(tester).position.pixels, offset);
      await app.coverHome(tester);
      await openHome(tester);
      await tester.pumpAndSettle();
      expect(_homeScroll(tester).position.pixels, offset);
      expect(app.reads, reads);

      await app.coverHome(tester);
      await app.intention(
        tester,
        UpdateIntention(
          id: durabilityIntention(1071),
          title: 'Изменённое промежуточное',
          description: null,
        ),
      );
      await app.intention(
        tester,
        UpdateIntention(
          id: durabilityIntention(1),
          title: 'Новое исходное намерение',
          description: null,
        ),
      );
      expect(app.reads, reads);
      await app.back(tester);
      await _until(tester, find.text('Изменённое промежуточное'));
      expect(_homeScroll(tester).position.pixels, offset);
      expect(app.reads, reads + 2);
      reads = app.reads;

      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      await tester.pumpAndSettle();
      expect(_homeScroll(tester).position.pixels, offset);
      expect(app.reads, reads);
      _homeScroll(tester).position.jumpTo(0);
      await tester.pumpAndSettle();
      final english = lookupAppLocalizations(const Locale('en'));
      expect(
        find.byTooltip(english.statisticsCollapsePeriodSelector),
        findsOneWidget,
      );
      expect(find.text('2025'), findsWidgets);
      expect(find.text('2024'), findsWidgets);
      expect(
        tester
            .getSemantics(find.text(english.statisticsYearTab))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(find.text(english.statisticsIntermediateIntentions))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      await _tap(tester, find.text(english.statisticsMonthTab));
      await _until(tester, find.text(english.statisticsEmpty));
      expect(
        find.text(english.statisticsMonthPeriod(DateTime.utc(2026, 9))),
        findsOneWidget,
      );
      await _tap(tester, find.text(english.statisticsYearTab));
      await _until(tester, find.text(english.statisticsTotalItems(220)));
      expect(find.text('2025'), findsWidgets);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'скрытый подсчёт через связи не повторяется до возврата с глубокой прокруткой',
    (tester) async {
      final gate = _StatisticsRefreshGate();
      final app = await _start(
        tester,
        seedMore: _seedCatalog,
        reachabilityRunner: gate.compute,
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          gate,
        ),
      );
      addTearDown(() {
        gate.release();
        gate.releaseComputation();
      });
      await _until(tester, find.text(app.texts.statisticsEmpty));
      await _tap(tester, find.text(app.texts.statisticsYearTab));
      await _tap(tester, find.byTooltip(app.texts.statisticsPreviousYear));
      await _until(tester, find.text(app.texts.statisticsContribution(220)));
      await _tap(tester, find.text(app.texts.statisticsThroughRelations));
      await _until(tester, find.text(app.texts.statisticsTotalItems(222)));
      final row = find.text('Промежуточное 071');
      final oldCounts = find.descendant(
        of: find.ancestor(of: row, matching: find.byType(Card)),
        matching: find.text(app.texts.statisticsContributionCounts(220, 220)),
      );
      await _scrollTo(tester, row);
      final offset = _homeScroll(tester).position.pixels;
      expect(row.hitTestable(), findsOneWidget);
      gate.holdNextComputation();
      await app.choice(
        tester,
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(3071),
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(false),
          ),
        ),
      );
      await _untilCondition(
        tester,
        () => gate.computationStarted.isCompleted,
        'Подсчёт не начался',
      );
      expect(
        find.text(app.texts.statisticsRefreshing).hitTestable(),
        findsOneWidget,
      );
      expect(oldCounts.hitTestable(), findsOneWidget);
      final reads = app.reads;
      final sourceReads = gate.sourceReads;
      final computations = gate.computations;

      await openIntentionGraph(tester);
      await app.intention(
        tester,
        UpdateIntention(
          id: durabilityIntention(1),
          title: 'Новое исходное намерение',
          description: null,
        ),
      );
      await app.relation(
        tester,
        ArchiveLongTermRelation(durabilityRelation(2143)),
      );
      expect(gate.computationFinished.isCompleted, isFalse);
      gate.releaseComputation();
      await _untilCondition(
        tester,
        () =>
            gate.computationFinished.isCompleted &&
            app.diagnostics.events
                    .whereType<StatisticsReadDiagnosticsEvent>()
                    .last
                    .status
                is DiagnosticsFailed,
        'Старый подсчёт не завершился отказом устаревшего снимка',
      );
      await tester.pumpAndSettle();
      expect(app.reads, reads);
      expect(gate.sourceReads, sourceReads);
      expect(gate.computations, computations);
      expect(
        app.diagnostics.events
            .whereType<StatisticsReadDiagnosticsEvent>()
            .last
            .status,
        isA<DiagnosticsFailed>().having(
          (status) => status.code,
          'устаревший снимок',
          DiagnosticsFailureCode.conflict,
        ),
      );

      gate.holdNextRead();
      await openHome(tester);
      await tester.pumpAndSettle();
      expect(app.reads, reads + 1);
      expect(
        find.text(app.texts.statisticsRefreshing).hitTestable(),
        findsOneWidget,
      );
      expect(row.hitTestable(), findsOneWidget);
      expect(oldCounts.hitTestable(), findsOneWidget);
      expect(_homeScroll(tester).position.pixels, offset);

      gate.release();
      await _until(tester, find.text(app.texts.statisticsRefreshUnavailable));
      expect(
        find.text(app.texts.statisticsRefreshUnavailable).hitTestable(),
        findsOneWidget,
      );
      final retry = find.text(app.texts.commonRetry);
      expect(retry.hitTestable(), findsOneWidget);
      expect(row.hitTestable(), findsOneWidget);
      expect(oldCounts.hitTestable(), findsOneWidget);
      expect(_homeScroll(tester).position.pixels, offset);
      await tester.tap(retry);
      await tester.pump();
      await _until(
        tester,
        find.text(app.texts.statisticsRefreshing),
        absent: true,
      );
      expect(find.text(app.texts.statisticsRefreshing), findsNothing);
      expect(find.text(app.texts.statisticsRefreshUnavailable), findsNothing);
      expect(retry, findsNothing);
      expect(_homeScroll(tester).position.pixels, offset);
      expect(find.text('Промежуточное 070').hitTestable(), findsOneWidget);
      expect(app.reads, reads + 2);
      expect(gate.sourceReads, sourceReads + 1);
      expect(gate.computations, computations + 1);

      _homeScroll(tester).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('2025'), findsOneWidget);
      expect(find.text(app.texts.statisticsContribution(219)), findsOneWidget);
      expect(find.text(app.texts.statisticsTotalItems(222)), findsOneWidget);
      await _scrollTo(tester, row);
      final card = find.ancestor(of: row, matching: find.byType(Card));
      expect(
        find.descendant(
          of: card,
          matching: find.text(app.texts.statisticsContributionCounts(0, 1)),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'полночь и возврат приложения обновляют границу невыполненного только при показе',
    (tester) async {
      final clock = ControlledDailyChoiceLocalDate(
        _today,
        untilNextDate: const Duration(seconds: 2),
      );
      final app = await _start(tester, clock: clock);
      await _until(tester, find.text(app.texts.statisticsEmpty));
      await app.choice(
        tester,
        durabilityCreate(date: _today, completed: false),
      );
      await _until(tester, find.text(app.texts.statisticsUpcoming(1)));
      clock.today = CalendarDate.fromParts(2026, 10, 13);
      clock.untilNextDate = const Duration(hours: 12);
      await tester.pump(const Duration(seconds: 2));
      await _until(tester, find.text(app.texts.statisticsMissed(1)));
      expect(find.text(app.texts.statisticsUpcoming(0)), findsOneWidget);
      expect(
        find.text(app.texts.statisticsMonthPeriod(DateTime.utc(2026, 10))),
        findsOneWidget,
      );
      await app.choice(
        tester,
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(201),
          patch: DailyChoiceFieldsPatch(
            date: DailyChoiceFieldSet(CalendarDate.fromParts(2026, 10, 14)),
          ),
        ),
      );
      await _until(tester, find.text(app.texts.statisticsUpcoming(1)));
      await openIntentionGraph(tester);
      await tester.pumpAndSettle();
      final reads = app.reads;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      clock.today = CalendarDate.fromParts(2026, 10, 15);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(app.reads, reads);
      await openHome(tester);
      await _until(tester, find.text(app.texts.statisticsMissed(1)));
      expect(find.text(app.texts.statisticsUpcoming(0)), findsOneWidget);
      expect(app.reads, reads + 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'новый запуск на том же SQLite начинает текущий месяц и исходные намерения',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
      addTearDown(harness.dispose);
      final first = await _start(
        tester,
        connectionFactory: () =>
            openFileBackedLocalDatabase(harness.databaseFile),
      );
      await _until(tester, find.text(first.texts.statisticsEmpty));
      await first.choice(tester, durabilityCreate(date: _today));
      await _until(tester, find.text(first.texts.statisticsContribution(1)));
      await _tap(tester, find.text(first.texts.statisticsYearTab));
      await _tap(tester, find.byTooltip(first.texts.statisticsPreviousYear));
      await _tap(tester, find.text(first.texts.statisticsThroughRelations));
      await _until(tester, find.text(first.texts.statisticsEmpty));
      await _tap(
        tester,
        find.byTooltip(first.texts.statisticsExpandPeriodSelector),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(first.runtime.shutdown);

      final second = await _start(
        tester,
        seed: false,
        connectionFactory: () =>
            openFileBackedLocalDatabase(harness.databaseFile),
      );
      await _until(tester, find.text(second.texts.statisticsContribution(1)));
      expect(find.text('Намерение 1'), findsOneWidget);
      expect(find.text('Намерение 3'), findsNothing);
      expect(
        find.byTooltip(second.texts.statisticsExpandPeriodSelector),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(find.text(second.texts.statisticsMonthTab))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        find.text(second.texts.statisticsMonthPeriod(DateTime.utc(2026, 10))),
        findsOneWidget,
      );
      await _tap(tester, find.text(second.texts.statisticsYearTab));
      await _until(tester, find.text(second.texts.statisticsContribution(1)));
      expect(find.text('2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'команды SQLite отражаются после показа Главной без скрытых чтений',
    (tester) async {
      final app = await _start(tester);
      await _until(tester, find.text(app.texts.statisticsEmpty));
      final initialReads = app.reads;

      await openIntentionGraph(tester);
      await tester.pumpAndSettle();
      await app.choice(
        tester,
        durabilityCreate(date: _today, completed: false),
      );
      await app.choice(
        tester,
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(201),
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(true),
          ),
        ),
      );
      await app.intention(
        tester,
        UpdateIntention(
          id: durabilityIntention(1),
          title: 'Быть здоровым',
          description: null,
        ),
      );
      expect(app.reads, initialReads);
      await openHome(tester);
      await _until(tester, find.text('Быть здоровым'));
      expect(find.text(app.texts.statisticsContribution(1)), findsOneWidget);
      expect(
        find.text(app.texts.statisticsPlannedContribution(1)),
        findsOneWidget,
      );
      expect(app.reads, initialReads + 1);

      await _tap(tester, find.text(app.texts.statisticsIntermediateIntentions));
      await _until(tester, find.text('Намерение 2'));
      await app.coverHome(tester);
      final coveredReads = app.reads;
      await app.choice(
        tester,
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(201),
          patch: DailyChoiceFieldsPatch(
            date: DailyChoiceFieldSet(CalendarDate.fromParts(2026, 11, 1)),
          ),
        ),
      );
      expect(app.reads, coveredReads);
      await app.back(tester);
      await _until(
        tester,
        find.text(app.texts.statisticsPlannedContribution(0)),
      );
      expect(app.reads, coveredReads + 1);

      await app.coverHome(tester);
      final replacingReads = app.reads;
      await app.choice(
        tester,
        UpdateDailyChoiceFields(
          choiceId: durabilityChoice(201),
          patch: DailyChoiceFieldsPatch(date: DailyChoiceFieldSet(_today)),
        ),
      );
      await app.choice(
        tester,
        ReplaceDailyChoicePath(
          choiceId: durabilityChoice(201),
          sourceIntentionId: durabilityIntention(1),
          selectedIntentionId: durabilityIntention(4),
          path: durabilityPath([103]),
        ),
      );
      await app.intention(tester, ArchiveIntention(durabilityIntention(4)));
      expect(app.reads, replacingReads);
      await openHome(tester);
      await _until(
        tester,
        find.text(app.texts.statisticsPlannedContribution(1)),
      );
      expect(find.text(app.texts.statisticsEmpty), findsOneWidget);
      expect(find.text('Намерение 2'), findsNothing);
      expect(app.reads, replacingReads + 1);
      await _tap(tester, find.text(app.texts.statisticsSelectedActions));
      await _until(tester, find.text('Намерение 4'));
      expect(find.text(app.texts.detailsArchived), findsOneWidget);
      expect(
        find.text(app.texts.statisticsContributionCounts(1, 1)),
        findsOneWidget,
      );

      await app.coverHome(tester);
      final deletingReads = app.reads;
      await app.choice(tester, DeleteDailyChoice(durabilityChoice(201)));
      expect(app.reads, deletingReads);
      await app.back(tester);
      await _until(
        tester,
        find.text(app.texts.statisticsPlannedContribution(0)),
      );
      expect(find.text(app.texts.statisticsEmpty), findsOneWidget);
      expect(app.reads, deletingReads + 1);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _StatisticsRefreshGate extends LocalDatabaseConnectionObserver {
  Completer<void>? _release;
  Completer<void>? _releaseComputation;
  var computationStarted = Completer<void>();
  var computationFinished = Completer<void>();
  var sourceReads = 0;
  var computations = 0;

  void holdNextComputation() {
    _releaseComputation = Completer<void>();
    computationStarted = Completer<void>();
    computationFinished = Completer<void>();
  }

  void releaseComputation() {
    final release = _releaseComputation;
    if (release != null && !release.isCompleted) release.complete();
  }

  Future<List<ContributionReachabilityEntry>> compute(
    ContributionRelationGraph graph,
    List<ContributionSeedGroup> groups,
  ) async {
    computations++;
    final release = _releaseComputation;
    if (release == null) {
      return runContributionReachabilityInIsolate(graph, groups);
    }
    computationStarted.complete();
    await release.future;
    _releaseComputation = null;
    try {
      return await runContributionReachabilityInIsolate(graph, groups);
    } finally {
      computationFinished.complete();
    }
  }

  void holdNextRead() => _release = Completer<void>();

  void release() {
    final release = _release;
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<List<Map<String, Object?>>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) async {
    if (statement.statements.single.contains('seed_key')) sourceReads++;
    final release = _release;
    if (release == null || rows.isEmpty || !rows.first.containsKey('planned')) {
      return rows;
    }
    await release.future;
    _release = null;
    throw sqlite.SqliteException(
      extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
      message: 'Управляемая недоступность чтения статистики',
    );
  }
}

final class _App {
  _App(this.runtime, this.container, this.diagnostics);

  final AppRuntime runtime;
  final ProviderContainer container;
  final InMemoryDiagnosticsSink diagnostics;
  final texts = lookupAppLocalizations(const Locale('ru'));

  int get completedPages => diagnostics.events
      .whereType<StatisticsReadDiagnosticsEvent>()
      .where(
        (event) =>
            event.readType == StatisticsReadDiagnosticsType.homePage &&
            event.stage == StatisticsReadDiagnosticsStage.titles &&
            event.status is DiagnosticsSucceeded,
      )
      .length;

  int get reads => diagnostics.events
      .whereType<StatisticsReadDiagnosticsEvent>()
      .where(
        (event) =>
            event.readType == StatisticsReadDiagnosticsType.homePage &&
            event.status is DiagnosticsStarted &&
            event.stage == StatisticsReadDiagnosticsStage.sourceData,
      )
      .length;

  Future<void> choice(WidgetTester tester, DailyChoiceCommand command) async {
    await tester.runAsync(() async {
      final coordinator = runtime.commandCoordinator;
      final start = switch (command) {
        CreateDailyChoice() => coordinator.acceptDailyChoiceCreation(
          DailyChoiceCreationFormKey(),
          command,
        ),
        UpdateDailyChoiceFields() => coordinator.acceptDailyChoiceUpdate(
          command,
        ),
        ReplaceDailyChoicePath() => coordinator.acceptDailyChoiceReplace(
          command,
        ),
        DeleteDailyChoice() => coordinator.acceptDailyChoiceDelete(command),
      };
      expect(start, isA<DailyChoiceCommandAccepted>());
      final completion = await (start as DailyChoiceCommandAccepted).future;
      expect(completion.isFailure, isFalse);
    });
    await tester.pump();
  }

  Future<void> intention(
    WidgetTester tester,
    ExistingIntentionCommand command,
  ) async {
    await tester.runAsync(() async {
      final start = runtime.commandCoordinator.acceptExisting(
        command,
        presentationTitle: 'Намерение',
      );
      expect(start, isA<IntentionCommandAccepted>());
      final completion = await (start as IntentionCommandAccepted).future;
      expect(completion.isFailure, isFalse);
    });
    await tester.pump();
  }

  Future<LongTermRelation> relation(
    WidgetTester tester,
    LongTermRelationCommand command,
  ) async {
    final relation = await tester.runAsync(() async {
      final coordinator = runtime.commandCoordinator;
      final start = switch (command) {
        CreateLongTermRelation() => coordinator.acceptRelationCreation(
          LongTermRelationCreationFormKey(),
          command,
        ),
        UpdateLongTermRelation() => coordinator.acceptRelationUpdate(command),
        ArchiveLongTermRelation() => coordinator.acceptRelationArchive(command),
        RestoreLongTermRelation() => coordinator.acceptRelationRestore(command),
        DeleteLongTermRelation() => coordinator.acceptRelationDelete(command),
      };
      if (start is! LongTermRelationCommandAccepted) {
        fail('Команда связи не принята: $start');
      }
      return switch ((await start.future).result) {
        GraphResultSuccess(value: LongTermRelationCreated(:final relation)) ||
        GraphResultSuccess(value: LongTermRelationUpdated(:final relation)) ||
        GraphResultSuccess(
          value: LongTermRelationDeleted(:final relation),
        ) => relation,
        GraphResultFailure(:final failure) => fail('Отказ команды: $failure'),
      };
    });
    await tester.pump();
    return relation!;
  }

  Future<void> coverHome(WidgetTester tester) async {
    unawaited(
      container
          .read(appRouterProvider)
          .push(IntentionDetailsRoute(intentionId: durabilityIntention(1))),
    );
    await _until(tester, find.byType(IntentionDetailsPage));
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await container.read(appRouterProvider).maybePop();
    await tester.pumpAndSettle();
  }
}

Future<_App> _start(
  WidgetTester tester, {
  ControlledDailyChoiceLocalDate? clock,
  LocalDataConnectionFactory connectionFactory = openInMemoryLocalDatabase,
  bool seed = true,
  Future<void> Function(AppDatabase)? seedMore,
  ContributionReachabilityRunner reachabilityRunner =
      runContributionReachabilityInIsolate,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late AppDatabase database;
  final diagnostics = InMemoryDiagnosticsSink();
  final runtime = AppRuntime(
    connectionFactory: connectionFactory,
    diagnosticsSink: diagnostics,
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    dailyChoiceLocalDateSource:
        (clock ?? ControlledDailyChoiceLocalDate(_today)).read,
    repositoryFactory: (opened) {
      database = opened;
      return DriftPersonalGraphRepository(
        opened,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 10, 12),
        diagnostics,
        dailyChoiceIdGenerator: FixedChoiceIds(durabilityChoice(201)),
        choicePathStepIdGenerator: SequentialStepIds(301),
        statisticsReachabilityRunner: reachabilityRunner,
      );
    },
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  if (seed) await tester.runAsync(() => seedDurabilityGraph(database));
  if (seedMore != null) await tester.runAsync(() => seedMore(database));
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _until(tester, find.byType(HomePage));
  return _App(runtime, ready.container, diagnostics);
}

ScrollableState _homeScroll(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find
          .descendant(
            of: find.descendant(
              of: find.byType(HomePage),
              matching: find.byType(CustomScrollView),
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    );

Future<void> _scrollTo(WidgetTester tester, Finder row) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    if (row.evaluate().isNotEmpty) {
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(find.byType(HomePage), const Offset(0, -700));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pumpAndSettle();
  }
  fail('Строка каталога не появилась: $row');
}

Future<void> _seedCatalog(AppDatabase database) =>
    database.transaction(() async {
      for (var index = 1; index <= 220; index++) {
        final middle = 1000 + index;
        final firstRelation = 2000 + index * 2;
        final choice = 3000 + index;
        final firstStep = 4000 + index * 2;
        await database.customStatement(
          'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, 0, 0, 1, 1)',
          [
            durabilityUuid(middle),
            'Промежуточное ${index.toString().padLeft(3, '0')}',
          ],
        );
        for (final (relation, source, selected) in [
          (firstRelation, 1, middle),
          (firstRelation + 1, middle, 4),
        ]) {
          await database.customStatement(
            "INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority) VALUES (?, ?, ?, 'need', 2)",
            [
              durabilityUuid(relation),
              durabilityUuid(source),
              durabilityUuid(selected),
            ],
          );
        }
        await database.customStatement(
          "INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, '2025-09-12', 1)",
          [durabilityUuid(choice), durabilityUuid(1), durabilityUuid(4)],
        );
        for (var step = 0; step < 2; step++) {
          await database.customStatement(
            'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id, previous_step_id) VALUES (?, ?, ?, ?)',
            [
              durabilityUuid(firstStep + step),
              durabilityUuid(choice),
              durabilityUuid(firstRelation + step),
              step == 0 ? null : durabilityUuid(firstStep),
            ],
          );
        }
      }
    });

Future<void> _until(
  WidgetTester tester,
  Finder finder, {
  bool absent = false,
}) => _untilCondition(
  tester,
  () => finder.evaluate().isNotEmpty != absent,
  absent
      ? 'Элемент не исчез: $finder'
      : 'Ожидаемый элемент не появился: $finder',
);

Future<void> _untilCondition(
  WidgetTester tester,
  bool Function() condition,
  String failure,
) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail(failure);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
