import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/application/daily_choice_id_generator.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_state.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_view_model.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/daily_choice_local_date.dart';
import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

DailyChoiceId _choice(int number) =>
    (DailyChoiceId.decode(_uuid(number)) as DailyChoiceIdDecodingSuccess).id;

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

void main() {
  test(
    'реальный каталог, отметки и подробности согласуют изменения графа',
    () async {
      final sourceDay = CalendarDate.fromParts(2026, 9, 24);
      final targetDay = CalendarDate.fromParts(2026, 9, 25);
      final database = AppDatabase(openInMemoryLocalDatabase());
      await database.open();
      addTearDown(database.close);
      await _seedGraph(database);
      for (var number = 201; number <= 251; number++) {
        await _insertChoice(
          database,
          number,
          sourceDay,
          completed: number != 201,
        );
      }

      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 24),
        InMemoryDiagnosticsSink(),
        dailyChoiceIdGenerator: _SequentialChoiceIds(401),
      );
      // Локальное сегодня совпадает с днём записей, но каталог выбирает этот
      // день явно и не зависит от первоначального охвата.
      final container = ProviderContainer(
        overrides: [
          inMemoryQuickCreationModeOverride,
          personalGraphRepositoryProvider.overrideWith((ref) => repository),
          ControlledDailyChoiceLocalDate(sourceDay).override,
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        dailyChoiceCatalogViewModelProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final marksProvider = dailyChoiceCalendarDayMarksViewModelProvider(
        sourceDay,
      );
      final marksSubscription = container.listen(marksProvider, (_, _) {});
      addTearDown(marksSubscription.close);
      Future<void> expectMarks(
        Map<CalendarDate, DailyChoiceDayStatus> expected,
      ) async {
        await _until(() {
          final marks = container.read(marksProvider);
          return !marks.hasReadFailure &&
              marks.dayStatuses != null &&
              marks.dayStatuses!.statuses.length == expected.length &&
              expected.entries.every(
                (entry) =>
                    marks.dayStatuses!.statuses[entry.key] == entry.value,
              );
        });
      }

      DailyChoiceCatalogLoaded catalog() =>
          container.read(dailyChoiceCatalogViewModelProvider)
              as DailyChoiceCatalogLoaded;
      final model = container.read(
        dailyChoiceCatalogViewModelProvider.notifier,
      );
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );

      model.selectDate(sourceDay);
      await _until(
        () =>
            container.read(dailyChoiceCatalogViewModelProvider)
                is DailyChoiceCatalogLoaded,
      );
      expect(catalog().selection.date, sourceDay);
      expect(catalog().totalCount, 51);
      expect(catalog().items, hasLength(50));
      expect(catalog().items.first.id, _choice(251));
      expect(catalog().nextCursor, isNotNull);
      await model.loadMore();
      expect(catalog().items.map((item) => item.id).toSet(), {
        _choice(201),
        for (var number = 202; number <= 251; number++) _choice(number),
      });
      expect(catalog().items.last.id, _choice(201));
      await expectMarks({sourceDay: DailyChoiceDayStatus.hasIncomplete});

      final details = DailyChoiceDetailsViewModel(repository, _choice(201));
      addTearDown(details.dispose);
      await _until(() => details.state is DailyChoiceDetailsLoaded);
      DailyChoiceDetailsLoaded opened() =>
          details.state as DailyChoiceDetailsLoaded;
      expect(opened().details.choice.id, _choice(201));
      expect(
        opened().details.path.map(
          (step) => step.relation.id.toCanonicalString(),
        ),
        [_uuid(101), _uuid(102)],
      );
      expect(
        opened().details.path.last.related.id,
        opened().details.selected.id,
      );

      // Единственный невыполненный выбор определяет отметку всего дня.
      for (final completed in [true, false]) {
        final command = coordinator.acceptDailyChoiceUpdate(
          UpdateDailyChoiceFields(
            choiceId: _choice(201),
            patch: DailyChoiceFieldsPatch(
              isCompleted: DailyChoiceFieldSet(completed),
            ),
          ),
        ) as DailyChoiceCommandAccepted;
        await command.future;
        await expectMarks({
          sourceDay: completed
              ? DailyChoiceDayStatus.allCompleted
              : DailyChoiceDayStatus.hasIncomplete,
        });
      }

      final update = coordinator.acceptDailyChoiceUpdate(
        UpdateDailyChoiceFields(
          choiceId: _choice(201),
          patch: DailyChoiceFieldsPatch(
            date: DailyChoiceFieldSet(targetDay),
            isCompleted: const DailyChoiceFieldSet(true),
          ),
        ),
      ) as DailyChoiceCommandAccepted;
      final moved = await update.future;
      expect(moved, isA<DailyChoiceCommandCompletion>());
      await _until(
        () =>
            catalog().freshness == DailyChoiceCatalogFreshness.current &&
            catalog().revision.compareTo(moved.revision!) ==
                GraphRevisionOrder.same &&
            opened().details.choice.isCompleted,
      );
      // Перенесённая запись исчезает из исходного дня вместе с количеством.
      expect(catalog().selection.date, sourceDay);
      expect(catalog().totalCount, 50);
      expect(catalog().items, hasLength(50));
      expect(catalog().nextCursor, isNull);
      expect(catalog().items.any((item) => item.id == _choice(201)), isFalse);
      expect(catalog().items.every((item) => item.date == sourceDay), isTrue);
      expect(opened().details.choice.date, targetDay);
      await expectMarks({
        sourceDay: DailyChoiceDayStatus.allCompleted,
        targetDay: DailyChoiceDayStatus.allCompleted,
      });

      final rename = coordinator.acceptExisting(
        UpdateIntention(
          id: opened().details.source.id,
          title: 'Новое основание',
          description: null,
        ),
        presentationTitle: 'Намерение 1',
      ) as IntentionCommandAccepted;
      await rename.future;
      await _until(
        () =>
            catalog().freshness == DailyChoiceCatalogFreshness.current &&
            catalog().items.every(
              (item) => item.source.title == 'Новое основание',
            ) &&
            opened().details.source.title == 'Новое основание',
      );
      expect(catalog().totalCount, 50);
      expect(catalog().items, hasLength(50));

      // В новом дне перенесённая запись доступна с подтверждёнными полями.
      model.selectDate(targetDay);
      await _until(
        () =>
            container.read(dailyChoiceCatalogViewModelProvider)
                is DailyChoiceCatalogLoaded &&
            catalog().selection.date == targetDay,
      );
      expect(catalog().totalCount, 1);
      expect(catalog().nextCursor, isNull);
      expect(catalog().items.single.id, _choice(201));
      expect(catalog().items.single.date, targetDay);
      expect(catalog().items.single.isCompleted, isTrue);
      expect(catalog().items.single.source.title, 'Новое основание');
      expect(opened().details.choice.date, catalog().items.single.date);

      final deletion = coordinator.acceptDailyChoiceDelete(
        DeleteDailyChoice(_choice(201)),
      ) as DailyChoiceCommandAccepted;
      await deletion.future;
      await _until(
        () =>
            catalog().freshness == DailyChoiceCatalogFreshness.current &&
            catalog().totalCount == 0 &&
            details.state is DailyChoiceDetailsNotFound,
      );
      expect(catalog(), isA<DailyChoiceCatalogEmpty>());
      expect(catalog().selection.date, targetDay);
      await expectMarks({sourceDay: DailyChoiceDayStatus.allCompleted});

      final creation = coordinator.acceptDailyChoiceCreation(
        DailyChoiceCreationFormKey(),
        _create(targetDay),
      ) as DailyChoiceCommandAccepted;
      await creation.future;
      await expectMarks({
        sourceDay: DailyChoiceDayStatus.allCompleted,
        targetDay: DailyChoiceDayStatus.hasIncomplete,
      });
      final moveLast = coordinator.acceptDailyChoiceUpdate(
        UpdateDailyChoiceFields(
          choiceId: _choice(401),
          patch: DailyChoiceFieldsPatch(date: DailyChoiceFieldSet(sourceDay)),
        ),
      ) as DailyChoiceCommandAccepted;
      await moveLast.future;
      await expectMarks({sourceDay: DailyChoiceDayStatus.hasIncomplete});
    },
  );

  test(
    'каталог одного дня на настоящем хранилище согласует выполнение, перенос, '
    'создание и удаление, не меняя соседний дубликат',
    () async {
      final day = CalendarDate.fromParts(2026, 9, 24);
      final pastDay = CalendarDate.fromParts(2026, 9, 23);
      final futureDay = CalendarDate.fromParts(2026, 9, 25);
      final database = AppDatabase(openInMemoryLocalDatabase());
      await database.open();
      addTearDown(database.close);
      await _seedGraph(database);
      // Пятьдесят три полных дубликата выбранного дня и по записи в соседних.
      for (var number = 201; number <= 253; number++) {
        await _insertChoice(database, number, day);
      }
      await _insertChoice(database, 301, pastDay);
      await _insertChoice(database, 302, futureDay, completed: true);

      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 24),
        InMemoryDiagnosticsSink(),
        dailyChoiceIdGenerator: _SequentialChoiceIds(401),
      );
      final container = ProviderContainer(
        overrides: [
          inMemoryQuickCreationModeOverride,
          personalGraphRepositoryProvider.overrideWith((ref) => repository),
          ControlledDailyChoiceLocalDate(day).override,
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        dailyChoiceCatalogViewModelProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      DailyChoiceCatalogLoaded catalog() =>
          container.read(dailyChoiceCatalogViewModelProvider)
              as DailyChoiceCatalogLoaded;
      bool shows(CalendarDate date, bool? isCompleted) =>
          switch (container.read(dailyChoiceCatalogViewModelProvider)) {
            final DailyChoiceCatalogLoaded loaded =>
              loaded.selection.date == date &&
                  loaded.selection.isCompleted == isCompleted &&
                  loaded.freshness == DailyChoiceCatalogFreshness.current,
            _ => false,
          };
      List<DailyChoiceId> ids() => [
        for (final item in catalog().items) item.id,
      ];
      final model = container.read(
        dailyChoiceCatalogViewModelProvider.notifier,
      );
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      Future<DailyChoiceCommandCompletion> confirm(
        DailyChoiceCommandStart start,
      ) async {
        final completion = await (start as DailyChoiceCommandAccepted).future;
        expect(completion.isFailure, isFalse);
        return completion;
      }

      Future<void> reconciled(DailyChoiceCommandCompletion completion) =>
          _until(
            () =>
                container.read(dailyChoiceCatalogViewModelProvider)
                    is DailyChoiceCatalogLoaded &&
                catalog().freshness == DailyChoiceCatalogFreshness.current &&
                catalog().revision.compareTo(completion.revision!) ==
                    GraphRevisionOrder.same,
          );

      // Первое открытие сразу читает выбранный день и загружает его целиком
      // двумя порциями.
      await _until(() => shows(day, null));
      expect(catalog().totalCount, 53);
      expect(ids(), [
        for (var number = 253; number > 203; number--) _choice(number),
      ]);
      await model.loadMore();
      expect(ids(), [
        for (var number = 253; number >= 201; number--) _choice(number),
      ]);
      expect(catalog().nextCursor, isNull);

      model.selectCompletion(false);
      await _until(() => shows(day, false));
      await model.loadMore();
      expect(catalog().totalCount, 53);
      expect(catalog().items, hasLength(53));

      // Выполнение одного дубликата убирает его из охвата невыполненных, а
      // его полный дубликат остаётся прежним.
      final completed = await confirm(
        coordinator.acceptDailyChoiceUpdate(
          UpdateDailyChoiceFields(
            choiceId: _choice(253),
            patch: const DailyChoiceFieldsPatch(
              isCompleted: DailyChoiceFieldSet(true),
            ),
          ),
        ),
      );
      await reconciled(completed);
      expect(catalog().totalCount, 52);
      expect(ids(), [
        for (var number = 252; number >= 201; number--) _choice(number),
      ]);
      final twin = catalog().items.first;
      expect(twin.id, _choice(252));
      expect(twin.date, day);
      expect(twin.isCompleted, isFalse);

      // Перенос другого дубликата на будущий день убирает только его.
      final moved = await confirm(
        coordinator.acceptDailyChoiceUpdate(
          UpdateDailyChoiceFields(
            choiceId: _choice(252),
            patch: DailyChoiceFieldsPatch(date: DailyChoiceFieldSet(futureDay)),
          ),
        ),
      );
      await reconciled(moved);
      expect(catalog().totalCount, 51);
      expect(ids(), [
        for (var number = 251; number >= 201; number--) _choice(number),
      ]);

      // Новая запись выбранного дня становится первой.
      final createdToday = await confirm(
        coordinator.acceptDailyChoiceCreation(
          DailyChoiceCreationFormKey(),
          _create(day),
        ),
      );
      await reconciled(createdToday);
      expect(catalog().totalCount, 52);
      expect(ids().first, _choice(401));
      expect(ids(), hasLength(52));

      // Запись другого дня не входит в выдачу.
      await confirm(
        coordinator.acceptDailyChoiceCreation(
          DailyChoiceCreationFormKey(),
          _create(pastDay),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(catalog().totalCount, 52);
      expect(ids(), isNot(contains(_choice(402))));

      final deleted = await confirm(
        coordinator.acceptDailyChoiceDelete(DeleteDailyChoice(_choice(401))),
      );
      await reconciled(deleted);
      expect(catalog().totalCount, 51);
      expect(ids(), isNot(contains(_choice(401))));

      // Сброс возвращает выполненную запись того же дня.
      model.clearFilters();
      await _until(() => shows(day, null));
      expect(catalog().totalCount, 52);
      expect(ids().first, _choice(253));
      expect(catalog().items.first.isCompleted, isTrue);

      // Перенесённая и созданная записи доступны выбором их дней.
      model.selectDate(futureDay);
      await _until(() => shows(futureDay, null));
      expect(ids(), [_choice(302), _choice(252)]);
      expect(catalog().totalCount, 2);
      expect(catalog().items.last.isCompleted, isFalse);
      model.selectDate(pastDay);
      await _until(() => shows(pastDay, null));
      expect(ids(), [_choice(402), _choice(301)]);
    },
  );
}

/// Засевает основание 1, промежуточное намерение 2, готовое действие 3 и
/// связи пути 1 → 2 → 3.
Future<void> _seedGraph(AppDatabase database) async {
  for (final number in [1, 2, 3]) {
    await database.customStatement(
      '''INSERT INTO intentions
       (id, title, is_action_ready, is_archived, created_at, updated_at)
       VALUES (?, ?, ?, 0, 1, 1)''',
      [_uuid(number), 'Намерение $number', number == 3 ? 1 : 0],
    );
  }
  for (final (number, source, target) in [(101, 1, 2), (102, 2, 3)]) {
    await database.customStatement(
      '''INSERT INTO long_term_relations
       (id, source_intention_id, related_intention_id,
        type, priority, is_archived)
       VALUES (?, ?, ?, 'need', 2, 0)''',
      [_uuid(number), _uuid(source), _uuid(target)],
    );
  }
}

/// Дневной выбор [number] действия 3 от основания 1 через путь 1 → 2 → 3.
Future<void> _insertChoice(
  AppDatabase database,
  int number,
  CalendarDate date, {
  bool completed = false,
}) async {
  await database.customStatement(
    '''INSERT INTO daily_choices
     (id, source_intention_id, selected_intention_id, choice_date,
      is_completed) VALUES (?, ?, ?, ?, ?)''',
    [
      _uuid(number),
      _uuid(1),
      _uuid(3),
      date.toCanonicalString(),
      if (completed) 1 else 0,
    ],
  );
  await database.customStatement(
    '''INSERT INTO daily_choice_path_steps
     (id, daily_choice_id, long_term_relation_id, previous_step_id)
     VALUES (?, ?, ?, NULL)''',
    [_uuid(number + 1000), _uuid(number), _uuid(101)],
  );
  await database.customStatement(
    '''INSERT INTO daily_choice_path_steps
     (id, daily_choice_id, long_term_relation_id, previous_step_id)
     VALUES (?, ?, ?, ?)''',
    [_uuid(number + 2000), _uuid(number), _uuid(102), _uuid(number + 1000)],
  );
}

IntentionId _intention(int number) =>
    (IntentionId.decode(_uuid(number)) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  _uuid(number),
) as LongTermRelationIdDecodingSuccess).id;

/// Невыполненный выбор действия 3 на [date] тем же путём, что и засеянные.
CreateDailyChoice _create(CalendarDate date) => CreateDailyChoice(
  sourceIntentionId: _intention(1),
  selectedIntentionId: _intention(3),
  path: ConfirmedChoicePath([
    ConfirmedChoicePathStep(
      relationId: _relation(101),
      sourceIntentionId: _intention(1),
      type: LongTermRelationType.need,
      relatedIntentionId: _intention(2),
    ),
    ConfirmedChoicePathStep(
      relationId: _relation(102),
      sourceIntentionId: _intention(2),
      type: LongTermRelationType.need,
      relatedIntentionId: _intention(3),
    ),
  ]),
  date: date,
  description: null,
  isCompleted: false,
);

final class _SequentialChoiceIds implements DailyChoiceIdGenerator {
  _SequentialChoiceIds(this._next);

  int _next;

  @override
  DailyChoiceId generate() => _choice(_next++);
}
