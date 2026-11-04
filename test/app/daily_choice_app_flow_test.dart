import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_detail_fields.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_page.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_tabs.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/daily_choice_creation_controls.dart';
import '../support/daily_choice_detail_fields_controls.dart';
import '../support/daily_choice_details_controls.dart';

import '../support/app_root_pages.dart';
import '../support/daily_choice_durability_fixture.dart';
import '../support/daily_choice_local_date.dart';
import '../support/daily_choice_catalog_controls.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/intention_choices_tab.dart';
import '../support/quick_creation.dart';

/// Дата дневных выборов, которые сценарии создают через форму. Она же —
/// локальное сегодня каталога: каталог открывается на дне этих записей.
final _formChoiceDate = CalendarDate.fromParts(2026, 9, 24);

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

List<DailyChoiceId> _savedIds(LocalDatabaseHarness harness) {
  final database = sqlite.sqlite3.open(harness.databaseFile.path);
  try {
    return [
      for (final row in database.select(
        'SELECT id FROM daily_choices ORDER BY creation_sequence',
      ))
        (DailyChoiceId.decode(
          row['id'] as String,
        ) as DailyChoiceIdDecodingSuccess).id,
    ];
  } finally {
    database.close();
  }
}

Future<DailyChoiceDetails> _read(
  PersonalGraphRepository repository,
  DailyChoiceId id,
) async {
  final result = await repository.getDailyChoice(id);
  expect(result, isA<DailyChoiceReadSuccess>());
  return (result as DailyChoiceReadSuccess).value.value!;
}

Future<void> _createFromPath(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await _tap(tester, find.byKey(const ValueKey('choice-path-select-action')));
  await _tap(
    tester,
    find.byKey(const ValueKey('choice-path-open-confirmation')),
  );
  await awaitDailyChoiceConfirmation(tester, waitFor: _until);
  await setDailyChoiceCreationDate(tester, _formChoiceDate);
  await tester.enterText(
    find.byKey(const ValueKey('daily-choice-description')),
    'Выбранный путь',
  );
  await _tap(tester, find.byKey(const ValueKey('daily-choice-completed')));
  await _tap(tester, find.byKey(const ValueKey('daily-choice-submit')));
  await _untilGone(tester, find.byType(DailyChoiceCreationPage));
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

/// Переносит выбор на [date] в панели и ждёт подтверждённой записи.
Future<void> _changeDate(WidgetTester tester, CalendarDate date) async {
  await setDailyChoiceDate(tester, date, tap: _tap);
  await _until(
    tester,
    find.byWidgetPredicate(
      (widget) => widget is DailyChoiceDetailFields && widget.date == date,
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

/// Меняет описание под полосой и ждёт подтверждённой записи.
Future<void> _changeDescription(WidgetTester tester, String text) async {
  await changeDailyChoiceDescription(tester, text, tap: _tap);
  await _untilGone(tester, dailyChoiceDescriptionEdit);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

/// Дата, которую каталог показывает до создания, и дата создаваемого выбора.
/// Локальное сегодня — между ними, чтобы ни одна из них не совпадала с ним.
final _catalogDate = CalendarDate.fromParts(2026, 10, 7);
final _todayDate = CalendarDate.fromParts(2026, 10, 8);
final _newChoiceDate = CalendarDate.fromParts(2026, 10, 9);

/// Четыре входа создания дневного выбора; у каждого своя исходная страница.
enum _CreationEntry {
  quickFromIntention('«От намерения» кнопки быстрого создания'),
  quickFromAction('«От действия» кнопки быстрого создания'),
  tabAsSource('«Добавить» на вкладке «Выборы», намерение исходное'),
  tabAsSelected('«Добавить» на вкладке «Выборы», намерение выбранное');

  const _CreationEntry(this.description);

  final String description;

  ChoicePathDraftDirection get direction => switch (this) {
    quickFromIntention || tabAsSource => ChoicePathDraftDirection.topDown,
    quickFromAction || tabAsSelected => ChoicePathDraftDirection.bottomUp,
  };

  /// Намерение, от которого входит создание.
  int get startIntention => switch (direction) {
    ChoicePathDraftDirection.topDown => 1,
    ChoicePathDraftDirection.bottomUp => 4,
  };
}

Finder _completion(DailyChoiceId id) =>
    find.byKey(ValueKey('daily-choice-completion-${id.toCanonicalString()}'));

/// Открывает исходную страницу входа: каталог на [_catalogDate] или вкладку
/// «Выборы» страницы намерения нужной роли.
Future<void> _openOrigin(
  WidgetTester tester,
  _CreationEntry entry,
  DailyChoiceId previous,
) async {
  switch (entry) {
    case _CreationEntry.quickFromIntention || _CreationEntry.quickFromAction:
      await openDailyChoices(tester, tap: _tap);
      await selectDailyChoiceCatalogDate(tester, _catalogDate, tap: _tap);
      await _until(tester, _completion(previous));
    case _CreationEntry.tabAsSource || _CreationEntry.tabAsSelected:
      await openIntentionGraph(tester, waitFor: _until);
      final title = find.text('Намерение ${entry.startIntention}');
      await _until(tester, title);
      await _tap(tester, title.first);
      await openIntentionChoicesTab(tester, waitFor: _until, tap: _tap);
      if (entry == _CreationEntry.tabAsSelected) {
        await _tap(
          tester,
          find.byKey(const ValueKey('intention-choices-role-selected')),
        );
      }
      await _until(tester, intentionChoicesAdd);
  }
}

/// Открывает вкладку «Выборы» страницы намерения 1.
Future<void> _openIntentionChoices(WidgetTester tester) async {
  await openIntentionGraph(tester, waitFor: _until);
  final title = find.text('Намерение 1');
  await _until(tester, title);
  await _tap(tester, title.first);
  await openIntentionChoicesTab(tester, waitFor: _until, tap: _tap);
}

/// Нажимает вход создания и доводит поток до пошагового выбора.
Future<void> _beginCreation(WidgetTester tester, _CreationEntry entry) async {
  switch (entry) {
    case _CreationEntry.quickFromIntention:
      await openDailyChoiceQuickCreation(
        tester,
        entry.direction,
        openedPage: find.byKey(const ValueKey('daily-choice-source-filter')),
        wait: _until,
      );
      await _tap(
        tester,
        find.byKey(ValueKey('daily-choice-source-${durabilityUuid(1)}')),
      );
    case _CreationEntry.quickFromAction:
      await openDailyChoiceQuickCreation(
        tester,
        entry.direction,
        openedPage: find.byKey(const ValueKey('daily-choice-action-filter')),
        wait: _until,
      );
      await _tap(
        tester,
        find.byKey(ValueKey('daily-choice-action-${durabilityUuid(4)}')),
      );
    case _CreationEntry.tabAsSource || _CreationEntry.tabAsSelected:
      await _tap(tester, intentionChoicesAdd);
  }
  await _until(tester, find.byType(ChoicePathPage));
}

/// Строит путь по связи 103 между намерениями 1 и 4 и подтверждает выбор
/// на [_newChoiceDate].
Future<void> _confirmNewChoice(
  WidgetTester tester,
  _CreationEntry entry,
) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await _tap(
    tester,
    find.byKey(ValueKey('choice-path-continue-${durabilityUuid(103)}')),
  );
  await _tap(
    tester,
    find.byKey(
      ValueKey(switch (entry.direction) {
        ChoicePathDraftDirection.topDown => 'choice-path-select-action',
        ChoicePathDraftDirection.bottomUp => 'choice-path-select-source',
      }),
    ),
  );
  await _tap(
    tester,
    find.byKey(const ValueKey('choice-path-open-confirmation')),
  );
  await awaitDailyChoiceConfirmation(tester, waitFor: _until);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await setDailyChoiceCreationDate(tester, _newChoiceDate);
  await _tap(tester, find.byKey(const ValueKey('daily-choice-submit')));
  await _untilGone(tester, find.byType(DailyChoiceCreationPage));
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

/// Сохранённый выбор сценариев панели: сегодня, на 18:00, с приоритетом P2.
final _panelChoice = durabilityChoice(201);
const _panelDescription = 'Выйти до заката';
final _panelChoiceRow = find.byKey(
  ValueKey('intention-choices-row-${_panelChoice.toCanonicalString()}'),
);

/// Запускает приложение над графом с сохранённым [_panelChoice].
Future<void> _startWithPanelChoice(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
  final seeded = await harness.openReadyDatabase();
  await seedDurabilityGraph(seeded);
  expect(
    await durabilityRepository(seeded).execute(
      durabilityCreate(
        date: _todayDate,
        description: _panelDescription,
        completed: false,
        schedule: DailyChoiceTime(hour: 18, minute: 0),
        priority: DailyChoicePriority.p2,
      ),
    ),
    isA<GraphCommandSucceeded>(),
  );
  await harness.closePersistenceObjectGraph();
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => openFileBackedLocalDatabase(harness.databaseFile),
    diagnosticsSink: InMemoryDiagnosticsSink(),
    dailyChoiceLocalDateSource: ControlledDailyChoiceLocalDate(_todayDate).read,
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
  expect(dailyChoiceDetails, findsOneWidget);
  expect(appNavigationDestinations().hitTestable(), findsNothing);
  expect(page.hitTestable(), findsNothing);
}

void main() {
  testWidgets('нажатие на карточку открывает панель на «Обзоре», а закрытие '
      'возвращает каталог с прежним состоянием', (tester) async {
    await _startWithPanelChoice(tester);
    await openDailyChoices(tester, tap: _tap);
    final row = find.byKey(const ValueKey('daily-choice-row-1'));
    await _until(tester, row);
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
    await expandDailyChoiceCatalogCalendar(tester);
    final viewport = shownDailyChoiceCatalogViewport(tester);

    await _tap(tester, row);
    await _until(tester, dailyChoiceDetailsReady);
    await tester.pumpAndSettle(const Duration(milliseconds: 1));

    expect(shownDailyChoice(tester), _panelChoice);
    final head = shownDailyChoiceHead(tester);
    expect(head.goal, 'Намерение 1');
    expect(head.action, 'Намерение 3');
    expect(head.priority, DoablePriority.p2);
    for (final value in [_panelDescription, 'Сегодня', '18:00']) {
      expect(dailyChoiceDetailsField(value), findsOneWidget, reason: value);
    }
    expect(dailyChoiceDetailsRelation(1), findsNothing);
    _expectCoveredByPanel(row);

    await closeDailyChoiceDetails(tester);
    expect(row.hitTestable(), findsOneWidget);
    expect(appNavigationDestinations().hitTestable(), findsWidgets);
    expect(shownDailyChoiceCatalogDate(tester), _todayDate);
    expect(shownDailyChoiceCatalogViewport(tester), viewport);
    expect(tester.takeException(), isNull);
  });

  testWidgets('строка вкладки «Выборы» открывает ту же панель, а закрытие '
      'возвращает вкладку', (tester) async {
    await _startWithPanelChoice(tester);
    await _openIntentionChoices(tester);

    await _tap(tester, _panelChoiceRow);
    await _until(tester, dailyChoiceDetailsReady);
    await tester.pumpAndSettle(const Duration(milliseconds: 1));

    expect(shownDailyChoice(tester), _panelChoice);
    _expectCoveredByPanel(_panelChoiceRow);

    await closeDailyChoiceDetails(tester);
    expect(_panelChoiceRow.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('выбор, удалённый из второй панели, оставляет первую открытой: '
      'она показывает, что выбора нет, а закрывает её пользователь', (
    tester,
  ) async {
    await _startWithPanelChoice(tester);
    await openDailyChoices(tester, tap: _tap);
    final row = find.byKey(const ValueKey('daily-choice-row-1'));
    await _tap(tester, row);
    await _until(tester, dailyChoiceDetailsReady);
    await openDailyChoicePathIntention(tester, 1, tap: _tap);
    await openIntentionChoicesTab(tester, waitFor: _until, tap: _tap);
    await _tap(tester, _panelChoiceRow);
    await _until(tester, dailyChoiceDetailsReady);

    await startDailyChoiceDeletion(tester, tap: _tap);
    await _tap(tester, find.text('Удалить'));
    await _untilGone(tester, dailyChoiceDetails);
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle(const Duration(milliseconds: 1));

    expect(
      dailyChoiceDetailsField('Дневной выбор больше не существует.'),
      findsOneWidget,
    );
    expect(dailyChoiceDetailsReady, findsNothing);
    expect(dailyChoiceDetailsOptions, findsNothing);
    expect(dailyChoiceDetailsField('Путь'), findsNothing);

    await closeDailyChoiceDetails(tester);
    await _untilGone(tester, row);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'полный путь через экраны переживает перезапуск, правки и удаление дубликата',
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
      // Каждый запуск открывает каталог на дне создаваемых записей.
      final localDate = ControlledDailyChoiceLocalDate(_formChoiceDate);
      AppRuntime start() => AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: () =>
            openFileBackedLocalDatabase(harness.databaseFile),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        dailyChoiceLocalDateSource: localDate.read,
      );
      var runtime = start();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
        await harness.dispose();
      });

      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(tester, waitFor: _until);
      await _until(tester, find.text('Намерение 1'));
      await _tap(tester, find.text('Намерение 1').first);
      await startDailyChoiceFromIntentionChoices(
        tester,
        waitFor: _until,
        tap: _tap,
      );
      await _tap(
        tester,
        find.byKey(ValueKey('choice-path-continue-${durabilityUuid(101)}')),
      );
      await _tap(
        tester,
        find.byKey(ValueKey('choice-path-continue-${durabilityUuid(102)}')),
      );
      await _createFromPath(tester);
      final firstId = _savedIds(harness).single;
      // Создание возвращает на вкладку «Выборы» страницы намерения.
      await _tap(tester, intentionChoicesAdd);
      await _tap(
        tester,
        find.byKey(ValueKey('choice-path-continue-${durabilityUuid(101)}')),
      );
      await _tap(
        tester,
        find.byKey(ValueKey('choice-path-continue-${durabilityUuid(102)}')),
      );
      await _createFromPath(tester);
      final ids = _savedIds(harness);
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2));
      final editedId = ids.last;
      final createdRepository = (await runtime.bootstrap() as AppRuntimeReady)
          .container
          .read(personalGraphRepositoryProvider);
      final createdStepIds = (await _read(
        createdRepository,
        editedId,
      )).path.map((step) => step.step.id).toList();

      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
      runtime = start();
      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(tester, waitFor: _until);
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      final repository = ready.container.read(personalGraphRepositoryProvider);
      final persisted = await _read(repository, editedId);
      expect(persisted.choice.date, _formChoiceDate);
      expect(persisted.choice.description?.value, 'Выбранный путь');
      expect(persisted.choice.isCompleted, isTrue);
      expect(persisted.path.map((step) => step.relation.id), [
        durabilityRelation(101),
        durabilityRelation(102),
      ]);
      expect(persisted.path.map((step) => step.step.id), createdStepIds);
      final stepIds = persisted.path.map((step) => step.step.id).toList();
      expect((await _read(repository, firstId)).choice.id, firstId);

      await openDailyChoices(tester, tap: _tap);
      await showDailyChoiceCatalogSection(tester, true);
      await _tap(tester, find.byKey(const ValueKey('daily-choice-row-2')));
      await _until(tester, dailyChoiceDetailsReady);
      expect(
        find.descendant(
          of: dailyChoiceDetails,
          matching: find.text('Намерение 1'),
        ),
        findsOneWidget,
      );
      await _changeDate(tester, CalendarDate.fromParts(2027, 1, 2));
      await showDailyChoicePath(tester, tap: _tap);
      expect(dailyChoiceDetailsRelation(1), findsOneWidget);
      expect(dailyChoiceDetailsRelation(2), findsOneWidget);
      expect(
        (await _read(repository, editedId)).choice.date,
        CalendarDate.fromParts(2027, 1, 2),
      );
      expect(
        (await _read(repository, editedId)).choice.description?.value,
        'Выбранный путь',
      );

      expect(
        await repository.execute(
          UpdateIntention(
            id: durabilityIntention(2),
            title: 'Новое промежуточное',
            description: null,
          ),
        ),
        isA<ResultSuccess>(),
      );
      await _until(tester, find.textContaining('Новое промежуточное'));
      expect(
        await repository.execute(ArchiveIntention(durabilityIntention(2))),
        isA<ResultSuccess>(),
      );
      await _until(
        tester,
        find.text('В пути есть архивированные намерения или связи.'),
      );
      expect(
        tester.getSemantics(dailyChoiceDetailsIntention(2)).label,
        contains('Архивировано'),
      );
      expect(
        tester.getSemantics(dailyChoiceDetailsRelation(2)).label,
        contains('Архивировано'),
      );
      await _changeDescription(tester, 'После архивирования');
      expect(
        await repository.execute(
          DisableIntentionReadiness(durabilityIntention(3)),
        ),
        isA<ResultSuccess>(),
      );
      await closeDailyChoiceDetails(tester);
      await selectDailyChoiceCatalogDate(
        tester,
        CalendarDate.fromParts(2027, 1, 2),
        tap: _tap,
      );
      final completion = find.byKey(
        ValueKey('daily-choice-completion-${editedId.toCanonicalString()}'),
      );
      await _until(tester, completion);
      expect(dailyChoiceCompletionState(tester, completion).completed, isTrue);
      await _tap(tester, completion);
      await showDailyChoiceCatalogSection(tester, false);
      await _until(tester, completion);
      expect(dailyChoiceCompletionState(tester, completion).completed, isFalse);
      await _tap(tester, find.byKey(const ValueKey('daily-choice-row-1')));
      await _until(tester, dailyChoiceDetails);
      final changed = await _read(repository, editedId);
      expect(changed.choice.id, editedId);
      expect(changed.choice.date, CalendarDate.fromParts(2027, 1, 2));
      expect(changed.choice.description?.value, 'После архивирования');
      expect(changed.choice.isCompleted, isFalse);
      expect(changed.path.map((step) => step.step.id), stepIds);
      expect(changed.path.map((step) => step.relation.scope), [
        RelationScope.archived,
        RelationScope.archived,
      ]);
      expect(changed.selected.readiness, IntentionReadiness.notReady);

      await startDailyChoiceDeletion(tester, tap: _tap);
      await _tap(tester, find.text('Удалить'));
      await _untilGone(tester, dailyChoiceDetails);
      await _until(tester, dailyChoiceCatalogDateControl);
      await selectDailyChoiceCatalogDate(tester, _formChoiceDate, tap: _tap);
      await showDailyChoiceCatalogSection(tester, true);
      await _until(tester, find.byKey(const ValueKey('daily-choice-row-1')));
      expect(_savedIds(harness), [firstId]);

      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
      runtime = start();
      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(tester, waitFor: _until);
      final reopened = (await runtime.bootstrap() as AppRuntimeReady).container
          .read(personalGraphRepositoryProvider);
      expect(
        (await _read(reopened, firstId)).path.map((step) => step.relation.id),
        [durabilityRelation(101), durabilityRelation(102)],
      );
      expect(
        (await reopened.getDailyChoice(
          editedId,
        ) as DailyChoiceReadSuccess).value.value,
        isNull,
      );
    },
  );

  for (final entry in _CreationEntry.values) {
    testWidgets('создание со входа ${entry.description} возвращает на исходную '
        'страницу и называет «Дневной выбор создан»', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
      final seeded = await harness.openReadyDatabase();
      await seedDurabilityGraph(seeded);
      final previous = durabilityChoice(201);
      expect(
        await durabilityRepository(seeded).execute(
          durabilityCreate(
            date: _catalogDate,
            description: 'Выбор прежнего дня',
            completed: false,
          ),
        ),
        isA<GraphCommandSucceeded>(),
      );
      await harness.closePersistenceObjectGraph();
      final runtime = AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: () =>
            openFileBackedLocalDatabase(harness.databaseFile),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        dailyChoiceLocalDateSource: ControlledDailyChoiceLocalDate(_todayDate)
            .read,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
        await harness.dispose();
      });

      await tester.pumpWidget(MainApp(runtime: runtime));
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      final router = ready.container.read(appRouterProvider);
      await _openOrigin(tester, entry, previous);
      final history = [for (final route in router.stackData) route.matchId];

      await _beginCreation(tester, entry);
      await _confirmNewChoice(tester, entry);

      expect(
        [for (final route in router.stackData) route.matchId],
        history,
        reason: 'Пошагового выбора и подтверждения в истории не осталось',
      );
      expect(find.textContaining('Дневной выбор создан'), findsOneWidget);
      final ids = _savedIds(harness);
      expect(ids, hasLength(2));
      final created = ids.last;
      final stored = await _read(
        ready.container.read(personalGraphRepositoryProvider),
        created,
      );
      expect(stored.choice.date, _newChoiceDate);
      expect(stored.path.map((step) => step.relation.id), [
        durabilityRelation(103),
      ]);
      switch (entry) {
        case _CreationEntry.quickFromIntention ||
            _CreationEntry.quickFromAction:
          // Каталог сохранил прежний день, а выдача этого дня не изменилась.
          expect(shownDailyChoiceCatalogDate(tester), _catalogDate);
          expect(_completion(previous), findsOneWidget);
          expect(_completion(created), findsNothing);
        case _CreationEntry.tabAsSource || _CreationEntry.tabAsSelected:
          expect(
            tester
                .widget<Tabs<IntentionDetailsTab>>(
                  find.byType(Tabs<IntentionDetailsTab>),
                )
                .value,
            IntentionDetailsTab.choices,
          );
          expect(
            tester
                .widget<ChoiceChip>(
                  find.byKey(
                    ValueKey(
                      'intention-choices-role-'
                      '${entry == _CreationEntry.tabAsSource ? 'source' : 'selected'}',
                    ),
                  ),
                )
                .selected,
            isTrue,
          );
          await _until(
            tester,
            find.byKey(
              ValueKey('intention-choices-row-${created.toCanonicalString()}'),
            ),
          );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
