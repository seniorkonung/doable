import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/encoded_diagnostics_log.dart';
import '../../support/graph_seed.dart';

final class _WriteFailure extends LocalDatabaseConnectionObserver {
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
  late _WriteFailure failure;
  late EncodedDiagnosticsLog diagnostics;
  final now = DateTime.utc(2026, 10, 9);

  setUp(() async {
    failure = _WriteFailure();
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
      for (var i = 1; i <= 3; i++) {
        seedIntention(raw, seedUuid(i), 'Намерение $i');
      }
      seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
      seedRelation(raw, seedUuid(102), seedUuid(2), seedUuid(3));
      seedAction(
        raw,
        id: seedUuid(11),
        path: [seedUuid(1), seedUuid(2)],
        description: 'Утром',
        hour: 18,
        priority: 2,
        isCompleted: true,
      );
    });
  });
  tearDown(() => database.close());

  SetActionPath command(List<int> path, {int id = 11}) => SetActionPath(
    actionId: seedActionId(id),
    path: ActionPath(path.map(seedIntentionId)),
  );
  List<List<Object?>> rows() => raw
      .select(
        'SELECT intention_id, previous_intention_id, role, order_date, order_hour, order_sequence FROM action_path_items ORDER BY position',
      )
      .map((r) => r.values.toList())
      .toList();

  test('замена сохраняет поля и публикует прежний и новый путь', () async {
    final initial = raw.select('SELECT * FROM actions').single;
    final result = await repository.execute(command([1, 2, 3]));
    final change =
        (result
                    as GraphCommandSucceeded<
                      ActionCommandSuccess,
                      ActionCommandFailure
                    >)
                .value
                .changes
                .single
            as ActionUpdatedChange;
    expect(change.before.path.intentions, [
      seedIntentionId(1),
      seedIntentionId(2),
    ]);
    expect(change.after.path.intentions, [
      seedIntentionId(1),
      seedIntentionId(2),
      seedIntentionId(3),
    ]);
    final updated = raw.select('SELECT * FROM actions').single;
    for (final key in initial.keys.where((key) => key != 'updated_at')) {
      expect(updated[key], initial[key], reason: key);
    }
    expect(updated['updated_at'], now.microsecondsSinceEpoch);
    expect(rows(), [
      [
        seedUuid(1),
        null,
        'root',
        '2026-10-08',
        18,
        initial['creation_sequence'],
      ],
      [
        seedUuid(2),
        seedUuid(1),
        'intermediate',
        '2026-10-08',
        18,
        initial['creation_sequence'],
      ],
      [
        seedUuid(3),
        seedUuid(2),
        'terminal',
        '2026-10-08',
        18,
        initial['creation_sequence'],
      ],
    ]);
    expect(diagnostics.events.map((e) => e['commandType']).toSet(), {
      'setPath',
    });
    final package =
        (await database.select(database.graphLogPackages).get()).single;
    final facts = GraphFormatCodec.decodePackage(
      package.facts!,
      GraphFormatVersion.ofCarrier(package.formatVersion!),
    );
    final record = (facts.single as GraphEntityChanged).record as ActionRecord;
    expect(record.path.intentions, change.after.path.intentions);
  });

  test('прежний путь не меняет время и ревизию', () async {
    final before = raw.select('SELECT * FROM actions').single;
    final result = await repository.execute(command([1, 2]));
    expect(
      result,
      isA<GraphCommandSucceeded<ActionCommandSuccess, ActionCommandFailure>>(),
    );
    expect(
      raw.select('SELECT * FROM actions').single['updated_at'],
      before['updated_at'],
    );
    expect(raw.select('SELECT * FROM graph_log_packages'), isEmpty);
  });

  test('сокращение до одного намерения сохраняет единственную роль', () async {
    final result = await repository.execute(command([2]));
    expect(
      result,
      isA<GraphCommandSucceeded<ActionCommandSuccess, ActionCommandFailure>>(),
    );
    expect(rows().single.take(3), [seedUuid(2), null, 'single']);
  });

  test('разрыв и отсутствие действия не меняют сохранённый путь', () async {
    final before = rows();
    for (final request in [
      command([2, 1]),
      command([1], id: 99),
    ]) {
      final result = await repository.execute(
        request,
      ) as GraphCommandFailed<ActionCommandSuccess, ActionCommandFailure>;
      expect(
        result.failure,
        request.actionId == seedActionId(99)
            ? isA<ActionNotFoundFailure>()
            : isA<ActionPathConflictFailure>(),
      );
      expect(rows(), before);
    }
    expect(raw.select('SELECT * FROM graph_log_packages'), isEmpty);
  });

  test(
    'сбой записи откатывает удаление прежнего пути и изменение времени',
    () async {
      final before = rows();
      failure.enabled = true;
      final result = await repository.execute(
        command([2, 3]),
      ) as GraphCommandFailed<ActionCommandSuccess, ActionCommandFailure>;
      expect(result.failure, isA<ActionUnexpectedFailure>());
      expect(rows(), before);
      expect(
        raw.select('SELECT updated_at FROM actions').single['updated_at'],
        1,
      );
      expect(raw.select('SELECT * FROM graph_log_packages'), isEmpty);
    },
  );
}
