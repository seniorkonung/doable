import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/daily_choice_durability_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';

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

final class _ChoiceUpdateGate extends LocalDatabaseConnectionObserver {
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

      final gate = _ChoiceUpdateGate();
      final runtime = AppRuntime(
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openFileBackedLocalDatabase(harness.databaseFile),
          gate,
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
      );
      addTearDown(() async {
        gate.release();
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
        await harness.dispose();
      });
      await tester.pumpWidget(MainApp(runtime: runtime));
      await _tap(
        tester,
        find.byKey(const ValueKey('catalog-open-daily-choices')),
      );
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
            .isNotEmpty)
          break;
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 350));
      }
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
}
