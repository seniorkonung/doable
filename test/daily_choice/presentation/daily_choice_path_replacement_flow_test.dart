import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_path_replace_page.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

DailyChoiceId _choice(int number) =>
    (DailyChoiceId.decode(_uuid(number)) as DailyChoiceIdDecodingSuccess).id;

Future<void> _seed(LocalDatabaseHarness harness) async {
  final database = await harness.openReadyDatabase();
  for (final (id, title, ready) in [
    (1, 'Старое основание', false),
    (2, 'Середина', false),
    (3, 'Старое действие', false),
    (4, 'Новое основание', false),
    (5, 'Новое действие', true),
    (6, 'Другое действие', true),
    (7, 'Другое основание', false),
  ]) {
    await database.customInsert(
      '''INSERT INTO intentions
         (id, title, is_action_ready, is_archived, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)''',
      variables: [
        Variable.withString(_uuid(id)),
        Variable.withString(title),
        Variable.withInt(ready ? 1 : 0),
        Variable.withInt(id == 1 ? 1 : 0),
        Variable.withInt(id),
        Variable.withInt(id),
      ],
    );
  }
  for (final (id, source, related, type, archived) in [
    (101, 1, 2, 'need', 1),
    (102, 2, 3, 'can', 0),
    (103, 4, 5, 'need', 0),
    (104, 4, 6, 'can', 0),
    (105, 7, 5, 'can', 0),
  ]) {
    await database.customInsert(
      '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id, type, priority,
          is_archived) VALUES (?, ?, ?, ?, 2, ?)''',
      variables: [
        Variable.withString(_uuid(id)),
        Variable.withString(_uuid(source)),
        Variable.withString(_uuid(related)),
        Variable.withString(type),
        Variable.withInt(archived),
      ],
    );
  }
  for (final (id, source, action, date, description) in [
    (201, 1, 3, '2024-09-24', 'Прежнее описание'),
    (202, 4, 5, '2026-09-24', 'Описание подсказки'),
  ]) {
    await database.customInsert(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date,
          description, is_completed) VALUES (?, ?, ?, ?, ?, 1)''',
      variables: [
        Variable.withString(_uuid(id)),
        Variable.withString(_uuid(source)),
        Variable.withString(_uuid(action)),
        Variable.withString(date),
        Variable.withString(description),
      ],
    );
  }
  for (final (id, owner, relation, previous) in [
    (301, 201, 101, null),
    (302, 201, 102, 301),
    (303, 202, 103, null),
  ]) {
    await database.customInsert(
      '''INSERT INTO daily_choice_path_steps
         (id, daily_choice_id, long_term_relation_id, previous_step_id)
         VALUES (?, ?, ?, ?)''',
      variables: [
        Variable.withString(_uuid(id)),
        Variable.withString(_uuid(owner)),
        Variable.withString(_uuid(relation)),
        previous == null
            ? const Variable<String>(null)
            : Variable.withString(_uuid(previous)),
      ],
    );
  }
  await harness.closePersistenceObjectGraph();
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Ожидаемый элемент не появился: $finder');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _waitFor(tester, finder);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<DailyChoiceDetails> _read(PersonalGraphRepository repository) async {
  final result = await repository.getDailyChoice(_choice(201));
  expect(result, isA<DailyChoiceReadSuccess>());
  return (result as DailyChoiceReadSuccess).value.value!;
}

int _choiceCount(LocalDatabaseHarness harness) {
  final database = sqlite.sqlite3.open(harness.databaseFile.path);
  try {
    return database
            .select('SELECT COUNT(*) AS amount FROM daily_choices')
            .single['amount']
        as int;
  } finally {
    database.close();
  }
}

int _creationSequence(LocalDatabaseHarness harness) {
  final database = sqlite.sqlite3.open(harness.databaseFile.path);
  try {
    return database.select(
          'SELECT creation_sequence FROM daily_choices WHERE id = ?',
          [_uuid(201)],
        ).single['creation_sequence']
        as int;
  } finally {
    database.close();
  }
}

List<String> _storedStepRelations(LocalDatabaseHarness harness) {
  final database = sqlite.sqlite3.open(harness.databaseFile.path);
  try {
    return database
        .select(
          'SELECT long_term_relation_id FROM daily_choice_path_steps WHERE daily_choice_id = ?',
          [_uuid(201)],
        )
        .map((row) => row['long_term_relation_id'] as String)
        .toList();
  } finally {
    database.close();
  }
}

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final bottomUp in [false, true]) {
    testWidgets(
      'конфликтная замена ${bottomUp ? 'снизу' : 'сверху'} актуализирует путь и сохраняет новые независимые поля',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.binding.platformDispatcher.localesTestValue = const [
          Locale('ru'),
        ];
        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
        final harness = (await tester.runAsync(
          LocalDatabaseHarness.fileBacked,
        ))!;
        await tester.runAsync(() => _seed(harness));
        final runtime = AppRuntime(
          connectionFactory: () =>
              openFileBackedLocalDatabase(harness.databaseFile),
          diagnosticsSink: InMemoryDiagnosticsSink(),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await runtime.shutdown();
          await harness.dispose();
        });
        await tester.pumpWidget(MainApp(runtime: runtime));
        final ready = await runtime.bootstrap() as AppRuntimeReady;
        final repository = ready.container.read(
          personalGraphRepositoryProvider,
        );
        final oldPath = (await _read(repository)).path
            .map((step) => step.relation.id)
            .toList();

        await _tap(
          tester,
          find.byKey(const ValueKey('catalog-open-daily-choices')),
        );
        await _tap(tester, find.byKey(const ValueKey('daily-choice-row-2')));
        await tester.pumpAndSettle();
        await _waitFor(tester, find.byType(DailyChoiceDetailsPage));
        await _tap(
          tester,
          find.byKey(const ValueKey('daily-choice-replace-open')),
        );
        await _tap(
          tester,
          find.byKey(
            ValueKey(
              bottomUp
                  ? 'daily-choice-replace-bottom-up'
                  : 'daily-choice-replace-top-down',
            ),
          ),
        );
        await _tap(
          tester,
          find.text(bottomUp ? 'Новое действие' : 'Новое основание'),
        );
        await _tap(
          tester,
          find.byKey(ValueKey('choice-path-continue-${_uuid(103)}')),
        );
        await _tap(
          tester,
          find.byKey(
            ValueKey(
              bottomUp
                  ? 'choice-path-select-source'
                  : 'choice-path-select-action',
            ),
          ),
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('choice-path-open-confirmation')),
        );
        await _waitFor(tester, find.byType(DailyChoicePathReplacePage));

        final database = sqlite.sqlite3.open(harness.databaseFile.path);
        database.execute(
          'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
          [_uuid(103)],
        );
        database.execute(
          'UPDATE daily_choices SET choice_date = ?, description = ?, is_completed = 0 WHERE id = ?',
          ['2026-09-25', 'Актуальное описание', _uuid(201)],
        );
        database.close();
        await _tap(
          tester,
          find.byKey(const ValueKey('daily-choice-replace-confirm')),
        );
        await _waitFor(
          tester,
          find.byKey(const ValueKey('daily-choice-replace-refresh-path')),
        );
        final afterConflict = await _read(repository);
        expect(afterConflict.path.map((step) => step.relation.id), oldPath);
        expect(afterConflict.choice.description?.value, 'Актуальное описание');

        await _tap(
          tester,
          find.byKey(const ValueKey('daily-choice-replace-refresh-path')),
        );
        await _waitFor(tester, find.byType(ChoicePathPage));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('daily-choice-replace-refresh-path')),
          findsOneWidget,
        );
        expect(
          (await _read(repository)).path.map((step) => step.relation.id),
          oldPath,
        );

        await _tap(
          tester,
          find.byKey(const ValueKey('daily-choice-replace-refresh-path')),
        );
        await _tap(
          tester,
          find.byKey(
            ValueKey('choice-path-continue-${_uuid(bottomUp ? 105 : 104)}'),
          ),
        );
        await _tap(
          tester,
          find.byKey(
            ValueKey(
              bottomUp
                  ? 'choice-path-select-source'
                  : 'choice-path-select-action',
            ),
          ),
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('choice-path-open-confirmation')),
        );
        await tester.pumpAndSettle();
        await _waitFor(tester, find.text('Актуальное описание'));
        expect(find.textContaining('2026-09-25'), findsWidgets);
        expect(
          find.textContaining(
            bottomUp ? 'Другое основание' : 'Другое действие',
          ),
          findsWidgets,
        );
        expect(
          (await _read(repository)).path.map((step) => step.relation.id),
          oldPath,
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('daily-choice-replace-confirm')),
        );
        await _waitFor(
          tester,
          find.byKey(const ValueKey('daily-choice-replace-open')),
        );
        final after = await _read(repository);
        expect(after.choice.id, _choice(201));
        expect(after.choice.date, CalendarDate.fromParts(2026, 9, 25));
        expect(after.choice.description?.value, 'Актуальное описание');
        expect(after.choice.isCompleted, isFalse);
        expect(after.path.map((step) => step.relation.id.toCanonicalString()), [
          _uuid(bottomUp ? 105 : 104),
        ]);
        expect(_choiceCount(harness), 2);
        final suggestions = await repository.getChoicePathSuggestions(
          ChoicePathSuggestionsForSource(after.choice.sourceIntentionId),
        );
        expect(suggestions, isA<ChoicePathSuggestionsSuccess>());
        final updatedSuggestion = (suggestions as ChoicePathSuggestionsSuccess)
            .value
            .items
            .singleWhere((item) => item.originChoiceId == _choice(201));
        expect(
          updatedSuggestion.path.map(
            (step) => step.relation.id.toCanonicalString(),
          ),
          [_uuid(bottomUp ? 105 : 104)],
        );
      },
    );
  }

  for (final bottomUp in [false, true]) {
    for (final suggestion in [false, true]) {
      final locale = bottomUp == suggestion ? 'ru' : 'en';
      testWidgets(
        'замена ${bottomUp ? 'снизу' : 'сверху'} ${suggestion ? 'по подсказке' : 'по шагам'} сохраняет идентичность и поля ($locale)',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 2400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.binding.platformDispatcher.localesTestValue = [Locale(locale)];
          addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
          final harness = (await tester.runAsync(
            LocalDatabaseHarness.fileBacked,
          ))!;
          await tester.runAsync(() => _seed(harness));
          final runtime = AppRuntime(
            connectionFactory: () =>
                openFileBackedLocalDatabase(harness.databaseFile),
            diagnosticsSink: InMemoryDiagnosticsSink(),
          );
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await runtime.shutdown();
            await harness.dispose();
          });
          await tester.pumpWidget(MainApp(runtime: runtime));
          final ready = await runtime.bootstrap() as AppRuntimeReady;
          final repository = ready.container.read(
            personalGraphRepositoryProvider,
          );
          final before = await _read(repository);
          final originalSequence = _creationSequence(harness);
          expect(
            _storedStepRelations(harness),
            containsAll([_uuid(101), _uuid(102)]),
          );

          await _tap(
            tester,
            find.byKey(const ValueKey('catalog-open-daily-choices')),
          );
          await _tap(tester, find.byKey(const ValueKey('daily-choice-row-2')));
          await tester.pumpAndSettle();
          await _waitFor(tester, find.byType(DailyChoiceDetailsPage));
          await _tap(
            tester,
            find.byKey(const ValueKey('daily-choice-replace-open')),
          );
          await _tap(
            tester,
            find.byKey(
              ValueKey(
                bottomUp
                    ? 'daily-choice-replace-bottom-up'
                    : 'daily-choice-replace-top-down',
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              locale == 'ru'
                  ? (bottomUp ? 'Выбор действия' : 'Выбор основания')
                  : (bottomUp ? 'Select an action' : 'Select a reason'),
            ),
            findsOneWidget,
          );
          await _tap(
            tester,
            find.text(bottomUp ? 'Новое действие' : 'Новое основание'),
          );

          if (suggestion) {
            await _tap(
              tester,
              find.byKey(const ValueKey('choice-suggestion-select-0')),
            );
          } else {
            await _tap(
              tester,
              find.byKey(ValueKey('choice-path-continue-${_uuid(103)}')),
            );
            await _tap(
              tester,
              find.byKey(
                ValueKey(
                  bottomUp
                      ? 'choice-path-select-source'
                      : 'choice-path-select-action',
                ),
              ),
            );
            await _tap(
              tester,
              find.byKey(const ValueKey('choice-path-open-confirmation')),
            );
          }
          await _waitFor(tester, find.byType(DailyChoicePathReplacePage));
          await _waitFor(
            tester,
            find.byKey(const ValueKey('daily-choice-replace-confirm')),
          );
          expect(
            find.text(
              locale == 'ru'
                  ? 'Подтвердить замену пути'
                  : 'Confirm path replacement',
            ),
            findsWidgets,
          );
          expect(
            find.text(
              locale == 'ru'
                  ? 'Исходное намерение: Новое основание'
                  : 'Source intention: Новое основание',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              locale == 'ru'
                  ? 'Выбранное действие: Новое действие'
                  : 'Selected action: Новое действие',
            ),
            findsOneWidget,
          );
          final semantics = tester.ensureSemantics();
          await tester.pump();
          expect(
            find.bySemanticsLabel(
              RegExp(locale == 'ru' ? 'Шаг 1:' : 'Step 1:'),
            ),
            findsOneWidget,
          );
          semantics.dispose();
          expect(find.byType(DailyChoiceCreationPage), findsNothing);
          expect(_choiceCount(harness), 2);
          expect(
            (await _read(repository)).choice.selectedIntentionId,
            before.choice.selectedIntentionId,
          );
          await _tap(
            tester,
            find.byKey(const ValueKey('daily-choice-replace-confirm')),
          );
          await _waitFor(
            tester,
            find.byKey(const ValueKey('daily-choice-replace-open')),
          );
          await _waitFor(
            tester,
            find.textContaining(
              locale == 'ru'
                  ? 'Чтобы Новое основание, я сегодня Новое действие'
                  : 'To Новое основание, today I Новое действие',
            ),
          );
          expect(
            tester
                .widget<DailyChoiceDetailsPage>(
                  find.byType(DailyChoiceDetailsPage),
                )
                .choiceId,
            _choice(201),
          );
          final after = await _read(repository);
          expect(after.choice.id, before.choice.id);
          expect(_creationSequence(harness), originalSequence);
          expect(after.choice.date, CalendarDate.fromParts(2024, 9, 24));
          expect(after.choice.description?.value, 'Прежнее описание');
          expect(after.choice.isCompleted, isTrue);
          expect(after.choice.sourceIntentionId.toCanonicalString(), _uuid(4));
          expect(
            after.choice.selectedIntentionId.toCanonicalString(),
            _uuid(5),
          );
          expect(
            after.path.map((step) => step.relation.id.toCanonicalString()),
            [_uuid(103)],
          );
          expect(_choiceCount(harness), 2);
          expect(_storedStepRelations(harness), [_uuid(103)]);
        },
      );
    }
  }

  testWidgets('отмена, возврат и смена ветви не меняют прежний путь', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
    await tester.runAsync(() => _seed(harness));
    final runtime = AppRuntime(
      connectionFactory: () =>
          openFileBackedLocalDatabase(harness.databaseFile),
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
      await harness.dispose();
    });
    await tester.pumpWidget(MainApp(runtime: runtime));
    final ready = await runtime.bootstrap() as AppRuntimeReady;
    final repository = ready.container.read(personalGraphRepositoryProvider);
    final original = await _read(repository);

    await _tap(
      tester,
      find.byKey(const ValueKey('catalog-open-daily-choices')),
    );
    await _tap(tester, find.byKey(const ValueKey('daily-choice-row-2')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('daily-choice-replace-open')));
    await _tap(
      tester,
      find.byKey(const ValueKey('daily-choice-replace-top-down')),
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('daily-choice-source-cancel')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('daily-choice-replace-bottom-up')),
      findsOneWidget,
    );

    await _tap(
      tester,
      find.byKey(const ValueKey('daily-choice-replace-bottom-up')),
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('daily-choice-action-cancel')),
    );
    await tester.pumpAndSettle();
    await _tap(
      tester,
      find.byKey(const ValueKey('daily-choice-replace-bottom-up')),
    );
    await _tap(tester, find.text('Новое действие'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('daily-choice-replace-top-down')),
      findsOneWidget,
    );

    await _tap(
      tester,
      find.byKey(const ValueKey('daily-choice-replace-top-down')),
    );
    await _tap(tester, find.text('Новое основание'));
    await tester.pumpAndSettle();
    await _tap(
      tester,
      find.byKey(ValueKey('choice-path-continue-${_uuid(103)}')),
    );
    await _tap(tester, find.byKey(const ValueKey('choice-path-back-0')));
    await _tap(
      tester,
      find.byKey(ValueKey('choice-path-continue-${_uuid(104)}')),
    );
    await _tap(tester, find.byKey(const ValueKey('choice-path-select-action')));
    await _tap(
      tester,
      find.byKey(const ValueKey('choice-path-open-confirmation')),
    );
    await _waitFor(tester, find.byType(DailyChoicePathReplacePage));
    expect(find.textContaining('Другое действие'), findsWidgets);
    expect(_choiceCount(harness), 2);
    await _tap(
      tester,
      find.byKey(const ValueKey('daily-choice-replace-cancel')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('daily-choice-replace-top-down')),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final after = await _read(repository);
    expect(after.choice.sourceIntentionId, original.choice.sourceIntentionId);
    expect(
      after.choice.selectedIntentionId,
      original.choice.selectedIntentionId,
    );
    expect(
      after.path.map((step) => step.relation.id),
      original.path.map((step) => step.relation.id),
    );
    expect(_choiceCount(harness), 2);
  });
}
