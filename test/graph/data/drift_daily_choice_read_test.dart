import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

DailyChoiceId _choiceId(int number) =>
    (DailyChoiceId.decode(_uuid(number)) as DailyChoiceIdDecodingSuccess).id;

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;
  late _ReadProbe probe;
  late InMemoryDiagnosticsSink diagnostics;

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
  });

  tearDown(() => database.close());

  void addIntention(
    int number, {
    String? title,
    int archived = 0,
    int ready = 0,
  }) {
    raw.execute(
      '''INSERT INTO intentions
         (id, title, description, is_action_ready, is_archived, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, 1, 1)''',
      [
        _uuid(number),
        title ?? 'Намерение $number',
        'Описание $number',
        ready,
        archived,
      ],
    );
  }

  void addRelation(
    int number,
    int source,
    int related, {
    String type = 'need',
    int archived = 0,
  }) {
    raw.execute(
      '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id, type, priority, description, is_archived)
         VALUES (?, ?, ?, ?, 2, ?, ?)''',
      [
        _uuid(number),
        _uuid(source),
        _uuid(related),
        type,
        'Связь $number',
        archived,
      ],
    );
  }

  void addChoice(
    int number,
    int source,
    int selected, {
    String? description = ' Выбор ',
  }) {
    raw.execute(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date, description, is_completed)
         VALUES (?, ?, ?, '2026-09-23', ?, 1)''',
      [_uuid(number), _uuid(source), _uuid(selected), description],
    );
  }

  void addStep(int number, int choice, int relation, [int? previous]) {
    raw.execute(
      '''INSERT INTO daily_choice_path_steps
         (id, daily_choice_id, long_term_relation_id, previous_step_id)
         VALUES (?, ?, ?, ?)''',
      [
        _uuid(number),
        _uuid(choice),
        _uuid(relation),
        previous == null ? null : _uuid(previous),
      ],
    );
  }

  test(
    'читает текущий многошаговый путь целиком и различает архив и готовность',
    () async {
      addIntention(1, archived: 1);
      addIntention(2, title: 'Переименованное намерение');
      addIntention(3, ready: 0);
      addRelation(101, 1, 2, archived: 1);
      addRelation(102, 2, 3, type: 'can');
      addChoice(201, 1, 3);
      addStep(301, 201, 101);
      addStep(302, 201, 102, 301);
      addChoice(202, 1, 3);
      addStep(303, 202, 101);

      final result = await repository.getDailyChoice(_choiceId(201));
      expect(result, isA<DailyChoiceReadSuccess>());
      expect(
        diagnostics.events
            .whereType<DailyChoiceReadDiagnosticsEvent>()
            .last
            .status,
        isA<DiagnosticsSucceeded>(),
      );
      final details = (result as DailyChoiceReadSuccess).value.value!;
      expect(details.choice.description!.value, ' Выбор ');
      expect(details.choice.isCompleted, isTrue);
      expect(details.source.archiveState, IntentionArchiveState.archived);
      expect(details.selected.readiness, IntentionReadiness.notReady);
      expect(details.path, hasLength(2));
      expect(details.path.map((step) => step.relation.type), [
        LongTermRelationType.need,
        LongTermRelationType.can,
      ]);
      expect(details.path.first.related.title, 'Переименованное намерение');
      expect(details.path.first.relation.scope, RelationScope.archived);
      expect(details.path.first.relation.priority, RelationPriority.p2);
      expect(details.path.last.related.id, details.selected.id);
      expect(() => details.path.clear(), throwsUnsupportedError);

      raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
        'Новое название',
        _uuid(2),
      ]);
      raw.execute(
        'UPDATE long_term_relations SET description = ? WHERE id = ?',
        ['Новое описание перехода', _uuid(101)],
      );
      final refreshed = await repository.getDailyChoice(_choiceId(201));
      final refreshedPath =
          (refreshed as DailyChoiceReadSuccess).value.value!.path;
      expect(refreshedPath.first.related.title, 'Новое название');
      expect(refreshedPath.first.description!.value, 'Новое описание перехода');
    },
  );

  test('отсутствие выбора отличается от повреждения', () async {
    final absent = await repository.getDailyChoice(_choiceId(201));
    expect((absent as DailyChoiceReadSuccess).value.value, isNull);

    addIntention(1);
    addIntention(2);
    addRelation(101, 1, 2);
    addChoice(201, 1, 2);
    expect(
      await repository.getDailyChoice(_choiceId(201)),
      isA<DailyChoiceReadError>().having(
        (value) => value.failure.category,
        'категория',
        GraphFailureCategory.corruption,
      ),
    );
    expect(
      (diagnostics.events
                  .whereType<DailyChoiceReadDiagnosticsEvent>()
                  .last
                  .status
              as DiagnosticsFailed)
          .code,
      DiagnosticsFailureCode.corruption,
    );
  });

  test('различает временную недоступность и неизвестный отказ', () async {
    probe.failure = sqlite.SqliteException(
      extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
      message: 'занято',
    );
    expect(
      await repository.getDailyChoice(_choiceId(201)),
      isA<DailyChoiceReadError>().having(
        (value) => value.failure.category,
        'категория',
        GraphFailureCategory.unavailable,
      ),
    );
    expect(
      (diagnostics.events
                  .whereType<DailyChoiceReadDiagnosticsEvent>()
                  .last
                  .status
              as DiagnosticsFailed)
          .code,
      DiagnosticsFailureCode.unavailable,
    );
    probe.failure = StateError('неизвестный отказ');
    expect(
      await repository.getDailyChoice(_choiceId(201)),
      isA<DailyChoiceReadError>().having(
        (value) => value.failure.category,
        'категория',
        GraphFailureCategory.unexpected,
      ),
    );
    expect(
      (diagnostics.events
                  .whereType<DailyChoiceReadDiagnosticsEvent>()
                  .last
                  .status
              as DiagnosticsFailed)
          .code,
      DiagnosticsFailureCode.unexpected,
    );
  });

  test('отклоняет повреждённые поля и отсутствующую связь', () async {
    addIntention(1);
    addIntention(2);
    addRelation(101, 1, 2);
    addChoice(201, 1, 2);
    addStep(301, 201, 101);
    Future<void> expectCorruption() async {
      expect(
        await repository.getDailyChoice(_choiceId(201)),
        isA<DailyChoiceReadError>().having(
          (value) => value.failure.category,
          'категория',
          GraphFailureCategory.corruption,
        ),
      );
    }

    raw.execute('PRAGMA ignore_check_constraints = ON');
    raw.execute(
      "UPDATE daily_choices SET choice_date = '2026-02-30' WHERE id = ?",
      [_uuid(201)],
    );
    await expectCorruption();
    raw.execute(
      "UPDATE daily_choices SET choice_date = '2026-09-23', description = ' ' WHERE id = ?",
      [_uuid(201)],
    );
    await expectCorruption();
    raw.execute(
      "UPDATE daily_choices SET description = 'Описание', is_completed = 2 WHERE id = ?",
      [_uuid(201)],
    );
    await expectCorruption();
    raw.execute('UPDATE daily_choices SET is_completed = 1 WHERE id = ?', [
      _uuid(201),
    ]);
    raw.execute('PRAGMA foreign_keys = OFF');
    raw.execute(
      'UPDATE daily_choice_path_steps SET long_term_relation_id = ? WHERE id = ?',
      [_uuid(999), _uuid(301)],
    );
    await expectCorruption();
  });

  test(
    'отклоняет повреждённые текущие данные участников и переходов',
    () async {
      addIntention(1);
      addIntention(2);
      addRelation(101, 1, 2);
      addChoice(201, 1, 2);
      addStep(301, 201, 101);
      Future<void> expectCorruption() async {
        expect(
          await repository.getDailyChoice(_choiceId(201)),
          isA<DailyChoiceReadError>().having(
            (value) => value.failure.category,
            'категория',
            GraphFailureCategory.corruption,
          ),
        );
      }

      raw.execute('PRAGMA ignore_check_constraints = ON');
      raw.execute('UPDATE long_term_relations SET priority = 5 WHERE id = ?', [
        _uuid(101),
      ]);
      await expectCorruption();
      raw.execute('UPDATE long_term_relations SET priority = 2 WHERE id = ?', [
        _uuid(101),
      ]);
      raw.execute("UPDATE intentions SET title = '' WHERE id = ?", [_uuid(2)]);
      await expectCorruption();
    },
  );

  test('отклоняет цикл и постороннюю цепочку того же владельца', () async {
    for (var i = 1; i <= 4; i++) {
      addIntention(i);
    }
    addRelation(101, 1, 2);
    addRelation(102, 3, 4);
    addRelation(103, 4, 3);
    addChoice(201, 1, 2);
    addStep(301, 201, 101);
    raw.execute('BEGIN');
    addStep(302, 201, 102, 303);
    addStep(303, 201, 103, 302);
    raw.execute('COMMIT');
    expect(
      await repository.getDailyChoice(_choiceId(201)),
      isA<DailyChoiceReadError>().having(
        (value) => value.failure.category,
        'категория',
        GraphFailureCategory.corruption,
      ),
    );
  });

  test(
    'отклоняет ветвление и чужой шаг как повреждение целого выбора',
    () async {
      for (var i = 1; i <= 4; i++) {
        addIntention(i);
      }
      addRelation(101, 1, 2);
      addRelation(102, 2, 3);
      addRelation(103, 2, 4);
      addChoice(201, 1, 3);
      addStep(301, 201, 101);
      addStep(302, 201, 102, 301);
      raw.execute('DROP INDEX daily_choice_path_steps_one_successor');
      addStep(303, 201, 103, 301);
      expect(
        await repository.getDailyChoice(_choiceId(201)),
        isA<DailyChoiceReadError>().having(
          (value) => value.failure.category,
          'категория',
          GraphFailureCategory.corruption,
        ),
      );

      raw.execute('DELETE FROM daily_choice_path_steps WHERE id = ?', [
        _uuid(303),
      ]);
      addChoice(202, 1, 4);
      addStep(304, 202, 101);
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute(
        'UPDATE daily_choice_path_steps SET previous_step_id = ? WHERE id = ?',
        [_uuid(304), _uuid(302)],
      );
      expect(
        await repository.getDailyChoice(_choiceId(201)),
        isA<DailyChoiceReadError>().having(
          (value) => value.failure.category,
          'категория',
          GraphFailureCategory.corruption,
        ),
      );
    },
  );

  test(
    'читает длинный путь порциями и не загружает посторонние выборы',
    () async {
      const length = 405;
      for (var i = 1; i <= length + 1; i++) {
        addIntention(i);
      }
      addChoice(2000, 1, length + 1);
      for (var i = 1; i <= length; i++) {
        addRelation(3000 + i, i, i + 1);
        addStep(4000 + i, 2000, 3000 + i, i == 1 ? null : 3999 + i);
      }
      addChoice(2001, 1, 2);
      addStep(5000, 2001, 3001);
      probe.selects.clear();

      final result = await repository.getDailyChoice(_choiceId(2000));
      expect(result, isA<DailyChoiceReadSuccess>());
      expect(
        (result as DailyChoiceReadSuccess).value.value!.path,
        hasLength(length),
      );
      final reads = probe.selects;
      expect(reads.length, lessThanOrEqualTo(7));
      expect(
        reads
            .where(
              (statement) => statement.statements.single.contains(
                'FROM daily_choices WHERE id = ?',
              ),
            )
            .single
            .arguments,
        [_uuid(2000)],
      );
      expect(
        reads
            .where(
              (statement) => statement.statements.single.contains(
                'FROM daily_choice_path_steps WHERE daily_choice_id = ?',
              ),
            )
            .single
            .arguments,
        [_uuid(2000)],
      );
      expect(
        reads.every((statement) => statement.arguments.length <= 400),
        isTrue,
      );
    },
  );

  test(
    'отклоняет разрыв, лишний шаг и повтор намерения без частичного пути',
    () async {
      for (var i = 1; i <= 4; i++) {
        addIntention(i);
      }
      addRelation(101, 1, 2);
      addRelation(102, 2, 3);
      addRelation(103, 3, 2);
      addRelation(104, 3, 4);
      addChoice(201, 1, 4);
      addStep(301, 201, 101);
      addStep(302, 201, 104, 301);
      Future<void> expectCorruption() async {
        final result = await repository.getDailyChoice(_choiceId(201));
        expect(
          result,
          isA<DailyChoiceReadError>().having(
            (value) => value.failure.category,
            'категория',
            GraphFailureCategory.corruption,
          ),
        );
      }

      await expectCorruption();
      raw.execute(
        'UPDATE daily_choice_path_steps SET long_term_relation_id = ? WHERE id = ?',
        [_uuid(102), _uuid(302)],
      );
      addStep(303, 201, 103, 302);
      await expectCorruption();
      raw.execute('DELETE FROM daily_choice_path_steps WHERE id = ?', [
        _uuid(303),
      ]);
      addStep(303, 201, 104, 302);
      final valid = await repository.getDailyChoice(_choiceId(201));
      expect(valid, isA<DailyChoiceReadSuccess>());
    },
  );
}

final class _ReadProbe extends LocalDatabaseConnectionObserver {
  Object? failure;
  final selects = <LocalDatabaseSqlStatement>[];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    if (statement.statements.single.contains(
      'FROM daily_choices WHERE id = ?',
    )) {
      final error = failure;
      if (error != null) throw error;
    }
    selects.add(statement);
  }
}
