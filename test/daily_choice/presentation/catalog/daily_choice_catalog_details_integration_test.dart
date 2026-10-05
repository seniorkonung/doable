import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_id_generator.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
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
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/daily_choice_catalog_controls.dart';
import '../../../support/daily_choice_local_date.dart';
import '../../../support/in_memory_diagnostics_sink.dart';

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
    'реальный каталог и подробности согласуют дубликаты и изменения графа',
    () async {
      final sourceDay = CalendarDate.fromParts(2026, 9, 24);
      final targetDay = CalendarDate.fromParts(2026, 9, 25);
      final database = AppDatabase(openInMemoryLocalDatabase());
      await database.open();
      addTearDown(database.close);
      await _seedGraph(database);
      for (var number = 201; number <= 251; number++) {
        await _insertChoice(database, number, sourceDay);
      }

      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 24),
        InMemoryDiagnosticsSink(),
      );
      // Локальное сегодня совпадает с днём записей, но каталог выбирает этот
      // день явно и не зависит от первоначального охвата.
      final container = ProviderContainer(
        overrides: [
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
    },
  );

  test(
    'каталог одного дня на настоящем хранилище согласует выполнение, перенос, '
    'создание и удаление, не меняя соседний дубликат',
    () async {
      final day = CalendarDate.fromParts(2026, 9, 24);
      final pastDay = CalendarDate.fromParts(2026, 9, 23);
      final futureDay = CalendarDate.fromParts(2026, 9, 25);
      final reads = _ReadProbe();
      final diagnostics = InMemoryDiagnosticsSink();
      final database = AppDatabase(
        observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          reads,
        ),
      );
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
        diagnostics,
        dailyChoiceIdGenerator: _SequentialChoiceIds(401),
      );
      final container = ProviderContainer(
        overrides: [
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
      int catalogReadEvents() => diagnostics.events
          .whereType<DailyChoiceCatalogPageReadDiagnosticsEvent>()
          .length;

      /// Чтения выдачи с последней очистки ограничены днём [date] и
      /// проверяют пути не более [rows] строк.
      void expectReadsOf(CalendarDate date, {required int rows}) {
        final catalogReads = [
          ...reads.matching('ORDER BY choice_date DESC'),
          ...reads.matching('COUNT(*) AS total_count'),
        ];
        expect(catalogReads, isNotEmpty);
        for (final read in catalogReads) {
          expect(read.sql, contains('choice_date = ?'));
          expect(read.arguments.first, date.toCanonicalString());
        }
        final paths = reads.matching('WHERE daily_choice_id IN');
        expect(
          paths.fold<int>(0, (sum, read) => sum + read.arguments.length),
          lessThanOrEqualTo(rows),
        );
      }

      Future<DailyChoiceCommandCompletion> confirm(
        DailyChoiceCommandStart start,
      ) async {
        reads.clear();
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
      expectReadsOf(day, rows: 50);
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
      expectReadsOf(day, rows: 52);

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
      expectReadsOf(day, rows: 51);

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
      expectReadsOf(day, rows: 52);

      // Запись другого дня не входит в выдачу и не вызывает чтений.
      final readEventsBefore = catalogReadEvents();
      await confirm(
        coordinator.acceptDailyChoiceCreation(
          DailyChoiceCreationFormKey(),
          _create(pastDay),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(catalog().totalCount, 52);
      expect(ids(), isNot(contains(_choice(402))));
      expect(catalogReadEvents(), readEventsBefore);

      final deleted = await confirm(
        coordinator.acceptDailyChoiceDelete(DeleteDailyChoice(_choice(401))),
      );
      await reconciled(deleted);
      expect(catalog().totalCount, 51);
      expect(ids(), isNot(contains(_choice(401))));
      expectReadsOf(day, rows: 51);

      // Сброс возвращает выполненную запись того же дня.
      reads.clear();
      model.clearFilters();
      await _until(() => shows(day, null));
      expect(catalog().totalCount, 52);
      expect(ids().first, _choice(253));
      expect(catalog().items.first.isCompleted, isTrue);
      expectReadsOf(day, rows: 50);

      // Перенесённая и созданная записи доступны выбором их дней.
      reads.clear();
      model.selectDate(futureDay);
      await _until(() => shows(futureDay, null));
      expect(ids(), [_choice(302), _choice(252)]);
      expect(catalog().totalCount, 2);
      expect(catalog().items.last.isCompleted, isFalse);
      expectReadsOf(futureDay, rows: 2);
      reads.clear();
      model.selectDate(pastDay);
      await _until(() => shows(pastDay, null));
      expect(ids(), [_choice(402), _choice(301)]);
      expectReadsOf(pastDay, rows: 2);

      // Пути и граф читаются только адресно.
      for (final table in [
        'FROM daily_choice_path_steps',
        'FROM long_term_relations',
        'FROM intentions',
      ]) {
        expect(
          reads.everMatching(table).map((read) => read.sql),
          everyElement(contains('WHERE')),
        );
      }
    },
  );

  testWidgets(
    'на настоящем хранилище выбор дня читает одну первую порцию, а просмотр '
    'периода не читает хранилище и не пишет диагностику чтений',
    (tester) async {
      final day = CalendarDate.fromParts(2026, 9, 24);
      final otherDay = CalendarDate.fromParts(2026, 9, 25);
      final reads = _ReadProbe();
      final diagnostics = InMemoryDiagnosticsSink();
      final database = AppDatabase(
        observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          reads,
        ),
      );
      final router = AppRouter();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        await tester.runAsync(database.close);
      });
      await tester.runAsync(() async {
        await database.open();
        await _seedGraph(database);
        for (var number = 201; number <= 251; number++) {
          await _insertChoice(database, number, day);
        }
        await _insertChoice(database, 301, otherDay);
      });
      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 24),
        diagnostics,
      );
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalGraphRepositoryProvider.overrideWithValue(repository),
            ControlledDailyChoiceLocalDate(day).override,
          ],
          child: MaterialApp.router(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router.config(),
          ),
        ),
      );
      openDailyChoicesOn(router);
      await tester.pump();
      DailyChoiceCatalogState state() => ProviderScope.containerOf(
        tester.element(find.byType(DailyChoiceCatalogPage)),
        listen: false,
      ).read(dailyChoiceCatalogViewModelProvider);
      // События чтения выдачи после отметки [from] в журнале диагностики.
      List<String> catalogReadEvents({int from = 0}) => [
        for (final event
            in diagnostics.events
                .skip(from)
                .whereType<DailyChoiceCatalogPageReadDiagnosticsEvent>())
          '${event.isContinuation ? 'continuation' : 'first'}:'
              '${event.pageSize}:${switch (event.status) {
                DiagnosticsStarted() => 'started',
                DiagnosticsSucceeded() => 'succeeded',
                DiagnosticsFailed(:final code) => 'failed:${code.name}',
              }}',
      ];
      Future<void> settleStorage() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }

      Future<void> loadedOn(CalendarDate date) async {
        for (var attempt = 0; attempt < 100; attempt++) {
          final current = state();
          if (current is DailyChoiceCatalogLoaded &&
              current.selection.date == date) {
            break;
          }
          await settleStorage();
        }
        final current = state();
        expect(current, isA<DailyChoiceCatalogLoaded>());
        expect((current as DailyChoiceCatalogLoaded).selection.date, date);
        await tester.pump();
      }

      void expectFirstPortionOf(CalendarDate date, {int from = 0}) {
        expect(catalogReadEvents(from: from), [
          'first:50:started',
          'first:50:succeeded',
        ]);
        final portion = reads.matching('ORDER BY choice_date DESC');
        final count = reads.matching('COUNT(*) AS total_count');
        expect(portion, hasLength(1));
        expect(count, hasLength(1));
        for (final read in [...portion, ...count]) {
          expect(read.arguments.first, date.toCanonicalString());
        }
      }

      await loadedOn(day);
      expect((state() as DailyChoiceCatalogLoaded).totalCount, 51);
      expectFirstPortionOf(day);

      // Перелистывание недель и месяцев, раскрытие и сворачивание не
      // читают хранилище и не добавляют событий чтения.
      reads.clear();
      final eventsBefore = diagnostics.events.length;
      await showDailyChoiceCatalogPeriod(
        tester,
        CalendarDate.fromParts(2026, 10, 12),
      );
      await expandDailyChoiceCatalogCalendar(tester);
      await showDailyChoiceCatalogPeriod(
        tester,
        CalendarDate.fromParts(2026, 7, 15),
      );
      final texts = AppLocalizations.of(
        tester.element(dailyChoiceCatalogDateControl),
      );
      await tester.tap(find.byTooltip(texts.dailyChoiceCalendarCollapse));
      await tester.pump(const Duration(seconds: 1));
      await settleStorage();
      expect(reads.matching('SELECT'), isEmpty);
      expect(diagnostics.events, hasLength(eventsBefore));
      expect(shownDailyChoiceCatalogDate(tester), day);

      // Выбор другого дня читает ровно одну первую порцию этого дня.
      reads.clear();
      await selectDailyChoiceCatalogDate(tester, otherDay);
      await loadedOn(otherDay);
      expect(
        (state() as DailyChoiceCatalogLoaded).items.single.id,
        _choice(301),
      );
      expectFirstPortionOf(otherDay, from: eventsBefore);

      // Повторный выбор того же дня ничего не читает.
      final eventsAfterSelection = diagnostics.events.length;
      reads.clear();
      await selectDailyChoiceCatalogDate(tester, otherDay);
      await settleStorage();
      expect(reads.matching('SELECT'), isEmpty);
      expect(diagnostics.events, hasLength(eventsAfterSelection));
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

/// Журнал чтений SQLite с аргументами: с последней очистки и за всю проверку.
final class _ReadProbe extends LocalDatabaseConnectionObserver {
  final _reads = <({String sql, List<Object?> arguments})>[];
  final _all = <({String sql, List<Object?> arguments})>[];

  /// Начинает новый отрезок для [matching]; журнал всей проверки остаётся.
  void clear() => _reads.clear();

  /// Чтения с последней очистки, текст которых содержит [fragment].
  List<({String sql, List<Object?> arguments})> matching(String fragment) => [
    for (final read in _reads)
      if (read.sql.contains(fragment)) read,
  ];

  /// Все чтения с начала проверки, текст которых содержит [fragment].
  List<({String sql, List<Object?> arguments})> everMatching(String fragment) =>
      [
        for (final read in _all)
          if (read.sql.contains(fragment)) read,
      ];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select) {
      final read = (
        sql: statement.statements.single,
        arguments: statement.arguments,
      );
      _reads.add(read);
      _all.add(read);
    }
  }
}
