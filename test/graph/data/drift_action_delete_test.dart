import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/data/local/app_database.dart' hide Action;
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/encoded_diagnostics_log.dart';
import '../../support/graph_seed.dart';

ActionId _action(int number) =>
    (ActionId.decode(seedUuid(number)) as ActionIdDecodingSuccess).id;

void main() {
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late EncodedDiagnosticsLog diagnostics;

  setUp(() async {
    diagnostics = EncodedDiagnosticsLog();
    database = AppDatabase(openInMemoryLocalDatabase(setup: (db) => raw = db));
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 7),
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
      );
      seedAction(raw, id: seedUuid(12), path: [seedUuid(1), seedUuid(2)]);
    });
  });

  tearDown(() => database.close());

  List<Map<String, Object?>> rows(
    String sql, [
    List<Object?> parameters = const [],
  ]) => [
    for (final row in raw.select(sql, parameters)) Map<String, Object?>.of(row),
  ];

  test('удаляет действие вместе с путём, а намерения, связи и другие '
      'действия остаются', () async {
    final intentions = rows('SELECT * FROM intentions ORDER BY id');
    final relations = rows('SELECT * FROM long_term_relations ORDER BY id');
    final otherAction = rows('SELECT * FROM actions WHERE id = ?', [
      seedUuid(12),
    ]);
    final otherPath = rows(
      'SELECT * FROM action_path_items WHERE action_id = ? ORDER BY position',
      [seedUuid(12)],
    );

    final result = await repository.execute(DeleteAction(_action(11)));

    final confirmed =
        (result
                as GraphCommandSucceeded<
                  ActionCommandSuccess,
                  ActionCommandFailure
                >)
            .value;
    expect(confirmed.value, isA<ActionDeleted>());
    final change = confirmed.changes.single as ActionDeletedChange;
    expect(change.before.id, _action(11));
    expect(change.before.path.intentions.map((id) => id.toCanonicalString()), [
      seedUuid(1),
      seedUuid(2),
      seedUuid(3),
    ]);
    expect(change.after, isNull);
    expect(
      rows('SELECT id FROM actions WHERE id = ?', [seedUuid(11)]),
      isEmpty,
    );
    expect(
      rows('SELECT * FROM action_path_items WHERE action_id = ?', [
        seedUuid(11),
      ]),
      isEmpty,
    );
    expect(rows('SELECT * FROM intentions ORDER BY id'), intentions);
    expect(rows('SELECT * FROM long_term_relations ORDER BY id'), relations);
    expect(
      rows('SELECT * FROM actions WHERE id = ?', [seedUuid(12)]),
      otherAction,
    );
    expect(
      rows(
        'SELECT * FROM action_path_items WHERE action_id = ? ORDER BY position',
        [seedUuid(12)],
      ),
      otherPath,
    );
    expect(
      diagnostics.events.map((event) => (event['stage'], event['outcome'])),
      [
        ('validation', 'started'),
        ('validation', 'succeeded'),
        ('write', 'started'),
        ('write', 'succeeded'),
      ],
    );
    expect(diagnostics.events.map((event) => event['commandType']).toSet(), {
      'delete',
    });
  });

  test(
    'повторное удаление сообщает об отсутствии и ничего не восстанавливает',
    () async {
      await repository.execute(DeleteAction(_action(11)));

      final result = await repository.execute(DeleteAction(_action(11)));

      expect(
        (result as GraphCommandFailed).failure,
        isA<ActionNotFoundFailure>(),
      );
      expect(rows('SELECT id FROM actions'), [
        {'id': seedUuid(12)},
      ]);
    },
  );
}
