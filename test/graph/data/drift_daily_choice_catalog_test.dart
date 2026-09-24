import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

final class _ReadProbe extends LocalDatabaseConnectionObserver {
  final statements = <String>[];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select) {
      statements.add(statement.statements.single);
    }
  }
}

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _ReadProbe probe;

  setUp(() async {
    probe = _ReadProbe();
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        probe,
      ),
    );
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
  }) {
    raw.execute(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date,
          description, is_completed)
         VALUES (?, ?, ?, ?, 'Описание выбора', ?)''',
      [_uuid(number), _uuid(1), _uuid(longPath ? 3 : 2), date, completed],
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

  test('читает все даты и дубликаты по убыванию даты и создания', () async {
    addChoice(201, date: '2026-09-22');
    addChoice(202, completed: 1);
    addChoice(203);
    addChoice(204, date: '2026-09-24', longPath: true);
    addChoice(205);

    final ids = <String>[];
    DailyChoiceCatalogCursor? cursor;
    var reads = 0;
    do {
      final result = page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(pageSize: 2, cursor: cursor),
        ),
      );
      if (reads == 0) {
        expect((result as DailyChoiceCatalogFirstPage).totalCount, 5);
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

    expect(ids, [_uuid(204), _uuid(205), _uuid(203), _uuid(202), _uuid(201)]);
    expect(reads, 3);
    expect(
      page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(
            date: CalendarDate.fromParts(2026, 9, 23),
            isCompleted: true,
          ),
        ),
      ).items.single.id.toCanonicalString(),
      _uuid(202),
    );
    expect(
      (page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(isCompleted: false),
        ),
      ) as DailyChoiceCatalogFirstPage).totalCount,
      4,
    );
    expect(
      (page(
        await repository.getDailyChoiceCatalogPage(DailyChoiceCatalogQuery()),
      ) as DailyChoiceCatalogFirstPage).totalCount,
      5,
    );
  });

  test(
    'проверяет путь выбранной порции, не читая остальные пути и описания',
    () async {
      addChoice(201);
      addChoice(202, longPath: true);
      raw.execute(
        'DELETE FROM daily_choice_path_steps WHERE daily_choice_id = ?',
        [_uuid(201)],
      );
      probe.statements.clear();

      final first = page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(pageSize: 1),
        ),
      );
      expect(first.items.single.id.toCanonicalString(), _uuid(202));
      expect((first as DailyChoiceCatalogFirstPage).totalCount, 2);
      expect(
        probe.statements
            .where(
              (sql) =>
                  sql.contains('FROM daily_choices') && !sql.contains('COUNT('),
            )
            .every((sql) => sql.contains('LIMIT')),
        isTrue,
      );
      expect(
        probe.statements
            .where((sql) => sql.contains('FROM long_term_relations'))
            .every((sql) => !sql.contains('description')),
        isTrue,
      );
      expect(
        probe.statements
            .where((sql) => sql.contains('FROM intentions'))
            .every((sql) => !sql.contains('description')),
        isTrue,
      );
      expect(
        probe.statements.any(
          (sql) => sql.contains('SELECT id FROM intentions'),
        ),
        isTrue,
      );

      expect(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(pageSize: 1, cursor: first.nextCursor),
        ),
        isA<DailyChoiceCatalogPageError>().having(
          (result) => result.failure.category,
          'категория',
          GraphFailureCategory.corruption,
        ),
      );
    },
  );

  test('отклоняет чужой курсор, другую выборку и устаревшую ревизию', () async {
    addChoice(201);
    addChoice(202);
    final first = page(
      await repository.getDailyChoiceCatalogPage(
        DailyChoiceCatalogQuery(pageSize: 1),
      ),
    );
    final cursor = first.nextCursor;
    expect(cursor, isNotNull);
    for (final query in [
      DailyChoiceCatalogQuery(pageSize: 2, cursor: cursor),
      DailyChoiceCatalogQuery(pageSize: 1, isCompleted: true, cursor: cursor),
    ]) {
      expect(
        await repository.getDailyChoiceCatalogPage(query),
        isA<DailyChoiceCatalogPageError>().having(
          (result) => result.failure.category,
          'категория',
          GraphFailureCategory.validation,
        ),
      );
    }
    final other = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      diagnostics,
    );
    expect(
      await other.getDailyChoiceCatalogPage(
        DailyChoiceCatalogQuery(pageSize: 1, cursor: cursor),
      ),
      isA<DailyChoiceCatalogPageError>().having(
        (result) => result.failure.category,
        'категория',
        GraphFailureCategory.validation,
      ),
    );

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
        DailyChoiceCatalogQuery(pageSize: 1, cursor: cursor),
      ),
      isA<DailyChoiceCatalogPageError>().having(
        (result) => result.failure.category,
        'категория',
        GraphFailureCategory.conflict,
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
    'пустая выдача и верхняя граница порции сохраняют точное количество',
    () async {
      final empty = page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(pageSize: 100),
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
          DailyChoiceCatalogQuery(pageSize: 100),
        ),
      ) as DailyChoiceCatalogFirstPage;
      expect(first.items, hasLength(100));
      expect(first.totalCount, 101);
      final last = page(
        await repository.getDailyChoiceCatalogPage(
          DailyChoiceCatalogQuery(pageSize: 100, cursor: first.nextCursor),
        ),
      );
      expect(last.items.single.id.toCanonicalString(), _uuid(201));
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
      DailyChoiceCatalogQuery(pageSize: 2),
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

  test('проверяет длинный путь ограниченными пакетами ссылок', () async {
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
        DailyChoiceCatalogQuery(pageSize: 1),
      ),
    );
    expect(
      catalog.items.single.selected.id.toCanonicalString(),
      _uuid(length + 1),
    );
    expect(
      probe.statements
          .where((sql) => sql.contains('FROM long_term_relations'))
          .length,
      2,
    );
  });
}
