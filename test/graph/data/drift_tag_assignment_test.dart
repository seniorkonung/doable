import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

TagId _tagId(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionTagTarget _intention(int number) => IntentionTagTarget(
  (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id,
);

LongTermRelationTagTarget _relation(int number) => LongTermRelationTagTarget(
  (LongTermRelationId.decode(
    tagFixtureId(number),
  ) as LongTermRelationIdDecodingSuccess).id,
);

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
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      InMemoryDiagnosticsSink(),
    );
  });
  tearDown(() => database.close());

  Future<GraphRevision> revision() async => (await repository.getTagCatalog(
    const TagCatalogBrowseMode(),
  ) as TagCatalogSuccess).value.revision;

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

  List<sqlite.Row> assignment(int tag, TagTarget target) => switch (target) {
    IntentionTagTarget(:final intentionId) => raw.select(
      'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
      [tagFixtureId(tag), intentionId.toCanonicalString()],
    ),
    LongTermRelationTagTarget(:final relationId) => raw.select(
      'SELECT * FROM tag_assignments WHERE tag_id = ? AND long_term_relation_id = ?',
      [tagFixtureId(tag), relationId.toCanonicalString()],
    ),
  };

  for (final (description, target) in [
    ('архивного намерения', _intention(2)),
    ('связи в дневном пути', _relation(101)),
    ('архивной связи', _relation(102)),
  ]) {
    test(
      'назначение и снятие $description меняют только одну пару и одну ревизию',
      () async {
        final tag = _tagId(lastTagNumber);
        final before = graph();
        final firstRevision = await revision();
        probe.statements.clear();

        final assigned = await repository.execute(
          AssignTag(tagId: tag, target: target),
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
          if (target is IntentionTagTarget) isA<IntentionCatalogUpdated>(),
        ]);
        expect(
          assignmentResult.revision.compareTo(firstRevision),
          GraphRevisionOrder.newer,
        );
        expect(assignment(lastTagNumber, target), hasLength(1));
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
            assignment(lastTagNumber, target).single['creation_sequence']
                as int;
        probe.statements.clear();
        final repeated = await repository.execute(
          AssignTag(tagId: tag, target: target),
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
          assignment(lastTagNumber, target).single['creation_sequence'],
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
          RemoveTagAssignment(tagId: tag, target: target),
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
        expect(assignment(lastTagNumber, target), isEmpty);

        probe.statements.clear();
        final repeatedRemoval = await repository.execute(
          RemoveTagAssignment(tagId: tag, target: target),
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
          AssignTag(tagId: tag, target: target),
        );
        expect(
          (reassigned as TagCommandSucceeded).value.value,
          isA<TagAssignmentChanged>(),
        );
        expect(
          assignment(lastTagNumber, target).single['creation_sequence'],
          greaterThan(sequence),
        );
        expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      },
    );
  }

  test('отсутствие обеих идентичностей проверяется даже при повторе', () async {
    final existingTag = _tagId(firstTagNumber);
    final missingTag = _tagId(999);
    final existingTarget = _intention(2);
    final missingTarget = _intention(999);
    final before = graph();
    final beforeRevision = await revision();

    for (final command in [
      AssignTag(tagId: missingTag, target: existingTarget),
      RemoveTagAssignment(tagId: missingTag, target: existingTarget),
    ]) {
      final failed = await repository.execute(command);
      expect((failed as TagCommandFailed).failure, isA<TagNotFoundFailure>());
    }
    for (final command in [
      AssignTag(tagId: existingTag, target: missingTarget),
      RemoveTagAssignment(tagId: existingTag, target: missingTarget),
      AssignTag(tagId: existingTag, target: _relation(999)),
      RemoveTagAssignment(tagId: existingTag, target: _relation(999)),
    ]) {
      final failed = await repository.execute(command);
      expect(
        (failed as TagCommandFailed).failure,
        isA<TagTargetNotFoundFailure>(),
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
    final target = _intention(2);
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
      AssignTag(tagId: oldId, target: target),
      RemoveTagAssignment(tagId: oldId, target: target),
    ]) {
      final result = await repository.execute(command);
      expect((result as TagCommandFailed).failure, isA<TagNotFoundFailure>());
    }
    expect(graph(), before);
    expect(
      (await revision()).compareTo(beforeRevision),
      GraphRevisionOrder.same,
    );
    expect(assignment(999, target), isEmpty);
  });

  test(
    'отказ после записи откатывает назначение и снятие вместе с ревизией',
    () async {
      final tag = _tagId(lastTagNumber);
      final target = _intention(2);
      final before = graph();
      final firstRevision = await revision();

      probe.failAfterAssignmentWrite = true;
      final failedAssign = await repository.execute(
        AssignTag(tagId: tag, target: target),
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
        AssignTag(tagId: tag, target: target),
      );
      expect(assigned, isA<TagCommandSucceeded>());
      final assignedGraph = graph();
      final assignedRevision = await revision();
      probe.failAfterAssignmentWrite = true;
      final failedRemove = await repository.execute(
        RemoveTagAssignment(tagId: tag, target: target),
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
