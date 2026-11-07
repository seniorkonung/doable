import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar_day.dart';
import 'package:doable/src/action/presentation/day/action_day_marks_view_model.dart';
import 'package:doable/src/action/presentation/day/action_day_body.dart';
import 'package:doable/src/action/presentation/day/action_day_state.dart';
import 'package:doable/src/action/presentation/day/action_day_view_model.dart';
import 'package:doable/src/action/presentation/day/action_day_date_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention.dart'
    show IntentionArchiveState;
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart'
    show RelationScope;
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_page_target.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/intention_statistics_target.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_calendar.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/home_statistics_state.dart';
import 'package:doable/src/statistics/presentation/home_statistics_view_model.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_section.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_state.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/controlled_local_date.dart';
import '../support/action_day_controls.dart';
import '../support/action_panel_controls.dart';
import '../support/action_panel_edit_controls.dart';
import '../support/action_seed.dart';
import '../support/app_root_pages.dart';
import '../support/graph_durability_fixture.dart';
import '../support/graph_seed.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';

part 'intention_statistics_catalog_scenarios.dart';

final _today = CalendarDate.fromParts(2026, 10, 12);

void main() {
  _catalogNavigationScenarios();

  testWidgets(
    'возврат после команд атомарно заменяет карточки, календарь и две порционные разбивки',
    (tester) async {
      final app = await _start(tester, seed: _seedPagedBreakdowns);
      final provider = await app.open(tester);
      await app.ready(tester, provider);
      final row = find.descendant(
        of: find.byKey(const ValueKey(StatisticsBreakdown.terminalIntentions)),
        matching: find.text('Действие 2010'),
      );
      await _scrollTo(tester, row);
      final before = app.loaded(provider);
      expect(_counts(before), (121, 121));
      expect(before.breakdowns.relations!.items, hasLength(121));
      expect(before.breakdowns.terminalIntentions!.items, hasLength(121));
      final offset = _scroll(tester).position.pixels;
      expect(offset, greaterThan(1000));
      final other = await app.open(tester, intention: 5);
      await app.ready(tester, other);
      await app.action(
        tester,
        UpdateActionFields(
          actionId: seedActionId(4001),
          patch: ActionFieldsPatch(
            isCompleted: const ActionFieldSet(false),
            date: ActionFieldSet(_today),
          ),
        ),
      );
      await app.ready(tester, other);
      await tester.runAsync(() async {
        final start = app.runtime.commandCoordinator.acceptRelationArchive(
          ArchiveLongTermRelation(durabilityRelation(6000)),
        ) as LongTermRelationCommandAccepted;
        expect((await start.future).isFailure, isFalse);
      });
      await app.ready(tester, other);
      await app.intention(tester, ArchiveIntention(durabilityIntention(2120)));
      await app.ready(tester, other);
      await app.intention(
        tester,
        UpdateIntention(
          id: durabilityIntention(2119),
          title: 'Новое название действия',
          description: null,
        ),
      );
      await app.ready(tester, other);
      expect(_counts(app.loaded(provider)), (121, 121));

      final published = <(int, int, int)>[];
      final subscription = app.container.listen(provider, (_, next) {
        if (next.read case IntentionStatisticsLoaded(
          :final section,
          :final breakdowns,
          refreshStatus: IntentionStatisticsRefreshIdle(),
        )) {
          published.add((
            section.selectedCounts.planned,
            breakdowns.relations!.items.length,
            breakdowns.terminalIntentions!.items.length,
          ));
        }
      });
      addTearDown(subscription.close);
      final continuation = app.probe.holdNextContinuation();
      final reads = app.probe.sourceReads;
      final computations = app.probe.computations;
      app.container.read(appRouterProvider).pop();
      await _wait(tester, () => continuation.started.isCompleted);
      await tester.pumpAndSettle();
      expect(_counts(app.loaded(provider)), (121, 121));
      expect(app.loaded(provider).breakdowns.relations!.items, hasLength(121));
      expect(
        app.loaded(provider).breakdowns.terminalIntentions!.items,
        hasLength(121),
      );
      expect(published, isEmpty);
      expect(
        _text(app.texts.statisticsRefreshing).hitTestable(),
        findsOneWidget,
      );
      expect(row.hitTestable(), findsOneWidget);
      expect(_scroll(tester).position.pixels, offset);
      continuation.release.complete();
      await app.ready(tester, provider);
      await tester.pumpAndSettle();
      expect(published, [(120, 120, 120)]);
      expect(app.probe.sourceReads, reads + 1);
      expect(app.probe.computations, computations + 1);
      expect(_scroll(tester).position.pixels, offset);
      final after = app.loaded(provider);
      expect(_counts(after), (120, 119));
      expect(
        [
          for (final view in StatisticsView.values)
            (
              after.section.cards[view].planned,
              after.section.cards[view].contribution,
            ),
        ],
        [(0, 0), (120, 119), (0, 0), (120, 119)],
      );
      expect(
        (after.section.calendar as IntentionStatisticsMonthCalendar).statuses,
        {
          CalendarDate.fromParts(2026, 10, 10): ActionDayStatus.allCompleted,
          _today: ActionDayStatus.hasIncomplete,
        },
      );
      expect(
        (after.section.details as IntentionStatisticsThroughRelationsDetails)
            .explicitPathActions,
        120,
      );
      expect(after.breakdowns.relations!.totalItems, 120);
      expect(after.breakdowns.terminalIntentions!.totalItems, 120);
      expect(
        after.breakdowns.terminalIntentions!.items.any(
          (item) => item.id == durabilityIntention(4),
        ),
        isFalse,
      );
      final archived = after.breakdowns.relations!.items.singleWhere(
        (item) => item.relatedIntention.id == durabilityIntention(2120),
      );
      expect(archived.scope, RelationScope.archived);
      expect(
        archived.relatedIntention.archiveState,
        IntentionArchiveState.archived,
      );
      expect(archived.relatedIntention.counts.contribution, 1);
      for (final items in [
        after.breakdowns.terminalIntentions!.items,
        after.breakdowns.relations!.items.map((item) => item.relatedIntention),
      ]) {
        expect(
          items
              .singleWhere((item) => item.id == durabilityIntention(2119))
              .title,
          'Новое название действия',
        );
      }
      expect(
        app.container.read(provider).selection.period,
        StatisticsMonth(2026, 10),
      );
      expect(
        app.container.read(provider).selection.view,
        StatisticsView.throughRelations,
      );
      _scroll(tester).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        _text(app.texts.statisticsPeriodCompleted(119, 120)).hitTestable(),
        findsWidgets,
      );
      expect(
        _text(
          app.texts.statisticsPeriodActionsShare(
            after.section.selectedCounts.planned /
                after.section.periodCounts.planned,
          ),
        ).hitTestable(),
        findsWidgets,
      );
      await _scrollTo(tester, _text('Новое название действия'));
      expect(_text('Новое название действия').hitTestable(), findsWidgets);
      await tester.tap(_text(app.texts.detailsRelationsTab).first);
      await tester.pumpAndSettle();
      // 119 исходящих «нужно», одна исходящая «можно» и одна входящая «нужно».
      expect(
        find.bySemanticsLabel(app.texts.detailsRelationsTabSemantic(121, 2)),
        findsOneWidget,
      );
      _scroll(tester).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(_text(app.texts.detailsOverviewTab).first);
      await tester.pumpAndSettle();
      expect(
        _text(app.texts.detailsAddDescription).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'только верхний экземпляр читает раздел, поздний ответ скрытого и закрытого не запускает чтения',
    (tester) async {
      final app = await _start(
        tester,
        seed: (database) => _seedPath(database, 201, [1, 2, 3], _today),
      );
      final first = await app.open(tester);
      await app.ready(tester, first);
      final hidden = app.probe.holdNextComputation();
      await app.action(
        tester,
        UpdateActionFields(
          actionId: seedActionId(201),
          patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
        ),
      );
      await _wait(tester, () => hidden.started.isCompleted);
      final second = await app.open(
        tester,
        view: StatisticsView.intermediateIntentions,
        period: StatisticsYear(2026),
      );
      await app.ready(tester, second);
      expect(_counts(app.loaded(second)), (1, 1));
      expect(_counts(app.loaded(first)), (1, 0));
      final upperReads = app.probe.sourceReads;
      final upperComputations = app.probe.computations;
      await app.action(
        tester,
        UpdateActionFields(
          actionId: seedActionId(201),
          patch: ActionFieldsPatch(
            isCompleted: const ActionFieldSet(false),
            date: ActionFieldSet(CalendarDate.fromParts(2026, 10, 11)),
          ),
        ),
      );
      await app.ready(tester, second);
      expect(_counts(app.loaded(second)), (1, 0));
      expect(app.probe.sourceReads, upperReads + 1);
      expect(app.probe.computations, upperComputations + 1);
      expect(hidden.finished.isCompleted, isFalse);
      final reads = app.probe.sourceReads;
      final computations = app.probe.computations;
      final finished = app.finishedSections;
      hidden.release.complete();
      await _wait(tester, () => app.finishedSections == finished + 1);
      expect(hidden.finished.isCompleted, isTrue);
      expect(app.probe.sourceReads, reads);
      expect(app.probe.computations, computations);
      expect(
        app.lastSectionStatus,
        isA<DiagnosticsFailed>().having(
          (status) => status.code,
          'устаревший снимок',
          DiagnosticsFailureCode.conflict,
        ),
      );
      expect(
        app.container.read(first).selection.period,
        StatisticsMonth(2026, 10),
      );
      expect(
        app.container.read(first).selection.view,
        StatisticsView.throughRelations,
      );
      expect(app.container.read(second).selection.period, StatisticsYear(2026));
      expect(
        app.container.read(second).selection.view,
        StatisticsView.intermediateIntentions,
      );

      app.container.read(appRouterProvider).pop();
      await app.ready(tester, first);
      await tester.pumpAndSettle();
      expect(app.probe.sourceReads, reads + 1);
      expect(app.probe.computations, computations + 1);
      final calendar =
          app.loaded(first).section.calendar
              as IntentionStatisticsMonthCalendar;
      expect(calendar.statuses.keys, [CalendarDate.fromParts(2026, 10, 11)]);
      expect(_text(app.texts.statisticsPeriodCompleted(0, 1)), findsOneWidget);

      final closed = app.probe.holdNextComputation();
      await app.action(
        tester,
        UpdateActionFields(
          actionId: seedActionId(201),
          patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
        ),
      );
      await _wait(tester, () => closed.started.isCompleted);
      app.container.read(appRouterProvider).pop();
      await tester.pumpAndSettle();
      await _wait(
        tester,
        () =>
            app.container.read(homeStatisticsViewModelProvider).read
                is HomeStatisticsLoaded,
      );
      final closedReads = app.probe.sourceReads;
      final closedComputations = app.probe.computations;
      final closedFinished = app.finishedSections;
      closed.release.complete();
      await _wait(tester, () => app.finishedSections == closedFinished + 1);
      expect(app.probe.sourceReads, closedReads);
      expect(app.probe.computations, closedComputations);
      expect(find.byType(IntentionDetailsPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'полночь и возврат приложения меняют только отметку дня без чтения и записи в SQLite',
    (tester) async {
      final clock = ControlledLocalDate(
        _today,
        untilNextDate: const Duration(seconds: 2),
      );
      final app = await _start(
        tester,
        clock: clock,
        seed: (database) => _seedPath(database, 201, [1, 2, 3], _today),
      );
      final provider = await app.open(tester);
      await app.ready(tester, provider);
      final before = app.loaded(provider);
      final saved = await tester.runAsync(() => _actionState(app.database));
      final reads = app.probe.sourceReads;
      final computations = app.probe.computations;
      expect(app.container.read(provider).selection.localDate, _today);
      expect(_text(app.texts.statisticsPeriodCompleted(0, 1)), findsOneWidget);

      final nextDay = CalendarDate.fromParts(2026, 10, 13);
      clock.today = nextDay;
      clock.untilNextDate = const Duration(hours: 12);
      await tester.pump(const Duration(seconds: 2));
      await _wait(
        tester,
        () => app.container.read(provider).selection.localDate == nextDay,
      );
      expect(_text(app.texts.statisticsPeriodCompleted(0, 1)), findsOneWidget);

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      clock.today = _today;
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await _wait(
        tester,
        () => app.container.read(provider).selection.localDate == _today,
      );
      await app.ready(tester, provider);
      expect(_counts(app.loaded(provider)), _counts(before));
      expect(app.probe.sourceReads, reads);
      expect(app.probe.computations, computations);
      expect(
        app.container.read(provider).selection.period,
        StatisticsMonth(2026, 10),
      );
      expect(
        app.container.read(provider).selection.view,
        StatisticsView.throughRelations,
      );
      expect(await tester.runAsync(() => _actionState(app.database)), saved);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _text(String text) => find.descendant(
  of: find.byType(IntentionDetailsPage),
  matching: find.text(text),
);

(int, int) _counts(IntentionStatisticsLoaded data) => (
  data.section.selectedCounts.planned,
  data.section.selectedCounts.contribution,
);

final class _App {
  _App(
    this.runtime,
    this.container,
    this.database,
    this.probe,
    this.diagnostics,
  );

  final AppRuntime runtime;
  final ProviderContainer container;
  final AppDatabase database;
  final _StatisticsProbe probe;
  final InMemoryDiagnosticsSink diagnostics;
  Iterable<StatisticsReadDiagnosticsEvent> get _sectionResults =>
      diagnostics.events.whereType<StatisticsReadDiagnosticsEvent>().where(
        (event) =>
            event.readType == StatisticsReadDiagnosticsType.intentionSection &&
            event.stage == StatisticsReadDiagnosticsStage.titles &&
            event.status is! DiagnosticsStarted,
      );
  int get finishedSections => _sectionResults.length;
  DiagnosticsStatus get lastSectionStatus => _sectionResults.last.status;
  AppLocalizations get texts => lookupAppLocalizations(const Locale('ru'));
  IntentionStatisticsLoaded loaded(
    IntentionStatisticsViewModelProvider provider,
  ) => container.read(provider).read as IntentionStatisticsLoaded;

  Future<IntentionStatisticsViewModelProvider> open(
    WidgetTester tester, {
    StatisticsView view = StatisticsView.throughRelations,
    StatisticsPeriod? period,
    int intention = 2,
  }) async {
    unawaited(
      container
          .read(appRouterProvider)
          .push(
            IntentionDetailsRoute(
              intentionId: durabilityIntention(intention),
              target: StatisticsTarget(
                IntentionStatisticsTarget(
                  view: view,
                  period: period ?? StatisticsMonth(2026, 10),
                ),
              ),
            ),
          ),
    );
    await _wait(
      tester,
      () => find.byType(IntentionStatisticsSectionSliver).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await _wait(
      tester,
      () =>
          find.byType(IntentionStatisticsSectionSliver).evaluate().length == 1,
    );
    return tester
        .widget<IntentionStatisticsSectionSliver>(
          find.byType(IntentionStatisticsSectionSliver),
        )
        .provider;
  }

  Future<void> ready(
    WidgetTester tester,
    IntentionStatisticsViewModelProvider provider,
  ) => _wait(
    tester,
    () => switch (container.read(provider).read) {
      IntentionStatisticsLoaded(
        refreshStatus: IntentionStatisticsRefreshIdle(),
      ) =>
        true,
      _ => false,
    },
  );

  Future<void> action(WidgetTester tester, ActionCommand command) async {
    await tester.runAsync(() async {
      final coordinator = runtime.commandCoordinator;
      final start = switch (command) {
        UpdateActionFields() => coordinator.acceptActionUpdate(command),
        DeleteAction() => coordinator.acceptActionDelete(command),
      };
      expect(start, isA<ActionCommandAccepted>());
      expect(
        (await (start as ActionCommandAccepted).future).isFailure,
        isFalse,
      );
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
      expect(
        (await (start as IntentionCommandAccepted).future).isFailure,
        isFalse,
      );
    });
    await tester.pump();
  }
}

Future<_App> _start(
  WidgetTester tester, {
  ControlledLocalDate? clock,
  Future<void> Function(AppDatabase)? seed,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late AppDatabase database;
  final probe = _StatisticsProbe();
  final diagnostics = InMemoryDiagnosticsSink();
  final runtime = AppRuntime(
    connectionFactory: () => observeConfiguredLocalDatabaseConnection(
      openInMemoryLocalDatabase(),
      probe,
    ),
    diagnosticsSink: diagnostics,
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    localDateSource: (clock ?? ControlledLocalDate(_today)).read,
    repositoryFactory: (opened) {
      database = opened;
      return DriftPersonalGraphRepository(
        opened,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 10, 12),
        diagnostics,
        intentionStatisticsRunner: probe.compute,
      );
    },
  );
  addTearDown(() async {
    probe.releaseAll();
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  await tester.runAsync(() async {
    await seedDurabilityGraph(database);
    if (seed != null) await seed(database);
  });
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _wait(tester, () => find.byType(HomePage).evaluate().isNotEmpty);
  await _wait(
    tester,
    () =>
        ready.container.read(homeStatisticsViewModelProvider).read
            is HomeStatisticsLoaded,
  );
  return _App(runtime, ready.container, database, probe, diagnostics);
}

final class _StatisticsProbe extends LocalDatabaseConnectionObserver {
  var sourceReads = 0;
  var computations = 0;
  _ComputationHold? _nextComputation;
  _ReadHold? _nextContinuation;
  _ReadHold? _nextCatalogRead;

  _ReadHold holdNextContinuation() => _nextContinuation = _ReadHold();
  _ReadHold holdNextCatalogRead() => _nextCatalogRead = _ReadHold();
  final _holds = <_ComputationHold>[];

  _ComputationHold holdNextComputation() {
    final hold = _ComputationHold();
    _holds.add(hold);
    _nextComputation = hold;
    return hold;
  }

  void releaseAll() {
    final catalog = _nextCatalogRead;
    if (catalog != null && !catalog.release.isCompleted) {
      catalog.release.complete();
    }
    final read = _nextContinuation;
    if (read != null && !read.release.isCompleted) read.release.complete();
    for (final hold in _holds) {
      if (!hold.release.isCompleted) hold.release.complete();
    }
  }

  @override
  Future<List<Map<String, Object?>>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isNotEmpty && rows.first.containsKey('seed_key')) {
      sourceReads++;
    }
    final catalog = _nextCatalogRead;
    if (catalog != null &&
        rows.isNotEmpty &&
        rows.first.containsKey('root_title') &&
        rows.first.containsKey('creation_sequence')) {
      catalog.started.complete();
      await catalog.release.future;
      _nextCatalogRead = null;
    }
    final hold = _nextContinuation;
    if (hold != null &&
        rows.isNotEmpty &&
        rows.length < 100 &&
        rows.first.containsKey('intention_archived')) {
      hold.started.complete();
      await hold.release.future;
      _nextContinuation = null;
    }
    return rows;
  }

  Future<IntentionContributionResult<CalendarDate>> compute(
    ContributionRelationGraph graph,
    IntentionId intentionId,
    List<IntentionContributionGroup<CalendarDate>> groups,
    List<ContributionOutgoingRelation> relations,
  ) async {
    computations++;
    final hold = _nextComputation;
    _nextComputation = null;
    if (hold == null) {
      return runIntentionContributionInIsolate(
        graph,
        intentionId,
        groups,
        relations,
      );
    }
    hold.started.complete();
    await hold.release.future;
    try {
      return await runIntentionContributionInIsolate(
        graph,
        intentionId,
        groups,
        relations,
      );
    } finally {
      hold.finished.complete();
    }
  }
}

final class _ReadHold {
  final started = Completer<void>();
  final release = Completer<void>();
}

final class _ComputationHold {
  final started = Completer<void>();
  final release = Completer<void>();
  final finished = Completer<void>();
}

Future<void> _wait(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 500; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (condition()) return;
  }
  fail('Ожидаемое состояние не наступило');
}

ScrollableState _scroll(WidgetTester tester) => tester.state<ScrollableState>(
  find
      .descendant(
        of: find.byType(IntentionDetailsPage),
        matching: find.byType(Scrollable),
      )
      .first,
);

Future<void> _scrollTo(WidgetTester tester, Finder row) async {
  for (var i = 0; i < 150; i++) {
    if (row.hitTestable().evaluate().isNotEmpty) {
      return;
    }
    await tester.drag(find.byType(IntentionDetailsPage), const Offset(0, -900));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pumpAndSettle();
  }
  fail('Строка не появилась: $row');
}

Future<void> _seedPagedBreakdowns(AppDatabase database) =>
    seedGraph(database, () async {
      for (var i = 1; i <= 120; i++) {
        await database.customStatement(
          'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, 1, 0, 1, 1)',
          [durabilityUuid(2000 + i), 'Действие ${2000 + i}'],
        );
      }
      for (final (id, target) in [
        for (var i = 1; i <= 120; i++) (3000 + i, 2000 + i),
        (6000, 4),
      ]) {
        await database.customStatement(
          "INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, created_at, updated_at) VALUES (?, ?, ?, 'need', 2, 0, 0)",
          [durabilityUuid(id), durabilityUuid(2), durabilityUuid(target)],
        );
      }
      for (final (id, path) in [
        for (var i = 1; i <= 120; i++) (4000 + i, [1, 2, 2000 + i]),
        (7001, [1, 4]),
      ]) {
        await _insertAction(
          database,
          id,
          path,
          CalendarDate.fromParts(2026, 10, 10),
          isCompleted: true,
        );
      }
    });

/// Одно действие с путём из намерений [path] в одной точке сохранения графа.
Future<void> _seedPath(
  AppDatabase database,
  int id,
  List<int> path,
  CalendarDate date,
) => seedGraph(database, () => _insertAction(database, id, path, date));

Future<void> _insertAction(
  AppDatabase database,
  int id,
  List<int> path,
  CalendarDate date, {
  bool isCompleted = false,
}) async {
  await database.customStatement(
    '''INSERT INTO actions
       (id, title, date, priority, is_completed, created_at, updated_at)
       VALUES (?, 'Пробежка', ?, 4, ?, 1, 1)''',
    [
      seedUuid(id),
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}',
      isCompleted ? 1 : 0,
    ],
  );
  for (final (position, intention) in path.indexed) {
    await database.customStatement(insertActionPathItem, [
      seedUuid(id),
      position,
      durabilityUuid(intention),
      position == 0 ? null : durabilityUuid(path[position - 1]),
      actionPathRole(position, path.length),
    ]);
  }
}

Future<List<Object>> _actionState(AppDatabase database) async => [
  await durabilityRows(database, 'intentions'),
  await durabilityRows(database, 'long_term_relations'),
  await durabilityRows(database, 'actions'),
  await durabilityRows(database, 'action_path_items'),
];
