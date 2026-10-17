import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

TagId _tag(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

/// Выражение чтения строк каталога с условиями по тегам, в котором
/// внедряется отказ.
bool _isCatalogRows(String sql) =>
    sql.contains('json_each(') && sql.contains('LIMIT');

final class _ReadProbe extends LocalDatabaseConnectionObserver {
  /// Однократный отказ после первого подходящего выражения.
  bool Function(String sql)? failAfter;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    final matches = failAfter;
    if (matches != null && matches(statement.statements.single)) {
      failAfter = null;
      throw StateError('CANARY-отказ совместного поиска');
    }
  }
}

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository graph;
  late _ReadProbe probe;
  late InMemoryDiagnosticsSink diagnostics;

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
    seedRawGraph(raw, () {
      raw.execute(
        'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, 1, 1)',
        [tagFixtureId(4), 'Намерение 4'],
      );
      // Назначения другого тега тем же намерениям чередуются с назначениями
      // выбранного тега.
      for (final (tagNumber, intentionNumber) in [
        (lastTagNumber, 1),
        (lastTagNumber, 4),
        (firstTagNumber, 4),
      ]) {
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(tagNumber), tagFixtureId(intentionNumber)],
        );
      }
    });
    diagnostics = InMemoryDiagnosticsSink();
    graph = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 28),
      diagnostics,
    );
  });
  tearDown(() => database.close());

  TaggedIntentionsPage page(TaggedIntentionsPageResult result) =>
      (result as TaggedIntentionsPageSuccess).value;

  Future<List<TaggedIntention>> collect(
    TagId tagId,
    TaggedIntentionsScope scope,
    int size,
  ) async {
    final all = <TaggedIntention>[];
    TaggedIntentionsCursor? cursor;
    do {
      final next = page(
        await graph.getTaggedIntentionsPage(
          TaggedIntentionsQuery(
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

  Future<void> expectCorruption(TaggedIntentionsScope scope) async {
    expect(
      await graph.getTaggedIntentionsPage(
        TaggedIntentionsQuery(
          tagId: _tag(firstTagNumber),
          scope: scope,
          pageSize: 1,
        ),
      ),
      isA<TaggedIntentionsPageError>().having(
        (error) => error.failure,
        'причина',
        isA<TaggedIntentionsCorruptionFailure>(),
      ),
    );
  }

  test('повреждение дополнительного намерения отклоняет всю порцию', () async {
    seedRawGraph(raw, () {
      raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
        ' CANARY-название ',
        tagFixtureId(4),
      ]);
    });
    await expectCorruption(TaggedIntentionsScope.active);
    final events = diagnostics.events
        .whereType<TaggedEntitiesPageReadDiagnosticsEvent>()
        .toList();
    expect(
      events.last.status,
      isA<DiagnosticsFailed>().having(
        (status) => status.code,
        'категория',
        DiagnosticsFailureCode.corruption,
      ),
    );
    expect(events.join(' '), isNot(contains('CANARY')));
  });

  test('недопустимый UTF-8 идентичности даёт повреждение', () async {
    seedRawGraph(raw, () {
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
    });
    await expectCorruption(TaggedIntentionsScope.active);
  });

  test(
    'неверная идентичность намерения отклоняет дополнительную строку',
    () async {
      seedRawGraph(raw, () {
        raw.execute('DELETE FROM tag_assignments WHERE intention_id = ?', [
          tagFixtureId(4),
        ]);
        raw.execute(
          'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, 1, 1)',
          ['CANARY-неверный-id', 'Намерение'],
        );
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(firstTagNumber), 'CANARY-неверный-id'],
        );
      });
      await expectCorruption(TaggedIntentionsScope.active);
    },
  );

  test('совместный поиск по обязательному и исключённому тегам сохраняет '
      'курсор навигации', () async {
    final additionalIds = <IntentionId>[];
    seedRawGraph(raw, () {
      for (var number = 10; number < 17; number++) {
        raw.execute(
          'INSERT INTO intentions (id, title, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
          [tagFixtureId(number), 'Намерение $number', 0, number, number],
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
    });
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
      await graph.getTaggedIntentionsPage(
        TaggedIntentionsQuery(
          tagId: _tag(firstTagNumber),
          scope: TaggedIntentionsScope.active,
          pageSize: 1,
        ),
      ),
    );
    expect(first.nextCursor, isNotNull);
    IntentionCatalogQuery catalogQuery({IntentionCatalogCursor? cursor}) =>
        IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: null,
          tagFilter: IntentionTagFilter(
            requiredTagIds: [_tag(firstTagNumber)],
            excludedTagIds: [_tag(lastTagNumber)],
          ),
          order: IntentionCatalogOrder.createdAtAscending,
          pageSize: 1,
          cursor: cursor,
        );
    final ids = [...first.items.map((item) => item.id)];
    var cursor = first.nextCursor;
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
      final result = await graph.getTaggedIntentionsPage(
        TaggedIntentionsQuery(
          tagId: _tag(firstTagNumber),
          scope: TaggedIntentionsScope.active,
          pageSize: 1,
          cursor: cursor,
        ),
      );
      expect(
        result,
        isA<TaggedIntentionsPageSuccess>(),
        reason: result is TaggedIntentionsPageError
            ? '${result.failure.runtimeType}'
            : null,
      );
      final next = page(result);
      expect(next.revision.compareTo(first.revision), GraphRevisionOrder.same);
      expect(next.tag.name, first.tag.name);
      ids.addAll(next.items.map((item) => item.id));
      cursor = next.nextCursor;
    }
    expect(ids, [_intention(1), _intention(4), ...additionalIds]);
    expect(ids.toSet(), hasLength(ids.length));
    expect(storedGraph(), before);
    expect(
      raw
          .select('SELECT * FROM main.sqlite_schema ORDER BY name')
          .map((row) => row.values.toList())
          .toList(),
      schemaBefore,
    );
  });

  test('успешные и отказавшие чтения каталога с обязательным и '
      'исключёнными тегами не меняют сохранённый граф', () async {
    seedRawGraph(raw, () {
      for (var number = 10; number < 17; number++) {
        raw.execute(
          'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
          [tagFixtureId(number), 'Намерение $number', number, number],
        );
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
    });
    Map<String, List<List<Object?>>> storedGraph() => {
      ...retainedTagFixtureGraph(raw),
      for (final table in ['tags', 'tag_assignments'])
        table: raw
            .select('SELECT * FROM $table ORDER BY rowid')
            .map((row) => row.values.toList())
            .toList(),
    };
    IntentionCatalogQuery query({IntentionCatalogCursor? cursor}) =>
        IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: null,
          tagFilter: IntentionTagFilter(
            requiredTagIds: [_tag(firstTagNumber)],
            excludedTagIds: [_tag(lastTagNumber), _tag(999)],
          ),
          order: IntentionCatalogOrder.createdAtAscending,
          pageSize: 1,
          cursor: cursor,
        );
    IntentionCatalogPage success(Result<IntentionCatalogPage> result) =>
        (result as ResultSuccess<IntentionCatalogPage>).value;
    final before = storedGraph();

    final first = success(await graph.getCatalogPage(query()));
    expect(first.nextCursor, isNotNull);
    expect(storedGraph(), before);
    final repeated = success(await graph.getCatalogPage(query()));
    expect(
      repeated.items.map((item) => item.id),
      first.items.map((item) => item.id),
    );
    expect(storedGraph(), before);
    final continuation = success(
      await graph.getCatalogPage(query(cursor: first.nextCursor)),
    );
    expect(continuation.items.single.id, isNot(first.items.single.id));
    expect(storedGraph(), before);

    for (final (point, failAfter, cursor) in [
      ('первая порция', _isCatalogRows, null),
      ('продолжение', _isCatalogRows, first.nextCursor),
    ]) {
      probe.failAfter = failAfter;
      expect(
        await graph.getCatalogPage(query(cursor: cursor)),
        isA<ResultFailure<IntentionCatalogPage>>().having(
          (result) => result.failure,
          'отказ: $point',
          isA<IntentionUnexpectedFailure>(),
        ),
      );
      expect(probe.failAfter, isNull, reason: point);
      expect(storedGraph(), before, reason: point);
    }
    expect(
      success(await graph.getCatalogPage(query())).items.single.id,
      first.items.single.id,
    );
    expect(storedGraph(), before);
  });

  test(
    'оба охвата содержат только прямые назначения намерениям в их порядке',
    () async {
      seedRawGraph(raw, () {
        raw.execute(
          'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
          [tagFixtureId(103), tagFixtureId(3), tagFixtureId(1), 'can', 2, 1],
        );
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(lastTagNumber), tagFixtureId(2)],
        );
      });
      for (final size in [1, 50, 100]) {
        final active = await collect(
          _tag(firstTagNumber),
          TaggedIntentionsScope.active,
          size,
        );
        expect(active.map((item) => item.id), [_intention(1), _intention(4)]);
        expect(active.map((item) => item.title), [
          'Намерение 1',
          'Намерение 4',
        ]);
        expect(
          active.every(
            (item) => item.archiveState == IntentionArchiveState.active,
          ),
          isTrue,
        );
        final archived = await collect(
          _tag(firstTagNumber),
          TaggedIntentionsScope.archived,
          size,
        );
        expect(archived.map((item) => item.id), [_intention(2)]);
        expect(archived.single.archiveState, IntentionArchiveState.archived);
      }
    },
  );

  test('тег без назначений пуст в обоих охватах при помеченных связанных намерениях', () async {
    seedRawGraph(raw, () {
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        tagFixtureId(305),
        'Без назначений',
      ]);
    });
    for (final scope in TaggedIntentionsScope.values) {
      final empty = page(
        await graph.getTaggedIntentionsPage(
          TaggedIntentionsQuery(tagId: _tag(305), scope: scope, pageSize: 1),
        ),
      );
      expect(empty.tag.id, _tag(305));
      expect(empty.items, isEmpty);
      expect(empty.nextCursor, isNull);
    }
  });

  test('пустой охват отличается от отсутствия тега', () async {
    final empty = page(
      await graph.getTaggedIntentionsPage(
        TaggedIntentionsQuery(
          tagId: _tag(lastTagNumber),
          scope: TaggedIntentionsScope.archived,
        ),
      ),
    );
    expect(empty.items, isEmpty);
    expect(empty.nextCursor, isNull);
    expect(empty.tag.id, _tag(lastTagNumber));
    seedRawGraph(raw, () {
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        tagFixtureId(303),
        'Только архив',
      ]);
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(303), tagFixtureId(2)],
      );
    });
    expect(
      page(
        await graph.getTaggedIntentionsPage(
          TaggedIntentionsQuery(
            tagId: _tag(303),
            scope: TaggedIntentionsScope.active,
          ),
        ),
      ).items,
      isEmpty,
    );
    expect(
      page(
        await graph.getTaggedIntentionsPage(
          TaggedIntentionsQuery(
            tagId: _tag(303),
            scope: TaggedIntentionsScope.archived,
          ),
        ),
      ).items,
      hasLength(1),
    );
    expect(
      await graph.getTaggedIntentionsPage(
        TaggedIntentionsQuery(
          tagId: _tag(999),
          scope: TaggedIntentionsScope.active,
        ),
      ),
      isA<TaggedIntentionsPageError>().having(
        (error) => error.failure,
        'причина',
        isA<TaggedIntentionsTagNotFound>(),
      ),
    );
  });

  test('одноимённые намерения одного охвата остаются разными', () async {
    seedRawGraph(raw, () {
      raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
        'Намерение 1',
        tagFixtureId(4),
      ]);
    });
    final active = await collect(
      _tag(firstTagNumber),
      TaggedIntentionsScope.active,
      1,
    );
    expect(active.map((item) => item.title), ['Намерение 1', 'Намерение 1']);
    expect(active.map((item) => item.id), [_intention(1), _intention(4)]);
  });

  test('новое назначение следует за оставшимися', () async {
    seedRawGraph(raw, () {
      raw.execute(
        'DELETE FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
        [tagFixtureId(firstTagNumber), tagFixtureId(1)],
      );
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(firstTagNumber), tagFixtureId(1)],
      );
    });
    final active = await collect(
      _tag(firstTagNumber),
      TaggedIntentionsScope.active,
      1,
    );
    expect(active.map((item) => item.id), [_intention(4), _intention(1)]);
  });

  test(
    'повтор назначения сохраняет ревизию и допустимость продолжения',
    () async {
      final first = page(
        await graph.getTaggedIntentionsPage(
          TaggedIntentionsQuery(
            tagId: _tag(firstTagNumber),
            scope: TaggedIntentionsScope.active,
            pageSize: 1,
          ),
        ),
      );
      expect(first.nextCursor, isNotNull);
      expect(
        await graph.execute(
          AssignTag(tagId: _tag(firstTagNumber), intentionId: _intention(1)),
        ),
        isA<GraphCommandSucceeded>(),
      );
      final next = page(
        await graph.getTaggedIntentionsPage(
          TaggedIntentionsQuery(
            tagId: _tag(firstTagNumber),
            scope: TaggedIntentionsScope.active,
            pageSize: 1,
            cursor: first.nextCursor,
          ),
        ),
      );
      expect(next.items.single.id, _intention(4));
      expect(next.nextCursor, isNull);
      expect(next.revision.compareTo(first.revision), GraphRevisionOrder.same);
    },
  );

  test('снятие назначения требует начать навигацию с новой основы', () async {
    final first = page(
      await graph.getTaggedIntentionsPage(
        TaggedIntentionsQuery(
          tagId: _tag(firstTagNumber),
          scope: TaggedIntentionsScope.active,
          pageSize: 1,
        ),
      ),
    );
    expect(first.nextCursor, isNotNull);
    expect(
      await graph.execute(
        RemoveTagAssignment(
          tagId: _tag(firstTagNumber),
          intentionId: _intention(1),
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    expect(
      await graph.getTaggedIntentionsPage(
        TaggedIntentionsQuery(
          tagId: _tag(firstTagNumber),
          scope: TaggedIntentionsScope.active,
          pageSize: 1,
          cursor: first.nextCursor,
        ),
      ),
      isA<TaggedIntentionsPageError>().having(
        (error) => error.failure,
        'причина',
        isA<TaggedIntentionsSnapshotExpired>(),
      ),
    );
    final updated = await collect(
      _tag(firstTagNumber),
      TaggedIntentionsScope.active,
      1,
    );
    expect(updated.map((item) => item.id), [_intention(4)]);
  });

  test('порции 1, 50 и 100 обходят намерения обоих охватов среди чужих назначений', () async {
    final expected = <TaggedIntentionsScope, List<IntentionId>>{
      TaggedIntentionsScope.active: [_intention(1), _intention(4)],
      TaggedIntentionsScope.archived: [_intention(2)],
    };
    seedRawGraph(raw, () {
      for (var number = 5; number <= 209; number++) {
        final archived = number.isOdd;
        final relationNumber = number + 1000;
        raw.execute(
          'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
          [
            tagFixtureId(number),
            'Новое намерение $number',
            number % 3 == 0 ? 1 : 0,
            archived ? 1 : 0,
            number,
            number,
          ],
        );
        raw.execute(
          'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
          [
            tagFixtureId(relationNumber),
            tagFixtureId(1),
            tagFixtureId(number),
            'need',
            2,
            archived ? 1 : 0,
          ],
        );
        for (final tagNumber in [lastTagNumber, firstTagNumber]) {
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [tagFixtureId(tagNumber), tagFixtureId(number)],
          );
        }
        expected[archived
                ? TaggedIntentionsScope.archived
                : TaggedIntentionsScope.active]!
            .add(_intention(number));
      }
    });
    for (final size in [1, 50, 100]) {
      for (final scope in TaggedIntentionsScope.values) {
        final rows = await collect(_tag(firstTagNumber), scope, size);
        expect(rows.map((row) => row.id), expected[scope]);
        expect(
          rows.map((row) => row.id).toSet(),
          hasLength(expected[scope]!.length),
        );
      }
    }
    seedRawGraph(raw, () {
      raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
        'Изменённое название',
        tagFixtureId(6),
      ]);
      raw.execute('UPDATE tags SET name = ? WHERE id = ?', [
        'Изменённый тег',
        tagFixtureId(firstTagNumber),
      ]);
    });
    final after = await collect(
      _tag(firstTagNumber),
      TaggedIntentionsScope.active,
      100,
    );
    expect(after.map((row) => row.id), expected[TaggedIntentionsScope.active]);
    expect(after[2].title, 'Изменённое название');
  });
}
