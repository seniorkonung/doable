import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/presentation/day/action_day_instance.dart';
import 'package:doable/src/action/presentation/day/action_day_marks_view_model.dart';
import 'package:doable/src/action/presentation/day/action_day_state.dart';
import 'package:doable/src/action/presentation/day/action_day_view_model.dart';
import 'package:doable/src/data/local/app_database.dart' hide Action;
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/date_grid.dart';
import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/design_system/components/detail_row.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/action_day_controls.dart';
import '../../../support/action_panel_controls.dart';
import '../../../support/action_panel_fixture.dart';
import '../../../support/action_seed.dart';
import '../../../support/graph_seed.dart';
import '../../../support/in_memory_diagnostics_sink.dart';
import 'action_day_page_test_support.dart';

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

void main() {
  test('реальный флажок, экраны дня, отметки и панель согласуют выполнение, '
      'перенос, переименование корня и удаление', () async {
    final sourceDay = CalendarDate.fromParts(2026, 9, 24);
    final targetDay = CalendarDate.fromParts(2026, 9, 25);
    final storage = await _openStorage();
    const description = 'Полное описание\nмногошагового действия\nна вечер';
    seedRawGraph(storage.raw, () {
      _seedPath(storage.raw);
      // Действие 201 заведено последним, поэтому в выполненных идёт после
      // остальных.
      for (final number in [
        for (var number = 202; number <= 251; number++) number,
        201,
      ]) {
        seedAction(
          storage.raw,
          id: seedUuid(number),
          path: _path,
          description: description,
          date: sourceDay.toCanonicalString(),
          hour: 18,
          priority: 2,
          isCompleted: number != 201,
        );
      }
    });

    final container = _container(storage.repository);
    final instance = ActionDayInstance(initialDate: sourceDay);
    final dayProvider = actionDayViewModelProvider(instance);
    container.listen(dayProvider, (_, _) {});
    final marksProvider = actionDayMarksViewModelProvider(instance);
    container.listen(marksProvider, (_, _) {});
    Future<void> expectMarks(Map<CalendarDate, ActionDayStatus> expected) =>
        _until(() {
          final marks = container.read(marksProvider);
          return !marks.hasReadFailure &&
              marks.dayStatuses != null &&
              marks.dayStatuses!.statuses.length == expected.length &&
              expected.entries.every(
                (entry) =>
                    marks.dayStatuses!.statuses[entry.key] == entry.value,
              );
        });

    ActionDayLoaded day() => container.read(dayProvider) as ActionDayLoaded;
    final model = container.read(dayProvider.notifier);
    // Второй экземпляр экрана дня читает тот же день и сворачивает свою
    // секцию невыполненных независимо от первого.
    final otherProvider = actionDayViewModelProvider(
      ActionDayInstance(initialDate: targetDay),
    );
    container.listen(otherProvider, (_, _) {});
    final otherModel = container.read(otherProvider.notifier);
    otherModel.selectDate(sourceDay);
    ActionDayLoaded otherDay() =>
        container.read(otherProvider) as ActionDayLoaded;
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );

    await _until(
      () =>
          container.read(dayProvider) is ActionDayLoaded &&
          container.read(otherProvider) is ActionDayLoaded,
    );
    otherModel.toggleSection(ActionDaySection.incomplete);
    expect(day().selection.date, sourceDay);
    expect(day().totalCount, 51);
    expect(day().items, hasLength(51));
    expect(day().incomplete.items.single.id, actionIdOf(201));
    expect(day().completed.totalCount, 50);
    expect(day().items.map((item) => item.id).toSet(), {
      actionIdOf(201),
      for (var number = 202; number <= 251; number++) actionIdOf(number),
    });
    expect(day().items.last.id, actionIdOf(251));
    await expectMarks({sourceDay: ActionDayStatus.hasIncomplete});

    final watched = _WatchedAction(storage.repository, actionIdOf(201));
    await _until(() => watched.details != null);
    ActionDetails opened() => watched.details!;
    expect(opened().action.id, actionIdOf(201));
    expect(_relationIds(opened()), [relationIdOf(101), relationIdOf(102)]);
    expect(
      opened().path.steps.last.intention.id,
      opened().action.path.intentions.last,
    );

    // Единственное невыполненное действие определяет отметку всего дня.
    for (final completed in [true, false]) {
      (completed ? model : otherModel).changeCompletion(
        actionIdOf(201),
        completed,
      );
      await _until(
        () =>
            day().freshness == ActionDayFreshness.current &&
            otherDay().freshness == ActionDayFreshness.current &&
            day().incomplete.totalCount == (completed ? 0 : 1) &&
            otherDay().incomplete.totalCount == (completed ? 0 : 1) &&
            opened().action.isCompleted == completed,
      );
      await expectMarks({
        sourceDay: completed
            ? ActionDayStatus.allCompleted
            : ActionDayStatus.hasIncomplete,
      });
      expect(day().selection.date, sourceDay);
      expect(day().selection.incompleteExpanded, isTrue);
      expect(day().selection.completedExpanded, isTrue);
      expect(otherDay().selection.date, sourceDay);
      expect(otherDay().selection.incompleteExpanded, isFalse);
      expect(otherDay().selection.completedExpanded, isTrue);
      expect(opened().action.schedule, ActionAtHour(18));
      expect(opened().action.priority, ActionPriority.p2);
      expect(opened().action.description?.value, description);
      expect(_relationIds(opened()), [relationIdOf(101), relationIdOf(102)]);
      if (completed) {
        for (final loaded in [day(), otherDay()]) {
          expect(loaded.completed.totalCount, 51);
          expect(loaded.completed.items.map((item) => item.id), [
            for (var number = 202; number <= 251; number++) actionIdOf(number),
          ]);
          expect(loaded.completed.nextCursor, isNotNull);
        }
        await model.loadMore(section: ActionDaySection.completed);
        await otherModel.loadMore(section: ActionDaySection.completed);
        for (final loaded in [day(), otherDay()]) {
          expect(loaded.completed.items.map((item) => item.id), [
            for (var number = 202; number <= 251; number++) actionIdOf(number),
            actionIdOf(201),
          ]);
          expect(loaded.completed.nextCursor, isNull);
          expect(loaded.completed.items.last.pathIntentionCount, 3);
        }
      } else {
        for (final loaded in [day(), otherDay()]) {
          expect(loaded.incomplete.items.single.id, actionIdOf(201));
          expect(loaded.completed.items.map((item) => item.id), [
            for (var number = 202; number <= 251; number++) actionIdOf(number),
          ]);
        }
      }
    }

    final moved = await _confirmed(
      coordinator.acceptActionUpdate(
        UpdateActionFields(
          actionId: actionIdOf(201),
          patch: ActionFieldsPatch(
            date: ActionFieldSet(targetDay),
            isCompleted: const ActionFieldSet(true),
          ),
        ),
      ),
    );
    await _until(
      () =>
          day().freshness == ActionDayFreshness.current &&
          day().revision.compareTo(moved) == GraphRevisionOrder.same &&
          opened().action.isCompleted,
    );
    // Перенесённое действие исчезает из исходного дня вместе с количеством.
    expect(day().selection.date, sourceDay);
    expect(day().totalCount, 50);
    expect(day().items, hasLength(50));
    expect(day().incomplete.nextCursor, isNull);
    expect(day().items.any((item) => item.id == actionIdOf(201)), isFalse);
    expect(day().items.every((item) => item.date == sourceDay), isTrue);
    expect(opened().action.date, targetDay);
    await expectMarks({
      sourceDay: ActionDayStatus.allCompleted,
      targetDay: ActionDayStatus.allCompleted,
    });

    final rename = coordinator.acceptExisting(
      UpdateIntention(
        id: opened().path.root.id,
        title: 'Новое основание',
        description: null,
      ),
      presentationTitle: 'Намерение 1',
    );
    if (rename is! IntentionCommandAccepted) fail('Переименование не принято');
    await rename.future;
    await _until(
      () =>
          day().freshness == ActionDayFreshness.current &&
          day().items.every((item) => item.rootTitle == 'Новое основание') &&
          opened().path.root.title == 'Новое основание',
    );
    expect(day().totalCount, 50);
    expect(day().items, hasLength(50));

    // В новом дне перенесённое действие доступно с подтверждёнными полями.
    model.selectDate(targetDay);
    await _until(
      () =>
          container.read(dayProvider) is ActionDayLoaded &&
          day().selection.date == targetDay,
    );
    expect(day().totalCount, 1);
    expect(day().incomplete.nextCursor, isNull);
    final item = day().items.single;
    expect(item.id, actionIdOf(201));
    expect(item.date, targetDay);
    expect(item.isCompleted, isTrue);
    expect(item.rootTitle, 'Новое основание');
    expect(opened().action.date, item.date);

    await _confirmed(
      coordinator.acceptActionDelete(DeleteAction(actionIdOf(201))),
    );
    await _until(
      () =>
          day().freshness == ActionDayFreshness.current &&
          day().totalCount == 0 &&
          watched.isMissing,
    );
    expect(day().selection.date, targetDay);
    await expectMarks({sourceDay: ActionDayStatus.allCompleted});

    // Выполненное действие, снятое с выполнения при переносе, делает
    // невыполненным новый день; обратный перенос оставляет отметку
    // невыполненного только за исходным днём.
    await _confirmed(
      coordinator.acceptActionUpdate(
        UpdateActionFields(
          actionId: actionIdOf(202),
          patch: ActionFieldsPatch(
            date: ActionFieldSet(targetDay),
            isCompleted: const ActionFieldSet(false),
          ),
        ),
      ),
    );
    await expectMarks({
      sourceDay: ActionDayStatus.allCompleted,
      targetDay: ActionDayStatus.hasIncomplete,
    });
    await _confirmed(
      coordinator.acceptActionUpdate(
        UpdateActionFields(
          actionId: actionIdOf(202),
          patch: ActionFieldsPatch(date: ActionFieldSet(sourceDay)),
        ),
      ),
    );
    await expectMarks({sourceDay: ActionDayStatus.hasIncomplete});
  });

  test('экран одного дня на настоящем хранилище согласует выполнение, перенос '
      'из дня и в день и удаление, не меняя соседний дубликат', () async {
    final day = CalendarDate.fromParts(2026, 9, 24);
    final pastDay = CalendarDate.fromParts(2026, 9, 23);
    final futureDay = CalendarDate.fromParts(2026, 9, 25);
    final storage = await _openStorage();
    seedRawGraph(storage.raw, () {
      _seedPath(storage.raw);
      // Пятьдесят три полных дубликата выбранного дня; в соседних днях
      // действия заведены после них, поэтому в порядке создания идут позже.
      for (var number = 201; number <= 253; number++) {
        seedAction(
          storage.raw,
          id: seedUuid(number),
          path: _path,
          date: day.toCanonicalString(),
        );
      }
      seedAction(
        storage.raw,
        id: seedUuid(301),
        path: _path,
        date: pastDay.toCanonicalString(),
      );
      seedAction(
        storage.raw,
        id: seedUuid(302),
        path: _path,
        date: futureDay.toCanonicalString(),
        isCompleted: true,
      );
      seedAction(
        storage.raw,
        id: seedUuid(303),
        path: _path,
        date: pastDay.toCanonicalString(),
      );
    });

    final container = _container(storage.repository);
    final dayProvider = actionDayViewModelProvider(
      ActionDayInstance(initialDate: day),
    );
    container.listen(dayProvider, (_, _) {});
    ActionDayLoaded loaded() => container.read(dayProvider) as ActionDayLoaded;
    bool shows(CalendarDate date) => switch (container.read(dayProvider)) {
      final ActionDayLoaded state =>
        state.selection.date == date &&
            state.freshness == ActionDayFreshness.current,
      _ => false,
    };
    var includeCompleted = false;
    List<ActionId> ids() => [
      for (final item
          in includeCompleted ? loaded().items : loaded().incomplete.items)
        item.id,
    ];
    final model = container.read(dayProvider.notifier);
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    Future<GraphRevision> update(int number, ActionFieldsPatch patch) =>
        _confirmed(
          coordinator.acceptActionUpdate(
            UpdateActionFields(actionId: actionIdOf(number), patch: patch),
          ),
        );
    Future<void> reconciled(GraphRevision revision) => _until(
      () =>
          container.read(dayProvider) is ActionDayLoaded &&
          loaded().freshness == ActionDayFreshness.current &&
          loaded().revision.compareTo(revision) == GraphRevisionOrder.same,
    );

    // Первое открытие сразу читает выбранный день и загружает его целиком
    // двумя порциями.
    await _until(() => shows(day));
    expect(loaded().totalCount, 53);
    expect(ids(), [
      for (var number = 201; number <= 250; number++) actionIdOf(number),
    ]);
    await model.loadMore(section: ActionDaySection.incomplete);
    expect(ids(), [
      for (var number = 201; number <= 253; number++) actionIdOf(number),
    ]);
    expect(loaded().incomplete.nextCursor, isNull);

    await model.loadMore(section: ActionDaySection.incomplete);
    expect(loaded().totalCount, 53);
    expect(loaded().items, hasLength(53));

    // Выполнение одного дубликата убирает его из охвата невыполненных, а
    // его полный дубликат остаётся прежним.
    model.changeCompletion(actionIdOf(253), true);
    await _until(
      () =>
          loaded().freshness == ActionDayFreshness.current &&
          loaded().incomplete.totalCount == 52,
    );
    expect(ids(), [
      for (var number = 201; number <= 252; number++) actionIdOf(number),
    ]);
    final twin = loaded().incomplete.items.last;
    expect(twin.id, actionIdOf(252));
    expect(twin.date, day);
    expect(twin.isCompleted, isFalse);

    // Перенос другого дубликата на будущий день убирает только его.
    await reconciled(
      await update(252, ActionFieldsPatch(date: ActionFieldSet(futureDay))),
    );
    expect(loaded().incomplete.totalCount, 51);
    expect(ids(), [
      for (var number = 201; number <= 251; number++) actionIdOf(number),
    ]);

    // При равных времени и приоритете действие, пришедшее из соседнего дня,
    // идёт после прежних по порядку создания.
    await reconciled(
      await update(303, ActionFieldsPatch(date: ActionFieldSet(day))),
    );
    expect(loaded().incomplete.totalCount, 52);
    expect(ids(), [
      for (var number = 201; number <= 251; number++) actionIdOf(number),
      actionIdOf(303),
    ]);

    // Правка действия другого дня не входит в выдачу этого дня.
    await update(
      301,
      const ActionFieldsPatch(priority: ActionFieldSet(ActionPriority.p1)),
    );
    final deleted = await _confirmed(
      coordinator.acceptActionDelete(DeleteAction(actionIdOf(303))),
    );
    await reconciled(deleted);
    expect(loaded().incomplete.totalCount, 51);
    expect(ids(), [
      for (var number = 201; number <= 251; number++) actionIdOf(number),
    ]);

    // Раскрытые выполненные сохраняют обе прочитанные секции того же дня.
    includeCompleted = true;
    expect(loaded().totalCount, 52);
    expect(ids().last, actionIdOf(253));
    expect(loaded().completed.items.single.isCompleted, isTrue);

    // Перенесённые действия доступны выбором их дней.
    model.selectDate(futureDay);
    await _until(() => shows(futureDay));
    expect(ids(), [actionIdOf(252), actionIdOf(302)]);
    expect(loaded().totalCount, 2);
    expect(loaded().incomplete.items.single.isCompleted, isFalse);
    model.selectDate(pastDay);
    await _until(() => shows(pastDay));
    expect(ids(), [actionIdOf(301)]);
    expect(loaded().incomplete.items.single.priority, ActionPriority.p1);
  });

  test('реальные правки пересобирают обе секции до прежнего объёма и '
      'сохраняются при отказе чтения', () async {
    final day = CalendarDate.fromParts(2026, 9, 24);
    final probe = _ActionDayReadFailure();
    final storage = await _openStorage(observer: probe);
    seedRawGraph(storage.raw, () {
      _seedPath(storage.raw);
      for (var number = 201; number <= 251; number++) {
        seedAction(
          storage.raw,
          id: seedUuid(number),
          path: _path,
          date: day.toCanonicalString(),
        );
        seedAction(
          storage.raw,
          id: seedUuid(number + 100),
          path: _path,
          date: day.toCanonicalString(),
          hour: 18,
          isCompleted: true,
        );
      }
    });

    final container = _container(storage.repository);
    final provider = actionDayViewModelProvider(
      ActionDayInstance(initialDate: day),
    );
    container.listen(provider, (_, value) {
      if (value is ActionDayLoaded) {
        expect(
          value.items.where((item) => item.id == actionIdOf(201)).length,
          lessThanOrEqualTo(1),
        );
        expect(
          value.incomplete.items.every((item) => !item.isCompleted),
          isTrue,
        );
        expect(value.completed.items.every((item) => item.isCompleted), isTrue);
      }
    });
    ActionDayLoaded loaded() => container.read(provider) as ActionDayLoaded;
    await _until(() => container.read(provider) is ActionDayLoaded);
    final model = container.read(provider.notifier);
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final watched = _WatchedAction(storage.repository, actionIdOf(201));
    await _until(() => watched.details != null);
    ActionDetails opened() => watched.details!;
    await model.loadMore(section: ActionDaySection.completed);
    expect(
      (loaded().incomplete.items.length, loaded().completed.items.length),
      (50, 51),
    );

    probe.failNext = true;
    await _confirmed(
      coordinator.acceptActionUpdate(
        UpdateActionFields(
          actionId: actionIdOf(201),
          patch: ActionFieldsPatch(
            schedule: ActionFieldSet(ActionAtHour(18)),
            priority: const ActionFieldSet(ActionPriority.p2),
          ),
        ),
      ),
    );
    await _until(
      () =>
          loaded().freshness == ActionDayFreshness.stale &&
          opened().action.priority == ActionPriority.p2,
    );
    expect(loaded().incomplete.items.first.schedule, const ActionAllDay());
    expect(opened().action.schedule, ActionAtHour(18));

    await _confirmed(
      coordinator.acceptActionUpdate(
        UpdateActionFields(
          actionId: actionIdOf(201),
          patch: const ActionFieldsPatch(
            priority: ActionFieldSet(ActionPriority.p1),
          ),
        ),
      ),
    );
    await _until(
      () =>
          loaded().freshness == ActionDayFreshness.current &&
          opened().action.priority == ActionPriority.p1,
    );
    expect(
      (loaded().incomplete.items.length, loaded().completed.items.length),
      (50, 51),
    );
    expect(
      loaded().incomplete.items.any((item) => item.id == actionIdOf(201)),
      isFalse,
    );
    await model.loadMore(section: ActionDaySection.incomplete);
    final moved = loaded().incomplete.items.last;
    expect(moved.id, actionIdOf(201));
    expect(moved.schedule, ActionAtHour(18));
    expect(moved.priority, ActionPriority.p1);
    expect(moved.pathIntentionCount, 3);

    model.changeCompletion(moved.id, true);
    await _until(
      () =>
          loaded().freshness == ActionDayFreshness.current &&
          loaded().completed.totalCount == 52 &&
          opened().action.isCompleted,
    );
    expect(loaded().incomplete.totalCount, 50);
    expect(
      loaded().incomplete.items.any((item) => item.id == moved.id),
      isFalse,
    );
    expect(loaded().completed.items.first.id, moved.id);
    expect(loaded().completed.items.first.pathIntentionCount, 3);
    expect(loaded().completed.items, hasLength(52));
  });

  testWidgets('перенос даты в панели оставляет её открытой с новой датой, а '
      'после закрытия экран дня и отметки обоих дней согласованы', (
    tester,
  ) async {
    final day = CalendarDate.fromParts(2026, 9, 23);
    final targetDay = CalendarDate.fromParts(2026, 9, 27);
    final storage = await _openStorage();
    seedRawGraph(storage.raw, () {
      _seedPath(storage.raw);
      seedAction(
        storage.raw,
        id: seedUuid(201),
        path: _path,
        date: day.toCanonicalString(),
      );
    });
    await pumpActionDay(
      tester,
      storage.repository,
      today: day,
      locale: const Locale('ru'),
      size: const Size(360, 900),
    );
    Future<void> until(bool Function() condition) async {
      for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(condition(), isTrue);
    }

    final row = find.byKey(const ValueKey('action-day-row-1'));
    await until(() => row.evaluate().isNotEmpty);
    await expandActionDayCalendar(tester);
    await until(
      () => actionDayDayMark(day, mark: DayMark.todo).evaluate().isNotEmpty,
    );
    await tester.tap(row);
    await until(() => actionPanelReady.evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(DetailRow, 'Дата'),
        matching: find.byType(Button),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(DateGrid),
        matching: find.text('${targetDay.day}'),
      ),
    );
    await until(() => actionPanelField('27 сент.').evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    expect(actionPanel, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await closeActionPanel(tester);
    await until(() => row.evaluate().isEmpty);
    await until(
      () =>
          actionDayDayMark(
            targetDay,
            mark: DayMark.todo,
          ).evaluate().isNotEmpty &&
          actionDayDayMark(day).evaluate().isEmpty,
    );
    expect(shownActionDayDate(tester), day);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// Настоящее хранилище в памяти: низкоуровневое соединение для засева и
/// репозиторий над ним.
typedef _Storage = ({
  sqlite.Database raw,
  DriftPersonalGraphRepository repository,
});

Future<_Storage> _openStorage({
  LocalDatabaseConnectionObserver? observer,
}) async {
  late sqlite.Database raw;
  final connection = openInMemoryLocalDatabase(setup: (db) => raw = db);
  final database = AppDatabase(
    observer == null
        ? connection
        : observeConfiguredLocalDatabaseConnection(connection, observer),
  );
  await database.open();
  addTearDown(database.close);
  return (
    raw: raw,
    repository: DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 24),
      InMemoryDiagnosticsSink(),
    ),
  );
}

ProviderContainer _container(PersonalGraphRepository repository) {
  final container = ProviderContainer(
    overrides: [
      personalGraphRepositoryProvider.overrideWith((ref) => repository),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Путь всех засеянных действий: намерение 1 → 2 → 3.
final _path = [seedUuid(1), seedUuid(2), seedUuid(3)];

/// Засевает намерения 1, 2, 3 и связи пути 1 → 2 → 3. Вызывать внутри
/// `seedRawGraph`.
void _seedPath(sqlite.Database raw) {
  for (var number = 1; number <= 3; number++) {
    seedIntention(raw, seedUuid(number), 'Намерение $number');
  }
  seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
  seedRelation(raw, seedUuid(102), seedUuid(2), seedUuid(3));
}

/// Идентификаторы связей звеньев сохранённого пути [details] по порядку.
List<LongTermRelationId> _relationIds(ActionDetails details) => [
  for (final step in details.path.steps)
    switch (step.link) {
      ExistingActionPathLink(:final relation) => relation.id,
      DeletedActionPathLink() => fail('Звено пути потеряло связь'),
    },
];

/// Подтверждённая ревизия принятой команды; отказ или непринятая команда
/// проваливают проверку.
Future<GraphRevision> _confirmed(ActionCommandStart start) async {
  if (start is! ActionCommandAccepted) fail('Команда не принята');
  final change = (await start.future).confirmedChange;
  if (change == null) fail('Команда отклонена');
  return change.revision;
}

/// Действие, наблюдаемое так же, как его наблюдает панель: последний снимок
/// потока `watchAction`.
final class _WatchedAction {
  _WatchedAction(PersonalGraphRepository repository, ActionId id) {
    final subscription = repository
        .watchAction(id)
        .listen((result) => _latest = result);
    addTearDown(subscription.cancel);
  }

  ActionReadResult? _latest;

  /// Действие последнего снимка; `null`, пока снимка нет или действия нет.
  ActionDetails? get details => switch (_latest) {
    ActionReadSuccess(value: GraphSnapshot(:final value)) => value,
    _ => null,
  };

  /// Последний снимок сообщил, что действия нет.
  bool get isMissing => switch (_latest) {
    ActionReadSuccess(value: GraphSnapshot(value: null)) => true,
    _ => false,
  };
}

/// Отказ реального чтения выдачи дня после подтверждённой команды не
/// откатывает запись.
final class _ActionDayReadFailure extends LocalDatabaseConnectionObserver {
  bool failNext = false;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (failNext &&
        statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains('WHERE a.date = ?')) {
      failNext = false;
      throw StateError('Управляемый отказ чтения выдачи дня');
    }
  }
}
