import 'dart:convert';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/data/local/app_database.dart' hide Action;
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/encoded_diagnostics_log.dart';
import '../../support/graph_seed.dart';

ActionId _action(int number) =>
    (ActionId.decode(seedUuid(number)) as ActionIdDecodingSuccess).id;

/// Отказывает записи строки действия, пока включён.
final class _ActionWriteFailure extends LocalDatabaseConnectionObserver {
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    final error = failure;
    if (error != null &&
        statement.operation == LocalDatabaseSqlOperation.update &&
        statement.statements.single.contains('"actions"')) {
      throw error;
    }
  }
}

void main() {
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late EncodedDiagnosticsLog diagnostics;
  late _ActionWriteFailure writeFailure;
  final changedAt = DateTime.utc(2026, 10, 7, 12);

  setUp(() async {
    writeFailure = _ActionWriteFailure();
    diagnostics = EncodedDiagnosticsLog();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        writeFailure,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => changedAt,
      diagnostics,
    );
    seedRawGraph(raw, () {
      for (var number = 1; number <= 3; number++) {
        seedIntention(raw, seedUuid(number), 'Намерение $number');
      }
      seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
      seedRelation(raw, seedUuid(102), seedUuid(2), seedUuid(3));
      seedAction(
        raw,
        id: seedUuid(11),
        path: [seedUuid(1), seedUuid(2), seedUuid(3)],
        description: 'Утром',
        hour: 18,
        priority: 2,
      );
      seedAction(raw, id: seedUuid(12), path: [seedUuid(1)]);
    });
  });

  tearDown(() => database.close());

  Future<ConfirmedGraphResult<ActionCommandSuccess>> update(
    ActionFieldsPatch patch, {
    int number = 11,
  }) async {
    final result = await repository.execute(
      UpdateActionFields(actionId: _action(number), patch: patch),
    );
    return (result
            as GraphCommandSucceeded<
              ActionCommandSuccess,
              ActionCommandFailure
            >)
        .value;
  }

  List<Map<String, Object?>> rows(String table) => [
    for (final row in raw.select('SELECT * FROM $table ORDER BY 1, 2'))
      Map<String, Object?>.of(row),
  ];

  test(
    'меняет все поля одним изменением, обновляет только время изменения '
    'и не трогает путь, кроме копии ключа порядка, намерения и связи',
    () async {
      final untouched = {
        for (final table in [
          'intentions',
          'long_term_relations',
          'action_path_items',
        ])
          table: rows(table),
      };
      final otherAction = raw.select('SELECT * FROM actions WHERE id = ?', [
        seedUuid(12),
      ]).single;
      final sequence = raw.select(
        'SELECT creation_sequence FROM actions WHERE id = ?',
        [seedUuid(11)],
      ).single['creation_sequence'];

      final confirmed = await update(
        ActionFieldsPatch(
          title: ActionFieldSet(ActionTitle('Длинная пробежка')),
          description: const ActionFieldSet<ActionDescription?>(null),
          date: ActionFieldSet(CalendarDate.fromParts(2026, 10, 12)),
          schedule: const ActionFieldSet<ActionSchedule>(ActionAllDay()),
          priority: const ActionFieldSet(ActionPriority.p1),
          isCompleted: const ActionFieldSet(true),
        ),
      );

      expect(confirmed.value, isA<ActionFieldsUpdated>());
      final change = confirmed.changes.single as ActionUpdatedChange;
      expect(
        change.revision.compareTo(confirmed.revision),
        GraphRevisionOrder.same,
      );
      expect(change.before.title, ActionTitle('Пробежка'));
      expect(change.before.date, CalendarDate.fromParts(2026, 10, 8));
      expect(change.after.title, ActionTitle('Длинная пробежка'));
      expect(change.after.description, isNull);
      expect(change.after.date, CalendarDate.fromParts(2026, 10, 12));
      expect(change.after.schedule, const ActionAllDay());
      expect(change.after.priority, ActionPriority.p1);
      expect(change.after.isCompleted, isTrue);
      expect(change.after.path.intentions, change.before.path.intentions);
      expect(change.after.updatedAt.value, changedAt);
      expect(change.after.createdAt, change.before.createdAt);
      expect(
        raw.select('SELECT * FROM actions WHERE id = ?', [seedUuid(11)]).single,
        {
          'creation_sequence': sequence,
          'id': seedUuid(11),
          'title': 'Длинная пробежка',
          'description': null,
          'date': '2026-10-12',
          'scheduled_hour': null,
          'priority': 1,
          'is_completed': 1,
          'created_at': 1,
          'updated_at': changedAt.microsecondsSinceEpoch,
        },
      );
      expect(
        raw.select('SELECT * FROM actions WHERE id = ?', [seedUuid(12)]).single,
        otherAction,
      );
      for (final entry in untouched.entries) {
        expect(rows(entry.key), switch (entry.key) {
          // Строки пути меняют только копию ключа порядка вслед за датой
          // и часом действия.
          'action_path_items' => [
            for (final row in entry.value)
              row['action_id'] == seedUuid(11)
                  ? {...row, 'order_date': '2026-10-12', 'order_hour': -1}
                  : row,
          ],
          _ => entry.value,
        }, reason: entry.key);
      }
      expect(
        diagnostics.events.map((event) => (event['stage'], event['outcome'])),
        [
          ('validation', 'started'),
          ('validation', 'succeeded'),
          ('write', 'started'),
          ('write', 'succeeded'),
          ('resultRead', 'started'),
          ('resultRead', 'succeeded'),
        ],
      );
      expect(diagnostics.events.map((event) => event['commandType']).toSet(), {
        'updateFields',
      });
    },
  );

  test('пустая правка и прежние значения не меняют время изменения и не '
      'продвигают ревизию', () async {
    final first = await update(
      const ActionFieldsPatch(priority: ActionFieldSet(ActionPriority.p3)),
    );

    for (final patch in [
      const ActionFieldsPatch(),
      ActionFieldsPatch(
        title: ActionFieldSet(ActionTitle('Пробежка')),
        description: ActionFieldSet(ActionDescription.fromInput('Утром')),
        date: ActionFieldSet(CalendarDate.fromParts(2026, 10, 8)),
        schedule: ActionFieldSet(ActionAtHour(18)),
        priority: const ActionFieldSet(ActionPriority.p3),
        isCompleted: const ActionFieldSet(false),
      ),
    ]) {
      final confirmed = await update(patch);

      expect(
        confirmed.revision.compareTo(first.revision),
        GraphRevisionOrder.same,
      );
      final change = confirmed.changes.single as ActionUpdatedChange;
      expect(change.after.updatedAt, change.before.updatedAt);
      expect(
        raw.select('SELECT updated_at FROM actions WHERE id = ?', [
          seedUuid(11),
        ]).single['updated_at'],
        changedAt.microsecondsSinceEpoch,
      );
    }
  });

  test(
    'отсутствующее действие не создаётся и даёт отказ «не найдено»',
    () async {
      final result = await repository.execute(
        UpdateActionFields(
          actionId: _action(99),
          patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
        ),
      );

      expect(
        (result as GraphCommandFailed).failure,
        isA<ActionNotFoundFailure>(),
      );
      expect(raw.select('SELECT id FROM actions'), hasLength(2));
      expect(diagnostics.events.last, {
        'operation': 'actionCommand',
        'commandType': 'updateFields',
        'stage': 'validation',
        'outcome': 'failed',
        'failureCode': 'notFound',
      });
    },
  );

  test('повреждённое сохранённое название даёт отказ «повреждение» без '
      'записи', () async {
    seedRawGraph(
      raw,
      () => raw.execute('UPDATE actions SET title = ? WHERE id = ?', [
        '  Пробежка  ',
        seedUuid(11),
      ]),
    );

    final result = await repository.execute(
      UpdateActionFields(
        actionId: _action(11),
        patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
      ),
    );

    expect(
      (result as GraphCommandFailed).failure,
      isA<ActionCorruptionFailure>(),
    );
    expect(
      raw.select('SELECT is_completed FROM actions WHERE id = ?', [
        seedUuid(11),
      ]).single['is_completed'],
      0,
    );
  });

  for (final (error, failure, code) in <(Object, Type, String)>[
    (
      sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
        message: 'CANARY-ошибка',
        causingStatement: 'CANARY-запрос',
        parametersToStatement: ['CANARY-название'],
      ),
      ActionUnavailableFailure,
      'unavailable',
    ),
    (StateError('CANARY-причина'), ActionUnexpectedFailure, 'unexpected'),
  ]) {
    test('сбой записи ($code) откатывает изменение, не продвигает ревизию и '
        'не раскрывает данные в диагностике', () async {
      final before = await update(const ActionFieldsPatch());
      writeFailure.failure = error;

      final result = await repository.execute(
        UpdateActionFields(
          actionId: _action(11),
          patch: ActionFieldsPatch(
            title: ActionFieldSet(ActionTitle('CANARY-название')),
          ),
        ),
      );
      writeFailure.failure = null;

      expect((result as GraphCommandFailed).failure.runtimeType, failure);
      expect(
        raw.select('SELECT title FROM actions WHERE id = ?', [
          seedUuid(11),
        ]).single['title'],
        'Пробежка',
      );
      final after = await update(const ActionFieldsPatch());
      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.same,
      );
      final failed = diagnostics.events.singleWhere(
        (event) => event['outcome'] == 'failed',
      );
      expect(failed, {
        'operation': 'actionCommand',
        'commandType': 'updateFields',
        'stage': 'write',
        'outcome': 'failed',
        'failureCode': code,
      });
      expect(jsonEncode(diagnostics.events), isNot(contains('CANARY')));
    });
  }
}
