import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart'
    as daily_page;
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/daily_choice_catalog_controls.dart';
import '../support/daily_choice_durability_fixture.dart';
import '../support/daily_choice_local_date.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';

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

Set<String> _storedIds(LocalDatabaseHarness harness, String table) {
  final database = sqlite.sqlite3.open(harness.databaseFile.path);
  try {
    return {
      for (final row in database.select('SELECT id FROM $table'))
        row['id'] as String,
    };
  } finally {
    database.close();
  }
}

List<String> _storedPathRelations(
  LocalDatabaseHarness harness,
  String choiceId,
) {
  final database = sqlite.sqlite3.open(harness.databaseFile.path);
  try {
    return [
      for (final row in database.select(
        '''SELECT long_term_relation_id FROM daily_choice_path_steps
           WHERE daily_choice_id = ?''',
        [choiceId],
      ))
        row['long_term_relation_id'] as String,
    ];
  } finally {
    database.close();
  }
}

final class _ChoiceSqlGate extends LocalDatabaseConnectionObserver {
  Completer<void>? _entered;
  Completer<void>? _released;
  bool _fail = false;
  LocalDatabaseSqlOperation _operation = LocalDatabaseSqlOperation.update;
  String _table = 'daily_choices';

  bool get hasEntered => _entered?.isCompleted ?? false;

  void arm({
    required bool fail,
    LocalDatabaseSqlOperation operation = LocalDatabaseSqlOperation.update,
    String table = 'daily_choices',
  }) {
    _entered = Completer<void>();
    _released = Completer<void>();
    _fail = fail;
    _operation = operation;
    _table = table;
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
        statement.operation != _operation ||
        !statement.statements.any((sql) => sql.contains(_table))) {
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
  for (final failWriting in [false, true]) {
    testWidgets(
      failWriting
          ? 'отказ замены после ухода сохраняет прежний путь и сообщает один раз'
          : 'замена после ухода сохраняет новый путь и сообщает один раз',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.binding.platformDispatcher.localesTestValue = const [
          Locale('ru'),
        ];
        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
        tester.view.physicalSize = const Size(1200, 4000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final harness = (await tester.runAsync(
          LocalDatabaseHarness.fileBacked,
        ))!;
        final seeded = await harness.openReadyDatabase();
        await seedDurabilityGraph(seeded);
        expect(
          await durabilityRepository(seeded).execute(durabilityCreate()),
          isA<GraphCommandSucceeded>(),
        );
        await harness.closePersistenceObjectGraph();
        final gate = _ChoiceSqlGate();
        // Каталог открывается на дне заменяемого дневного выбора.
        final localDate = ControlledDailyChoiceLocalDate(durabilityChoiceDate);
        final runtime = AppRuntime(
          connectionFactory: () => observeConfiguredLocalDatabaseConnection(
            openFileBackedLocalDatabase(harness.databaseFile),
            gate,
          ),
          diagnosticsSink: InMemoryDiagnosticsSink(),
          dailyChoiceLocalDateSource: localDate.read,
        );
        addTearDown(() async {
          gate.release();
          await tester.pumpWidget(const SizedBox.shrink());
          await runtime.shutdown();
          await harness.dispose();
        });
        await tester.pumpWidget(MainApp(runtime: runtime));
        await openDailyChoices(tester, tap: _tap);
        await _tap(tester, find.byKey(const ValueKey('daily-choice-row-1')));
        await _tap(
          tester,
          find.byKey(const ValueKey('daily-choice-replace-open')),
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('daily-choice-replace-top-down')),
        );
        await _tap(tester, find.text('Намерение 1'));
        await _tap(
          tester,
          find.byKey(ValueKey('choice-path-continue-${durabilityUuid(103)}')),
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('choice-path-select-action')),
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('choice-path-open-confirmation')),
        );
        final confirm = find.byKey(
          const ValueKey('daily-choice-replace-confirm'),
        );
        await _until(tester, () => confirm.evaluate().isNotEmpty);
        gate.arm(
          fail: failWriting,
          operation: LocalDatabaseSqlOperation.delete,
          table: 'daily_choice_path_steps',
        );
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.tap(confirm);
        await tester.pump();
        await _until(tester, () => gate.hasEntered);
        expect(_storedPathRelations(harness, durabilityUuid(201)), [
          durabilityUuid(101),
          durabilityUuid(102),
        ]);

        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 350));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        gate.release();
        final ready = await runtime.bootstrap() as AppRuntimeReady;
        final repository = ready.container.read(
          personalGraphRepositoryProvider,
        );
        final result = await repository.getDailyChoice(durabilityChoice(201));
        expect(result, isA<DailyChoiceReadSuccess>());
        expect(
          (result as DailyChoiceReadSuccess).value.value!.path.map(
            (step) => step.relation.id,
          ),
          failWriting
              ? [durabilityRelation(101), durabilityRelation(102)]
              : [durabilityRelation(103)],
        );
        expect(_storedIds(harness, 'daily_choices'), {durabilityUuid(201)});
        expect(
          find.byKey(const ValueKey('graph-operation-message')),
          findsNothing,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('graph-operation-message'))
              .evaluate()
              .isNotEmpty,
        );
        expect(
          find.textContaining(
            failWriting
                ? 'Не удалось выполнить действие с дневным выбором'
                : 'Путь дневного выбора заменён',
          ),
          findsWidgets,
        );
        await tester.pumpAndSettle();
        final message = find.byKey(const ValueKey('graph-operation-message'));
        ScaffoldMessenger.of(tester.element(message.first))
            .hideCurrentSnackBar();
        await tester.pumpAndSettle();
        expect(message, findsNothing);
        for (var attempt = 0; attempt < 4; attempt++) {
          if (find
              .byKey(const ValueKey('daily-choice-row-1'))
              .evaluate()
              .isNotEmpty) {
            break;
          }
          await tester.binding.handlePopRoute();
          await tester.pump(const Duration(milliseconds: 350));
        }
        await _tap(tester, find.byKey(const ValueKey('daily-choice-row-1')));
        expect(
          find.textContaining(failWriting ? 'Намерение 3' : 'Намерение 4'),
          findsWidgets,
        );
        await tester.pump(const Duration(seconds: 1));
        expect(message, findsNothing);
      },
    );
  }

  testWidgets(
    'повтор по подсказке завершается после ухода, смены фокуса и повторного открытия',
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
      expect(
        await durabilityRepository(seeded).execute(durabilityCreate()),
        isA<GraphCommandSucceeded>(),
      );
      await harness.closePersistenceObjectGraph();
      final gate = _ChoiceSqlGate();
      // Каталог открывается на дне прежнего дневного выбора, а новый выбор
      // создаётся на другой день.
      final localDate = ControlledDailyChoiceLocalDate(durabilityChoiceDate);
      final createdDate = CalendarDate.fromParts(2027, 1, 2);
      final runtime = AppRuntime(
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openFileBackedLocalDatabase(harness.databaseFile),
          gate,
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        dailyChoiceLocalDateSource: localDate.read,
      );
      addTearDown(() async {
        gate.release();
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
        await harness.dispose();
      });
      await tester.pumpWidget(MainApp(runtime: runtime));
      await openDailyChoices(tester, tap: _tap);
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-create-from-action')),
      );
      await _tap(tester, find.text('Намерение 3'));
      await _tap(
        tester,
        find.byKey(const ValueKey('choice-suggestion-select-0')),
      );
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('daily-choice-submit'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-date')),
        createdDate.toCanonicalString(),
      );
      gate.arm(
        fail: false,
        operation: LocalDatabaseSqlOperation.insert,
        table: 'daily_choice_path_steps',
      );
      final submit = find.byKey(const ValueKey('daily-choice-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.tap(submit);
      await tester.pump();
      await _until(tester, () => gate.hasEntered);
      expect(_storedIds(harness, 'daily_choices'), {durabilityUuid(201)});

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 350));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      gate.release();
      await _until(
        tester,
        () => _storedIds(harness, 'daily_choices').length == 2,
      );
      expect(_storedIds(harness, 'daily_choice_path_steps'), hasLength(4));
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
      expect(find.textContaining('Дневной выбор создан'), findsWidgets);
      await tester.pumpAndSettle();
      final message = find.byKey(const ValueKey('graph-operation-message'));
      ScaffoldMessenger.of(tester.element(message.first)).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(message, findsNothing);
      // Новый выбор относится к другому дню: человек выбирает этот день.
      await selectDailyChoiceCatalogDate(tester, createdDate, tap: _tap);
      await _tap(tester, find.byKey(const ValueKey('daily-choice-row-1')));
      expect(
        find.textContaining(createdDate.toCanonicalString()),
        findsWidgets,
      );
      expect(_storedIds(harness, 'daily_choices'), hasLength(2));
      await tester.pump(const Duration(seconds: 1));
      expect(message, findsNothing);
    },
  );

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
      final localDate = ControlledDailyChoiceLocalDate(durabilityChoiceDate);
      final runtime = AppRuntime(
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openFileBackedLocalDatabase(harness.databaseFile),
          gate,
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        dailyChoiceLocalDateSource: localDate.read,
      );
      addTearDown(() async {
        gate.release();
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
        await harness.dispose();
      });
      await tester.pumpWidget(MainApp(runtime: runtime));
      await openDailyChoices(tester, tap: _tap);
      await _tap(tester, find.byKey(const ValueKey('daily-choice-row-1')));
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      final repository = ready.container.read(personalGraphRepositoryProvider);

      gate.arm(fail: true);
      await _tap(tester, find.byKey(const ValueKey('daily-choice-edit-open')));
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('daily-choice-edit-date'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-edit-date')),
        '2027-01-02',
      );
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-edit-description')),
        'Запись до commit',
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-edit-completed')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-edit-submit')),
      );
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
      expect(find.textContaining('Дневной выбор изменён'), findsNothing);
      expect(
        find.byKey(const ValueKey('graph-operation-message')),
        findsWidgets,
      );
      await tester.pumpAndSettle();
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

      gate.arm(fail: false);
      await _tap(tester, find.byKey(const ValueKey('daily-choice-edit-open')));
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('daily-choice-edit-date'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-edit-date')),
        '2027-01-02',
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-edit-submit')),
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
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('graph-operation-message'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.textContaining('Дневной выбор изменён'), findsWidgets);
      expect(
        find.byKey(const ValueKey('graph-operation-message')),
        findsWidgets,
      );
      await tester.pumpAndSettle();
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

      for (var attempt = 0; attempt < 4; attempt++) {
        if (find
            .byKey(const ValueKey('catalog-create-intention'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 350));
      }
      await openIntentionGraph(
        tester,
        waitFor: (tester, finder) =>
            _until(tester, () => finder.evaluate().isNotEmpty),
        content: find.text('Намерение 1'),
      );
      await _tap(tester, find.text('Намерение 1').first);
      await _tap(
        tester,
        find.byKey(const ValueKey('intention-details-delete')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('intention-details-confirm-delete')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('intention-details-show-blocking-relations')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('relation-neighborhood-daily-source')),
      );
      await _tap(
        tester,
        find.byKey(
          ValueKey('relation-neighborhood-select-daily-${durabilityUuid(201)}'),
        ),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('relation-neighborhood-type-can')),
      );
      await _tap(
        tester,
        find.byKey(
          ValueKey('relation-neighborhood-select-${durabilityUuid(104)}'),
        ),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('blocking-relations-review')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('blocking-relations-confirm-delete')),
      );
      await _until(
        tester,
        () => _storedIds(harness, 'daily_choices').length == 1,
      );
      expect(
        (await repository.getDailyChoice(
          durabilityChoice(201),
        ) as DailyChoiceReadSuccess).value.value,
        isNull,
      );
      expect(
        (await repository.getDailyChoice(
          durabilityChoice(202),
        ) as DailyChoiceReadSuccess).value.value,
        isNotNull,
      );
      expect(_storedIds(harness, 'daily_choices'), {durabilityUuid(202)});
      expect(
        _storedIds(harness, 'long_term_relations'),
        contains(durabilityUuid(101)),
      );
      expect(
        _storedIds(harness, 'long_term_relations'),
        isNot(contains(durabilityUuid(104))),
      );
      expect(_storedIds(harness, 'intentions'), hasLength(5));
    },
  );

  testWidgets(
    'принятый нижний выбор завершается после ухода и предъявляется один раз',
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
      await harness.closePersistenceObjectGraph();
      final gate = _ChoiceSqlGate();
      // Каждый запуск открывает каталог на одном и том же дне.
      final localDate = ControlledDailyChoiceLocalDate(durabilityChoiceDate);
      AppRuntime start() => AppRuntime(
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openFileBackedLocalDatabase(harness.databaseFile),
          gate,
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        dailyChoiceLocalDateSource: localDate.read,
      );
      var runtime = start();
      addTearDown(() async {
        gate.release();
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
        await harness.dispose();
      });
      await tester.pumpWidget(MainApp(runtime: runtime));
      await openDailyChoices(tester, tap: _tap);
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-create-from-action')),
      );
      await _tap(tester, find.text('Намерение 3'));
      await _tap(
        tester,
        find.byKey(ValueKey('choice-path-continue-${durabilityUuid(102)}')),
      );
      await _tap(
        tester,
        find.byKey(ValueKey('choice-path-continue-${durabilityUuid(101)}')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('choice-path-select-source')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('choice-path-open-confirmation')),
      );
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('daily-choice-date'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-date')),
        '2027-01-02',
      );
      gate.arm(
        fail: false,
        operation: LocalDatabaseSqlOperation.insert,
        table: 'daily_choice_path_steps',
      );
      final submit = find.byKey(const ValueKey('daily-choice-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      await _until(tester, () => gate.hasEntered);
      expect(_storedIds(harness, 'daily_choices'), isEmpty);
      expect(_storedIds(harness, 'daily_choice_path_steps'), isEmpty);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 350));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      gate.release();
      await _until(
        tester,
        () => _storedIds(harness, 'daily_choices').length == 1,
      );
      expect(_storedIds(harness, 'daily_choice_path_steps'), hasLength(2));
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
      expect(find.textContaining('Дневной выбор создан'), findsWidgets);
      await tester.pumpAndSettle();
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

      final id = (DailyChoiceId.decode(
        _storedIds(harness, 'daily_choices').single,
      ) as DailyChoiceIdDecodingSuccess).id;
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
      runtime = start();
      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(
        tester,
        waitFor: (tester, finder) =>
            _until(tester, () => finder.evaluate().isNotEmpty),
      );
      final repository = (await runtime.bootstrap() as AppRuntimeReady)
          .container
          .read(personalGraphRepositoryProvider);
      final saved = await repository.getDailyChoice(id);
      expect(saved, isA<DailyChoiceReadSuccess>());
      expect(
        (saved as DailyChoiceReadSuccess).value.value!.path.map(
          (step) => step.relation.id,
        ),
        [durabilityRelation(101), durabilityRelation(102)],
      );
      expect(saved.value.value!.choice.date.toCanonicalString(), '2027-01-02');
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

      final localDate = ControlledDailyChoiceLocalDate(_firstToday);
      late _ObservedRepository graph;
      AppRuntime start() => AppRuntime(
        connectionFactory: () =>
            openFileBackedLocalDatabase(harness.databaseFile),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        dailyChoiceLocalDateSource: localDate.read,
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
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-completion-filter')),
      );
      await tester.tap(find.text(l10n.dailyChoiceCatalogIncomplete).last);
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
        'фильтр выполнения': false,
        'сегодня': _firstToday,
        'загруженные записи': [durabilityUuid(_futureChoice)],
        'позиция прокрутки': position.maxScrollExtent,
      });
      expect(position.pixels, greaterThan(0));
      expect(first.catalogQueries.map(_conditions), [
        (_firstToday, null, false),
        (_futureDate, null, false),
        (_futureDate, false, false),
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
      expect(first.catalogQueries, hasLength(3));
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
      expect(second, isNot(same(first)));
      expect(secondContainer, isNot(same(firstContainer)));
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
        (_nextToday, null, false),
      ]);
      expect(_catalogView(tester, secondContainer), {
        'выбранный день': _nextToday,
        'просмотр календаря': DailyChoiceCalendarViewport(
          focusedDate: _nextToday,
          mode: DailyChoiceCalendarMode.week,
        ),
        'фильтр выполнения': null,
        'сегодня': _nextToday,
        'загруженные записи': [durabilityUuid(_nextTodayChoice)],
        'позиция прокрутки': 0.0,
      });
      expect(opened.totalCount, 1);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('daily-choice-completion-filter')),
          matching: find.text(l10n.dailyChoiceCatalogAllStates),
        ),
        findsOneWidget,
      );
      expect(_rowLabel(tester, 1), contains(_nextToday.toCanonicalString()));
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
        expect(_rowLabel(tester, 1), contains(date.toCanonicalString()));
      }
      expect(second.catalogQueries.map(_conditions), [
        (_nextToday, null, false),
        (durabilityChoiceDate, null, false),
        (_futureDate, null, false),
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
      container.read(dailyChoiceCatalogViewModelProvider);
  DailyChoiceCatalogLoaded? result() => switch (current()) {
    final DailyChoiceCatalogLoaded loaded
        when loaded.selection.date == date &&
            loaded.selection.isCompleted == isCompleted &&
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
      '${shown.selection.date} с охватом ${shown.selection.isCompleted}.',
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
    'фильтр выполнения': tester
        .state<FormFieldState<bool?>>(
          find.byType(DropdownButtonFormField<bool?>, skipOffstage: false),
        )
        .value,
    'сегодня': tester.widget<DailyChoiceCalendar>(calendar).today,
    'загруженные записи': switch (container.read(
      dailyChoiceCatalogViewModelProvider,
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

/// Подпись строки [number] выдачи каталога дневных выборов для экранного
/// диктора.
String _rowLabel(WidgetTester tester, int number) => tester
    .widget<Semantics>(
      find.byKey(ValueKey('daily-choice-row-$number'), skipOffstage: false),
    )
    .properties
    .label!;

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
  Future<FavoriteIntentionsResult> getFavoriteIntentions() =>
      _delegate.getFavoriteIntentions();

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => _delegate.getCatalogPage(query);

  @override
  Future<Result<IntentionCatalogReconciliationOutcome>>
  getCatalogReconciliationPortion(IntentionCatalogReconciliationQuery query) =>
      _delegate.getCatalogReconciliationPortion(query);

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => _delegate.watchIntention(id);

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => _delegate.getRelationCounts(intentionId);

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => _delegate.getRelationGroupPage(query);

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      _delegate.watchRelation(id);

  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) => _delegate.getSelectedRelations(query);

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => _delegate.watchSelectedRelations(query);

  @override
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) => _delegate.getChoicePathSuggestions(query);

  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => _delegate.getChoicePathContinuations(query);

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
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId tagId,
    IntentionId intentionId,
  ) => _delegate.getTagAssignmentStatus(tagId, intentionId);

  @override
  Future<TaggedIntentionsPageResult> getTaggedIntentionsPage(
    TaggedIntentionsQuery query,
  ) => _delegate.getTaggedIntentionsPage(query);

  @override
  Stream<TagReadResult> watchTag(TagId id) => _delegate.watchTag(id);
}
