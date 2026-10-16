import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;

  setUp(() async {
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(openInMemoryLocalDatabase(setup: (db) => raw = db));
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      diagnostics,
    );
    for (final number in [1, 2, 3]) {
      raw.execute(
        '''INSERT INTO intentions
           (id, title, description, is_action_ready, is_archived,
            created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, 1, 1)''',
        [
          _uuid(number),
          'Намерение $number',
          'Описание $number',
          number == 3 ? 0 : 1,
          number == 2 ? 1 : 0,
        ],
      );
    }
    for (final (number, source, target, archived) in [
      (101, 1, 2, 1),
      (102, 2, 3, 1),
    ]) {
      raw.execute(
        '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id, type, priority,
            description, is_archived)
           VALUES (?, ?, ?, 'need', 2, ?, ?)''',
        [
          _uuid(number),
          _uuid(source),
          _uuid(target),
          'Описание связи $number',
          archived,
        ],
      );
    }
  });
  tearDown(() => database.close());

  void addChoice(
    int number, {
    String date = '2026-09-23',
    int completed = 0,
    bool longPath = false,
    String? description = 'Описание выбора',
    int? scheduledMinute,
    int priority = 4,
  }) {
    raw.execute(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date,
          description, is_completed, scheduled_minute, priority)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        _uuid(number),
        _uuid(1),
        _uuid(longPath ? 3 : 2),
        date,
        description,
        completed,
        scheduledMinute,
        priority,
      ],
    );
    raw.execute(
      '''INSERT INTO daily_choice_path_steps
         (id, daily_choice_id, long_term_relation_id, previous_step_id)
         VALUES (?, ?, ?, NULL)''',
      [_uuid(number + 1000), _uuid(number), _uuid(101)],
    );
    if (longPath) {
      raw.execute(
        '''INSERT INTO daily_choice_path_steps
           (id, daily_choice_id, long_term_relation_id, previous_step_id)
           VALUES (?, ?, ?, ?)''',
        [_uuid(number + 2000), _uuid(number), _uuid(102), _uuid(number + 1000)],
      );
    }
  }

  DailyChoiceCatalogPage page(DailyChoiceCatalogPageResult result) =>
      (result as DailyChoiceCatalogPageSuccess).value;

  test(
    'краткая проекция читает сохранённые поля и число намерений пути',
    () async {
      const description = '  Первая строка\nВторая строка\nТретья строка  ';
      addChoice(
        201,
        longPath: true,
        description: description,
        scheduledMinute: 18 * 60,
        priority: 2,
      );
      raw.execute(
        '''INSERT INTO intentions
      (id, title, is_action_ready, is_archived, created_at, updated_at)
      VALUES (?, 'Конечное действие', 1, 0, 1, 1)''',
        [_uuid(4)],
      );
      raw.execute(
        '''INSERT INTO long_term_relations
      (id, source_intention_id, related_intention_id, type, priority, is_archived)
      VALUES (?, ?, ?, 'can', 1, 0)''',
        [_uuid(103), _uuid(3), _uuid(4)],
      );
      raw.execute(
        '''INSERT INTO daily_choice_path_steps
      (id, daily_choice_id, long_term_relation_id, previous_step_id)
      VALUES (?, ?, ?, ?)''',
        [_uuid(3201), _uuid(201), _uuid(103), _uuid(2201)],
      );
      raw.execute(
        'UPDATE daily_choices SET selected_intention_id = ? WHERE id = ?',
        [_uuid(4), _uuid(201)],
      );
      addChoice(202, description: null, scheduledMinute: 0, priority: 1);
      addChoice(203);

      final items = page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(
            date: CalendarDate.fromParts(2026, 9, 23),
            isCompleted: false,
          ),
        ),
      ).items;
      final timed = items.singleWhere(
        (item) => item.id.toCanonicalString() == _uuid(201),
      );
      expect(timed.schedule, DailyChoiceTime(hour: 18, minute: 0));
      expect(timed.priority, DailyChoicePriority.p2);
      expect(timed.description?.value, description);
      expect(timed.pathIntentionCount, 4);
      final midnight = items.singleWhere(
        (item) => item.id.toCanonicalString() == _uuid(202),
      );
      expect(midnight.schedule, DailyChoiceTime(hour: 0, minute: 0));
      expect(midnight.priority, DailyChoicePriority.p1);
      expect(midnight.description, isNull);
      expect(midnight.pathIntentionCount, 2);
      final allDay = items.singleWhere(
        (item) => item.id.toCanonicalString() == _uuid(203),
      );
      expect(allDay.schedule, const DailyChoiceAllDay());
      expect(allDay.priority, DailyChoicePriority.p4);
      expect(allDay.pathIntentionCount, 2);
    },
  );

  test(
    'читает дубликаты выбранного дня отдельно от выполненных и соседних дат',
    () async {
      addChoice(201, date: '2026-09-22');
      addChoice(202, completed: 1);
      addChoice(203, longPath: true);
      addChoice(204, date: '2026-09-24');
      addChoice(205);
      addChoice(206);
      final day = CalendarDate.fromParts(2026, 9, 23);
      final ids = <String>[];
      DailyChoiceCatalogCursor? cursor;
      var reads = 0;
      do {
        final result = page(
          await repository.getDailyChoiceCatalogPage(
            DailyChoiceCatalogQuery(
              date: day,
              isCompleted: false,
              pageSize: 2,
              cursor: cursor,
            ),
          ),
        );
        if (reads == 0) {
          expect((result as DailyChoiceCatalogFirstPage).totalCount, 3);
          expect(
            result.items.first.selected.readiness,
            IntentionReadiness.notReady,
          );
        } else {
          expect(result, isA<DailyChoiceCatalogContinuationPage>());
        }
        ids.addAll(result.items.map((item) => item.id.toCanonicalString()));
        cursor = result.nextCursor;
        reads++;
      } while (cursor != null);
      expect(ids, [_uuid(203), _uuid(205), _uuid(206)]);
      expect(reads, 2);
      final completed = page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(date: day, isCompleted: true),
        ),
      ) as DailyChoiceCatalogFirstPage;
      expect(completed.totalCount, 1);
      expect(completed.items.single.id.toCanonicalString(), _uuid(202));
    },
  );

  test('проверяет путь только выбранной порции, а повреждение следующей находит при продолжении', () async {
    final day = CalendarDate.fromParts(2026, 9, 23);
    addChoice(201, longPath: true);
    addChoice(202);
    raw.execute(
      'DELETE FROM daily_choice_path_steps WHERE daily_choice_id = ?',
      [_uuid(202)],
    );
    final first = page(
      await repository.getDailyChoiceCatalogPage(
        DailyChoiceCatalogQuery(date: day, isCompleted: false, pageSize: 1),
      ),
    );
    expect(first.items.single.id.toCanonicalString(), _uuid(201));
    expect((first as DailyChoiceCatalogFirstPage).totalCount, 2);

    expect(
      await repository.getDailyChoiceCatalogPage(
        DailyChoiceCatalogQuery(
          date: day,
          isCompleted: false,
          pageSize: 1,
          cursor: first.nextCursor,
        ),
      ),
      isA<DailyChoiceCatalogPageError>().having(
        (result) => result.failure.category,
        'категория',
        GraphFailureCategory.corruption,
      ),
    );
  });

  test('отклоняет устаревшую ревизию', () async {
    final day = CalendarDate.fromParts(2026, 9, 23);
    addChoice(201);
    addChoice(202);
    final first = page(
      await repository.getDailyChoiceCatalogPage(
        DailyChoiceCatalogQuery(date: day, isCompleted: false, pageSize: 1),
      ),
    );
    final cursor = first.nextCursor;
    expect(cursor, isNotNull);

    expect(
      await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: first.items.first.id,
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(true),
          ),
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    expect(
      await repository.getDailyChoiceCatalogPage(
        DailyChoiceCatalogQuery(
          date: day,
          isCompleted: false,
          pageSize: 1,
          cursor: cursor,
        ),
      ),
      isA<DailyChoiceCatalogPageError>().having(
        (result) => result.failure,
        'устаревшая ревизия',
        isA<DailyChoiceCatalogSnapshotExpired>(),
      ),
    );
    expect(
      diagnostics.events
          .whereType<DailyChoiceCatalogPageReadDiagnosticsEvent>()
          .last
          .status,
      isA<DiagnosticsFailed>(),
    );
  });

  test(
    'секции обходят весь день, полночь и время по приоритету и созданию',
    () async {
      final day = CalendarDate.fromParts(2026, 9, 23);
      addChoice(208, scheduledMinute: 18 * 60, priority: 1);
      addChoice(207, scheduledMinute: 9 * 60, priority: 2);
      addChoice(206, priority: 4);
      addChoice(205, scheduledMinute: 0, priority: 4);
      addChoice(204, scheduledMinute: 9 * 60, priority: 2);
      addChoice(203, priority: 1);
      addChoice(202, scheduledMinute: 0, priority: 1);
      addChoice(201, scheduledMinute: 1439);
      addChoice(209, completed: 1, priority: 1);
      addChoice(210, date: '2026-09-24', priority: 1);

      final ids = <String>[];
      DailyChoiceCatalogCursor? cursor;
      GraphRevision? revision;
      do {
        final portion = page(
          await repository.getDailyChoiceCatalogPage(
            DailyChoiceCatalogQuery(
              date: day,
              isCompleted: false,
              pageSize: 1,
              cursor: cursor,
            ),
          ),
        );
        revision ??= portion.revision;
        expect(portion.revision.compareTo(revision), GraphRevisionOrder.same);
        expect(portion.items.map((item) => item.date), everyElement(day));
        expect(
          portion.items.map((item) => item.isCompleted),
          everyElement(false),
        );
        ids.addAll(portion.items.map((item) => item.id.toCanonicalString()));
        cursor = portion.nextCursor;
      } while (cursor != null);

      expect(ids, [203, 206, 202, 205, 207, 204, 208, 201].map(_uuid));
    },
  );

  test(
    'сводка учитывает время за первой порцией только своей секции',
    () async {
      final day = CalendarDate.fromParts(2026, 9, 23);
      addChoice(201);
      addChoice(202);
      addChoice(203, scheduledMinute: 18 * 60);
      addChoice(204, completed: 1);
      addChoice(205, date: '2026-09-24', completed: 1, scheduledMinute: 0);

      for (final (completed, count, hasTimedChoices) in [
        (false, 3, true),
        (true, 1, false),
      ]) {
        final first = page(
          await repository.getDailyChoiceCatalogPage(
            DailyChoiceCatalogQuery(
              date: day,
              isCompleted: completed,
              pageSize: 1,
            ),
          ),
        ) as DailyChoiceCatalogFirstPage;
        expect(first.items.single.schedule, const DailyChoiceAllDay());
        expect(first.totalCount, count);
        expect(first.hasTimedChoices, hasTimedChoices);
      }
      final empty = page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(
            date: CalendarDate.fromParts(2026, 9, 22),
            isCompleted: false,
          ),
        ),
      ) as DailyChoiceCatalogFirstPage;
      expect(empty.totalCount, 0);
      expect(empty.hasTimedChoices, isFalse);
    },
  );

  test(
    'продолжение отклоняет другую дату, выполнение, размер и эпоху',
    () async {
      final day = CalendarDate.fromParts(2026, 9, 23);
      addChoice(201);
      addChoice(202);
      final first = page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(date: day, isCompleted: false, pageSize: 1),
        ),
      );
      final cursor = first.nextCursor;
      expect(cursor, isNotNull);
      for (final query in [
        DailyChoiceCatalogQuery(
          date: CalendarDate.fromParts(2026, 9, 24),
          isCompleted: false,
          pageSize: 1,
          cursor: cursor,
        ),
        DailyChoiceCatalogQuery(
          date: day,
          isCompleted: true,
          pageSize: 1,
          cursor: cursor,
        ),
        DailyChoiceCatalogQuery(
          date: day,
          isCompleted: false,
          pageSize: 2,
          cursor: cursor,
        ),
      ]) {
        expect(
          await repository.getDailyChoiceCatalogPage(query),
          isA<DailyChoiceCatalogPageError>().having(
            (result) => result.failure,
            'устаревшая основа запроса',
            isA<DailyChoiceCatalogSnapshotExpired>(),
          ),
        );
      }

      final anotherRepository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 23),
        diagnostics,
      );
      expect(
        await anotherRepository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(
            date: day,
            isCompleted: false,
            pageSize: 1,
            cursor: cursor,
          ),
        ),
        isA<DailyChoiceCatalogPageError>().having(
          (result) => result.failure,
          'другая эпоха',
          isA<DailyChoiceCatalogSnapshotExpired>(),
        ),
      );
      expect(
        page(
          await repository.getDailyChoiceCatalogPage(
            DailyChoiceCatalogQuery(
              date: day,
              isCompleted: false,
              pageSize: 1,
              cursor: cursor,
            ),
          ),
        ).items.single.id.toCanonicalString(),
        _uuid(202),
      );
    },
  );

  test(
    'пустая выдача и верхняя граница порции сохраняют точное количество',
    () async {
      final empty = page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(
            date: CalendarDate.fromParts(2026, 9, 23),
            isCompleted: false,
            pageSize: 100,
          ),
        ),
      ) as DailyChoiceCatalogFirstPage;
      expect(empty.items, isEmpty);
      expect(empty.totalCount, 0);
      expect(empty.nextCursor, isNull);

      for (var number = 201; number <= 301; number++) {
        addChoice(number);
      }
      final first = page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(
            date: CalendarDate.fromParts(2026, 9, 23),
            isCompleted: false,
            pageSize: 100,
          ),
        ),
      ) as DailyChoiceCatalogFirstPage;
      expect(first.items, hasLength(100));
      expect(first.totalCount, 101);
      final last = page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(
            date: CalendarDate.fromParts(2026, 9, 23),
            isCompleted: false,
            pageSize: 100,
            cursor: first.nextCursor,
          ),
        ),
      );
      expect(last.items.single.id.toCanonicalString(), _uuid(301));
      expect(last.nextCursor, isNull);
    },
  );

  test('повреждение одного выбранного пути отклоняет целую порцию', () async {
    addChoice(201);
    addChoice(202);
    raw.execute(
      'DELETE FROM daily_choice_path_steps WHERE daily_choice_id = ?',
      [_uuid(201)],
    );
    final result = await repository.getDailyChoiceCatalogPage(
      DailyChoiceCatalogQuery(
        date: CalendarDate.fromParts(2026, 9, 23),
        isCompleted: false,
        pageSize: 2,
      ),
    );
    expect(
      result,
      isA<DailyChoiceCatalogPageError>().having(
        (value) => value.failure.category,
        'категория',
        GraphFailureCategory.corruption,
      ),
    );
    expect(
      (diagnostics.events
                  .whereType<DailyChoiceCatalogPageReadDiagnosticsEvent>()
                  .last
                  .status
              as DiagnosticsFailed)
          .code,
      DiagnosticsFailureCode.corruption,
    );
  });

  test('принимает путь длиннее одной SQL-порции ссылок', () async {
    const length = 405;
    for (var number = 4; number <= length + 1; number++) {
      raw.execute(
        '''INSERT INTO intentions
           (id, title, is_action_ready, is_archived, created_at, updated_at)
           VALUES (?, ?, 0, 0, 1, 1)''',
        [_uuid(number), 'Намерение $number'],
      );
    }
    for (var number = 3; number <= length; number++) {
      raw.execute(
        '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id, type, priority,
            is_archived) VALUES (?, ?, ?, 'need', 2, 0)''',
        [_uuid(100 + number), _uuid(number), _uuid(number + 1)],
      );
    }
    raw.execute(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date,
          is_completed) VALUES (?, ?, ?, '2026-09-23', 0)''',
      [_uuid(201), _uuid(1), _uuid(length + 1)],
    );
    for (var number = 1; number <= length; number++) {
      raw.execute(
        '''INSERT INTO daily_choice_path_steps
           (id, daily_choice_id, long_term_relation_id, previous_step_id)
           VALUES (?, ?, ?, ?)''',
        [
          _uuid(1000 + number),
          _uuid(201),
          _uuid(100 + number),
          number == 1 ? null : _uuid(999 + number),
        ],
      );
    }

    final catalog = page(
      await repository.getDailyChoiceCatalogPage(
        DailyChoiceCatalogQuery(
          date: CalendarDate.fromParts(2026, 9, 23),
          isCompleted: false,
          pageSize: 1,
        ),
      ),
    );
    expect(
      catalog.items.single.selected.id.toCanonicalString(),
      _uuid(length + 1),
    );
  });

  test(
    'секция отдаёт больше пятидесяти полных дубликатов порциями '
    'по 50 по возрастанию создания без соседних дней и другой секции',
    () async {
      // Записи прошлого и будущего дня перемежаются с записями выбранного дня
      // в порядке создания, поэтому граница дня проверяется в каждой порции.
      final day = CalendarDate.fromParts(2026, 9, 23);
      final created = <String>[];
      final neighbours = <String>{};
      for (var index = 0; index < 120; index++) {
        addChoice(300 + index);
        created.add(_uuid(300 + index));
        if (index % 10 == 0) {
          addChoice(600 + index, date: '2026-09-22', completed: 1);
          addChoice(800 + index, date: '2026-09-24');
          addChoice(1000 + index, completed: 1);
          neighbours.addAll([
            _uuid(600 + index),
            _uuid(800 + index),
            _uuid(1000 + index),
          ]);
        }
      }

      final pages = <DailyChoiceCatalogPage>[];
      DailyChoiceCatalogCursor? cursor;
      do {
        final next = page(
          await repository.getDailyChoiceCatalogPage(
            DailyChoiceCatalogQuery(
              date: day,
              isCompleted: false,
              cursor: cursor,
            ),
          ),
        );
        pages.add(next);
        cursor = next.nextCursor;
      } while (cursor != null);

      expect(pages.map((portion) => portion.items.length), [50, 50, 20]);
      expect(
        pages.first,
        isA<DailyChoiceCatalogFirstPage>().having(
          (first) => first.totalCount,
          'точное количество дня',
          120,
        ),
      );
      expect(
        pages.skip(1),
        everyElement(isA<DailyChoiceCatalogContinuationPage>()),
      );
      final items = [for (final portion in pages) ...portion.items];
      expect(items.map((item) => item.id.toCanonicalString()), created);
      expect(items.map((item) => item.date), everyElement(day));
      // Полные дубликаты остаются самостоятельными записями: одинаковы
      // участники, дата и выполнение, различаются только идентификаторы.
      expect(
        items
            .map(
              (item) => (
                item.source.id,
                item.selected.id,
                item.date,
                item.isCompleted,
              ),
            )
            .toSet(),
        hasLength(1),
      );

      expect(
        items
            .map((item) => item.id.toCanonicalString())
            .toSet()
            .intersection(neighbours),
        isEmpty,
      );
    },
  );

  test('прошлые и будущие дни, выполненные записи и записи с архивными '
      'участниками и шагами доступны выбором дня и выполнения', () async {
    // Намерение 2 и обе связи пути архивированы: в коротком пути архивно
    // выбранное действие, в длинном — промежуточный шаг.
    addChoice(201, date: '2026-09-22', completed: 1);
    addChoice(202, date: '2026-09-22');
    addChoice(203, date: '2027-01-01', longPath: true);
    addChoice(204, date: '2027-01-01', completed: 1, longPath: true);
    final past = CalendarDate.fromParts(2026, 9, 22);
    final future = CalendarDate.fromParts(2027, 1, 1);

    for (final (date, completion, expected) in [
      (past, false, [202]),
      (past, true, [201]),
      (future, false, [203]),
      (CalendarDate.fromParts(2026, 9, 23), false, <int>[]),
    ]) {
      final result = page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(date: date, isCompleted: completion),
        ),
      ) as DailyChoiceCatalogFirstPage;
      expect(
        result.items.map((item) => item.id.toCanonicalString()),
        expected.map(_uuid),
        reason: 'день $date, выполнение $completion',
      );
      expect(result.totalCount, expected.length);
      expect(result.nextCursor, isNull);
      expect(result.items.map((item) => item.date), everyElement(date));
      expect(
        result.items.map((item) => item.isCompleted),
        everyElement(completion),
      );
    }

    final archivedAction = page(
      await repository.getDailyChoiceCatalogPage(
        DailyChoiceCatalogQuery(date: past, isCompleted: true),
      ),
    ).items.single;
    expect(archivedAction.selected.title, 'Намерение 2');
    expect(
      archivedAction.selected.archiveState,
      IntentionArchiveState.archived,
    );
    expect(archivedAction.source.archiveState, IntentionArchiveState.active);
    final archivedStep = page(
      await repository.getDailyChoiceCatalogPage(
        DailyChoiceCatalogQuery(date: future, isCompleted: false),
      ),
    ).items.single;
    expect(archivedStep.selected.title, 'Намерение 3');
    expect(archivedStep.selected.archiveState, IntentionArchiveState.active);
    expect(archivedStep.selected.readiness, IntentionReadiness.notReady);
  });
}
