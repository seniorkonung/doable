import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

TagId _tagId(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

final class _WriteProbe extends LocalDatabaseConnectionObserver {
  final statements = <String>[];
  bool failAfterAssignmentWrite = false;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    statements.addAll(statement.statements);
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (failAfterAssignmentWrite &&
        (statement.operation == LocalDatabaseSqlOperation.insert ||
            statement.operation == LocalDatabaseSqlOperation.delete) &&
        statement.statements.any((sql) => sql.contains('tag_assignments'))) {
      failAfterAssignmentWrite = false;
      throw StateError('Управляемый отказ после записи назначения.');
    }
  }
}

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;
  late _WriteProbe probe;

  setUp(() async {
    probe = _WriteProbe();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        probe,
      ),
    );
    await database.open();
    seedTagStorageFixture(raw);
    raw.execute(
      'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
      [tagFixtureId(4), 'Намерение без готовности', 104, 204],
    );
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      InMemoryDiagnosticsSink(),
    );
  });
  tearDown(() => database.close());

  Future<GraphRevision> revision() async => (await repository.getCatalogPage(
    IntentionCatalogQuery(
      scope: IntentionScope.all,
      titleFilter: null,
      order: IntentionCatalogOrder.createdAtAscending,
      pageSize: 1,
    ),
  ) as ResultSuccess<IntentionCatalogPage>).value.revision;

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
      table: raw
          .select('SELECT * FROM $table ORDER BY rowid')
          .map((row) => row.values.toList())
          .toList(),
  };

  List<sqlite.Row> assignment(int tag, IntentionId intentionId) => raw.select(
    'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
    [tagFixtureId(tag), intentionId.toCanonicalString()],
  );

  for (final (description, intentionId) in [
    ('активного действия', _intention(1)),
    ('архивированного действия', _intention(2)),
    ('намерения без готовности', _intention(4)),
  ]) {
    test(
      'назначение и снятие $description меняют только одну пару и одну ревизию',
      () async {
        final tag = _tagId(lastTagNumber);
        final before = graph();
        final firstRevision = await revision();
        probe.statements.clear();

        final assigned = await repository.execute(
          AssignTag(tagId: tag, intentionId: intentionId),
        );
        expect(assigned, isA<TagCommandSucceeded>());
        final assignmentResult = (assigned as TagCommandSucceeded).value;
        expect(assignmentResult.value, isA<TagAssignmentChanged>());
        expect(
          (assignmentResult.value as TagAssignmentChanged).state,
          TagAssignmentState.assigned,
        );
        expect(assignmentResult.changes, [
          isA<TagAssignmentChangedChange>(),
          isA<IntentionCatalogUpdated>(),
        ]);
        expect(
          (assignmentResult.value as TagAssignmentChanged)
              .assignment
              .intentionId,
          intentionId,
        );
        expect(
          (assignmentResult.value as TagAssignmentChanged).assignment.tagId,
          tag,
        );
        expect(
          assignmentResult.revision.compareTo(firstRevision),
          GraphRevisionOrder.newer,
        );
        expect(assignment(lastTagNumber, intentionId), hasLength(1));
        expect(
          probe.statements.where(
            (sql) =>
                sql.contains('INSERT INTO') && sql.contains('tag_assignments'),
          ),
          hasLength(1),
        );
        expect(
          {
            for (final entry in graph().entries)
              if (entry.key != 'tag_assignments') entry.key: entry.value,
          },
          {
            for (final entry in before.entries)
              if (entry.key != 'tag_assignments') entry.key: entry.value,
          },
        );

        final sequence =
            assignment(lastTagNumber, intentionId).single['creation_sequence']
                as int;
        probe.statements.clear();
        final repeated = await repository.execute(
          AssignTag(tagId: tag, intentionId: intentionId),
        );
        expect(
          (repeated as TagCommandSucceeded).value.value,
          isA<TagAssignmentUnchanged>(),
        );
        expect(
          repeated.value.revision.compareTo(assignmentResult.revision),
          GraphRevisionOrder.same,
        );
        expect(
          assignment(lastTagNumber, intentionId).single['creation_sequence'],
          sequence,
        );
        expect(
          probe.statements.where(
            (sql) =>
                sql.contains('INSERT INTO') && sql.contains('tag_assignments'),
          ),
          isEmpty,
        );

        final removed = await repository.execute(
          RemoveTagAssignment(tagId: tag, intentionId: intentionId),
        );
        expect(
          (removed as TagCommandSucceeded).value.value,
          isA<TagAssignmentChanged>(),
        );
        expect(
          (removed.value.value as TagAssignmentChanged).state,
          TagAssignmentState.absent,
        );
        expect(
          removed.value.revision.compareTo(repeated.value.revision),
          GraphRevisionOrder.newer,
        );
        expect(assignment(lastTagNumber, intentionId), isEmpty);

        probe.statements.clear();
        final repeatedRemoval = await repository.execute(
          RemoveTagAssignment(tagId: tag, intentionId: intentionId),
        );
        expect(
          (repeatedRemoval as TagCommandSucceeded).value.value,
          isA<TagAssignmentUnchanged>(),
        );
        expect(
          repeatedRemoval.value.revision.compareTo(removed.value.revision),
          GraphRevisionOrder.same,
        );
        expect(
          probe.statements.where(
            (sql) =>
                sql.contains('DELETE FROM') && sql.contains('tag_assignments'),
          ),
          isEmpty,
        );

        final reassigned = await repository.execute(
          AssignTag(tagId: tag, intentionId: intentionId),
        );
        expect(
          (reassigned as TagCommandSucceeded).value.value,
          isA<TagAssignmentChanged>(),
        );
        expect(
          assignment(lastTagNumber, intentionId).single['creation_sequence'],
          greaterThan(sequence),
        );
        expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      },
    );
  }

  test(
    'снятие последнего назначения сохраняет тег для нового назначения',
    () async {
      final tagId = _tagId(firstTagNumber);
      for (final number in [1, 2]) {
        final result = await repository.execute(
          RemoveTagAssignment(tagId: tagId, intentionId: _intention(number)),
        );
        expect(
          (result as TagCommandSucceeded).value.value,
          isA<TagAssignmentChanged>(),
        );
      }
      expect(
        raw.select('SELECT 1 FROM tag_assignments WHERE tag_id = ?', [
          tagFixtureId(firstTagNumber),
        ]),
        isEmpty,
      );
      expect(
        raw.select('SELECT name FROM tags WHERE id = ?', [
          tagFixtureId(firstTagNumber),
        ]).single['name'],
        'Дом',
      );

      final result = await repository.execute(
        AssignTag(tagId: tagId, intentionId: _intention(4)),
      );
      expect(
        (result as TagCommandSucceeded).value.value,
        isA<TagAssignmentChanged>(),
      );
      expect(assignment(firstTagNumber, _intention(4)), hasLength(1));
      expect(
        raw
            .select('SELECT tag_id, intention_id FROM tag_assignments')
            .map((row) => row.values.toList()),
        [
          [tagFixtureId(lastTagNumber), tagFixtureId(3)],
          [tagFixtureId(firstTagNumber), tagFixtureId(4)],
        ],
      );
    },
  );

  test('отсутствие обеих идентичностей проверяется даже при повторе', () async {
    final existingTag = _tagId(firstTagNumber);
    final missingTag = _tagId(999);
    final existingIntentionId = _intention(2);
    final missingIntentionId = _intention(999);
    final before = graph();
    final beforeRevision = await revision();

    for (final command in [
      AssignTag(tagId: missingTag, intentionId: existingIntentionId),
      RemoveTagAssignment(tagId: missingTag, intentionId: existingIntentionId),
    ]) {
      final failed = await repository.execute(command);
      expect((failed as TagCommandFailed).failure, isA<TagNotFoundFailure>());
      expect((failed.failure as TagNotFoundFailure).tagId, missingTag);
    }
    for (final command in [
      AssignTag(tagId: existingTag, intentionId: missingIntentionId),
      RemoveTagAssignment(tagId: existingTag, intentionId: missingIntentionId),
    ]) {
      final failed = await repository.execute(command);
      expect(
        (failed as TagCommandFailed).failure,
        isA<TagIntentionNotFoundFailure>(),
      );
      expect(
        (failed.failure as TagIntentionNotFoundFailure).intentionId,
        missingIntentionId,
      );
    }
    expect(graph(), before);
    expect(
      (await revision()).compareTo(beforeRevision),
      GraphRevisionOrder.same,
    );
  });

  test('удалённый тег не подменяется новым одноимённым тегом', () async {
    final oldId = _tagId(firstTagNumber);
    final intentionId = _intention(2);
    raw.execute('DELETE FROM tags WHERE id = ?', [
      tagFixtureId(firstTagNumber),
    ]);
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(999),
      'Дом',
    ]);
    final before = graph();
    final beforeRevision = await revision();

    for (final command in [
      AssignTag(tagId: oldId, intentionId: intentionId),
      RemoveTagAssignment(tagId: oldId, intentionId: intentionId),
    ]) {
      final result = await repository.execute(command);
      expect((result as TagCommandFailed).failure, isA<TagNotFoundFailure>());
    }
    expect(graph(), before);
    expect(
      (await revision()).compareTo(beforeRevision),
      GraphRevisionOrder.same,
    );
    expect(assignment(999, intentionId), isEmpty);
  });

  test(
    'самостоятельный жизненный цикл тега сохраняет прежние назначения и граф',
    () async {
      final before = graph();
      final created = await repository.execute(
        CreateTag(TagName.fromInput('Новый тег')),
      ) as TagCommandSucceeded;
      final tagId = (created.value.value as TagCreated).tag.id;
      expect(
        raw.select('SELECT 1 FROM tag_assignments WHERE tag_id = ?', [
          tagId.toCanonicalString(),
        ]),
        isEmpty,
      );

      final conflict = await repository.execute(
        RenameTag(tagId: tagId, name: TagName.fromInput('Дом')),
      ) as TagCommandFailed;
      expect(conflict.failure, isA<TagNameOccupiedFailure>());
      expect(
        (await revision()).compareTo(created.value.revision),
        GraphRevisionOrder.same,
      );

      final renamed = await repository.execute(
        RenameTag(tagId: tagId, name: TagName.fromInput('Новое название')),
      ) as TagCommandSucceeded;
      expect((renamed.value.value as TagRenamed).after.id, tagId);
      final repeatedRename = await repository.execute(
        RenameTag(tagId: tagId, name: TagName.fromInput('Новое название')),
      ) as TagCommandSucceeded;
      expect(repeatedRename.value.value, isA<TagUnchanged>());
      expect(
        repeatedRename.value.revision.compareTo(renamed.value.revision),
        GraphRevisionOrder.same,
      );

      final assigned = await repository.execute(
        AssignTag(tagId: tagId, intentionId: _intention(4)),
      ) as TagCommandSucceeded;
      final deleted =
          await repository.execute(DeleteTag(tagId)) as TagCommandSucceeded;
      expect(deleted.value.value, isA<TagDeleted>());
      expect(
        deleted.value.revision.compareTo(assigned.value.revision),
        GraphRevisionOrder.newer,
      );
      expect(graph(), before);
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'отказ после записи откатывает назначение и снятие вместе с ревизией',
    () async {
      final tag = _tagId(lastTagNumber);
      final intentionId = _intention(2);
      final before = graph();
      final firstRevision = await revision();

      probe.failAfterAssignmentWrite = true;
      final failedAssign = await repository.execute(
        AssignTag(tagId: tag, intentionId: intentionId),
      );
      expect(
        (failedAssign as TagCommandFailed).failure,
        isA<TagUnexpectedFailure>(),
      );
      expect(graph(), before);
      expect(
        (await revision()).compareTo(firstRevision),
        GraphRevisionOrder.same,
      );

      final assigned = await repository.execute(
        AssignTag(tagId: tag, intentionId: intentionId),
      );
      expect(assigned, isA<TagCommandSucceeded>());
      final assignedGraph = graph();
      final assignedRevision = await revision();
      probe.failAfterAssignmentWrite = true;
      final failedRemove = await repository.execute(
        RemoveTagAssignment(tagId: tag, intentionId: intentionId),
      );
      expect(
        (failedRemove as TagCommandFailed).failure,
        isA<TagUnexpectedFailure>(),
      );
      expect(graph(), assignedGraph);
      expect(
        (await revision()).compareTo(assignedRevision),
        GraphRevisionOrder.same,
      );
    },
  );
}
