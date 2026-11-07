import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/application/intention_actions.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar_viewport.dart';
import 'package:doable/src/action/presentation/day/action_day_date_page.dart';
import 'package:doable/src/action/presentation/day/action_day_root_page.dart'
    as day_page;
import 'package:doable/src/action/presentation/day/action_day_state.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/action_day_controls.dart';
import '../support/action_day_provider.dart';
import '../support/action_panel_controls.dart';
import '../support/action_panel_edit_controls.dart';
import '../support/action_panel_fixture.dart';
import '../support/action_seed.dart';
import '../support/app_root_pages.dart';
import '../support/controlled_local_date.dart';
import '../support/graph_durability_fixture.dart';
import '../support/graph_seed.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/local_database_harness.dart';

part 'action_day_completion_lifecycle_scenarios.dart';

/// Локальное сегодня запуска, в котором человек настраивает календарь.
final _firstToday = CalendarDate.fromParts(2026, 10, 4);

/// Локальное сегодня следующего запуска — на следующий день.
final _nextToday = CalendarDate.fromParts(2026, 10, 5);

/// Будущий день, который человек выбирает в первом запуске.
final _futureDate = CalendarDate.fromParts(2026, 11, 15);

/// Прошлый день, в котором лежат изменяемые действия сценариев.
final _pastDate = CalendarDate.fromParts(2026, 9, 23);

/// Прошлое выполненное действие: [_pastDate].
const _pastAction = 201;

/// Будущее невыполненное действие с другим путём: [_futureDate].
const _futureAction = 202;

/// Выполненное действие дня следующего запуска: [_nextToday].
const _nextTodayAction = 203;

/// Путь «Намерение 1» → «Намерение 2» → «Намерение 3».
final _longPath = [seedUuid(1), seedUuid(2), seedUuid(3)];

/// Путь «Намерение 1» → «Намерение 4».
final _shortPath = [seedUuid(1), seedUuid(4)];

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Состояние пользовательского сценария не достигнуто.');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, () => finder.evaluate().isNotEmpty);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

/// Намерения 1–4 и связи «нужно»: 1 → 2, 2 → 3 и 1 → 4.
void _seedIntentions(sqlite.Database raw) {
  for (var number = 1; number <= 4; number++) {
    seedIntention(raw, seedUuid(number), 'Намерение $number');
  }
  seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
  seedRelation(raw, seedUuid(102), seedUuid(2), seedUuid(3));
  seedRelation(raw, seedUuid(103), seedUuid(1), seedUuid(4));
}

/// Готовит хранилище: открывает его, записывает [write] без захвата фактов и
/// закрывает, чтобы приложение открыло готовый файл.
Future<void> _seed(
  LocalDatabaseHarness harness,
  void Function(sqlite.Database raw) write,
) async {
  late sqlite.Database raw;
  await harness.openReadyDatabase(setup: (database) => raw = database);
  seedRawGraph(raw, () => write(raw));
  await harness.closePersistenceObjectGraph();
}

/// Репозиторий запуска с фиксированным временем записи.
DriftPersonalGraphRepository _repository(AppDatabase database) =>
    DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      InMemoryDiagnosticsSink(),
      relationIdGenerator: UuidV7LongTermRelationIdGenerator(),
    );

/// Подтверждённое действие с путём; чтение ждёт записи, которая идёт.
Future<ActionDetails> _read(
  PersonalGraphRepository repository,
  ActionId id,
) async {
  final result = await repository.watchAction(id).first;
  expect(result, isA<ActionReadSuccess>());
  return (result as ActionReadSuccess).value.value!;
}

/// Значение колонки [column] сохранённого действия [number].
Object? _stored(LocalDatabaseHarness harness, int number, String column) {
  final database = sqlite.sqlite3.open(harness.databaseFile.path);
  try {
    return database.select('SELECT $column FROM actions WHERE id = ?', [
      seedUuid(number),
    ]).single[column];
  } finally {
    database.close();
  }
}

final class _ActionSqlGate extends LocalDatabaseConnectionObserver {
  Completer<void>? _entered;
  Completer<void>? _released;
  bool _fail = false;

  bool get hasEntered => _entered?.isCompleted ?? false;

  void arm({required bool fail}) {
    _entered = Completer<void>();
    _released = Completer<void>();
    _fail = fail;
  }

  void release() {
    final released = _released;
    if (released != null && !released.isCompleted) released.complete();
  }

  @override
  Future<void> afterStatement(LocalDatabaseSqlStatement statement) async {
    final entered = _entered;
    final released = _released;
    if (entered == null ||
        released == null ||
        entered.isCompleted ||
        statement.operation != LocalDatabaseSqlOperation.update ||
        !statement.statements.any((sql) => sql.contains('actions'))) {
      return;
    }
    entered.complete();
    await released.future;
    if (_fail) {
      throw sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
        message: 'Управляемый отказ записи',
      );
    }
  }
}

void main() {
  _completionLifecycleScenarios();

  testWidgets(
    'уход и потеря фокуса сохраняют результат одной команды без частичной записи',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
      await _seed(harness, (raw) {
        _seedIntentions(raw);
        for (final number in [201, 202]) {
          seedAction(
            raw,
            id: seedUuid(number),
            path: _longPath,
            description: 'Выбор\nдня',
            date: _pastDate.toCanonicalString(),
            isCompleted: true,
            timestamp: number,
          );
        }
      });

      final gate = _ActionSqlGate();
      // Экран дня открывается на дне изменяемых действий.
      final localDate = ControlledLocalDate(_pastDate);
      final runtime = AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openFileBackedLocalDatabase(harness.databaseFile),
          gate,
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        localDateSource: localDate.read,
      );
      addTearDown(() async {
        gate.release();
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
        await harness.dispose();
      });
      await tester.pumpWidget(MainApp(runtime: runtime));
      await openActions(tester, tap: _tap);
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('action-day-section-completed'))
            .evaluate()
            .isNotEmpty,
      );
      await showActionDaySection(tester, ActionDaySection.completed);
      await _tap(tester, find.byKey(const ValueKey('action-day-row-2')));
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      final repository = ready.container.read(personalGraphRepositoryProvider);

      gate.arm(fail: true);
      await _until(tester, () => actionPanelReady.evaluate().isNotEmpty);
      await saveActionPanelDescription(
        tester,
        'Запись до commit',
        waitFor: (tester, finder) =>
            _until(tester, () => finder.evaluate().isNotEmpty),
        tap: _tap,
      );
      await _until(tester, () => gate.hasEntered);
      expect(_stored(harness, 202, 'description'), 'Выбор\nдня');
      final failedRead = _read(repository, actionIdOf(202));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 350));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      gate.release();
      final unchanged = (await failedRead).action;
      expect(unchanged.date, _pastDate);
      expect(unchanged.description?.value, 'Выбор\nдня');
      expect(unchanged.isCompleted, isTrue);
      expect(_stored(harness, 202, 'description'), 'Выбор\nдня');
      expect(
        find.byKey(const ValueKey('graph-operation-message')),
        findsNothing,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('graph-operation-message'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.byKey(const ValueKey('graph-operation-message')),
        findsWidgets,
      );
      await tester.pumpAndSettle();
      expect(actionPanel, findsNothing);
      ScaffoldMessenger.of(
        tester.element(
          find.byKey(const ValueKey('graph-operation-message')).first,
        ),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('graph-operation-message')),
        findsNothing,
      );

      // Закрытая до результата панель открывается заново.
      await _tap(tester, find.byKey(const ValueKey('action-day-row-2')));
      await _until(tester, () => actionPanelReady.evaluate().isNotEmpty);
      gate.arm(fail: false);
      await chooseActionPanelDate(
        tester,
        CalendarDate.fromParts(2027, 1, 2),
        from: _pastDate,
        tap: _tap,
      );
      await _until(tester, () => gate.hasEntered);
      var readCompleted = false;
      final pendingRead = _read(repository, actionIdOf(202)).then((result) {
        readCompleted = true;
        return result;
      });
      await tester.pump();
      expect(readCompleted, isFalse);
      expect(_stored(harness, 202, 'date'), '2026-09-23');
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 350));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      gate.release();
      final confirmed = (await pendingRead).action;
      expect(confirmed.date.toCanonicalString(), '2027-01-02');
      expect(confirmed.description?.value, 'Выбор\nдня');
      expect(confirmed.isCompleted, isTrue);
      expect(_stored(harness, 202, 'date'), '2027-01-02');
      expect(
        find.byKey(const ValueKey('graph-operation-message')),
        findsNothing,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(actionPanel, findsNothing);
      expect(
        find.byKey(const ValueKey('graph-operation-message')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'новый запуск открывает экран дня на новом сегодня без прежних календаря, '
    'секций и прокрутки, а календарь не меняет сохранённые действия',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      // Раскрытый календарь с выдачей выше экрана: экран дня прокручивается.
      tester.view.physicalSize = const Size(1200, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final l10n = lookupAppLocalizations(const Locale('ru'));

      final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
      await _seed(harness, (raw) {
        _seedIntentions(raw);
        seedAction(
          raw,
          id: seedUuid(_pastAction),
          path: _longPath,
          description: 'Выбор\nдня',
          date: _pastDate.toCanonicalString(),
          isCompleted: true,
          timestamp: 1,
        );
        seedAction(
          raw,
          id: seedUuid(_futureAction),
          path: _shortPath,
          description: 'Будущее действие',
          date: _futureDate.toCanonicalString(),
          timestamp: 2,
        );
        seedAction(
          raw,
          id: seedUuid(_nextTodayAction),
          path: _longPath,
          description: 'Выбор\nдня',
          date: _nextToday.toCanonicalString(),
          isCompleted: true,
          timestamp: 3,
        );
      });
      final stored = durabilityFileState(harness.databaseFile);
      expect(_storedActions(stored), {
        (seedUuid(_pastAction), _pastDate.toCanonicalString(), 1, 'Выбор\nдня'),
        (
          seedUuid(_futureAction),
          _futureDate.toCanonicalString(),
          0,
          'Будущее действие',
        ),
        (
          seedUuid(_nextTodayAction),
          _nextToday.toCanonicalString(),
          1,
          'Выбор\nдня',
        ),
      });
      expect(stored['таблица action_path_items'], hasLength(8));

      final localDate = ControlledLocalDate(_firstToday);
      late _ObservedRepository graph;
      AppRuntime start() => AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: () =>
            openFileBackedLocalDatabase(harness.databaseFile),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        localDateSource: localDate.read,
        repositoryFactory: (database) =>
            graph = _ObservedRepository(_repository(database)),
      );
      var runtime = start();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
        await harness.dispose();
      });

      // Первый запуск: человек выбирает будущий день и невыполненные,
      // раскрывает календарь на другом месяце и прокручивает экран дня.
      await tester.pumpWidget(MainApp(runtime: runtime));
      await _until(tester, () => find.byType(HomePage).evaluate().isNotEmpty);
      final first = graph;
      final firstContainer =
          (await runtime.bootstrap() as AppRuntimeReady).container;
      await openActions(tester, tap: _tap);
      expect(
        (await _dayResult(
          tester,
          firstContainer,
          date: _firstToday,
          completedExpanded: null,
        )).items,
        isEmpty,
      );
      await selectActionDayDate(tester, _futureDate, tap: _tap);
      await _dayResult(
        tester,
        firstContainer,
        date: _futureDate,
        completedExpanded: null,
      );
      await showActionDaySection(tester, ActionDaySection.incomplete);
      await _dayResult(
        tester,
        firstContainer,
        date: _futureDate,
        completedExpanded: false,
      );
      await expandActionDayCalendar(tester, tap: _tap);
      await showActionDayPeriod(
        tester,
        CalendarDate.fromParts(2026, 12, 15),
        tap: _tap,
      );
      final position = _dayPosition(tester);
      expect(position.maxScrollExtent, greaterThan(0));
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final configured = _dayView(tester, firstContainer);
      expect(configured, {
        'выбранный день': _futureDate,
        'просмотр календаря': ActionDayCalendarViewport(
          focusedDate: CalendarDate.fromParts(2026, 12, 1),
          mode: ActionDayCalendarMode.month,
        ),
        'раскрытие невыполненных': true,
        'раскрытие выполненных': false,
        'сегодня': _firstToday,
        'загруженные записи': [seedUuid(_futureAction)],
        'позиция прокрутки': position.maxScrollExtent,
      });
      expect(position.pixels, greaterThan(0));
      expect(first.dayQueries.map(_conditions), [
        (_firstToday, ActionDaySection.incomplete, false),
        (_firstToday, ActionDaySection.completed, false),
        (_futureDate, ActionDaySection.incomplete, false),
        (_futureDate, ActionDaySection.completed, false),
      ]);

      // Возврат в работающее приложение сохраняет календарь, секции и
      // прокрутку и ничего не читает заново.
      await openHome(
        tester,
        waitFor: (tester, finder) =>
            _until(tester, () => finder.evaluate().isNotEmpty),
      );
      await openActions(tester, tap: _tap);
      await _until(
        tester,
        () => find.byType(day_page.ActionDayRootPage).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(_dayView(tester, firstContainer), configured);
      expect(first.dayQueries, hasLength(4));
      expect(first.commands, isEmpty);
      expect(durabilityFileState(harness.databaseFile), stored);

      // Полное завершение процесса: дерево виджетов, контейнер и хранилище
      // прежнего запуска освобождены. Новый запуск — на следующий день.
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
      localDate.today = _nextToday;
      runtime = start();
      await tester.pumpWidget(MainApp(runtime: runtime));
      await _until(tester, () => find.byType(HomePage).evaluate().isNotEmpty);
      final second = graph;
      final secondContainer =
          (await runtime.bootstrap() as AppRuntimeReady).container;
      expectHomeRootPage(secondContainer.read(appRouterProvider));
      expect(
        find.byType(day_page.ActionDayRootPage, skipOffstage: false),
        findsNothing,
      );
      // Экран дня ещё не открыт и выдачу не читал.
      expect(second.dayQueries, isEmpty);

      await openActions(tester, tap: _tap);
      final opened = await _dayResult(
        tester,
        secondContainer,
        date: _nextToday,
        completedExpanded: null,
      );
      // Первое и единственное чтение — новое сегодня со всеми состояниями.
      expect(second.dayQueries.map(_conditions), [
        (_nextToday, ActionDaySection.incomplete, false),
        (_nextToday, ActionDaySection.completed, false),
      ]);
      expect(_dayView(tester, secondContainer), {
        'выбранный день': _nextToday,
        'просмотр календаря': ActionDayCalendarViewport(
          focusedDate: _nextToday,
          mode: ActionDayCalendarMode.week,
        ),
        'раскрытие невыполненных': true,
        'раскрытие выполненных': true,
        'сегодня': _nextToday,
        'загруженные записи': [seedUuid(_nextTodayAction)],
        'позиция прокрутки': 0.0,
      });
      expect(opened.totalCount, 1);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('action-day-section-incomplete')),
          matching: find.text(l10n.actionDaySectionIncomplete),
        ),
        findsOneWidget,
      );
      await showActionDaySection(tester, ActionDaySection.completed);
      expect(
        find.byKey(
          ValueKey('action-day-completion-${seedUuid(_nextTodayAction)}'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(durabilityFileState(harness.databaseFile), stored);

      // Сохранённые прошлое и будущее действия доступны выбором их дня.
      for (final (date, action) in [
        (_pastDate, _pastAction),
        (_futureDate, _futureAction),
      ]) {
        await selectActionDayDate(tester, date, tap: _tap);
        final result = await _dayResult(
          tester,
          secondContainer,
          date: date,
          completedExpanded: null,
        );
        expect(result.items.map((item) => item.id), [actionIdOf(action)]);
        await showActionDaySection(
          tester,
          result.items.single.isCompleted
              ? ActionDaySection.completed
              : ActionDaySection.incomplete,
        );
        expect(
          find.byKey(
            ValueKey('action-day-completion-${seedUuid(action)}'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
      }
      expect(second.dayQueries.map(_conditions), [
        (_nextToday, ActionDaySection.incomplete, false),
        (_nextToday, ActionDaySection.completed, false),
        (_pastDate, ActionDaySection.incomplete, false),
        (_pastDate, ActionDaySection.completed, false),
        (_futureDate, ActionDaySection.incomplete, false),
        (_futureDate, ActionDaySection.completed, false),
      ]);
      expect(second.commands, isEmpty);
      expect(durabilityFileState(harness.databaseFile), stored);
    },
  );
}

/// Сохранённые действия снимка [durabilityFileState]: идентификатор, дата,
/// выполнение и описание.
Set<(Object?, Object?, Object?, Object?)> _storedActions(
  Map<String, Object?> state,
) => {
  for (final row in state['таблица actions']! as List<Object?>)
    if (row case final Map<String, Object?> row)
      (row['id'], row['date'], row['is_completed'], row['description']),
};

/// Условия чтения выдачи дня: день, секция и продолжение ли это загруженной
/// выдачи.
(CalendarDate, ActionDaySection, bool) _conditions(ActionDayQuery query) =>
    (query.date, query.section, query.cursor != null);

/// Дожидается выдачи открытого экрана дня за [date]; если задан
/// [completedExpanded], ещё и нужного раскрытия секции выполненных.
///
/// Модель экрана читается только после построения страницы: чтение
/// контейнером раньше страницы само создало бы модель и первое чтение
/// выдачи.
Future<ActionDayLoaded> _dayResult(
  WidgetTester tester,
  ProviderContainer container, {
  required CalendarDate date,
  required bool? completedExpanded,
}) async {
  await _until(
    tester,
    () => find.byType(day_page.ActionDayRootPage).evaluate().isNotEmpty,
  );
  ActionDayState current() =>
      container.read(openedActionDayProvider(container));
  ActionDayLoaded? result() => switch (current()) {
    final ActionDayLoaded loaded
        when loaded.selection.date == date &&
            (completedExpanded == null ||
                loaded.selection.completedExpanded == completedExpanded) &&
            loaded.freshness == ActionDayFreshness.current =>
      loaded,
    _ => null,
  };
  for (var attempt = 0; attempt < 500 && result() == null; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  if (result() == null) {
    final shown = current();
    fail(
      'Экран дня не показал выдачу за $date с раскрытием выполненных '
      '$completedExpanded: состояние ${shown.runtimeType} за '
      '${shown.selection.date} с раскрытием '
      '${shown.selection.completedExpanded}.',
    );
  }
  await tester.pumpAndSettle();
  return result()!;
}

/// Параметры открытого экрана дня, как их видит человек: выбранный день,
/// просматриваемый период, раскрытие секций, сегодняшний день календаря,
/// загруженные записи и позиция общей прокрутки.
///
/// Календарь и секции прокручиваются вместе с выдачей, поэтому читаются и за
/// верхним краем экрана.
Map<String, Object?> _dayView(
  WidgetTester tester,
  ProviderContainer container,
) {
  final calendar = find.byType(ActionDayCalendar, skipOffstage: false);
  return {
    'выбранный день': shownActionDayDate(tester),
    'просмотр календаря': shownActionDayViewport(tester),
    'раскрытие невыполненных': container
        .read(openedActionDayProvider(container))
        .selection
        .incompleteExpanded,
    'раскрытие выполненных': container
        .read(openedActionDayProvider(container))
        .selection
        .completedExpanded,
    'сегодня': tester.widget<ActionDayCalendar>(calendar).today,
    'загруженные записи': switch (container.read(
      openedActionDayProvider(container),
    )) {
      final ActionDayLoaded loaded => [
        for (final item in loaded.items) item.id.toCanonicalString(),
      ],
      final other => fail('Экран дня без выдачи: $other'),
    },
    'позиция прокрутки': _dayPosition(tester).pixels,
  };
}

/// Общая прокрутка открытого экрана дня: календарь, секции и выдача
/// прокручиваются вместе.
ScrollPosition _dayPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.descendant(
              of: find.byType(day_page.ActionDayRootPage),
              matching: find.byType(CustomScrollView),
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// Реальный адаптер, который записывает условия чтений выдачи дня и дошедшие
/// до хранилища команды.
final class _ObservedRepository implements PersonalGraphRepository {
  _ObservedRepository(this._delegate);

  final PersonalGraphRepository _delegate;

  /// Чтения выдачи дня в порядке обращения.
  final dayQueries = <ActionDayQuery>[];

  /// Команды, дошедшие до хранилища.
  final commands = <GraphCommand<GraphCommandOutcome, GraphCommandFailure>>[];

  @override
  Future<ActionDayPageResult> getActionDayPage(ActionDayQuery query) {
    dayQueries.add(query);
    return _delegate.getActionDayPage(query);
  }

  @override
  Future<ActionDayStatusesReadResult> getActionDayStatuses(
    ActionDayStatusQuery query,
  ) => _delegate.getActionDayStatuses(query);

  @override
  Stream<ActionReadResult> watchAction(ActionId id) =>
      _delegate.watchAction(id);

  @override
  Future<IntentionActionsPageResult> getIntentionActionsPage(
    IntentionActionsQuery query,
  ) => _delegate.getIntentionActionsPage(query);

  @override
  Future<StatisticsPageResult> getStatisticsPage(StatisticsQuery query) =>
      _delegate.getStatisticsPage(query);

  @override
  Future<IntentionStatisticsSectionResult> getIntentionStatisticsSection(
    IntentionStatisticsQuery query,
  ) => _delegate.getIntentionStatisticsSection(query);

  @override
  Future<IntentionStatisticsBreakdownResult<T>>
  getIntentionStatisticsBreakdown<T>(StatisticsBreakdownCursor<T> cursor) =>
      _delegate.getIntentionStatisticsBreakdown(cursor);

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) {
    commands.add(command);
    return _delegate.execute(command);
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => _delegate.getCatalogPage(query);

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => _delegate.watchIntention(id);

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  ) => _delegate.getRelationGroupPage(query);

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      _delegate.watchRelation(id);

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) =>
      _delegate.getTagCatalog(mode);

  @override
  Future<TagAssignmentsResult> getTagAssignments(IntentionId intentionId) =>
      _delegate.getTagAssignments(intentionId);

  @override
  Stream<TagReadResult> watchTag(TagId id) => _delegate.watchTag(id);
}
