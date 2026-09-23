import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

IntentionId _intention(int number) =>
    (IntentionId.decode(_uuid(number)) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  _uuid(number),
) as LongTermRelationIdDecodingSuccess).id;

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 500; attempt += 1) {
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

Future<void> _openPath(WidgetTester tester) async {
  await _waitFor(tester, find.text('Основание'));
  await _tap(tester, find.text('Основание').first);
  await _waitFor(
    tester,
    find.byKey(const ValueKey('intention-details-choose-path')),
  );
  await _tap(
    tester,
    find.byKey(const ValueKey('intention-details-choose-path')),
  );
}

Future<void> _continue(WidgetTester tester, int relation) async {
  await _tap(
    tester,
    find.byKey(ValueKey('choice-path-continue-${_uuid(relation)}')),
  );
}

Future<void> _openConfirmation(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('choice-path-select-action')));
  await _tap(
    tester,
    find.byKey(const ValueKey('choice-path-open-confirmation')),
  );
  await _waitFor(tester, find.byKey(const ValueKey('daily-choice-date')));
}

Future<void> _save(WidgetTester tester, {bool doubleTap = false}) async {
  await tester.enterText(
    find.byKey(const ValueKey('daily-choice-date')),
    '2026-09-24',
  );
  final submit = find.byKey(const ValueKey('daily-choice-submit'));
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  if (doubleTap) await tester.tap(submit);
  await tester.pump();
  await _waitFor(tester, find.textContaining('Дневной выбор создан'));
  await _waitFor(
    tester,
    find.byKey(const ValueKey('choice-path-select-action')),
  );
  await tester.pumpAndSettle();
  await _waitFor(
    tester,
    find.byKey(const ValueKey('choice-path-select-action')),
  );
}

Future<void> _seed(LocalDatabaseHarness harness) async {
  final database = await harness.openReadyDatabase();
  for (final (number, title, ready) in [
    (1, 'Основание', false),
    (2, 'Действие в середине', true),
    (3, 'Продолжение действия', true),
    (4, 'Другая ветвь', false),
    (5, 'Другое действие', true),
  ]) {
    await database.customInsert(
      '''INSERT INTO intentions
         (id, title, is_action_ready, is_archived, created_at, updated_at)
         VALUES (?, ?, ?, 0, ?, ?)''',
      variables: [
        Variable.withString(_uuid(number)),
        Variable.withString(title),
        Variable.withInt(ready ? 1 : 0),
        Variable.withInt(number),
        Variable.withInt(number),
      ],
    );
  }
  for (final (number, source, related, type) in [
    (101, 1, 2, 'need'),
    (102, 2, 3, 'can'),
    (103, 1, 4, 'can'),
    (104, 4, 5, 'need'),
  ]) {
    await database.customInsert(
      '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id, type, priority,
          is_archived) VALUES (?, ?, ?, ?, 2, 0)''',
      variables: [
        Variable.withString(_uuid(number)),
        Variable.withString(_uuid(source)),
        Variable.withString(_uuid(related)),
        Variable.withString(type),
      ],
    );
  }
  await harness.closePersistenceObjectGraph();
}

List<DailyChoiceId> _savedIds(LocalDatabaseHarness harness) {
  final raw = sqlite.sqlite3.open(harness.databaseFile.path);
  try {
    return [
      for (final row in raw.select(
        'SELECT id FROM daily_choices ORDER BY creation_sequence',
      ))
        (DailyChoiceId.decode(
          row['id'] as String,
        ) as DailyChoiceIdDecodingSuccess).id,
    ];
  } finally {
    raw.close();
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

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets(
    'от намерения сохраняет показанную ветвь, действие в середине и отдельный дубликат',
    (tester) async {
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

      await _openPath(tester);
      await _continue(tester, 101);
      await _waitFor(
        tester,
        find.byKey(const ValueKey('choice-path-select-action')),
      );
      expect(
        find.byKey(ValueKey('choice-path-continue-${_uuid(102)}')),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const ValueKey('choice-path-back-0')));
      await _continue(tester, 103);
      await _continue(tester, 104);
      await _openConfirmation(tester);
      await _save(tester, doubleTap: true);

      final firstId = _savedIds(harness).single;
      final first = await _read(repository, firstId);
      expect(first.choice.sourceIntentionId, _intention(1));
      expect(first.choice.selectedIntentionId, _intention(5));
      expect(first.choice.date, CalendarDate.fromParts(2026, 9, 24));
      expect(first.path.map((step) => step.relation.id), [
        _relation(103),
        _relation(104),
      ]);

      await _tap(tester, find.byKey(const ValueKey('choice-path-back-0')));
      await _continue(tester, 101);
      await _openConfirmation(tester);
      await _save(tester);
      final secondId = _savedIds(harness).last;
      final second = await _read(repository, secondId);
      expect(second.choice.selectedIntentionId, _intention(2));
      expect(second.path.map((step) => step.relation.id), [_relation(101)]);

      await _openConfirmation(tester);
      await _save(tester);
      final ids = _savedIds(harness);
      expect(ids, hasLength(3));
      expect(ids.toSet(), hasLength(3));
      final duplicate = await _read(repository, ids.last);
      expect(
        duplicate.choice.selectedIntentionId,
        second.choice.selectedIntentionId,
      );
      expect(duplicate.choice.date, second.choice.date);
      expect(duplicate.path.map((step) => step.relation.id), [_relation(101)]);
      expect((await _read(repository, firstId)).path, hasLength(2));
    },
  );

  testWidgets(
    'конфликт после выбора пути не создаёт запись и не показывает успех',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      final semantics = tester.ensureSemantics();

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

      await _openPath(tester);
      await _waitFor(tester, find.text('Choose a path to an action'));
      expect(find.text('Choose a path to an action'), findsOneWidget);
      await _continue(tester, 101);
      await _waitFor(tester, find.bySemanticsLabel(RegExp('Step 1:')));
      expect(find.bySemanticsLabel(RegExp('Step 1:')), findsOneWidget);
      await _openConfirmation(tester);
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-date')),
        '2026-02-30',
      );
      await _tap(tester, find.byKey(const ValueKey('daily-choice-submit')));
      expect(find.textContaining('Check the daily choice date.'), findsWidgets);
      expect(_savedIds(harness), isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-date')),
        '2026-09-24',
      );
      final archived = await repository.execute(
        ArchiveLongTermRelation(_relation(101)),
      );
      expect(archived, isA<GraphCommandSucceeded>());
      await _tap(tester, find.byKey(const ValueKey('daily-choice-submit')));
      await _waitFor(
        tester,
        find.byKey(const ValueKey('daily-choice-failure')),
      );
      expect(find.textContaining('Daily choice created'), findsNothing);
      expect(_savedIds(harness), isEmpty);
      await _tap(tester, find.byKey(const ValueKey('daily-choice-cancel')));
      await _waitFor(tester, find.text('Choose a path to an action'));
      expect(_savedIds(harness), isEmpty);
      semantics.dispose();
    },
  );
}
