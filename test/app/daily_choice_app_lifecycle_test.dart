import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_date_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart'
    as daily_page;
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart';
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
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/daily_choice_detail_fields_controls.dart';
import '../support/daily_choice_details_controls.dart';

import '../support/app_root_pages.dart';
import '../support/controlled_local_date.dart';
import '../support/daily_choice_catalog_controls.dart';
import '../support/daily_choice_catalog_provider.dart';
import '../support/daily_choice_durability_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/in_memory_quick_creation_mode_store.dart';

part 'daily_choice_completion_lifecycle_scenarios.dart';

/// Локальное сегодня запуска, в котором человек настраивает календарь.
final _firstToday = CalendarDate.fromParts(2026, 10, 4);

/// Локальное сегодня следующего запуска — на следующий день.
final _nextToday = CalendarDate.fromParts(2026, 10, 5);

/// Будущий день, который человек выбирает в первом запуске.
final _futureDate = CalendarDate.fromParts(2026, 11, 15);

/// Прошлый выполненный дневной выбор: [durabilityChoiceDate].
const _pastChoice = 201;

/// Будущий невыполненный дневной выбор с другим путём: [_futureDate].
const _futureChoice = 202;

/// Выполненный дневной выбор дня следующего запуска: [_nextToday].
const _nextTodayChoice = 203;

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

String _storedDate(LocalDatabaseHarness harness, int choiceNumber) {
  final database = sqlite.sqlite3.open(harness.databaseFile.path);
  try {
    return database.select(
          'SELECT choice_date FROM daily_choices WHERE id = ?',
          [durabilityUuid(choiceNumber)],
        ).single['choice_date']
        as String;
  } finally {
    database.close();
  }
}

final class _ChoiceSqlGate extends LocalDatabaseConnectionObserver {
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
        !statement.statements.any((sql) => sql.contains('daily_choices'))) {
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
      final seeded = await harness.openReadyDatabase();
      await seedDurabilityGraph(seeded);
      for (final (choice, step) in [(201, 301), (202, 303)]) {
        expect(
          await durabilityRepository(
            seeded,
            choiceNumber: choice,
            firstStepNumber: step,
          ).execute(durabilityCreate()),
          isA<GraphCommandSucceeded>(),
        );
      }
      await harness.closePersistenceObjectGraph();

      final gate = _ChoiceSqlGate();
      // Каталог открывается на дне изменяемых дневных выборов.
      final localDate = ControlledLocalDate(durabilityChoiceDate);
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
      await openDailyChoices(tester, tap: _tap);
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('daily-choice-section-true'))
            .evaluate()
            .isNotEmpty,
      );
      await showDailyChoiceCatalogSection(tester, true);
      await _tap(tester, find.byKey(const ValueKey('daily-choice-row-2')));
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      final repository = ready.container.read(personalGraphRepositoryProvider);

      gate.arm(fail: true);
      await changeDailyChoiceDescription(tester, 'Запись до commit', tap: _tap);
      await _until(tester, () => gate.hasEntered);
      expect(_storedDate(harness, 202), '2026-09-23');
      final failedRead = repository.getDailyChoice(durabilityChoice(202));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 350));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      gate.release();
      final unchanged = await failedRead;
      expect(unchanged, isA<DailyChoiceReadSuccess>());
      expect(
        (unchanged as DailyChoiceReadSuccess).value.value!.choice.date
            .toCanonicalString(),
        '2026-09-23',
      );
      expect(
        unchanged.value.value!.choice.description?.value,
        '  Выбор\nдня  ',
      );
      expect(unchanged.value.value!.choice.isCompleted, isTrue);
      expect(unchanged.value.value!.path, hasLength(2));
      expect(_storedDate(harness, 202), '2026-09-23');
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
      expect(dailyChoiceDetails, findsNothing);
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
      await _tap(tester, find.byKey(const ValueKey('daily-choice-row-2')));
      await _until(tester, () => dailyChoiceDetailsReady.evaluate().isNotEmpty);
      gate.arm(fail: false);
      await setDailyChoiceDate(
        tester,
        CalendarDate.fromParts(2027, 1, 2),
        tap: _tap,
      );
      await _until(tester, () => gate.hasEntered);
      var readCompleted = false;
      final pendingRead = repository.getDailyChoice(durabilityChoice(202)).then(
        (result) {
          readCompleted = true;
          return result;
        },
      );
      await tester.pump();
      expect(readCompleted, isFalse);
      expect(_storedDate(harness, 202), '2026-09-23');
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 350));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      gate.release();
      final confirmed = await pendingRead;
      expect(confirmed, isA<DailyChoiceReadSuccess>());
      expect(
        (confirmed as DailyChoiceReadSuccess).value.value!.choice.date
            .toCanonicalString(),
        '2027-01-02',
      );
      expect(
        confirmed.value.value!.choice.description?.value,
        '  Выбор\nдня  ',
      );
      expect(confirmed.value.value!.choice.isCompleted, isTrue);
      expect(_storedDate(harness, 202), '2027-01-02');
      expect(
        find.byKey(const ValueKey('graph-operation-message')),
        findsNothing,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(dailyChoiceDetails, findsNothing);
      expect(
        find.byKey(const ValueKey('graph-operation-message')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'новый запуск открывает каталог на новом сегодня без прежних календаря, '
    'фильтра и прокрутки, а календарь не меняет сохранённые дневные выборы',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      // Раскрытый календарь с выдачей выше экрана: каталог прокручивается.
      tester.view.physicalSize = const Size(1200, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final l10n = lookupAppLocalizations(const Locale('ru'));

      final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
      final seeded = await harness.openReadyDatabase();
      await seedDurabilityGraph(seeded);
      for (final (choice, firstStep, command) in [
        (_pastChoice, 301, durabilityCreate()),
        (
          _futureChoice,
          303,
          durabilityCreate(
            path: const [103],
            date: _futureDate,
            description: 'Будущий выбор',
            completed: false,
          ),
        ),
        (_nextTodayChoice, 305, durabilityCreate(date: _nextToday)),
      ]) {
        expect(
          await durabilityRepository(
            seeded,
            choiceNumber: choice,
            firstStepNumber: firstStep,
          ).execute(command),
          isA<GraphCommandSucceeded>(),
        );
      }
      await harness.closePersistenceObjectGraph();
      final stored = durabilityFileState(harness.databaseFile);
      expect(_storedChoices(stored), {
        (
          durabilityUuid(_pastChoice),
          durabilityChoiceDate.toCanonicalString(),
          1,
          '  Выбор\nдня  ',
        ),
        (
          durabilityUuid(_futureChoice),
          _futureDate.toCanonicalString(),
          0,
          'Будущий выбор',
        ),
        (
          durabilityUuid(_nextTodayChoice),
          _nextToday.toCanonicalString(),
          1,
          '  Выбор\nдня  ',
        ),
      });
      expect(stored['таблица daily_choice_path_steps'], hasLength(5));

      final localDate = ControlledLocalDate(_firstToday);
      late _ObservedRepository graph;
      AppRuntime start() => AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: () =>
            openFileBackedLocalDatabase(harness.databaseFile),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        localDateSource: localDate.read,
        repositoryFactory: (database) => graph = _ObservedRepository(
          DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.now().toUtc(),
            InMemoryDiagnosticsSink(),
            relationIdGenerator: UuidV7LongTermRelationIdGenerator(),
          ),
        ),
      );
      var runtime = start();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
        await harness.dispose();
      });

      // Первый запуск: человек выбирает будущий день и невыполненные,
      // раскрывает календарь на другом месяце и прокручивает каталог.
      await tester.pumpWidget(MainApp(runtime: runtime));
      await _until(tester, () => find.byType(HomePage).evaluate().isNotEmpty);
      final first = graph;
      final firstContainer =
          (await runtime.bootstrap() as AppRuntimeReady).container;
      await openDailyChoices(tester, tap: _tap);
      expect(
        (await _catalogResult(
          tester,
          firstContainer,
          date: _firstToday,
          isCompleted: null,
        )).items,
        isEmpty,
      );
      await selectDailyChoiceCatalogDate(tester, _futureDate, tap: _tap);
      await _catalogResult(
        tester,
        firstContainer,
        date: _futureDate,
        isCompleted: null,
      );
      await showDailyChoiceCatalogSection(tester, false);
      await _catalogResult(
        tester,
        firstContainer,
        date: _futureDate,
        isCompleted: false,
      );
      await expandDailyChoiceCatalogCalendar(tester, tap: _tap);
      await showDailyChoiceCatalogPeriod(
        tester,
        CalendarDate.fromParts(2026, 12, 15),
        tap: _tap,
      );
      final position = _catalogPosition(tester);
      expect(position.maxScrollExtent, greaterThan(0));
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final configured = _catalogView(tester, firstContainer);
      expect(configured, {
        'выбранный день': _futureDate,
        'просмотр календаря': DailyChoiceCalendarViewport(
          focusedDate: CalendarDate.fromParts(2026, 12, 1),
          mode: DailyChoiceCalendarMode.month,
        ),
        'раскрытие невыполненных': true,
        'раскрытие выполненных': false,
        'сегодня': _firstToday,
        'загруженные записи': [durabilityUuid(_futureChoice)],
        'позиция прокрутки': position.maxScrollExtent,
      });
      expect(position.pixels, greaterThan(0));
      expect(first.catalogQueries.map(_conditions), [
        (_firstToday, false, false),
        (_firstToday, true, false),
        (_futureDate, false, false),
        (_futureDate, true, false),
      ]);

      // Возврат в работающее приложение сохраняет календарь, фильтр и
      // прокрутку и ничего не читает заново.
      await openHome(
        tester,
        waitFor: (tester, finder) =>
            _until(tester, () => finder.evaluate().isNotEmpty),
      );
      await openDailyChoices(tester, tap: _tap);
      await _until(
        tester,
        () => find
            .byType(daily_page.DailyChoiceCatalogPage)
            .evaluate()
            .isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(_catalogView(tester, firstContainer), configured);
      expect(first.catalogQueries, hasLength(4));
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
        find.byType(daily_page.DailyChoiceCatalogPage, skipOffstage: false),
        findsNothing,
      );
      // Каталог ещё не открыт и выдачу не читал.
      expect(second.catalogQueries, isEmpty);

      await openDailyChoices(tester, tap: _tap);
      final opened = await _catalogResult(
        tester,
        secondContainer,
        date: _nextToday,
        isCompleted: null,
      );
      // Первое и единственное чтение — новое сегодня со всеми состояниями.
      expect(second.catalogQueries.map(_conditions), [
        (_nextToday, false, false),
        (_nextToday, true, false),
      ]);
      expect(_catalogView(tester, secondContainer), {
        'выбранный день': _nextToday,
        'просмотр календаря': DailyChoiceCalendarViewport(
          focusedDate: _nextToday,
          mode: DailyChoiceCalendarMode.week,
        ),
        'раскрытие невыполненных': true,
        'раскрытие выполненных': true,
        'сегодня': _nextToday,
        'загруженные записи': [durabilityUuid(_nextTodayChoice)],
        'позиция прокрутки': 0.0,
      });
      expect(opened.totalCount, 1);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('daily-choice-section-false')),
          matching: find.text(l10n.dailyChoiceCatalogIncomplete),
        ),
        findsOneWidget,
      );
      await showDailyChoiceCatalogSection(tester, true);
      expect(
        find.byKey(
          ValueKey(
            'daily-choice-completion-${durabilityUuid(_nextTodayChoice)}',
          ),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(durabilityFileState(harness.databaseFile), stored);

      // Сохранённые прошлый и будущий выборы доступны выбором их дня.
      for (final (date, choice) in [
        (durabilityChoiceDate, _pastChoice),
        (_futureDate, _futureChoice),
      ]) {
        await selectDailyChoiceCatalogDate(tester, date, tap: _tap);
        final result = await _catalogResult(
          tester,
          secondContainer,
          date: date,
          isCompleted: null,
        );
        expect(result.items.map((item) => item.id), [durabilityChoice(choice)]);
        await showDailyChoiceCatalogSection(
          tester,
          result.items.single.isCompleted,
        );
        expect(
          find.byKey(
            ValueKey('daily-choice-completion-${durabilityUuid(choice)}'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
      }
      expect(second.catalogQueries.map(_conditions), [
        (_nextToday, false, false),
        (_nextToday, true, false),
        (durabilityChoiceDate, false, false),
        (durabilityChoiceDate, true, false),
        (_futureDate, false, false),
        (_futureDate, true, false),
      ]);
      expect(second.commands, isEmpty);
      expect(durabilityFileState(harness.databaseFile), stored);
    },
  );
}

/// Сохранённые дневные выборы снимка [durabilityFileState]: идентификатор,
/// дата, выполнение и описание.
Set<(Object?, Object?, Object?, Object?)> _storedChoices(
  Map<String, Object?> state,
) => {
  for (final row in state['таблица daily_choices']! as List<Object?>)
    if (row case final Map<String, Object?> row)
      (row['id'], row['choice_date'], row['is_completed'], row['description']),
};

/// Условия чтения выдачи каталога: день, охват выполнения и продолжение ли
/// это загруженной выдачи.
(CalendarDate?, bool?, bool) _conditions(DailyChoiceCatalogQuery query) =>
    (query.date, query.isCompleted, query.cursor != null);

/// Дожидается выдачи открытого каталога дневных выборов за [date] с охватом
/// [isCompleted].
///
/// Модель каталога читается только после построения страницы: чтение
/// контейнером раньше страницы само создало бы модель и первое чтение
/// выдачи.
Future<DailyChoiceCatalogLoaded> _catalogResult(
  WidgetTester tester,
  ProviderContainer container, {
  required CalendarDate date,
  required bool? isCompleted,
}) async {
  await _until(
    tester,
    () => find.byType(daily_page.DailyChoiceCatalogPage).evaluate().isNotEmpty,
  );
  DailyChoiceCatalogState current() =>
      container.read(openedDailyChoiceCatalogProvider(container));
  DailyChoiceCatalogLoaded? result() => switch (current()) {
    final DailyChoiceCatalogLoaded loaded
        when loaded.selection.date == date &&
            (isCompleted == null ||
                loaded.selection.completedExpanded == isCompleted) &&
            loaded.freshness == DailyChoiceCatalogFreshness.current =>
      loaded,
    _ => null,
  };
  for (var attempt = 0; attempt < 500 && result() == null; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  if (result() == null) {
    final shown = current();
    fail(
      'Каталог дневных выборов не показал выдачу за $date с охватом '
      'выполнения $isCompleted: состояние ${shown.runtimeType} за '
      '${shown.selection.date} с охватом ${shown.selection.completedExpanded}.',
    );
  }
  await tester.pumpAndSettle();
  return result()!;
}

/// Параметры открытого каталога дневных выборов, как их видит человек:
/// выбранный день, просматриваемый период, значение фильтра выполнения,
/// сегодняшний день календаря, загруженные записи и позиция общей прокрутки.
///
/// Календарь и фильтр прокручиваются вместе с выдачей, поэтому читаются и за
/// верхним краем экрана.
Map<String, Object?> _catalogView(
  WidgetTester tester,
  ProviderContainer container,
) {
  final calendar = find.byType(DailyChoiceCalendar, skipOffstage: false);
  return {
    'выбранный день': shownDailyChoiceCatalogDate(tester),
    'просмотр календаря': shownDailyChoiceCatalogViewport(tester),
    'раскрытие невыполненных': container
        .read(openedDailyChoiceCatalogProvider(container))
        .selection
        .incompleteExpanded,
    'раскрытие выполненных': container
        .read(openedDailyChoiceCatalogProvider(container))
        .selection
        .completedExpanded,
    'сегодня': tester.widget<DailyChoiceCalendar>(calendar).today,
    'загруженные записи': switch (container.read(
      openedDailyChoiceCatalogProvider(container),
    )) {
      final DailyChoiceCatalogLoaded loaded => [
        for (final item in loaded.items) item.id.toCanonicalString(),
      ],
      final other => fail('Каталог дневных выборов без выдачи: $other'),
    },
    'позиция прокрутки': _catalogPosition(tester).pixels,
  };
}

/// Общая прокрутка открытого каталога дневных выборов: календарь, фильтры и
/// выдача прокручиваются вместе.
ScrollPosition _catalogPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.descendant(
              of: find.byType(daily_page.DailyChoiceCatalogPage),
              matching: find.byType(CustomScrollView),
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// Реальный адаптер, который записывает условия чтений выдачи каталога
/// дневных выборов и дошедшие до хранилища команды.
final class _ObservedRepository implements PersonalGraphRepository {
  _ObservedRepository(this._delegate);

  final PersonalGraphRepository _delegate;

  /// Чтения выдачи каталога дневных выборов в порядке обращения.
  final catalogQueries = <DailyChoiceCatalogQuery>[];

  /// Команды, дошедшие до хранилища.
  final commands = <GraphCommand<GraphCommandOutcome, GraphCommandFailure>>[];

  @override
  Future<ActionDayPageResult> getActionDayPage(ActionDayQuery query) =>
      _delegate.getActionDayPage(query);

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
  Future<DailyChoiceDayStatusesReadResult> getDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  ) => _delegate.getDailyChoiceDayStatuses(query);

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) {
    commands.add(command);
    return _delegate.execute(command);
  }

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) {
    catalogQueries.add(query);
    return _delegate.getDailyChoiceCatalogPage(query);
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
    RelationGroupPageQuery query,
  ) => _delegate.getRelationGroupPage(query);

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      _delegate.watchRelation(id);

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      _delegate.getDailyChoice(id);

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      _delegate.watchDailyChoice(id);

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) =>
      _delegate.getTagCatalog(mode);

  @override
  Future<TagAssignmentsResult> getTagAssignments(IntentionId intentionId) =>
      _delegate.getTagAssignments(intentionId);

  @override
  Stream<TagReadResult> watchTag(TagId id) => _delegate.watchTag(id);
}
