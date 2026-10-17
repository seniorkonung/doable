import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/application/daily_choice_id_generator.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_instance.dart';
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
import '../../../support/graph_seed.dart';
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
    'реальный флажок, каталоги, отметки и подробности согласуют выполнение',
    () async {
      final sourceDay = CalendarDate.fromParts(2026, 9, 24);
      final targetDay = CalendarDate.fromParts(2026, 9, 25);
      final database = AppDatabase(openInMemoryLocalDatabase());
      await database.open();
      addTearDown(database.close);
      await _seedGraph(database);
      const description = 'Полное описание\nмногошагового выбора\nна вечер';
      for (final number in [
        for (var number = 202; number <= 251; number++) number,
        201,
      ]) {
        await _insertChoice(
          database,
          number,
          sourceDay,
          completed: number != 201,
          scheduledMinute: 1080,
          priority: 2,
          description: description,
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
      final instance = DailyChoiceCatalogInstance(initialDate: sourceDay);
      final catalogProvider = dailyChoiceCatalogViewModelProvider(instance);
      final subscription = container.listen(catalogProvider, (_, _) {});
      addTearDown(subscription.close);
      final marksProvider = dailyChoiceCalendarDayMarksViewModelProvider(
        instance,
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
          container.read(catalogProvider) as DailyChoiceCatalogLoaded;
      final model = container.read(catalogProvider.notifier);
      final otherProvider = dailyChoiceCatalogViewModelProvider(
        DailyChoiceCatalogInstance(initialDate: targetDay),
      );
      final otherSubscription = container.listen(otherProvider, (_, _) {});
      addTearDown(otherSubscription.close);
      final otherModel = container.read(otherProvider.notifier);
      otherModel.selectDate(sourceDay);
      otherModel.toggleSection(false);
      otherModel.toggleSection(true);
      DailyChoiceCatalogLoaded otherCatalog() =>
          container.read(otherProvider) as DailyChoiceCatalogLoaded;
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );

      model.selectDate(sourceDay);
      await _until(
        () =>
            container.read(catalogProvider) is DailyChoiceCatalogLoaded &&
            container.read(otherProvider) is DailyChoiceCatalogLoaded,
      );
      expect(catalog().selection.date, sourceDay);
      expect(catalog().totalCount, 51);
      expect(catalog().items, hasLength(51));
      expect(catalog().incomplete.items.single.id, _choice(201));
      expect(catalog().completed.totalCount, 50);
      await model.loadMore(isCompleted: false);
      expect(catalog().items.map((item) => item.id).toSet(), {
        _choice(201),
        for (var number = 202; number <= 251; number++) _choice(number),
      });
      expect(catalog().items.last.id, _choice(251));
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
        (completed ? model : otherModel).changeCompletion(
          _choice(201),
          completed,
        );
        await _until(
          () =>
              catalog().freshness == DailyChoiceCatalogFreshness.current &&
              otherCatalog().freshness == DailyChoiceCatalogFreshness.current &&
              catalog().incomplete.totalCount == (completed ? 0 : 1) &&
              otherCatalog().incomplete.totalCount == (completed ? 0 : 1) &&
              opened().details.choice.isCompleted == completed,
        );
        await expectMarks({
          sourceDay: completed
              ? DailyChoiceDayStatus.allCompleted
              : DailyChoiceDayStatus.hasIncomplete,
        });
        expect(catalog().selection.date, sourceDay);
        expect(catalog().selection.incompleteExpanded, isTrue);
        expect(catalog().selection.completedExpanded, isFalse);
        expect(otherCatalog().selection.date, sourceDay);
        expect(otherCatalog().selection.incompleteExpanded, isFalse);
        expect(otherCatalog().selection.completedExpanded, isTrue);
        expect(
          opened().details.choice.schedule,
          DailyChoiceTime(hour: 18, minute: 0),
        );
        expect(opened().details.choice.priority, DailyChoicePriority.p2);
        expect(opened().details.choice.description?.value, description);
        expect(opened().details.path.map((step) => step.relation.id), [
          _relation(101),
          _relation(102),
        ]);
        if (completed) {
          for (final loaded in [catalog(), otherCatalog()]) {
            expect(loaded.completed.totalCount, 51);
            expect(loaded.completed.items.map((item) => item.id), [
              for (var number = 202; number <= 251; number++) _choice(number),
            ]);
            expect(loaded.completed.nextCursor, isNotNull);
          }
          await model.loadMore(isCompleted: true);
          await otherModel.loadMore(isCompleted: true);
          for (final loaded in [catalog(), otherCatalog()]) {
            expect(loaded.completed.items.map((item) => item.id), [
              for (var number = 202; number <= 251; number++) _choice(number),
              _choice(201),
            ]);
            expect(loaded.completed.nextCursor, isNull);
            expect(loaded.completed.items.last.pathIntentionCount, 3);
          }
        } else {
          for (final loaded in [catalog(), otherCatalog()]) {
            expect(loaded.incomplete.items.single.id, _choice(201));
            expect(loaded.completed.items.map((item) => item.id), [
              for (var number = 202; number <= 251; number++) _choice(number),
            ]);
          }
        }
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
      expect(catalog().incomplete.nextCursor, isNull);
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
            container.read(catalogProvider) is DailyChoiceCatalogLoaded &&
            catalog().selection.date == targetDay,
      );
      expect(catalog().totalCount, 1);
      expect(catalog().incomplete.nextCursor, isNull);
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
      expect(
        catalog(),
        isA<DailyChoiceCatalogLoaded>().having(
          (state) => state.totalCount,
          'количество',
          0,
        ),
      );
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
      final catalogProvider = dailyChoiceCatalogViewModelProvider(
        DailyChoiceCatalogInstance(initialDate: day),
      );
      final subscription = container.listen(catalogProvider, (_, _) {});
      addTearDown(subscription.close);
      DailyChoiceCatalogLoaded catalog() =>
          container.read(catalogProvider) as DailyChoiceCatalogLoaded;
      bool shows(CalendarDate date, bool? isCompleted) =>
          switch (container.read(catalogProvider)) {
            final DailyChoiceCatalogLoaded loaded =>
              loaded.selection.date == date &&
                  loaded.freshness == DailyChoiceCatalogFreshness.current,
            _ => false,
          };
      var includeCompleted = false;
      List<DailyChoiceId> ids() => [
        for (final item
            in includeCompleted ? catalog().items : catalog().incomplete.items)
          item.id,
      ];
      final model = container.read(catalogProvider.notifier);
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
                container.read(catalogProvider) is DailyChoiceCatalogLoaded &&
                catalog().freshness == DailyChoiceCatalogFreshness.current &&
                catalog().revision.compareTo(completion.revision!) ==
                    GraphRevisionOrder.same,
          );

      // Первое открытие сразу читает выбранный день и загружает его целиком
      // двумя порциями.
      await _until(() => shows(day, null));
      expect(catalog().totalCount, 53);
      expect(ids(), [
        for (var number = 201; number <= 250; number++) _choice(number),
      ]);
      await model.loadMore(isCompleted: false);
      expect(ids(), [
        for (var number = 201; number <= 253; number++) _choice(number),
      ]);
      expect(catalog().incomplete.nextCursor, isNull);

      await _until(() => shows(day, false));
      await model.loadMore(isCompleted: false);
      expect(catalog().totalCount, 53);
      expect(catalog().items, hasLength(53));

      // Выполнение одного дубликата убирает его из охвата невыполненных, а
      // его полный дубликат остаётся прежним.
      model.changeCompletion(_choice(253), true);
      await _until(
        () =>
            catalog().freshness == DailyChoiceCatalogFreshness.current &&
            catalog().incomplete.totalCount == 52,
      );
      expect(catalog().incomplete.totalCount, 52);
      expect(ids(), [
        for (var number = 201; number <= 252; number++) _choice(number),
      ]);
      final twin = catalog().incomplete.items.last;
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
      expect(catalog().incomplete.totalCount, 51);
      expect(ids(), [
        for (var number = 201; number <= 251; number++) _choice(number),
      ]);

      // При равных времени и приоритете новая запись идёт после прежних.
      final createdToday = await confirm(
        coordinator.acceptDailyChoiceCreation(
          DailyChoiceCreationFormKey(),
          _create(day),
        ),
      );
      await reconciled(createdToday);
      expect(catalog().incomplete.totalCount, 52);
      expect(ids().last, _choice(401));
      expect(ids(), hasLength(52));

      // Запись другого дня не входит в выдачу.
      await confirm(
        coordinator.acceptDailyChoiceCreation(
          DailyChoiceCreationFormKey(),
          _create(pastDay),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(catalog().incomplete.totalCount, 52);
      expect(ids(), isNot(contains(_choice(402))));

      final deleted = await confirm(
        coordinator.acceptDailyChoiceDelete(DeleteDailyChoice(_choice(401))),
      );
      await reconciled(deleted);
      expect(catalog().incomplete.totalCount, 51);
      expect(ids(), isNot(contains(_choice(401))));

      // Раскрытие выполненных сохраняет обе прочитанные секции того же дня.
      includeCompleted = true;
      model.toggleSection(true);
      await _until(() => shows(day, null));
      expect(catalog().totalCount, 52);
      expect(ids().last, _choice(253));
      expect(catalog().completed.items.single.isCompleted, isTrue);

      // Перенесённая и созданная записи доступны выбором их дней.
      model.selectDate(futureDay);
      await _until(() => shows(futureDay, null));
      expect(ids(), [_choice(252), _choice(302)]);
      expect(catalog().totalCount, 2);
      expect(catalog().incomplete.items.single.isCompleted, isFalse);
      model.selectDate(pastDay);
      await _until(() => shows(pastDay, null));
      expect(ids(), [_choice(301), _choice(402)]);
    },
  );

  test('реальные правки пересобирают обе секции до прежнего объёма и сохраняются при отказе чтения', () async {
    final day = CalendarDate.fromParts(2026, 9, 24);
    final probe = _CatalogReadFailure();
    final database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        probe,
      ),
    );
    await database.open();
    addTearDown(database.close);
    await _seedGraph(database);
    await seedGraph(database, () async {
      await database.customStatement(
        "INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, 'can', 1, 0)",
        [_uuid(103), _uuid(1), _uuid(3)],
      );
    });
    for (var number = 201; number <= 251; number++) {
      await _insertChoice(database, number, day);
      await _insertChoice(database, number + 100, day, completed: true);
    }
    await seedGraph(database, () async {
      await database.customStatement(
        'UPDATE daily_choices SET scheduled_minute = 1080 WHERE is_completed = 1',
      );
    });
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 24),
      InMemoryDiagnosticsSink(),
    );
    final container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    addTearDown(container.dispose);
    final provider = dailyChoiceCatalogViewModelProvider(
      DailyChoiceCatalogInstance(initialDate: day),
    );
    final subscription = container.listen(provider, (_, value) {
      if (value is DailyChoiceCatalogLoaded) {
        expect(
          value.items.where((item) => item.id == _choice(201)).length,
          lessThanOrEqualTo(1),
        );
        expect(
          value.incomplete.items.every((item) => !item.isCompleted),
          isTrue,
        );
        expect(value.completed.items.every((item) => item.isCompleted), isTrue);
      }
    });
    addTearDown(subscription.close);
    DailyChoiceCatalogLoaded catalog() =>
        container.read(provider) as DailyChoiceCatalogLoaded;
    await _until(() => container.read(provider) is DailyChoiceCatalogLoaded);
    final model = container.read(provider.notifier);
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final details = DailyChoiceDetailsViewModel(repository, _choice(201));
    addTearDown(details.dispose);
    await _until(() => details.state is DailyChoiceDetailsLoaded);
    DailyChoiceDetailsLoaded opened() =>
        details.state as DailyChoiceDetailsLoaded;
    await model.loadMore(isCompleted: true);
    expect(
      (catalog().incomplete.items.length, catalog().completed.items.length),
      (50, 51),
    );

    probe.failNext = true;
    final update = coordinator.acceptDailyChoiceUpdate(
      UpdateDailyChoiceFields(
        choiceId: _choice(201),
        patch: DailyChoiceFieldsPatch(
          schedule: DailyChoiceFieldSet(DailyChoiceTime(hour: 18, minute: 0)),
          priority: const DailyChoiceFieldSet(DailyChoicePriority.p2),
        ),
      ),
    ) as DailyChoiceCommandAccepted;
    expect((await update.future).isFailure, isFalse);
    await _until(
      () =>
          catalog().freshness == DailyChoiceCatalogFreshness.stale &&
          opened().details.choice.priority == DailyChoicePriority.p2,
    );
    expect(
      catalog().incomplete.items.first.schedule,
      const DailyChoiceAllDay(),
    );
    expect(
      opened().details.choice.schedule,
      DailyChoiceTime(hour: 18, minute: 0),
    );

    final replace = coordinator.acceptDailyChoiceReplace(
      ReplaceDailyChoicePath(
        choiceId: _choice(201),
        sourceIntentionId: _intention(1),
        selectedIntentionId: _intention(3),
        path: ConfirmedChoicePath([
          ConfirmedChoicePathStep(
            relationId: _relation(103),
            sourceIntentionId: _intention(1),
            type: LongTermRelationType.can,
            relatedIntentionId: _intention(3),
          ),
        ]),
      ),
    ) as DailyChoiceCommandAccepted;
    expect((await replace.future).isFailure, isFalse);
    await _until(
      () =>
          catalog().freshness == DailyChoiceCatalogFreshness.current &&
          opened().details.path.length == 1,
    );
    expect(
      (catalog().incomplete.items.length, catalog().completed.items.length),
      (50, 51),
    );
    expect(
      catalog().incomplete.items.any((item) => item.id == _choice(201)),
      isFalse,
    );
    await model.loadMore(isCompleted: false);
    final moved = catalog().incomplete.items.last;
    expect(moved.id, _choice(201));
    expect(moved.schedule, DailyChoiceTime(hour: 18, minute: 0));
    expect(moved.priority, DailyChoicePriority.p2);
    expect(moved.pathIntentionCount, 2);

    model.changeCompletion(moved.id, true);
    await _until(
      () =>
          catalog().freshness == DailyChoiceCatalogFreshness.current &&
          catalog().completed.totalCount == 52 &&
          opened().details.choice.isCompleted,
    );
    expect(catalog().incomplete.totalCount, 50);
    expect(
      catalog().incomplete.items.any((item) => item.id == moved.id),
      isFalse,
    );
    expect(catalog().completed.items.first.id, moved.id);
    expect(catalog().completed.items.first.pathIntentionCount, 2);
    expect(catalog().completed.items, hasLength(52));
  });
}

/// Засевает основание 1, промежуточное намерение 2, готовое действие 3 и
/// связи пути 1 → 2 → 3.
Future<void> _seedGraph(AppDatabase database) => seedGraph(database, () async {
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
});

/// Дневной выбор [number] действия 3 от основания 1 через путь 1 → 2 → 3.
Future<void> _insertChoice(
  AppDatabase database,
  int number,
  CalendarDate date, {
  bool completed = false,
  int? scheduledMinute,
  int priority = 4,
  String? description,
}) => seedGraph(database, () async {
  await database.customStatement(
    '''INSERT INTO daily_choices
     (id, source_intention_id, selected_intention_id, choice_date,
      is_completed, scheduled_minute, priority, description)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
    [
      _uuid(number),
      _uuid(1),
      _uuid(3),
      date.toCanonicalString(),
      if (completed) 1 else 0,
      scheduledMinute,
      priority,
      description,
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
});

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

/// Отказ реального чтения после подтверждённой команды не откатывает запись.
final class _CatalogReadFailure extends LocalDatabaseConnectionObserver {
  bool failNext = false;
  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (failNext &&
        statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains(
          'FROM daily_choices WHERE choice_date',
        )) {
      failNext = false;
      throw StateError('Управляемый отказ чтения каталога');
    }
  }
}
