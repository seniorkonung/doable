import 'package:doable/main.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/action_path.dart' as ui;
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/action_day_controls.dart';
import '../support/action_panel_controls.dart';
import '../support/action_panel_edit_controls.dart';
import '../support/action_panel_fixture.dart';
import '../support/action_seed.dart';
import '../support/app_root_pages.dart';
import '../support/controlled_local_date.dart';
import '../support/graph_seed.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/local_database_harness.dart';

/// Дата действий, которые сценарий готовит в хранилище. Она же — локальное
/// сегодня: экран дня открывается на дне этих записей.
final _actionDate = CalendarDate.fromParts(2026, 9, 24);

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Ожидаемый элемент не появился: $finder');
}

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

/// Намерения 1 → 2 → 3 и связи «нужно» между соседними.
void _seedIntentions(sqlite.Database raw) {
  for (var number = 1; number <= 3; number++) {
    seedIntention(raw, seedUuid(number), 'Намерение $number');
  }
  seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
  seedRelation(raw, seedUuid(102), seedUuid(2), seedUuid(3));
}

/// Идентификаторы сохранённых действий в порядке создания.
List<ActionId> _savedIds(LocalDatabaseHarness harness) {
  final database = sqlite.sqlite3.open(harness.databaseFile.path);
  try {
    return [
      for (final row in database.select(
        'SELECT id FROM actions ORDER BY creation_sequence',
      ))
        (ActionId.decode(row['id'] as String) as ActionIdDecodingSuccess).id,
    ];
  } finally {
    database.close();
  }
}

/// Действие с сохранённым путём на текущих данных; `null` — действия нет.
Future<ActionDetails?> _readOrNull(
  PersonalGraphRepository repository,
  ActionId id,
) async {
  final result = await repository.watchAction(id).first;
  expect(result, isA<ActionReadSuccess>());
  return (result as ActionReadSuccess).value.value;
}

Future<ActionDetails> _read(
  PersonalGraphRepository repository,
  ActionId id,
) async => (await _readOrNull(repository, id))!;

/// Переносит действие на [date] в листе даты панели и ждёт подтверждённой
/// записи: пока снимок не пришёл, панель называет прежнюю дату «Сегодня».
Future<void> _changeDate(WidgetTester tester, CalendarDate date) async {
  await chooseActionPanelDate(tester, date, from: _actionDate, tap: _tap);
  await _untilGone(tester, actionPanelField('Сегодня'));
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

/// Меняет описание и ждёт подтверждённой записи.
Future<void> _changeDescription(WidgetTester tester, String text) async {
  await saveActionPanelDescription(tester, text, waitFor: _until, tap: _tap);
  await _untilGone(tester, actionPanelTextEdit(tester));
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

/// Локальное сегодня сценариев с сохранённым действием панели.
final _todayDate = CalendarDate.fromParts(2026, 10, 8);

/// Сохранённое действие сценария панели: сегодня, на 18:00, с приоритетом P2.
final _panelAction = actionIdOf(201);
const _panelDescription = 'Выйти до заката';

/// Запускает приложение над графом с сохранённым [_panelAction].
Future<void> _startWithPanelAction(WidgetTester tester) async {
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
    _seedIntentions(raw);
    seedAction(
      raw,
      id: seedUuid(201),
      path: [seedUuid(1), seedUuid(2), seedUuid(3)],
      description: _panelDescription,
      date: _todayDate.toCanonicalString(),
      hour: 18,
      priority: 2,
    );
  });
  await harness.closePersistenceObjectGraph();
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => openFileBackedLocalDatabase(harness.databaseFile),
    diagnosticsSink: InMemoryDiagnosticsSink(),
    localDateSource: ControlledLocalDate(_todayDate).read,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
    await harness.dispose();
  });
  await tester.pumpWidget(MainApp(runtime: runtime));
}

/// Пока панель открыта, панель навигации и [page] под ней не принимают нажатий.
void _expectCoveredByPanel(Finder page) {
  expect(actionPanel, findsOneWidget);
  expect(appNavigationDestinations().hitTestable(), findsNothing);
  expect(page.hitTestable(), findsNothing);
}

void main() {
  testWidgets('нажатие на строку открывает панель действия на «Обзоре», а '
      'закрытие возвращает экран дня с прежним состоянием', (tester) async {
    await _startWithPanelAction(tester);
    await openActions(tester, tap: _tap);
    final row = find.byKey(const ValueKey('action-day-row-1'));
    await _until(tester, row);
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
    await expandActionDayCalendar(tester);
    final viewport = shownActionDayViewport(tester);

    await _tap(tester, row);
    await _until(tester, actionPanelReady);
    await tester.pumpAndSettle(const Duration(milliseconds: 1));

    expect(shownActionId(tester), _panelAction);
    final head = shownActionHead(tester);
    expect(head.goal, 'Намерение 1');
    expect(head.action, 'Пробежка');
    expect(head.priority, DoablePriority.p2);
    for (final value in [_panelDescription, 'Сегодня', '18:00']) {
      expect(actionPanelField(value), findsOneWidget, reason: value);
    }
    expect(find.byType(ui.ActionPath), findsNothing);
    _expectCoveredByPanel(row);

    await closeActionPanel(tester);
    expect(row.hitTestable(), findsOneWidget);
    expect(appNavigationDestinations().hitTestable(), findsWidgets);
    expect(shownActionDayDate(tester), _todayDate);
    expect(shownActionDayViewport(tester), viewport);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'сохранённые действия переживают перезапуск, правки и удаление дубликата',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
      late sqlite.Database raw;
      await harness.openReadyDatabase(setup: (database) => raw = database);
      // Два выполненных действия с одним путём: создания через интерфейс
      // больше нет, поэтому готовим их в хранилище.
      seedRawGraph(raw, () {
        _seedIntentions(raw);
        for (final number in [201, 202]) {
          seedAction(
            raw,
            id: seedUuid(number),
            path: [seedUuid(1), seedUuid(2), seedUuid(3)],
            description: 'Выбранный путь',
            date: _actionDate.toCanonicalString(),
            isCompleted: true,
            timestamp: number,
          );
        }
      });
      await harness.closePersistenceObjectGraph();
      // Каждый запуск открывает экран дня на дне готовых записей.
      final localDate = ControlledLocalDate(_actionDate);
      AppRuntime start() => AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: () =>
            openFileBackedLocalDatabase(harness.databaseFile),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        localDateSource: localDate.read,
      );
      var runtime = start();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
        await harness.dispose();
      });

      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(tester, waitFor: _until);
      final ids = _savedIds(harness);
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2));
      final firstId = ids.first;
      final editedId = ids.last;
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      final repository = ready.container.read(personalGraphRepositoryProvider);
      final persisted = await _read(repository, editedId);
      expect(persisted.action.date, _actionDate);
      expect(persisted.action.description?.value, 'Выбранный путь');
      expect(persisted.action.isCompleted, isTrue);
      expect(persisted.action.path.intentions, [
        intentionIdOf(1),
        intentionIdOf(2),
        intentionIdOf(3),
      ]);
      expect(persisted.path.steps.map((step) => step.link), [
        isA<ExistingActionPathLink>().having(
          (link) => link.relation.id,
          'связь',
          relationIdOf(101),
        ),
        isA<ExistingActionPathLink>().having(
          (link) => link.relation.id,
          'связь',
          relationIdOf(102),
        ),
      ]);
      expect((await _read(repository, firstId)).action.id, firstId);

      await openActions(tester, tap: _tap);
      await showActionDaySection(tester, ActionDaySection.completed);
      await _tap(tester, find.byKey(const ValueKey('action-day-row-2')));
      await _until(tester, actionPanelReady);
      expect(shownActionId(tester), editedId);
      expect(
        find.descendant(of: actionPanel, matching: find.text('Намерение 1')),
        findsOneWidget,
      );
      final movedDate = CalendarDate.fromParts(2027, 1, 2);
      await _changeDate(tester, movedDate);
      await showActionPanelPath(tester, waitFor: _until, tap: _tap);
      expect(shownActionPanelPathNames(tester), [
        'Намерение 1',
        'Намерение 2',
        'Намерение 3',
      ]);
      expect((await _read(repository, editedId)).action.date, movedDate);
      expect(
        (await _read(repository, editedId)).action.description?.value,
        'Выбранный путь',
      );

      expect(
        await repository.execute(
          UpdateIntention(
            id: intentionIdOf(2),
            title: 'Новое промежуточное',
            description: null,
          ),
        ),
        isA<ResultSuccess>(),
      );
      await _until(tester, find.textContaining('Новое промежуточное'));
      expect(
        await repository.execute(ArchiveIntention(intentionIdOf(2))),
        isA<ResultSuccess>(),
      );
      await _until(
        tester,
        find.text('Архивные намерения и связи остаются в сохранённом пути.'),
      );
      expect(shownActionPanelPathNames(tester), [
        'Намерение 1',
        'Новое промежуточное',
        'Намерение 3',
      ]);
      final archivedPath = tester.widget<ui.ActionPath>(
        find.byType(ui.ActionPath),
      );
      expect(
        (archivedPath.root as ui.ActionPathExistingStep).archived,
        isFalse,
      );
      expect(
        [
          for (final link in archivedPath.links)
            (
              (link.relation as ui.ActionPathExistingRelation).archived,
              (link.step as ui.ActionPathExistingStep).archived,
            ),
        ],
        [(true, true), (true, false)],
      );
      await _changeDescription(tester, 'После архивирования');
      await closeActionPanel(tester);
      await selectActionDayDate(tester, movedDate, tap: _tap);
      final completion = find.byKey(
        ValueKey('action-day-completion-${editedId.toCanonicalString()}'),
      );
      await _until(tester, completion);
      expect(actionCompletionState(tester, completion).completed, isTrue);
      await _tap(tester, completion);
      await showActionDaySection(tester, ActionDaySection.incomplete);
      await _until(tester, completion);
      expect(actionCompletionState(tester, completion).completed, isFalse);
      await _tap(tester, find.byKey(const ValueKey('action-day-row-1')));
      await _until(tester, actionPanel);
      final changed = await _read(repository, editedId);
      expect(changed.action.id, editedId);
      expect(changed.action.date, movedDate);
      expect(changed.action.description?.value, 'После архивирования');
      expect(changed.action.isCompleted, isFalse);
      expect(changed.action.path.intentions, [
        intentionIdOf(1),
        intentionIdOf(2),
        intentionIdOf(3),
      ]);
      expect(
        changed.path.steps.map(
          (step) => (step.link as ExistingActionPathLink).relation.scope,
        ),
        everyElement(RelationScope.archived),
      );

      await startActionPanelDeletion(tester, tap: _tap);
      await _untilGone(tester, actionPanel);
      await _until(tester, actionDayDateControl);
      await selectActionDayDate(tester, _actionDate, tap: _tap);
      await showActionDaySection(tester, ActionDaySection.completed);
      await _until(tester, find.byKey(const ValueKey('action-day-row-1')));
      expect(_savedIds(harness), [firstId]);

      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
      runtime = start();
      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(tester, waitFor: _until);
      final reopened = (await runtime.bootstrap() as AppRuntimeReady).container
          .read(personalGraphRepositoryProvider);
      expect(
        (await _read(reopened, firstId)).path.steps.map(
          (step) => (step.link as ExistingActionPathLink).relation.id,
        ),
        [relationIdOf(101), relationIdOf(102)],
      );
      expect(await _readOrNull(reopened, editedId), isNull);
    },
  );
}
