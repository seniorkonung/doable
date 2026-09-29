import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tagged_entities_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

part 'tagged_entities_catalog_storage_scenarios.dart';

TagId _tag(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  tagFixtureId(number),
) as LongTermRelationIdDecodingSuccess).id;

final class _ReadProbe extends LocalDatabaseConnectionObserver {
  final statements = <String>[];
  var failAfterFilterInsert = false;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select) {
      statements.add(statement.statements.single);
    }
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (failAfterFilterInsert &&
        statement.statements.single.startsWith(
          'INSERT INTO temp.doable_catalog_excluded_tags',
        )) {
      failAfterFilterInsert = false;
      throw StateError('CANARY-отказ после служебной вставки');
    }
  }
}

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository graph;
  late _ReadProbe probe;
  Directory? fileDirectory;

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
  tearDown(() async {
    await database.close();
    await fileDirectory?.delete(recursive: true);
    fileDirectory = null;
  });

  _taggedEntitiesCatalogStorageScenarios(() async {
    await database.close();
    fileDirectory = await Directory.systemTemp.createTemp('doable_tag_cursor_');
    final file = File('${fileDirectory!.path}/graph.sqlite');
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openFileBackedLocalDatabase(file, setup: (db) => raw = db),
        probe,
      ),
    );
    await database.open();
    seedTagStorageFixture(raw);
    graph = _storageScenarioRepository(database);
    return (
      database: database,
      raw: raw,
      graph: graph,
      probe: probe,
      file: file,
    );
  });

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

  Future<void> expectCorruption(TaggedEntitiesScope scope) async {
    expect(
      await graph.getTaggedEntitiesPage(
        TaggedEntitiesQuery(
          tagId: _tag(firstTagNumber),
          scope: scope,
          pageSize: 1,
        ),
      ),
      isA<TaggedEntitiesPageError>().having(
        (error) => error.failure,
        'причина',
        isA<TaggedEntitiesCorruptionFailure>(),
      ),
    );
  }

  test(
    'отсутствующий получатель вне охвата и порции отклоняет чтение',
    () async {
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(firstTagNumber), tagFixtureId(999)],
      );
      await expectCorruption(TaggedEntitiesScope.active);
    },
  );

  test('отсутствующий участник связи отклоняет порцию', () async {
    raw.execute('PRAGMA foreign_keys = OFF');
    raw.execute('DELETE FROM intentions WHERE id = ?', [tagFixtureId(3)]);
    await expectCorruption(TaggedEntitiesScope.active);
  });

  test('отсутствующая архивная связь не исчезает за фильтром', () async {
    raw.execute('PRAGMA foreign_keys = OFF');
    raw.execute('DELETE FROM long_term_relations WHERE id = ?', [
      tagFixtureId(102),
    ]);
    await expectCorruption(TaggedEntitiesScope.active);
    await expectCorruption(TaggedEntitiesScope.archived);
  });

  test(
    'оставшиеся назначения отсутствующего тега означают повреждение',
    () async {
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute('DELETE FROM tags WHERE id = ?', [
        tagFixtureId(firstTagNumber),
      ]);
      await expectCorruption(TaggedEntitiesScope.active);
    },
  );

  test('отсутствующий участник вне порции и охвата отклоняет чтение', () async {
    raw.execute('PRAGMA foreign_keys = OFF');
    raw.execute('DELETE FROM tag_assignments WHERE intention_id = ?', [
      tagFixtureId(2),
    ]);
    raw.execute('DELETE FROM intentions WHERE id = ?', [tagFixtureId(2)]);
    await expectCorruption(TaggedEntitiesScope.active);
  });

  test('назначение без получателя не превращается в пустой успех', () async {
    raw.execute('PRAGMA ignore_check_constraints = ON');
    raw.execute('INSERT INTO tag_assignments (tag_id) VALUES (?)', [
      tagFixtureId(firstTagNumber),
    ]);
    await expectCorruption(TaggedEntitiesScope.active);
  });

  test('повреждение дополнительной строки отклоняет всю порцию', () async {
    raw.execute('DELETE FROM daily_choice_path_steps');
    raw.execute('PRAGMA ignore_check_constraints = ON');
    raw.execute('UPDATE long_term_relations SET type = ? WHERE id = ?', [
      'CANARY-вид',
      tagFixtureId(101),
    ]);
    await expectCorruption(TaggedEntitiesScope.active);
  });

  test('нестрогое название получателя отклоняет всю порцию', () async {
    raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
      ' CANARY-название ',
      tagFixtureId(1),
    ]);
    await expectCorruption(TaggedEntitiesScope.active);
  });

  test('начальный BOM сохранённого названия не удаляется при чтении', () async {
    raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
      '\uFEFFНамерение',
      tagFixtureId(1),
    ]);
    await expectCorruption(TaggedEntitiesScope.active);
  });

  test('начальный BOM названия тега не удаляется при чтении', () async {
    raw.execute('PRAGMA ignore_check_constraints = ON');
    raw.execute('UPDATE tags SET name = ? WHERE id = ?', [
      '\uFEFFДом',
      tagFixtureId(firstTagNumber),
    ]);
    await expectCorruption(TaggedEntitiesScope.active);
  });

  test('недопустимый UTF-8 идентичности даёт повреждение', () async {
    raw.execute('DELETE FROM tag_assignments WHERE tag_id = ?', [
      tagFixtureId(firstTagNumber),
    ]);
    raw.execute('''INSERT INTO intentions (id, title, created_at, updated_at)
      VALUES (CAST(x'FF' AS TEXT), 'Намерение', 1, 1)''');
    raw.execute(
      '''INSERT INTO tag_assignments (tag_id, intention_id)
      VALUES (?, CAST(x'FF' AS TEXT))''',
      [tagFixtureId(firstTagNumber)],
    );
    await expectCorruption(TaggedEntitiesScope.active);
  });

  test(
    'неверная идентичность участника отклоняет дополнительную строку',
    () async {
      raw.execute(
        'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, 1, 1)',
        ['CANARY-неверный-id', 'Участник'],
      );
      raw.execute(
        '''INSERT INTO long_term_relations
      (id, source_intention_id, related_intention_id, type, priority)
      VALUES (?, ?, ?, 'need', 1)''',
        [tagFixtureId(103), tagFixtureId(3), 'CANARY-неверный-id'],
      );
      raw.execute(
        'DELETE FROM tag_assignments WHERE tag_id = ? AND long_term_relation_id = ?',
        [tagFixtureId(firstTagNumber), tagFixtureId(101)],
      );
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
        [tagFixtureId(firstTagNumber), tagFixtureId(103)],
      );
      await expectCorruption(TaggedEntitiesScope.active);
    },
  );

  for (final (table, number) in [
    ('intentions', 2),
    ('long_term_relations', 102),
  ]) {
    test(
      'недопустимое архивное состояние $table не скрывается охватом',
      () async {
        raw.execute('PRAGMA ignore_check_constraints = ON');
        raw.execute('UPDATE $table SET is_archived = 2 WHERE id = ?', [
          tagFixtureId(number),
        ]);
        await expectCorruption(TaggedEntitiesScope.active);
        await expectCorruption(TaggedEntitiesScope.archived);
      },
    );
  }

  test(
    'повреждение назначений другого тега не затрагивает выбранный',
    () async {
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(lastTagNumber), tagFixtureId(999)],
      );
      final result = await graph.getTaggedEntitiesPage(
        TaggedEntitiesQuery(
          tagId: _tag(firstTagNumber),
          scope: TaggedEntitiesScope.active,
        ),
      );
      expect(result, isA<TaggedEntitiesPageSuccess>());
    },
  );

  test(
    'проверка ссылок выбранного тега выполняется один раз за обход',
    () async {
      probe.statements.clear();
      await collect(_tag(firstTagNumber), TaggedEntitiesScope.active, 1);
      expect(
        probe.statements.where(
          (sql) =>
              sql.contains('LEFT JOIN') &&
              sql.contains('tag_assignments a') &&
              sql.contains('LIMIT 1'),
        ),
        hasLength(1),
      );
    },
  );

  for (final (scope, scopeLabel) in [
    (TaggedEntitiesScope.active, 'активный охват'),
    (TaggedEntitiesScope.archived, 'архивный охват'),
  ]) {
    for (final (label, filter) in [
      ('без условий', IntentionTagFilter.empty),
      (
        'обязательный тег',
        IntentionTagFilter(requiredTagIds: [_tag(firstTagNumber)]),
      ),
      (
        'исключённый тег',
        IntentionTagFilter(excludedTagIds: [_tag(lastTagNumber)]),
      ),
      (
        'совместные условия',
        IntentionTagFilter(
          requiredTagIds: [_tag(firstTagNumber)],
          excludedTagIds: [_tag(lastTagNumber)],
        ),
      ),
      (
        'пересечение условий',
        IntentionTagFilter(
          requiredTagIds: [_tag(firstTagNumber)],
          excludedTagIds: [_tag(firstTagNumber)],
        ),
      ),
      (
        'отсутствующий обязательный тег',
        IntentionTagFilter(requiredTagIds: [_tag(999)]),
      ),
    ]) {
      test(
        'совместный поиск сохраняет курсор навигации: $scopeLabel, $label',
        () async {
          final additionalIds = <IntentionId>[];
          for (var number = 10; number < 17; number++) {
            raw.execute(
              'INSERT INTO intentions (id, title, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
              [
                tagFixtureId(number),
                'Намерение $number',
                scope == TaggedEntitiesScope.archived ? 1 : 0,
                number,
                number,
              ],
            );
            additionalIds.add(_intention(number));
            for (final tagNumber in [
              firstTagNumber,
              if (number.isEven) lastTagNumber,
            ]) {
              raw.execute(
                'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
                [tagFixtureId(tagNumber), tagFixtureId(number)],
              );
            }
          }
          Map<String, List<List<Object?>>> storedGraph() => {
            ...retainedTagFixtureGraph(raw),
            for (final table in ['tags', 'tag_assignments', 'sqlite_sequence'])
              table: raw
                  .select('SELECT * FROM $table ORDER BY rowid')
                  .map((row) => row.values.toList())
                  .toList(),
          };
          final before = storedGraph();
          final schemaBefore = raw
              .select('SELECT * FROM main.sqlite_schema ORDER BY name')
              .map((row) => row.values.toList())
              .toList();
          final first = page(
            await graph.getTaggedEntitiesPage(
              TaggedEntitiesQuery(
                tagId: _tag(firstTagNumber),
                scope: scope,
                pageSize: 1,
              ),
            ),
          );
          expect(first.nextCursor, isNotNull);
          IntentionCatalogQuery catalogQuery({
            IntentionCatalogCursor? cursor,
          }) => IntentionCatalogQuery(
            scope: scope == TaggedEntitiesScope.active
                ? IntentionScope.active
                : IntentionScope.archived,
            titleFilter: null,
            tagFilter: filter,
            order: IntentionCatalogOrder.createdAtAscending,
            pageSize: 1,
            cursor: cursor,
          );
          final targets = [...first.items.map((item) => item.target)];
          var cursor = first.nextCursor;
          probe.statements.clear();
          while (cursor != null) {
            final catalog = await graph.getCatalogPage(catalogQuery());
            expect(catalog, isA<ResultSuccess<IntentionCatalogPage>>());
            final catalogPage =
                (catalog as ResultSuccess<IntentionCatalogPage>).value;
            expect(
              catalogPage.revision.compareTo(first.revision),
              GraphRevisionOrder.same,
            );
            final repeated = await graph.getCatalogPage(catalogQuery());
            expect(repeated, isA<ResultSuccess<IntentionCatalogPage>>());
            final repeatedPage =
                (repeated as ResultSuccess<IntentionCatalogPage>).value;
            expect(
              repeatedPage.items.map((item) => item.id),
              catalogPage.items.map((item) => item.id),
            );
            expect(
              (repeatedPage as IntentionCatalogFirstPage).totalCount,
              (catalogPage as IntentionCatalogFirstPage).totalCount,
            );
            if (catalogPage.nextCursor != null) {
              final continuation = await graph.getCatalogPage(
                catalogQuery(cursor: catalogPage.nextCursor),
              );
              expect(continuation, isA<ResultSuccess<IntentionCatalogPage>>());
              final continuedPage =
                  (continuation as ResultSuccess<IntentionCatalogPage>).value;
              expect(
                continuedPage.revision.compareTo(first.revision),
                GraphRevisionOrder.same,
              );
              expect(
                continuedPage.items.single.id,
                isNot(catalogPage.items.single.id),
              );
            }
            final result = await graph.getTaggedEntitiesPage(
              TaggedEntitiesQuery(
                tagId: _tag(firstTagNumber),
                scope: scope,
                pageSize: 1,
                cursor: cursor,
              ),
            );
            expect(
              result,
              isA<TaggedEntitiesPageSuccess>(),
              reason: result is TaggedEntitiesPageError
                  ? '${result.failure.runtimeType}'
                  : null,
            );
            final next = page(result);
            expect(
              next.revision.compareTo(first.revision),
              GraphRevisionOrder.same,
            );
            expect(next.tag.name, first.tag.name);
            targets.addAll(next.items.map((item) => item.target));
            cursor = next.nextCursor;
          }
          expect(targets, [
            IntentionTagTarget(
              scope == TaggedEntitiesScope.active
                  ? _intention(1)
                  : _intention(2),
            ),
            LongTermRelationTagTarget(
              scope == TaggedEntitiesScope.active
                  ? _relation(101)
                  : _relation(102),
            ),
            ...additionalIds.map(IntentionTagTarget.new),
          ]);
          expect(targets.toSet(), hasLength(targets.length));
          expect(storedGraph(), before);
          expect(
            raw
                .select('SELECT * FROM main.sqlite_schema ORDER BY name')
                .map((row) => row.values.toList())
                .toList(),
            schemaBefore,
          );
          expect(
            probe.statements.where(
              (sql) =>
                  sql.contains('LEFT JOIN') &&
                  sql.contains('tag_assignments a') &&
                  sql.contains('LIMIT 1'),
            ),
            isEmpty,
          );
        },
      );
    }
  }

  test(
    'смена хранилища лишает продолжение свидетельства целостности',
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
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(firstTagNumber), tagFixtureId(999)],
      );
      expect(
        await graph.getTaggedEntitiesPage(
          TaggedEntitiesQuery(
            tagId: _tag(firstTagNumber),
            scope: TaggedEntitiesScope.active,
            pageSize: 1,
            cursor: first.nextCursor,
          ),
        ),
        isA<TaggedEntitiesPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TaggedEntitiesSnapshotExpired>(),
        ),
      );
      await expectCorruption(TaggedEntitiesScope.active);
    },
  );

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
        .where(
          (sql) =>
              sql.contains('FROM tag_assignments a') &&
              sql.contains('ORDER BY a.creation_sequence'),
        )
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
