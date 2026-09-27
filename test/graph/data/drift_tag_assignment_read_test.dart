import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignments_page.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  tagFixtureId(number),
) as LongTermRelationIdDecodingSuccess).id;

void _insertMissingTagReference(
  sqlite.Database database,
  String recipientColumn,
  String recipientId,
) {
  final tagId = tagFixtureId(999);
  database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
    tagId,
    'Временный тег',
  ]);
  database.execute(
    'INSERT INTO tag_assignments (tag_id, $recipientColumn) VALUES (?, ?)',
    [tagId, recipientId],
  );
  database.execute('DELETE FROM tags WHERE id = ?', [tagId]);
}

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
  late DriftPersonalGraphRepository graph;
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
    seedTagStorageFixture(raw);
    graph = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 27),
      diagnostics,
    );
    probe.statements.clear();
  });
  tearDown(() => database.close());

  TagAssignmentsPage assignments(TagAssignmentsPageResult result) =>
      (result as TagAssignmentsPageSuccess).value;

  TagSelectionPage selection(TagCatalogPageResult result) =>
      (result as TagCatalogPageSuccess).value as TagSelectionPage;

  test(
    'порции назначений сохраняют порядок создания для обоих получателей',
    () async {
      for (var number = 303; number <= 405; number++) {
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          tagFixtureId(number),
          'Тег $number',
        ]);
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(number), tagFixtureId(1)],
        );
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
          [tagFixtureId(number), tagFixtureId(101)],
        );
      }
      for (final target in [
        IntentionTagTarget(_intention(1)),
        LongTermRelationTagTarget(_relation(101)),
      ]) {
        for (final size in [1, 50, 100]) {
          final names = <String>[];
          TagAssignmentsCursor? cursor;
          do {
            final page = assignments(
              await graph.getTagAssignmentsPage(
                TagAssignmentsQuery(
                  target: target,
                  pageSize: size,
                  cursor: cursor,
                ),
              ),
            );
            expect(page.items.length, lessThanOrEqualTo(size));
            names.addAll(page.items.map((tag) => tag.name.value));
            cursor = page.nextCursor;
          } while (cursor != null);
          expect(names, ['Дом', for (var n = 303; n <= 405; n++) 'Тег $n']);
        }
      }
    },
  );

  test(
    'ключ порядка назначения повторяет создание тега и остаётся неизменным',
    () {
      final tagId = tagFixtureId(firstTagNumber);
      final expected = raw.select(
        'SELECT creation_sequence FROM tags WHERE id = ?',
        [tagId],
      ).single['creation_sequence'];
      final assignment = raw.select(
        'SELECT creation_sequence, tag_creation_sequence FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
        [tagId, tagFixtureId(1)],
      ).single;
      expect(assignment['tag_creation_sequence'], expected);

      expect(
        () => raw.execute(
          'UPDATE tag_assignments SET tag_creation_sequence = ? WHERE creation_sequence = ?',
          [(expected as int) + 1, assignment['creation_sequence']],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      expect(
        () => raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id, tag_creation_sequence) VALUES (?, ?, ?)',
          [tagFixtureId(lastTagNumber), tagFixtureId(1), expected],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      expect(
        raw.select(
          'SELECT tag_creation_sequence FROM tag_assignments WHERE creation_sequence = ?',
          [assignment['creation_sequence']],
        ).single['tag_creation_sequence'],
        expected,
      );
    },
  );

  test(
    'повторное назначение не переносит тег в конец списка получателя',
    () async {
      for (final (target, column, recipientId) in [
        (IntentionTagTarget(_intention(1)), 'intention_id', tagFixtureId(1)),
        (
          LongTermRelationTagTarget(_relation(101)),
          'long_term_relation_id',
          tagFixtureId(101),
        ),
      ]) {
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
          [tagFixtureId(lastTagNumber), recipientId],
        );
        raw.execute(
          'DELETE FROM tag_assignments WHERE tag_id = ? AND $column = ?',
          [tagFixtureId(firstTagNumber), recipientId],
        );
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
          [tagFixtureId(firstTagNumber), recipientId],
        );
        final first = assignments(
          await graph.getTagAssignmentsPage(
            TagAssignmentsQuery(target: target, pageSize: 1),
          ),
        );
        final second = assignments(
          await graph.getTagAssignmentsPage(
            TagAssignmentsQuery(
              target: target,
              pageSize: 1,
              cursor: first.nextCursor,
            ),
          ),
        );
        expect(
          [first.items.single.name.value, second.items.single.name.value],
          ['Дом', 'Работа'],
        );
        expect(second.nextCursor, isNull);
      }
    },
  );

  test(
    'выбор помечает только назначения получателя и проверяет его отсутствие',
    () async {
      final target = IntentionTagTarget(_intention(1));
      final first = selection(
        await graph.getTagCatalogPage(
          TagCatalogQuery(pageSize: 1, mode: TagCatalogSelectionMode(target)),
        ),
      );
      expect(first.rows.single.isAssigned, isTrue);
      final second = selection(
        await graph.getTagCatalogPage(
          TagCatalogQuery(
            pageSize: 1,
            cursor: first.nextCursor,
            mode: TagCatalogSelectionMode(target),
          ),
        ),
      );
      expect(second.rows.single.isAssigned, isFalse);
      expect(second.nextCursor, isNull);
      expect(
        probe.statements
            .where((sql) => sql.contains('FROM tags t'))
            .every(
              (sql) =>
                  sql.contains('EXISTS(') &&
                  sql.contains('LIMIT ?') &&
                  !sql.contains('OFFSET'),
            ),
        isTrue,
      );

      final missing = IntentionTagTarget(_intention(999));
      expect(
        await graph.getTagAssignmentsPage(TagAssignmentsQuery(target: missing)),
        isA<TagAssignmentsPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentsTargetNotFound>(),
        ),
      );
      expect(
        await graph.getTagCatalogPage(
          TagCatalogQuery(mode: TagCatalogSelectionMode(missing)),
        ),
        isA<TagCatalogPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TagCatalogTargetNotFound>(),
        ),
      );
    },
  );

  test('существующий получатель без назначений даёт пустую порцию', () async {
    final target = IntentionTagTarget(_intention(3));
    raw.execute('DELETE FROM tag_assignments WHERE intention_id = ?', [
      tagFixtureId(3),
    ]);
    final page = assignments(
      await graph.getTagAssignmentsPage(TagAssignmentsQuery(target: target)),
    );
    expect(page.items, isEmpty);
    expect(page.nextCursor, isNull);
    final mainQueries = probe.statements.where(
      (sql) => sql.contains('FROM tag_assignments a JOIN tags t'),
    );
    expect(mainQueries, hasLength(1));
    expect(
      mainQueries.single,
      allOf(contains('LIMIT ?'), isNot(contains('OFFSET'))),
    );
  });

  test('каталог выбора обходит большой список без пропусков', () async {
    for (var number = 303; number <= 405; number++) {
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        tagFixtureId(number),
        'Тег $number',
      ]);
    }
    final target = LongTermRelationTagTarget(_relation(102));
    for (final size in [1, 50, 100]) {
      final names = <String>[];
      final assigned = <bool>[];
      TagCatalogCursor? cursor;
      do {
        final page = selection(
          await graph.getTagCatalogPage(
            TagCatalogQuery(
              pageSize: size,
              cursor: cursor,
              mode: TagCatalogSelectionMode(target),
            ),
          ),
        );
        expect(page.rows.length, lessThanOrEqualTo(size));
        names.addAll(page.rows.map((row) => row.tag.name.value));
        assigned.addAll(page.rows.map((row) => row.isAssigned));
        cursor = page.nextCursor;
      } while (cursor != null);
      expect(names, [
        'Дом',
        'Работа',
        for (var n = 303; n <= 405; n++) 'Тег $n',
      ]);
      expect(assigned, [true, for (var n = 0; n < 104; n++) false]);
    }
  });

  test('проверка ссылок выполняется один раз за обход каждого вида', () async {
    for (var number = 303; number <= 305; number++) {
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        tagFixtureId(number),
        'Тег $number',
      ]);
      for (final column in ['intention_id', 'long_term_relation_id']) {
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
          [
            tagFixtureId(number),
            tagFixtureId(column == 'intention_id' ? 1 : 101),
          ],
        );
      }
    }
    for (final target in [
      IntentionTagTarget(_intention(1)),
      LongTermRelationTagTarget(_relation(101)),
    ]) {
      probe.statements.clear();
      TagAssignmentsCursor? assignmentCursor;
      var assignmentPages = 0;
      do {
        final page = assignments(
          await graph.getTagAssignmentsPage(
            TagAssignmentsQuery(
              target: target,
              pageSize: 1,
              cursor: assignmentCursor,
            ),
          ),
        );
        assignmentCursor = page.nextCursor;
        assignmentPages++;
      } while (assignmentCursor != null);
      expect(assignmentPages, greaterThan(1));
      expect(
        probe.statements.where((sql) => sql.contains('LEFT JOIN tags')),
        hasLength(1),
      );

      probe.statements.clear();
      TagCatalogCursor? catalogCursor;
      var catalogPages = 0;
      do {
        final page = selection(
          await graph.getTagCatalogPage(
            TagCatalogQuery(
              mode: TagCatalogSelectionMode(target),
              pageSize: 1,
              cursor: catalogCursor,
            ),
          ),
        );
        catalogCursor = page.nextCursor;
        catalogPages++;
      } while (catalogCursor != null);
      expect(catalogPages, greaterThan(1));
      expect(
        probe.statements.where((sql) => sql.contains('LEFT JOIN tags')),
        hasLength(1),
      );
    }
  });

  test('повреждённая ссылка вне первой порции отклоняет оба чтения', () async {
    raw.execute('PRAGMA foreign_keys = OFF');
    for (final target in [
      IntentionTagTarget(_intention(1)),
      LongTermRelationTagTarget(_relation(101)),
    ]) {
      final (column, id) = switch (target) {
        IntentionTagTarget() => ('intention_id', tagFixtureId(1)),
        LongTermRelationTagTarget() => (
          'long_term_relation_id',
          tagFixtureId(101),
        ),
      };
      _insertMissingTagReference(raw, column, id);
      expect(
        await graph.getTagAssignmentsPage(
          TagAssignmentsQuery(target: target, pageSize: 1),
        ),
        isA<TagAssignmentsPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentsCorruptionFailure>(),
        ),
      );
      expect(
        await graph.getTagCatalogPage(
          TagCatalogQuery(mode: TagCatalogSelectionMode(target), pageSize: 1),
        ),
        isA<TagCatalogPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TagCatalogCorruptionFailure>(),
        ),
      );
      raw.execute('DELETE FROM tag_assignments WHERE tag_id = ?', [
        tagFixtureId(999),
      ]);
    }
  });

  test('продолжение замечает повреждение после первой порции', () async {
    raw.execute('PRAGMA foreign_keys = OFF');
    for (final target in [
      IntentionTagTarget(_intention(1)),
      LongTermRelationTagTarget(_relation(101)),
    ]) {
      final (column, id) = switch (target) {
        IntentionTagTarget() => ('intention_id', tagFixtureId(1)),
        LongTermRelationTagTarget() => (
          'long_term_relation_id',
          tagFixtureId(101),
        ),
      };
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        tagFixtureId(target is IntentionTagTarget ? 303 : 304),
        target is IntentionTagTarget
            ? 'Дополнительный тег намерения'
            : 'Дополнительный тег связи',
      ]);
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
        [tagFixtureId(target is IntentionTagTarget ? 303 : 304), id],
      );
      final firstAssignments = assignments(
        await graph.getTagAssignmentsPage(
          TagAssignmentsQuery(target: target, pageSize: 1),
        ),
      );
      expect(firstAssignments.nextCursor, isNotNull);
      _insertMissingTagReference(raw, column, id);
      expect(
        await graph.getTagAssignmentsPage(
          TagAssignmentsQuery(
            target: target,
            pageSize: 1,
            cursor: firstAssignments.nextCursor,
          ),
        ),
        isA<TagAssignmentsPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentsCorruptionFailure>(),
        ),
      );
      raw.execute('DELETE FROM tag_assignments WHERE tag_id = ?', [
        tagFixtureId(999),
      ]);
      expect(
        await graph.getTagAssignmentsPage(
          TagAssignmentsQuery(
            target: target,
            pageSize: 1,
            cursor: firstAssignments.nextCursor,
          ),
        ),
        isA<TagAssignmentsPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentsSnapshotExpired>(),
        ),
      );

      final firstSelection = selection(
        await graph.getTagCatalogPage(
          TagCatalogQuery(mode: TagCatalogSelectionMode(target), pageSize: 1),
        ),
      );
      expect(firstSelection.nextCursor, isNotNull);
      _insertMissingTagReference(raw, column, id);
      expect(
        await graph.getTagCatalogPage(
          TagCatalogQuery(
            mode: TagCatalogSelectionMode(target),
            pageSize: 1,
            cursor: firstSelection.nextCursor,
          ),
        ),
        isA<TagCatalogPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TagCatalogCorruptionFailure>(),
        ),
      );
      raw.execute('DELETE FROM tag_assignments WHERE tag_id = ?', [
        tagFixtureId(999),
      ]);
      expect(
        await graph.getTagCatalogPage(
          TagCatalogQuery(
            mode: TagCatalogSelectionMode(target),
            pageSize: 1,
            cursor: firstSelection.nextCursor,
          ),
        ),
        isA<TagCatalogPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TagCatalogSnapshotExpired>(),
        ),
      );
    }
  });

  test('чужие и устаревшие продолжения не смешивают снимки', () async {
    final target = IntentionTagTarget(_intention(1));
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(lastTagNumber), tagFixtureId(1)],
    );
    final first = assignments(
      await graph.getTagAssignmentsPage(
        TagAssignmentsQuery(target: target, pageSize: 1),
      ),
    );
    expect(first.nextCursor, isNotNull);
    final other = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 27),
      diagnostics,
    );
    expect(
      await other.getTagAssignmentsPage(
        TagAssignmentsQuery(
          target: target,
          pageSize: 1,
          cursor: first.nextCursor,
        ),
      ),
      isA<TagAssignmentsPageError>().having(
        (error) => error.failure,
        'причина',
        isA<TagAssignmentsInvalidCursor>(),
      ),
    );
    expect(
      await graph.getTagAssignmentsPage(
        TagAssignmentsQuery(
          target: LongTermRelationTagTarget(_relation(101)),
          pageSize: 1,
          cursor: first.nextCursor,
        ),
      ),
      isA<TagAssignmentsPageError>().having(
        (error) => error.failure,
        'причина',
        isA<TagAssignmentsInvalidCursor>(),
      ),
    );
    expect(
      await graph.execute(
        const CreateIntention(title: 'Новое намерение', description: null),
      ),
      isA<GraphCommandSucceeded>(),
    );
    expect(
      await graph.getTagAssignmentsPage(
        TagAssignmentsQuery(
          target: target,
          pageSize: 1,
          cursor: first.nextCursor,
        ),
      ),
      isA<TagAssignmentsPageError>().having(
        (error) => error.failure,
        'причина',
        isA<TagAssignmentsSnapshotExpired>(),
      ),
    );
  });

  test(
    'повреждение дополнительной строки и отсутствующей ссылки отклоняет порцию',
    () async {
      final target = IntentionTagTarget(_intention(1));
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        'некорректный-id',
        'Повреждённый',
      ]);
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        ['некорректный-id', tagFixtureId(1)],
      );
      expect(
        await graph.getTagAssignmentsPage(
          TagAssignmentsQuery(target: target, pageSize: 1),
        ),
        isA<TagAssignmentsPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentsCorruptionFailure>(),
        ),
      );
      raw.execute('DELETE FROM tag_assignments WHERE tag_id = ?', [
        'некорректный-id',
      ]);
      raw.execute('DELETE FROM tags WHERE id = ?', ['некорректный-id']);
      _insertMissingTagReference(raw, 'intention_id', tagFixtureId(1));
      expect(
        await graph.getTagAssignmentsPage(TagAssignmentsQuery(target: target)),
        isA<TagAssignmentsPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentsCorruptionFailure>(),
        ),
      );
      expect(
        await graph.getTagCatalogPage(
          TagCatalogQuery(mode: TagCatalogSelectionMode(target)),
        ),
        isA<TagCatalogPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TagCatalogCorruptionFailure>(),
        ),
      );
    },
  );

  test(
    'осиротевшее назначение не выглядит отсутствующим получателем',
    () async {
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(firstTagNumber), tagFixtureId(999)],
      );
      final target = IntentionTagTarget(_intention(999));
      expect(
        await graph.getTagAssignmentsPage(TagAssignmentsQuery(target: target)),
        isA<TagAssignmentsPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentsCorruptionFailure>(),
        ),
      );
      expect(
        await graph.getTagCatalogPage(
          TagCatalogQuery(mode: TagCatalogSelectionMode(target)),
        ),
        isA<TagCatalogPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TagCatalogCorruptionFailure>(),
        ),
      );
    },
  );
}
