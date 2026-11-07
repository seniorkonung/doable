import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';

import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/encoded_diagnostics_log.dart';
import '../../support/graph_seed.dart';

final class _PathWriteFailure extends LocalDatabaseConnectionObserver {
  bool enabled = false;
  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (enabled &&
        statement.statements.any(
          (sql) => sql.contains('INSERT INTO action_path_items'),
        )) {
      throw StateError('Сбой записи');
    }
  }
}

void main() {
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late _PathWriteFailure failure;
  late EncodedDiagnosticsLog diagnostics;
  final now = DateTime.utc(2026, 10, 7);

  setUp(() async {
    failure = _PathWriteFailure();
    diagnostics = EncodedDiagnosticsLog();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        failure,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now,
      diagnostics,
    );
    seedRawGraph(raw, () {
      seedIntention(raw, seedUuid(1), 'Первое');
      seedIntention(raw, seedUuid(2), 'Второе');
      seedIntention(raw, seedUuid(3), 'Третье');
      seedRelation(raw, seedUuid(4), seedUuid(1), seedUuid(2));
      seedRelation(raw, seedUuid(5), seedUuid(2), seedUuid(3));
      raw.execute("UPDATE long_term_relations SET type = 'can' WHERE id = ?", [
        seedUuid(5),
      ]);
    });
  });
  tearDown(() => database.close());

  CreateAction command(List<int> path) => CreateAction(
    title: ActionTitle('Пробежка'),
    description: ActionDescription.fromInput('Утром'),
    path: ActionPath(path.map(seedIntentionId)),
    date: CalendarDate.fromParts(2026, 10, 8),
    schedule: ActionAtHour(18),
    priority: ActionPriority.p2,
  );

  test('создаёт действие и полный путь одной подтверждённой записью', () async {
    final result = await repository.execute(command([1, 2, 3]));
    final confirmed =
        (result
                as GraphCommandSucceeded<
                  ActionCommandSuccess,
                  ActionCommandFailure
                >)
            .value;
    final change = confirmed.changes.single as ActionCreatedChange;
    final action = change.after;
    expect(change.before, isNull);
    expect(action.path.intentions, [
      seedIntentionId(1),
      seedIntentionId(2),
      seedIntentionId(3),
    ]);
    expect(action.createdAt.value, now);
    expect(action.updatedAt, action.createdAt);
    expect(action.isCompleted, isFalse);
    expect(action.title, ActionTitle('Пробежка'));
    expect(action.description, ActionDescription.fromInput('Утром'));
    expect(action.date, CalendarDate.fromParts(2026, 10, 8));
    expect(action.schedule, ActionAtHour(18));
    expect(action.priority, ActionPriority.p2);
    final package =
        (await database.select(database.graphLogPackages).get()).single;
    final facts = GraphFormatCodec.decodePackage(
      package.facts!,
      GraphFormatVersion.ofCarrier(package.formatVersion!),
    );
    expect(facts, hasLength(1));
    final record = (facts.single as GraphEntityCreated).record as ActionRecord;
    expect(record.id, action.id);
    expect(record.path.intentions, action.path.intentions);
    expect(diagnostics.events.map((event) => event['commandType']).toSet(), {
      'create',
    });
    expect(
      raw
          .select(
            'SELECT role, order_date, order_hour, order_sequence FROM action_path_items ORDER BY position',
          )
          .map((r) => r.values.toList())
          .toList(),
      [
        ['root', '2026-10-08', 18, action.creationSequence.value],
        ['intermediate', '2026-10-08', 18, action.creationSequence.value],
        ['terminal', '2026-10-08', 18, action.creationSequence.value],
      ],
    );
  });

  test('сбой записи пути откатывает действие и факт', () async {
    failure.enabled = true;
    final result = await repository.execute(command([1, 2]));
    expect(
      (result as GraphCommandFailed<ActionCommandSuccess, ActionCommandFailure>)
          .failure,
      isA<ActionUnexpectedFailure>(),
    );
    expect(raw.select('SELECT * FROM actions'), isEmpty);
    expect(raw.select('SELECT * FROM action_path_items'), isEmpty);
    expect(raw.select('SELECT * FROM graph_log_packages'), isEmpty);
    expect(diagnostics.events.last['stage'], 'write');
    expect(diagnostics.events.last['outcome'], 'failed');
  });

  test('одинаковые данные создают отдельные действия', () async {
    final first =
        (await repository.execute(command([1]))
                    as GraphCommandSucceeded<
                      ActionCommandSuccess,
                      ActionCommandFailure
                    >)
                .value
                .value
            as ActionCreated;
    final second =
        (await repository.execute(command([1]))
                    as GraphCommandSucceeded<
                      ActionCommandSuccess,
                      ActionCommandFailure
                    >)
                .value
                .value
            as ActionCreated;
    expect(first.action.id, isNot(second.action.id));
    expect(raw.select('SELECT * FROM actions'), hasLength(2));
  });

  test('путь из одного намерения сохраняет единственную роль', () async {
    final result = await repository.execute(command([1]));
    expect(
      result,
      isA<GraphCommandSucceeded<ActionCommandSuccess, ActionCommandFailure>>(),
    );
    expect(
      raw.select('SELECT role FROM action_path_items').single['role'],
      'single',
    );
  });

  test('архивная связь или отсутствующее намерение отклоняются', () async {
    seedRawGraph(
      raw,
      () => raw.execute('UPDATE long_term_relations SET is_archived = 1'),
    );
    for (final path in [
      [1, 2],
      [1, 9],
    ]) {
      final result = await repository.execute(command(path));
      expect(
        (result
                as GraphCommandFailed<
                  ActionCommandSuccess,
                  ActionCommandFailure
                >)
            .failure,
        isA<ActionPathConflictFailure>(),
      );
    }
    expect(raw.select('SELECT * FROM actions'), isEmpty);
    expect(diagnostics.events.last['stage'], 'validation');
    expect(diagnostics.events.last['failureCode'], 'conflict');
  });

  test('архивное намерение отклоняется', () async {
    seedRawGraph(raw, () {
      raw.execute('UPDATE long_term_relations SET is_archived = 1');
      raw.execute('UPDATE intentions SET is_archived = 1 WHERE id = ?', [
        seedUuid(2),
      ]);
    });
    final result = await repository.execute(command([2]));
    expect(
      (result as GraphCommandFailed<ActionCommandSuccess, ActionCommandFailure>)
          .failure,
      isA<ActionPathConflictFailure>(),
    );
    expect(raw.select('SELECT * FROM actions'), isEmpty);
  });

  test('разрыв пути отклоняется без записи действия', () async {
    final result = await repository.execute(command([2, 1]));
    expect(
      (result as GraphCommandFailed<ActionCommandSuccess, ActionCommandFailure>)
          .failure,
      isA<ActionPathConflictFailure>(),
    );
    expect(raw.select('SELECT * FROM actions'), isEmpty);
  });
}
