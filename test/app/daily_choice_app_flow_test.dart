import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/daily_choice_durability_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';

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
  final date = find.byKey(const ValueKey('daily-choice-date'));
  await _until(tester, date);
  await tester.enterText(date, '2026-09-24');
  await tester.enterText(
    find.byKey(const ValueKey('daily-choice-description')),
    'Выбранный путь',
  );
  await _tap(tester, find.byKey(const ValueKey('daily-choice-completed')));
  await _tap(tester, find.byKey(const ValueKey('daily-choice-submit')));
  await _until(tester, find.byKey(const ValueKey('choice-path-select-action')));
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

Future<void> _edit(
  WidgetTester tester, {
  String? date,
  String? description,
  bool toggleCompletion = false,
}) async {
  await _tap(tester, find.byKey(const ValueKey('daily-choice-edit-open')));
  final submit = find.byKey(const ValueKey('daily-choice-edit-submit'));
  await _until(tester, submit);
  if (date != null) {
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-edit-date')),
      date,
    );
  }
  if (description != null) {
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-edit-description')),
      description,
    );
  }
  if (toggleCompletion) {
    await _tap(
      tester,
      find.byKey(const ValueKey('daily-choice-edit-completed')),
    );
  }
  await _tap(tester, submit);
  await _until(tester, find.byKey(const ValueKey('daily-choice-edit-open')));
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

void main() {
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
      AppRuntime start() => AppRuntime(
        connectionFactory: () =>
            openFileBackedLocalDatabase(harness.databaseFile),
        diagnosticsSink: InMemoryDiagnosticsSink(),
      );
      var runtime = start();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
        await harness.dispose();
      });

      await tester.pumpWidget(MainApp(runtime: runtime));
      await _until(tester, find.text('Намерение 1'));
      await _tap(tester, find.text('Намерение 1').first);
      await _tap(
        tester,
        find.byKey(const ValueKey('intention-details-choose-path')),
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
      await _until(
        tester,
        find.byKey(const ValueKey('catalog-open-daily-choices')),
      );
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      final repository = ready.container.read(personalGraphRepositoryProvider);
      final persisted = await _read(repository, editedId);
      expect(persisted.choice.date, CalendarDate.fromParts(2026, 9, 24));
      expect(persisted.choice.description?.value, 'Выбранный путь');
      expect(persisted.choice.isCompleted, isTrue);
      expect(persisted.path.map((step) => step.relation.id), [
        durabilityRelation(101),
        durabilityRelation(102),
      ]);
      expect(persisted.path.map((step) => step.step.id), createdStepIds);
      final stepIds = persisted.path.map((step) => step.step.id).toList();
      expect((await _read(repository, firstId)).choice.id, firstId);

      await _tap(
        tester,
        find.byKey(const ValueKey('catalog-open-daily-choices')),
      );
      await _tap(tester, find.byKey(const ValueKey('daily-choice-row-1')));
      await _until(
        tester,
        find.byKey(const ValueKey('daily-choice-edit-open')),
      );
      expect(find.textContaining('Чтобы Намерение 1'), findsWidgets);
      expect(
        find.byKey(const ValueKey('daily-choice-relation-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('daily-choice-relation-2')),
        findsOneWidget,
      );

      await _edit(tester, date: '2027-01-02');
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
      await _until(tester, find.text('Архивировано'));
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey('daily-choice-intention-2')),
            )
            .properties
            .label,
        contains('Архивировано'),
      );
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey('daily-choice-relation-2')),
            )
            .properties
            .label,
        contains('Архивировано'),
      );
      await _edit(tester, description: 'После архивирования');
      expect(
        await repository.execute(
          DisableIntentionReadiness(durabilityIntention(3)),
        ),
        isA<ResultSuccess>(),
      );
      await _until(tester, find.textContaining('Не готово к действию'));
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey('daily-choice-intention-3')),
            )
            .properties
            .label,
        contains('Не готово к действию'),
      );
      await _edit(tester, toggleCompletion: true);
      final changed = await _read(repository, editedId);
      expect(changed.choice.date, CalendarDate.fromParts(2027, 1, 2));
      expect(changed.choice.description?.value, 'После архивирования');
      expect(changed.choice.isCompleted, isFalse);
      expect(changed.path.map((step) => step.step.id), stepIds);
      expect(changed.path.map((step) => step.relation.scope), [
        RelationScope.archived,
        RelationScope.archived,
      ]);
      expect(changed.selected.readiness, IntentionReadiness.notReady);

      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-delete-open')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-delete-cancel')),
      );
      expect(_savedIds(harness), hasLength(2));
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-delete-open')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-delete-confirm')),
      );
      await _until(tester, find.byKey(const ValueKey('daily-choice-row-1')));
      expect(_savedIds(harness), [firstId]);

      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
      runtime = start();
      await tester.pumpWidget(MainApp(runtime: runtime));
      await _until(
        tester,
        find.byKey(const ValueKey('catalog-open-daily-choices')),
      );
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
}
