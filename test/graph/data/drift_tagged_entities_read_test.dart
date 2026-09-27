import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tagged_entities_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

TagId _tag(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  tagFixtureId(number),
) as LongTermRelationIdDecodingSuccess).id;

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
  late _ReadProbe probe;

  setUp(() async {
    probe = _ReadProbe();
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
      () => DateTime.utc(2026, 9, 28),
      InMemoryDiagnosticsSink(),
    );
    probe.statements.clear();
  });
  tearDown(() => database.close());

  TaggedEntitiesPage page(TaggedEntitiesPageResult result) =>
      (result as TaggedEntitiesPageSuccess).value;

  Future<List<TaggedEntity>> collect(
    TagId tagId,
    TaggedEntitiesScope scope,
    int size,
  ) async {
    final all = <TaggedEntity>[];
    TaggedEntitiesCursor? cursor;
    do {
      final next = page(
        await graph.getTaggedEntitiesPage(
          TaggedEntitiesQuery(
            tagId: tagId,
            scope: scope,
            pageSize: size,
            cursor: cursor,
          ),
        ),
      );
      expect(next.items.length, lessThanOrEqualTo(size));
      all.addAll(next.items);
      cursor = next.nextCursor;
    } while (cursor != null);
    return all;
  }

  test('оба охвата смешивают виды в порядке назначения без соседей', () async {
    raw.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(103), tagFixtureId(3), tagFixtureId(1), 'can', 2, 1],
    );
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
      [tagFixtureId(firstTagNumber), tagFixtureId(103)],
    );
    raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
      'Намерение 1',
      tagFixtureId(2),
    ]);

    for (final size in [1, 50, 100]) {
      final active = await collect(
        _tag(firstTagNumber),
        TaggedEntitiesScope.active,
        size,
      );
      expect(active.map((item) => item.target).toSet(), hasLength(2));
      expect(active[0], isA<TaggedIntention>());
      expect((active[0] as TaggedIntention).id, _intention(1));
      expect((active[0] as TaggedIntention).title, 'Намерение 1');
      expect(active[1], isA<TaggedLongTermRelation>());
      final relation = active[1] as TaggedLongTermRelation;
      expect(relation.id, _relation(101));
      expect(relation.type, LongTermRelationType.need);
      expect(relation.sourceTitle, 'Намерение 1');
      expect(relation.relatedTitle, 'Намерение 3');
      expect(relation.scope, RelationScope.active);

      final archived = await collect(
        _tag(firstTagNumber),
        TaggedEntitiesScope.archived,
        size,
      );
      expect(archived, hasLength(3));
      expect(archived[0], isA<TaggedIntention>());
      expect((archived[0] as TaggedIntention).id, _intention(2));
      expect(
        (archived[0] as TaggedIntention).archiveState,
        IntentionArchiveState.archived,
      );
      expect((archived[0] as TaggedIntention).title, 'Намерение 1');
      expect(archived[1], isA<TaggedLongTermRelation>());
      expect(archived[2], isA<TaggedLongTermRelation>());
      final archivedRelation = archived[2] as TaggedLongTermRelation;
      expect(archivedRelation.id, _relation(103));
      expect(archivedRelation.scope, RelationScope.archived);
      expect(archivedRelation.sourceTitle, 'Намерение 3');
      expect(archivedRelation.relatedTitle, 'Намерение 1');
    }
  });

  test('пустой охват отличается от отсутствия тега', () async {
    final empty = page(
      await graph.getTaggedEntitiesPage(
        TaggedEntitiesQuery(
          tagId: _tag(lastTagNumber),
          scope: TaggedEntitiesScope.archived,
        ),
      ),
    );
    expect(empty.items, isEmpty);
    expect(empty.nextCursor, isNull);
    expect(empty.tag.id, _tag(lastTagNumber));
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(303),
      'Только архив',
    ]);
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(303), tagFixtureId(2)],
    );
    expect(
      page(
        await graph.getTaggedEntitiesPage(
          TaggedEntitiesQuery(
            tagId: _tag(303),
            scope: TaggedEntitiesScope.active,
          ),
        ),
      ).items,
      isEmpty,
    );
    expect(
      page(
        await graph.getTaggedEntitiesPage(
          TaggedEntitiesQuery(
            tagId: _tag(303),
            scope: TaggedEntitiesScope.archived,
          ),
        ),
      ).items,
      hasLength(1),
    );
    expect(
      await graph.getTaggedEntitiesPage(
        TaggedEntitiesQuery(
          tagId: _tag(999),
          scope: TaggedEntitiesScope.active,
        ),
      ),
      isA<TaggedEntitiesPageError>().having(
        (error) => error.failure,
        'причина',
        isA<TaggedEntitiesTagNotFound>(),
      ),
    );
  });

  test('одноимённые намерения одного охвата остаются разными', () async {
    raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
      'Намерение 1',
      tagFixtureId(3),
    ]);
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(firstTagNumber), tagFixtureId(3)],
    );
    final active = await collect(
      _tag(firstTagNumber),
      TaggedEntitiesScope.active,
      1,
    );
    final intentions = active.whereType<TaggedIntention>().toList();
    expect(intentions.map((item) => item.title), [
      'Намерение 1',
      'Намерение 1',
    ]);
    expect(intentions.map((item) => item.id), [_intention(1), _intention(3)]);
  });

  test(
    'курсор привязан к тегу, охвату, размеру, экземпляру и снимку',
    () async {
      final first = page(
        await graph.getTaggedEntitiesPage(
          TaggedEntitiesQuery(
            tagId: _tag(firstTagNumber),
            scope: TaggedEntitiesScope.active,
            pageSize: 1,
          ),
        ),
      );
      final cursor = first.nextCursor;
      expect(cursor, isNotNull);
      for (final query in [
        TaggedEntitiesQuery(
          tagId: _tag(lastTagNumber),
          scope: TaggedEntitiesScope.active,
          pageSize: 1,
          cursor: cursor,
        ),
        TaggedEntitiesQuery(
          tagId: _tag(firstTagNumber),
          scope: TaggedEntitiesScope.archived,
          pageSize: 1,
          cursor: cursor,
        ),
        TaggedEntitiesQuery(
          tagId: _tag(firstTagNumber),
          scope: TaggedEntitiesScope.active,
          pageSize: 2,
          cursor: cursor,
        ),
      ]) {
        expect(
          await graph.getTaggedEntitiesPage(query),
          isA<TaggedEntitiesPageError>().having(
            (error) => error.failure,
            'причина',
            isA<TaggedEntitiesInvalidCursor>(),
          ),
        );
      }
      final other = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 28),
        InMemoryDiagnosticsSink(),
      );
      expect(
        await other.getTaggedEntitiesPage(
          TaggedEntitiesQuery(
            tagId: _tag(firstTagNumber),
            scope: TaggedEntitiesScope.active,
            pageSize: 1,
            cursor: cursor,
          ),
        ),
        isA<TaggedEntitiesPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TaggedEntitiesInvalidCursor>(),
        ),
      );

      raw.execute('UPDATE tags SET name = ? WHERE id = ?', [
        'Новый дом',
        tagFixtureId(firstTagNumber),
      ]);
      expect(
        await graph.getTaggedEntitiesPage(
          TaggedEntitiesQuery(
            tagId: _tag(firstTagNumber),
            scope: TaggedEntitiesScope.active,
            pageSize: 1,
            cursor: cursor,
          ),
        ),
        isA<TaggedEntitiesPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TaggedEntitiesSnapshotExpired>(),
        ),
      );
    },
  );

  test('новое назначение следует за оставшимися и запрос ограничен', () async {
    raw.execute(
      'DELETE FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
      [tagFixtureId(firstTagNumber), tagFixtureId(1)],
    );
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(firstTagNumber), tagFixtureId(1)],
    );
    probe.statements.clear();
    final active = await collect(
      _tag(firstTagNumber),
      TaggedEntitiesScope.active,
      1,
    );
    expect(active, [isA<TaggedLongTermRelation>(), isA<TaggedIntention>()]);
    final pageQueries = probe.statements
        .where((sql) => sql.contains('FROM tag_assignments a'))
        .toList();
    expect(pageQueries, hasLength(2));
    expect(
      pageQueries.every(
        (sql) =>
            sql.contains('LIMIT ?') &&
            !sql.contains('OFFSET') &&
            sql.contains('JOIN intentions'),
      ),
      isTrue,
    );
    final plan = raw
        .select('EXPLAIN QUERY PLAN ${pageQueries.first}', [
          tagFixtureId(firstTagNumber),
          0,
          0,
          2,
        ])
        .map((row) => row['detail'].toString())
        .join(' ');
    expect(plan, contains('tag_assignments_tag_order'));
  });

  test('порции 1, 50 и 100 полностью обходят смешанную выдачу', () async {
    final expected = <Object>[];
    for (var number = 4; number <= 106; number++) {
      final relationNumber = number + 1000;
      raw.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [tagFixtureId(number), 'Новое намерение $number', 0, 0, number, number],
      );
      raw.execute(
        'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
        [
          tagFixtureId(relationNumber),
          tagFixtureId(1),
          tagFixtureId(number),
          'need',
          2,
          0,
        ],
      );
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(firstTagNumber), tagFixtureId(number)],
      );
      expected.add(_intention(number));
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
        [tagFixtureId(firstTagNumber), tagFixtureId(relationNumber)],
      );
      expected.add(_relation(relationNumber));
    }
    final initial = [_intention(1), _relation(101), ...expected];
    for (final size in [1, 50, 100]) {
      final rows = await collect(
        _tag(firstTagNumber),
        TaggedEntitiesScope.active,
        size,
      );
      expect(
        rows.map(
          (row) => switch (row) {
            TaggedIntention(:final id) => id,
            TaggedLongTermRelation(:final id) => id,
          },
        ),
        initial,
      );
    }
    raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
      'Изменённое название',
      tagFixtureId(4),
    ]);
    raw.execute('UPDATE tags SET name = ? WHERE id = ?', [
      'Изменённый тег',
      tagFixtureId(firstTagNumber),
    ]);
    final after = await collect(
      _tag(firstTagNumber),
      TaggedEntitiesScope.active,
      100,
    );
    expect(
      after.map(
        (row) => switch (row) {
          TaggedIntention(:final id) => id,
          TaggedLongTermRelation(:final id) => id,
        },
      ),
      initial,
    );
    expect((after[2] as TaggedIntention).title, 'Изменённое название');
  });
}
