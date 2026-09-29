import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  tagFixtureId(number),
) as LongTermRelationIdDecodingSuccess).id;

TagId _tag(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase(setup: (db) => raw = db));
    await database.open();
    seedTagStorageFixture(raw);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 27),
      InMemoryDiagnosticsSink(),
    );
  });
  tearDown(() => database.close());

  void addIntention(int number, {bool archived = false}) {
    raw.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, 0, ?, 100, 200)',
      [tagFixtureId(number), 'Намерение $number', archived ? 1 : 0],
    );
  }

  void addRelation(int number, int source, int related) {
    raw.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority) VALUES (?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        tagFixtureId(source),
        tagFixtureId(related),
        'can',
        2,
      ],
    );
  }

  Future<void> assign(int tag, IntentionId intentionId) async {
    expect(
      await repository.execute(
        AssignTag(tagId: _tag(tag), intentionId: intentionId),
      ),
      isA<TagCommandSucceeded>(),
    );
  }

  List<List<Object?>> rows(String table) => raw
      .select('SELECT * FROM $table ORDER BY rowid')
      .map((row) => row.values.toList())
      .toList();

  Map<String, List<List<Object?>>> graph() => {
    for (final table in [
      'intentions',
      'intention_titles_fts',
      'long_term_relations',
      'daily_choices',
      'daily_choice_path_steps',
      'tags',
      'tag_assignments',
    ])
      table: rows(table),
  };

  List<Object?> assigned(int number) => raw
      .select(
        'SELECT tag_id FROM tag_assignments WHERE intention_id = ? ORDER BY creation_sequence',
        [tagFixtureId(number)],
      )
      .map((row) => row['tag_id'])
      .toList();

  Future<void> expectCompleteAssignments(IntentionId intentionId) async {
    final result = await repository.getTagAssignments(intentionId);
    final snapshot = (result as TagAssignmentsSuccess).value;
    expect(snapshot.intentionId, intentionId);
    expect(snapshot.items.map((tag) => tag.id), [
      _tag(firstTagNumber),
      _tag(lastTagNumber),
    ]);
  }

  Future<GraphRevision> revision(int intention) async =>
      (await repository.getRelationCounts(
        _intention(intention),
      ) as ResultSuccess<GraphSnapshot<RelationCounts>>).value.revision;

  test('удаление активного и архивного намерения снимает все назначения, сохраняя теги', () async {
    addIntention(4);
    addIntention(5, archived: true);
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(303),
      'Единственный',
    ]);
    await assign(firstTagNumber, _intention(4));
    await assign(lastTagNumber, _intention(4));
    await assign(303, _intention(5));
    final tagsBefore = rows('tags');
    final otherAssignments = [
      for (final id in [1, 2, 3]) assigned(id),
    ];
    final otherGraph = [
      rows('long_term_relations'),
      rows('daily_choices'),
      rows('daily_choice_path_steps'),
    ];

    await expectCompleteAssignments(_intention(4));
    expect(
      await repository.execute(DeleteIntention(_intention(4))),
      isA<ResultSuccess>(),
    );
    expect(
      raw.select('SELECT id FROM intentions WHERE id = ?', [tagFixtureId(4)]),
      isEmpty,
    );
    expect(assigned(4), isEmpty);
    expect([
      for (final id in [1, 2, 3]) assigned(id),
    ], otherAssignments);
    expect(assigned(5), [tagFixtureId(303)]);
    expect(rows('tags'), tagsBefore);
    expect([
      rows('long_term_relations'),
      rows('daily_choices'),
      rows('daily_choice_path_steps'),
    ], otherGraph);

    expect(
      await repository.execute(DeleteIntention(_intention(5))),
      isA<ResultSuccess>(),
    );
    expect(
      raw.select('SELECT id FROM intentions WHERE id = ?', [tagFixtureId(5)]),
      isEmpty,
    );
    expect(assigned(5), isEmpty);
    expect([
      for (final id in [1, 2, 3]) assigned(id),
    ], otherAssignments);
    expect(rows('tags'), tagsBefore);
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
    'удаление активной и архивной связи сохраняет все назначения намерениям',
    () async {
      addIntention(4);
      addRelation(103, 3, 4);
      await assign(firstTagNumber, _intention(3));
      await assign(firstTagNumber, _intention(4));
      await assign(lastTagNumber, _intention(4));
      await assign(lastTagNumber, _intention(2));
      final intentionsBefore = rows('intentions');
      final tagsBefore = rows('tags');
      final assignmentsBefore = rows('tag_assignments');
      final dailyChoicesBefore = rows('daily_choices');
      final pathBefore = rows('daily_choice_path_steps');

      await expectCompleteAssignments(_intention(4));
      expect(
        await repository.execute(DeleteLongTermRelation(_relation(103))),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        raw.select('SELECT id FROM long_term_relations WHERE id = ?', [
          tagFixtureId(103),
        ]),
        isEmpty,
      );
      expect(rows('tag_assignments'), assignmentsBefore);
      expect(rows('intentions'), intentionsBefore);
      expect(rows('tags'), tagsBefore);
      expect(rows('daily_choices'), dailyChoicesBefore);
      expect(rows('daily_choice_path_steps'), pathBefore);

      await expectCompleteAssignments(_intention(2));
      expect(
        await repository.execute(DeleteLongTermRelation(_relation(102))),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        raw.select('SELECT id FROM long_term_relations WHERE id = ?', [
          tagFixtureId(102),
        ]),
        isEmpty,
      );
      expect(rows('tags'), tagsBefore);
      expect(rows('tag_assignments'), assignmentsBefore);
      expect(rows('intentions'), intentionsBefore);
      expect(rows('daily_choices'), dailyChoicesBefore);
      expect(rows('daily_choice_path_steps'), pathBefore);
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'зависимости намерения и шаг пути блокируют удаление вместе с назначениями',
    () async {
      final before = graph();

      final active = await repository.execute(DeleteIntention(_intention(1)));
      expect(
        (active as ResultFailure).failure,
        isA<IntentionHasBlockingRelationsFailure>(),
      );
      expect(graph(), before);

      final archived = await repository.execute(DeleteIntention(_intention(2)));
      expect(
        (archived as ResultFailure).failure,
        isA<IntentionHasBlockingRelationsFailure>(),
      );
      expect(graph(), before);

      final relation = await repository.execute(
        DeleteLongTermRelation(_relation(101)),
      );
      expect(
        (relation as GraphCommandFailed).failure,
        isA<LongTermRelationReferencedByDailyPathFailure>(),
      );
      expect(graph(), before);
    },
  );

  test('новая зависимость после пустой проверки блокирует удаление в момент команды', () async {
    addIntention(4);
    await assign(firstTagNumber, _intention(4));
    expect(
      raw.select(
        'SELECT id FROM long_term_relations WHERE source_intention_id = ? OR related_intention_id = ?',
        [tagFixtureId(4), tagFixtureId(4)],
      ),
      isEmpty,
    );
    addRelation(103, 4, 3);
    final before = graph();

    final result = await repository.execute(DeleteIntention(_intention(4)));

    expect(
      (result as ResultFailure).failure,
      isA<IntentionHasBlockingRelationsFailure>(),
    );
    expect(graph(), before);
  });

  test(
    'отказ после начала каскада намерения откатывает получателя и назначения',
    () async {
      addIntention(4);
      await assign(firstTagNumber, _intention(4));
      await assign(lastTagNumber, _intention(4));
      final before = graph();
      final revisionBefore = await revision(4);
      await database.customStatement('''
      CREATE TEMP TRIGGER fail_intention_assignment_cascade
      AFTER DELETE ON tag_assignments
      WHEN OLD.intention_id = '${tagFixtureId(4)}'
      BEGIN
        SELECT RAISE(ABORT, 'canary intention assignment cascade');
      END
    ''');

      final result = await repository.execute(DeleteIntention(_intention(4)));

      expect(
        (result as ResultFailure).failure,
        isA<IntentionUnexpectedFailure>(),
      );
      expect(graph(), before);
      expect(
        (await revision(4)).compareTo(revisionBefore),
        GraphRevisionOrder.same,
      );
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test('отказ после удаления связи откатывает её и сохраняет назначения намерениям', () async {
    addIntention(4);
    addRelation(103, 3, 4);
    await assign(firstTagNumber, _intention(4));
    await assign(lastTagNumber, _intention(4));
    final before = graph();
    final revisionBefore = await revision(3);
    await database.customStatement('''
      CREATE TEMP TRIGGER fail_relation_delete
      AFTER DELETE ON long_term_relations
      WHEN OLD.id = '${tagFixtureId(103)}'
      BEGIN
        SELECT RAISE(ABORT, 'canary relation deletion');
      END
    ''');

    final result = await repository.execute(
      DeleteLongTermRelation(_relation(103)),
    );

    expect(
      (result as GraphCommandFailed).failure,
      isA<LongTermRelationUnexpectedFailure>(),
    );
    expect(graph(), before);
    expect(
      (await revision(3)).compareTo(revisionBefore),
      GraphRevisionOrder.same,
    );
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
  });
}
