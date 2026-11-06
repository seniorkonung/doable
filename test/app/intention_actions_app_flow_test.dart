import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/action_check.dart';
import 'package:doable/src/design_system/components/action_row.dart';
import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_tabs.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/action_panel_controls.dart';
import '../support/action_panel_edit_controls.dart';
import '../support/action_panel_fixture.dart';
import '../support/action_seed.dart';
import '../support/app_root_pages.dart';
import '../support/controlled_local_date.dart';
import '../support/graph_seed.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/intention_actions_tab.dart';
import '../support/intention_catalog_controls.dart';
import '../support/local_database_harness.dart';

final _today = CalendarDate.fromParts(2026, 10, 8);

/// Действие, путь которого проходит через намерение 2.
final _throughSecond = actionIdOf(201);

/// Действие из одного намерения 1.
final _onlyFirst = actionIdOf(202);

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Ожидаемый элемент не появился: $finder');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

/// Запускает приложение над графом «Намерение 1 → 2 → 3» с двумя действиями.
Future<void> _start(WidgetTester tester) async {
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
      title: 'Дойти до парка',
      path: [seedUuid(1), seedUuid(2), seedUuid(3)],
      date: _today.toCanonicalString(),
      hour: 18,
    );
    seedAction(
      raw,
      id: seedUuid(202),
      title: 'Выбрать цель',
      path: [seedUuid(1)],
      date: _today.toCanonicalString(),
    );
  });
  await harness.closePersistenceObjectGraph();
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => openFileBackedLocalDatabase(harness.databaseFile),
    diagnosticsSink: InMemoryDiagnosticsSink(),
    localDateSource: ControlledLocalDate(_today).read,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
    await harness.dispose();
  });
  await tester.pumpWidget(MainApp(runtime: runtime));
}

/// Открывает страницу намерения [title] из каталога намерений.
Future<void> _openIntention(WidgetTester tester, String title) async {
  await openIntentionGraph(
    tester,
    waitFor: _until,
    content: intentionCatalogRow(title),
  );
  await _tap(tester, intentionCatalogRow(title));
  await _until(tester, find.byType(IntentionDetailsPage));
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

Finder _row(ActionId id) =>
    find.byKey(ValueKey('intention-actions-row-${id.toCanonicalString()}'));

/// Строка целиком: ключ кнопки лежит на её области нажатия.
Finder _actionRow(ActionId id) =>
    find.ancestor(of: _row(id), matching: find.byType(ActionRow));

Finder _roleTile(String role) =>
    find.byKey(ValueKey('intention-actions-role-$role'));

String _tabLabel(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Tabs<IntentionDetailsTab>)))
        .detailsActionsTab;

void main() {
  testWidgets('число вкладки известно под «Обзором», а плитка с наибольшим '
      'числом открывается при первом показе', (tester) async {
    await _start(tester);
    await _openIntention(tester, 'Намерение 1');

    // Намерение 1 — корень обоих действий и конечное для одного из них.
    await _until(
      tester,
      find.descendant(
        of: find.byType(Tabs<IntentionDetailsTab>),
        matching: find.text('2'),
      ),
    );
    expect(_row(_onlyFirst), findsNothing);

    await openIntentionActionsTab(tester, waitFor: _until, tap: _tap);
    await _until(tester, _row(_onlyFirst));
    expect(_row(_throughSecond), findsOneWidget);
    expect(find.byType(ActionRow), findsNWidgets(2));
    // Под ролью «Корневое» корень пути — сама страница.
    expect(tester.widget<ActionRow>(_actionRow(_throughSecond)).goal, isNull);
    expect(find.text('Сегодня · 18:00'), findsOneWidget);
  });

  testWidgets('выполнение из панели, открытой над страницей, сразу видно в '
      'строке, а удаление убирает строку и сохраняет плитку', (tester) async {
    await _start(tester);
    await _openIntention(tester, 'Намерение 2');
    await openIntentionActionsTab(tester, waitFor: _until, tap: _tap);
    await _until(tester, _row(_throughSecond));
    // Под ролью «Промежуточное» над цепочкой стоит корень пути.
    expect(
      tester.widget<ActionRow>(_actionRow(_throughSecond)).goal,
      'Намерение 1',
    );
    expect(tester.widget<ActionRow>(_actionRow(_throughSecond)).done, isFalse);

    await _tap(tester, _row(_throughSecond));
    await _until(tester, actionPanelReady);
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
    await _tap(
      tester,
      find.descendant(of: actionPanelReady, matching: find.byType(ActionCheck)),
    );
    for (var attempt = 0; attempt < 500; attempt++) {
      if (tester.widget<ActionRow>(_actionRow(_throughSecond)).done) break;
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(tester.widget<ActionRow>(_actionRow(_throughSecond)).done, isTrue);

    await startActionPanelDeletion(tester, tap: _tap);
    for (var attempt = 0; attempt < 500; attempt++) {
      if (_row(_throughSecond).evaluate().isEmpty) break;
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 1));

    expect(_row(_throughSecond), findsNothing);
    expect(
      find.text(
        'Здесь появится действие, путь которого проходит через это намерение.',
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(_roleTile('intermediate')).getSemanticsData().label,
      startsWith('Промежуточное: 0'),
    );
    expect(find.text(_tabLabel(tester)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
