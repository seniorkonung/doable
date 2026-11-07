import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/presentation/path/path_page.dart';
import 'package:doable/src/action/presentation/path_start/path_start_picker_page.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/action_path.dart' as ui;
import 'package:doable/src/design_system/components/reason_chain.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/action_day_controls.dart';
import '../support/action_panel_controls.dart';
import '../support/action_panel_edit_controls.dart';
import '../support/action_seed.dart';
import '../support/app_root_pages.dart';
import '../support/controlled_local_date.dart';
import '../support/graph_seed.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/local_database_harness.dart';
import '../support/path_screen_controls.dart';

final _today = CalendarDate.fromParts(2026, 10, 8);
final _message = find.byKey(const ValueKey('graph-operation-message'));

Future<void> _untilTrue(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Ожидаемое условие не наступило');
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _untilTrue(tester, () => finder.evaluate().isNotEmpty);

Future<void> _untilGone(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    if (finder.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Элемент не исчез: $finder');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

/// Задерживает первую запись действия до [release], а затем по выбору
/// отказывает ей временной недоступностью хранилища.
final class _ActionWriteGate extends LocalDatabaseConnectionObserver {
  Completer<void>? _entered;
  final _released = Completer<void>();
  var _fail = false;

  bool get hasEntered => _entered?.isCompleted ?? false;

  void arm({required bool fail}) {
    _entered = Completer<void>();
    _fail = fail;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  Future<void> afterStatement(LocalDatabaseSqlStatement statement) async {
    final entered = _entered;
    if (entered == null ||
        entered.isCompleted ||
        statement.operation != LocalDatabaseSqlOperation.update ||
        !statement.statements.any((sql) => sql.contains('actions'))) {
      return;
    }
    entered.complete();
    await _released.future;
    if (_fail) {
      throw sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
        message: 'Управляемый отказ записи',
      );
    }
  }
}

/// Запускает приложение над намерениями 1 → 2 → 3 со связями «нужно» и
/// действием сегодня на 18:00 с путём 1 → 2 и открывает его панель.
Future<(LocalDatabaseHarness, _ActionWriteGate)> _openPanel(
  WidgetTester tester,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
  late sqlite.Database raw;
  await harness.openReadyDatabase(setup: (database) => raw = database);
  seedRawGraph(raw, () {
    for (var number = 1; number <= 3; number++) {
      seedIntention(raw, seedUuid(number), 'Намерение $number');
    }
    seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
    seedRelation(raw, seedUuid(102), seedUuid(2), seedUuid(3));
    seedAction(
      raw,
      id: seedUuid(201),
      path: [seedUuid(1), seedUuid(2)],
      description: 'Выйти до заката',
      date: _today.toCanonicalString(),
      hour: 18,
      priority: 2,
      isCompleted: true,
    );
  });
  await harness.closePersistenceObjectGraph();
  final gate = _ActionWriteGate();
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => observeConfiguredLocalDatabaseConnection(
      openFileBackedLocalDatabase(harness.databaseFile),
      gate,
    ),
    diagnosticsSink: InMemoryDiagnosticsSink(),
    localDateSource: ControlledLocalDate(_today).read,
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
    find.byKey(const ValueKey('action-day-section-completed')),
  );
  await showActionDaySection(tester, ActionDaySection.completed);
  await _tap(tester, find.byKey(const ValueKey('action-day-row-1')));
  await _until(tester, actionPanelReady);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  return (harness, gate);
}

/// Открывает «Изменить путь» и добавляет в конец «Намерение 3».
Future<void> _extendPath(WidgetTester tester) async {
  await openActionPanelPathEdit(tester, tap: _tap);
  await _until(tester, find.text('Намерение 3'));
  await _tap(tester, find.text('Намерение 3'));
  await _until(tester, find.text('Пока ничего не нужно'));
}

/// Путь действия в хранилище.
List<String> _storedPath(LocalDatabaseHarness harness) {
  final database = sqlite.sqlite3.open(harness.databaseFile.path);
  try {
    return [
      for (final row in database.select(
        'SELECT intention_id FROM action_path_items WHERE action_id = ? '
        'ORDER BY position',
        [seedUuid(201)],
      ))
        row['intention_id'] as String,
    ];
  } finally {
    database.close();
  }
}

int _shownChain(WidgetTester tester) =>
    (shownActionHead(tester).chain as ReasonChain).reasons;

void main() {
  testWidgets('«Изменить путь» сохраняет новый путь, и панель показывает его '
      'на вкладке «Путь» с прежними полями', (tester) async {
    final (harness, _) = await _openPanel(tester);

    await openActionPanelPathEdit(tester, tap: _tap);
    await _until(tester, pathScreen);
    expect(find.text('Изменить путь'), findsOneWidget);
    await _until(tester, find.text('Намерение 2'));
    expect(isPathSaveEnabled(tester), isFalse);

    await _tap(
      tester,
      find.descendant(of: pathScreen, matching: find.text('Намерение 1')),
    );
    await _until(tester, find.byType(PathStartPickerPage));
    expect(find.text('Изменение пути: с чего начинается путь'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _untilGone(tester, find.byType(PathStartPickerPage));

    await _tap(tester, find.text('Намерение 3'));
    await _until(tester, find.text('Пока ничего не нужно'));
    await _tap(tester, pathSave);
    await _untilGone(tester, find.byType(PathPage));
    await tester.pumpAndSettle(const Duration(milliseconds: 1));

    expect(find.byType(ui.ActionPath), findsOneWidget);
    expect(shownActionPanelPathNames(tester), [
      'Намерение 1',
      'Намерение 2',
      'Намерение 3',
    ]);
    expect(_storedPath(harness), [seedUuid(1), seedUuid(2), seedUuid(3)]);
    final head = shownActionHead(tester);
    expect(head.action, 'Пробежка');
    expect(head.done, isTrue);
    expect(_message, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('уход во время замены не спрашивает, а успех без сообщения '
      'показывает новый путь на прежней вкладке', (tester) async {
    final (harness, gate) = await _openPanel(tester);
    await _extendPath(tester);

    gate.arm(fail: false);
    await _tap(tester, pathSave);
    await _untilTrue(tester, () => gate.hasEntered);
    await tester.binding.handlePopRoute();
    await _untilGone(tester, find.byType(PathPage));
    expect(find.text('Отменить изменения?'), findsNothing);

    gate.release();
    await _until(
      tester,
      find.byWidgetPredicate(
        (widget) => widget is ReasonChain && widget.reasons == 3,
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
    expect(_shownChain(tester), 3);
    expect(find.byType(ui.ActionPath), findsNothing);
    expect(actionPanelField('Выйти до заката'), findsOneWidget);
    expect(_message, findsNothing);
    expect(_storedPath(harness), [seedUuid(1), seedUuid(2), seedUuid(3)]);
  });

  testWidgets('отказ замены после ухода показывается один раз на общей '
      'поверхности, а панель показывает прежний путь', (tester) async {
    final (harness, gate) = await _openPanel(tester);
    await _extendPath(tester);

    gate.arm(fail: true);
    await _tap(tester, pathSave);
    await _untilTrue(tester, () => gate.hasEntered);
    await tester.binding.handlePopRoute();
    await _untilGone(tester, find.byType(PathPage));
    expect(find.text('Отменить изменения?'), findsNothing);

    gate.release();
    await _until(tester, _message);
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
    // Одно сообщение рисует каждый Scaffold под общим ScaffoldMessenger.
    expect(
      find.descendant(
        of: _message,
        matching: find.textContaining(
          'Не удалось выполнить операцию с действием.',
        ),
      ),
      findsWidgets,
    );
    ScaffoldMessenger.of(tester.element(_message.first)).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(_message, findsNothing);
    expect(actionPanel, findsOneWidget);
    expect(find.byType(ui.ActionPath), findsNothing);
    expect(_shownChain(tester), 2);
    expect(_storedPath(harness), [seedUuid(1), seedUuid(2)]);
  });

  testWidgets('успех во время анимации ухода не закрывает панель действия', (
    tester,
  ) async {
    final (harness, gate) = await _openPanel(tester);
    await _extendPath(tester);

    gate.arm(fail: false);
    await _tap(tester, pathSave);
    await _untilTrue(tester, () => gate.hasEntered);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(PathPage, skipOffstage: false), findsOneWidget);

    gate.release();
    await _untilTrue(tester, () => _storedPath(harness).length == 3);
    expect(find.byType(PathPage, skipOffstage: false), findsOneWidget);
    await tester.pumpAndSettle();

    expect(actionPanel, findsOneWidget);
    expect(actionPanelField('Выйти до заката'), findsOneWidget);
    expect(_shownChain(tester), 3);
    expect(_storedPath(harness), [seedUuid(1), seedUuid(2), seedUuid(3)]);
    expect(_message, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
