import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_storage_fixture.dart';

void main() {
  test('полный обход навигации сохраняет порядок после нового процесса, переименования, локали и часов', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    late sqlite.Database raw;
    await harness.openReadyDatabase(setup: (db) => raw = db);
    expect(raw.select('SELECT id FROM tags'), isEmpty);
    _seedStoredNavigationGraph(raw);
    _seedNavigationRecipients(raw);
    final storedGraph = _storedNavigationGraphRows(raw);
    await harness.closePersistenceObjectGraph();

    final database = await harness.openReadyDatabase(setup: (db) => raw = db);
    expect(_storedNavigationGraphRows(raw), storedGraph);
    final graphBefore = retainedTagFixtureGraph(raw);
    final assignmentsBefore = _assignmentRows(raw);
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026),
      InMemoryDiagnosticsSink(),
    );
    final previousPages = <TaggedIntentionsPage>[];
    for (final scope in TaggedIntentionsScope.values) {
      final first = await repository.getTaggedIntentionsPage(
        TaggedIntentionsQuery(
          tagId: _navigationTagId(),
          scope: scope,
          pageSize: 1,
        ),
      );
      expect(first, isA<TaggedIntentionsPageSuccess>());
      final page = (first as TaggedIntentionsPageSuccess).value;
      expect(page.nextCursor, isNotNull);
      previousPages.add(page);
    }
    await harness.closePersistenceObjectGraph();

    await _runWorker(
      harness,
      'navigation_rename',
      locale: 'en',
      clockYear: 1900,
    );
    await _runWorker(
      harness,
      'navigation_verify',
      locale: 'ru',
      clockYear: 2100,
    );

    final reopened = await harness.openReadyDatabase(setup: (db) => raw = db);
    final nextRepository = DriftPersonalGraphRepository(
      reopened,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(1800),
      InMemoryDiagnosticsSink(),
    );
    for (final previous in previousPages) {
      expect(
        await nextRepository.getTaggedIntentionsPage(
          TaggedIntentionsQuery(
            tagId: previous.tag.id,
            scope: previous.scope,
            pageSize: 1,
            cursor: previous.nextCursor,
          ),
        ),
        isA<TaggedIntentionsPageError>().having(
          (result) => result.failure,
          'прежний курсор',
          isA<TaggedIntentionsInvalidCursor>(),
        ),
      );
      final first = (await nextRepository.getTaggedIntentionsPage(
        TaggedIntentionsQuery(
          tagId: previous.tag.id,
          scope: previous.scope,
          pageSize: 1,
        ),
      ) as TaggedIntentionsPageSuccess).value;
      expect(
        first.revision.compareTo(previous.revision),
        GraphRevisionOrder.differentEpoch,
      );
      expect(first.tag.name.value, 'Быт 🏷️');
      expect(first.items.single.id, previous.items.single.id);
    }
    expect(_assignmentRows(raw), assignmentsBefore);
    expect(retainedTagFixtureGraph(raw), graphBefore);
    expect(raw.select('PRAGMA integrity_check').single.values.single, 'ok');
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('навигация после остановки сохраняет удаления, конец повторного назначения и атомарность последнего номера', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    late sqlite.Database raw;
    await harness.openReadyDatabase(setup: (db) => raw = db);
    _seedNavigationRecipients(raw);
    await harness.closePersistenceObjectGraph();

    await _runWorker(harness, 'navigation_mutate', killAtReady: true);
    await _runWorker(
      harness,
      'navigation_verify_removed',
      locale: 'en',
      clockYear: 1900,
    );
    await harness.openReadyDatabase(setup: (db) => raw = db);
    final tagsBefore = _tagRows(raw);
    final assignmentsBefore = _assignmentRows(raw);
    final graphBefore = retainedTagFixtureGraph(raw);
    expect(
      raw
          .select('SELECT id, name FROM tags ORDER BY creation_sequence')
          .map((row) => (row['id'], row['name']))
          .toList(),
      [
        (tagFixtureId(firstTagNumber), 'Быт 🏷️'),
        (tagFixtureId(303), 'Без назначений'),
        (tagFixtureId(304), 'Только в архиве'),
        (tagFixtureId(restTagNumber), 'Отдых'),
        (tagFixtureId(305), 'Работа'),
      ],
    );
    for (final (table, number) in [
      ('tags', lastTagNumber),
      ('intentions', 5),
      ('long_term_relations', 106),
    ]) {
      expect(
        raw.select('SELECT id FROM $table WHERE id = ?', [
          tagFixtureId(number),
        ]),
        isEmpty,
      );
    }
    expect(
      raw.select('''
        SELECT MAX(creation_sequence) AS last FROM tag_assignments
      ''').single['last'],
      14,
    );
    expect(
      raw
          .select(
            "SELECT seq FROM sqlite_sequence WHERE name = 'tag_assignments'",
          )
          .single['seq'],
      15,
    );
    expect(raw.select('SELECT id FROM daily_choices'), hasLength(1));
    expect(raw.select('SELECT id FROM daily_choice_path_steps'), hasLength(1));
    await harness.closePersistenceObjectGraph();

    await _runWorker(
      harness,
      'navigation_assignment_before_commit',
      killAtReady: true,
    );
    await _runWorker(harness, 'navigation_verify_removed');
    await harness.openReadyDatabase(setup: (db) => raw = db);
    expect(_tagRows(raw), tagsBefore);
    expect(_assignmentRows(raw), assignmentsBefore);
    expect(retainedTagFixtureGraph(raw), graphBefore);
    expect(
      raw
          .select(
            "SELECT seq FROM sqlite_sequence WHERE name = 'tag_assignments'",
          )
          .single['seq'],
      15,
    );
    await harness.closePersistenceObjectGraph();

    await _runWorker(
      harness,
      'navigation_assignment_after_commit',
      killAtReady: true,
      clockYear: 1800,
    );
    await _runWorker(
      harness,
      'navigation_verify_reassigned',
      locale: 'en',
      clockYear: 2100,
    );
    await harness.openReadyDatabase(setup: (db) => raw = db);
    expect(_tagRows(raw), tagsBefore);
    expect(retainedTagFixtureGraph(raw), graphBefore);
    final assignmentsAfter = _assignmentRows(raw);
    expect(assignmentsAfter, hasLength(assignmentsBefore.length + 1));
    expect(
      assignmentsAfter.take(assignmentsBefore.length).toList(),
      assignmentsBefore,
    );
    expect(
      raw
          .select(
            '''
          SELECT creation_sequence FROM tag_assignments
          WHERE tag_id = ? AND intention_id = ?
        ''',
            [tagFixtureId(firstTagNumber), tagFixtureId(2)],
          )
          .single['creation_sequence'],
      16,
    );
    expect(raw.select('PRAGMA integrity_check').single.values.single, 'ok');
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'команды сохраняют назначения после остановки и нового процесса',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      await harness.openReadyDatabase(setup: (db) => raw = db);
      raw.execute(
        'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, 10, 10)',
        [tagFixtureId(900), 'Сохранённое намерение'],
      );
      _seedAssignmentRecipients(raw);
      expect(raw.select('SELECT id FROM tags'), isEmpty);
      await harness.closePersistenceObjectGraph();
      // Соединение, открытое до команд другого процесса, видит их подтверждённый результат.
      final originalConnection = sqlite.sqlite3.open(harness.databaseFile.path);
      composeDoableSqliteConnectionSetup(null)(originalConnection);
      addTearDown(originalConnection.close);

      await _runWorker(harness, 'assignments_mutate');
      await _runWorker(harness, 'assignments_verify');
      expect(
        originalConnection
            .select('SELECT id FROM tags ORDER BY creation_sequence')
            .map((row) => row['id'])
            .toList(),
        [tagFixtureId(301), tagFixtureId(303)],
      );

      await harness.openReadyDatabase(setup: (db) => raw = db);
      expect(
        raw
            .select(
              'SELECT creation_sequence, id, name FROM tags ORDER BY creation_sequence',
            )
            .map((row) => (row['creation_sequence'], row['id'], row['name']))
            .toList(),
        [(1, tagFixtureId(301), 'Быт'), (3, tagFixtureId(303), 'Работа')],
      );
      expect(
        raw
            .select('''
          SELECT creation_sequence, tag_id, intention_id
          FROM tag_assignments ORDER BY creation_sequence
        ''')
            .map(
              (row) => (
                row['creation_sequence'],
                row['tag_id'],
                row['intention_id'],
              ),
            )
            .toList(),
        [
          (2, tagFixtureId(303), tagFixtureId(1)),
          (6, tagFixtureId(301), tagFixtureId(1)),
        ],
      );
      expect(
        raw.select('SELECT id FROM intentions WHERE id = ?', [tagFixtureId(4)]),
        isEmpty,
      );
      expect(
        raw.select('SELECT id FROM long_term_relations WHERE id = ?', [
          tagFixtureId(103),
        ]),
        isEmpty,
      );
      expect(
        raw.select('SELECT id FROM intentions WHERE id = ?', [
          tagFixtureId(900),
        ]),
        hasLength(1),
      );
      expect(raw.select('SELECT id FROM daily_choices'), hasLength(1));
      expect(
        raw.select('SELECT id FROM daily_choice_path_steps'),
        hasLength(1),
      );
      expect(raw.select('PRAGMA integrity_check').single.values.single, 'ok');
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  // Пять последовательных процессов ограничены по времени внутри _runWorker.
  test(
    'остановка до commit откатывает назначение, после commit сохраняет его',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      await harness.openReadyDatabase(setup: (db) => raw = db);
      _seedAssignmentRecipients(raw);
      await harness.closePersistenceObjectGraph();
      await _runWorker(harness, 'assignments_mutate');

      await harness.openReadyDatabase(setup: (db) => raw = db);
      final tagsBefore = _tagRows(raw);
      final assignmentsBefore = _assignmentRows(raw);
      final graphBefore = retainedTagFixtureGraph(raw);
      await harness.closePersistenceObjectGraph();

      await _runWorker(harness, 'assignment_before_commit', killAtReady: true);
      await _runWorker(harness, 'assignment_before_commit_verify');
      await harness.openReadyDatabase(setup: (db) => raw = db);
      expect(_tagRows(raw), tagsBefore);
      expect(_assignmentRows(raw), assignmentsBefore);
      expect(retainedTagFixtureGraph(raw), graphBefore);
      expect(raw.select('PRAGMA integrity_check').single.values.single, 'ok');
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      await harness.closePersistenceObjectGraph();

      await _runWorker(harness, 'assignment_after_commit', killAtReady: true);
      await _runWorker(harness, 'assignment_after_commit_verify');
      await harness.openReadyDatabase(setup: (db) => raw = db);
      expect(_tagRows(raw), tagsBefore);
      expect(retainedTagFixtureGraph(raw), graphBefore);
      expect(
        raw
            .select(
              '''
        SELECT creation_sequence, tag_id FROM tag_assignments
        WHERE intention_id = ?
      ''',
              [tagFixtureId(2)],
            )
            .map((row) => (row['creation_sequence'], row['tag_id']))
            .toList(),
        [(7, tagFixtureId(303))],
      );
      expect(raw.select('PRAGMA integrity_check').single.values.single, 'ok');
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    },
    timeout: Timeout.none,
  );

  test('новый процесс сохраняет идентичность, назначения и оба порядка', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    late sqlite.Database raw;
    await harness.openReadyDatabase(setup: (db) => raw = db);
    seedTagStorageFixture(raw);
    final originalGraph = retainedTagFixtureGraph(raw);
    await harness.closePersistenceObjectGraph();

    await _runWorker(harness, 'mutate');

    final reopened = await harness.openReadyDatabase(setup: (db) => raw = db);
    final rows = raw.select(
      'SELECT creation_sequence, id, name FROM tags ORDER BY creation_sequence',
    );
    expect(rows, hasLength(2));
    expect(rows[0]['creation_sequence'], 1);
    expect(rows[0]['id'], tagFixtureId(firstTagNumber));
    expect(rows[0]['name'], 'Быт');
    expect(rows[1]['creation_sequence'], 3);
    expect(rows[1]['id'], isNot(tagFixtureId(lastTagNumber)));
    expect(rows[1]['name'], 'Работа');
    final newId = rows[1]['id'] as String;

    final repository = DriftPersonalGraphRepository(
      reopened,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(1900),
      InMemoryDiagnosticsSink(),
    );
    final snapshot = (await repository.getTagCatalog(
      const TagCatalogBrowseMode(),
    ) as TagCatalogSuccess).value;
    expect(snapshot.items.map((tag) => tag.id.toCanonicalString()), [
      tagFixtureId(firstTagNumber),
      newId,
    ]);

    final assignments = raw.select('''
      SELECT creation_sequence, tag_id, intention_id
      FROM tag_assignments ORDER BY creation_sequence
    ''');
    expect(assignments.map((row) => row['creation_sequence']), [1, 2]);
    expect(
      assignments.map((row) => row['tag_id']),
      everyElement(tagFixtureId(firstTagNumber)),
    );
    expect(assignments.map((row) => row['intention_id']), [
      tagFixtureId(1),
      tagFixtureId(2),
    ]);
    expect(
      raw
          .select('SELECT name FROM pragma_table_info(?) ORDER BY cid', [
            'tag_assignments',
          ])
          .map((row) => row['name']),
      ['creation_sequence', 'tag_id', 'tag_creation_sequence', 'intention_id'],
    );
    expect(
      raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [newId]),
      isEmpty,
    );
    expect(
      raw.select('SELECT * FROM tags WHERE id = ?', [
        tagFixtureId(lastTagNumber),
      ]),
      isEmpty,
    );
    expect(retainedTagFixtureGraph(raw), originalGraph);

    // Ограничения назначений действуют и на новом физическом соединении.
    void rejected(String sql, List<Object?> values) => expect(
      () => raw.execute(sql, values),
      throwsA(isA<sqlite.SqliteException>()),
    );
    rejected(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(firstTagNumber), tagFixtureId(1)],
    );
    rejected(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [newId, tagFixtureId(999)],
    );
    rejected(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(999), tagFixtureId(1)],
    );
    rejected('INSERT INTO tag_assignments (tag_id) VALUES (?)', [newId]);
    rejected(
      'UPDATE tag_assignments SET intention_id = ? WHERE creation_sequence = 1',
      [tagFixtureId(3)],
    );
    rejected('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(303),
      'БЫТ',
    ]);
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [newId, tagFixtureId(3)],
    );
    expect(
      raw.select(
        'SELECT creation_sequence FROM tag_assignments WHERE tag_id = ?',
        [newId],
      ).single['creation_sequence'],
      4,
    );
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
    'прерывание до commit откатывает каскад, после commit удаление долговечно',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      await harness.openReadyDatabase(setup: (db) => raw = db);
      seedTagStorageFixture(raw);
      final originalGraph = retainedTagFixtureGraph(raw);
      final originalTags = _tagRows(raw);
      final originalAssignments = _assignmentRows(raw);
      await harness.closePersistenceObjectGraph();

      await _runWorker(harness, 'delete_before_commit', killAtReady: true);
      await harness.openReadyDatabase(setup: (db) => raw = db);
      expect(_tagRows(raw), originalTags);
      expect(_assignmentRows(raw), originalAssignments);
      expect(retainedTagFixtureGraph(raw), originalGraph);
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      await harness.closePersistenceObjectGraph();

      await _runWorker(harness, 'delete_after_commit', killAtReady: true);
      await harness.openReadyDatabase(setup: (db) => raw = db);
      expect(raw.select('SELECT id FROM tags'), [
        isA<sqlite.Row>().having(
          (row) => row['id'],
          'id',
          tagFixtureId(lastTagNumber),
        ),
      ]);
      expect(raw.select('SELECT tag_id FROM tag_assignments'), [
        isA<sqlite.Row>().having(
          (row) => row['tag_id'],
          'tag_id',
          tagFixtureId(lastTagNumber),
        ),
      ]);
      expect(retainedTagFixtureGraph(raw), originalGraph);
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test('повреждённый файл не открывается как пустой каталог', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    late sqlite.Database raw;
    await harness.openReadyDatabase(setup: (db) => raw = db);
    seedTagStorageFixture(raw);
    await harness.closePersistenceObjectGraph();
    final bytes = await harness.databaseFile.readAsBytes();
    bytes[100] = 0xff;
    await harness.databaseFile.writeAsBytes(bytes, flush: true);
    final corrupted = await harness.databaseFile.readAsBytes();

    final opened = await harness.open();
    if (opened is LocalDataReady) {
      final repository = DriftPersonalGraphRepository(
        opened.database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(1900),
        InMemoryDiagnosticsSink(),
      );
      expect(
        await repository.getTagCatalog(const TagCatalogBrowseMode()),
        isA<TagCatalogError>().having(
          (result) => result.failure,
          'причина отказа',
          isA<TagCatalogCorruptionFailure>(),
        ),
      );
    }
    expect(await harness.databaseFile.readAsBytes(), corrupted);
  });

  test('чтение, назначение архивированному действию, навигация и снятие сохраняются после перезапусков', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    late sqlite.Database raw;
    await harness.openReadyDatabase(setup: (db) => raw = db);
    seedTagRecipientGraphFixture(raw);
    // Архивированное действие участвует в выполненном дневном выборе.
    raw.execute(
      'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, 1)',
      [tagFixtureId(203), tagFixtureId(1), tagFixtureId(2), '2026-09-24'],
    );
    raw.execute(
      'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
      [tagFixtureId(204), tagFixtureId(203), tagFixtureId(102)],
    );
    final graphBefore = retainedTagFixtureGraph(raw);
    await harness.closePersistenceObjectGraph();

    Future<DriftPersonalGraphRepository> restart() async {
      await harness.closePersistenceObjectGraph();
      final database = await harness.openReadyDatabase(setup: (db) => raw = db);
      return DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 25),
        InMemoryDiagnosticsSink(),
      );
    }

    final archivedAction =
        (IntentionId.decode(tagFixtureId(2)) as IntentionIdDecodingSuccess).id;
    final activeAction =
        (IntentionId.decode(tagFixtureId(1)) as IntentionIdDecodingSuccess).id;

    Future<void> expectState(
      DriftPersonalGraphRepository repository,
      TagId tagId, {
      required List<IntentionId> active,
      required List<IntentionId> archived,
    }) async {
      final catalog = (await repository.getTagCatalog(
        const TagCatalogBrowseMode(),
      ) as TagCatalogSuccess).value;
      expect(catalog.items.map((tag) => (tag.id, tag.name.value)), [
        (tagId, 'Дом'),
      ]);
      for (final intentionId in [activeAction, archivedAction]) {
        final snapshot = (await repository.getTagAssignments(
          intentionId,
        ) as TagAssignmentsSuccess).value;
        expect(snapshot.intentionId, intentionId);
        expect(
          snapshot.items.map((tag) => tag.id),
          [...active, ...archived].contains(intentionId) ? [tagId] : isEmpty,
        );
      }
      for (final (scope, expected) in [
        (TaggedIntentionsScope.active, active),
        (TaggedIntentionsScope.archived, archived),
      ]) {
        final page = (await repository.getTaggedIntentionsPage(
          TaggedIntentionsQuery(tagId: tagId, scope: scope),
        ) as TaggedIntentionsPageSuccess).value;
        expect(page.items.map((item) => item.id), expected);
        expect(page.nextCursor, isNull);
      }
      expect(retainedTagFixtureGraph(raw), graphBefore);
      expect(raw.select('PRAGMA integrity_check').single.values.single, 'ok');
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    }

    var repository = await restart();
    expect(
      (await repository.getTagCatalog(
        const TagCatalogBrowseMode(),
      ) as TagCatalogSuccess).value.items,
      isEmpty,
    );
    final created = await repository.execute(
      CreateTag(TagName.fromInput('Дом')),
    );
    final tagId =
        ((created as TagCommandSucceeded).value.value as TagCreated).tag.id;
    await expectState(repository, tagId, active: [], archived: []);

    for (final intentionId in [archivedAction, activeAction, archivedAction]) {
      expect(
        await repository.execute(
          AssignTag(tagId: tagId, intentionId: intentionId),
        ),
        isA<TagCommandSucceeded>(),
      );
    }
    final assignmentsBefore = _assignmentRows(raw);
    expect(assignmentsBefore, hasLength(2));

    repository = await restart();
    expect(_assignmentRows(raw), assignmentsBefore);
    await expectState(
      repository,
      tagId,
      active: [activeAction],
      archived: [archivedAction],
    );

    for (final intentionId in [activeAction, archivedAction]) {
      expect(
        (await repository.execute(
          RemoveTagAssignment(tagId: tagId, intentionId: intentionId),
        ) as TagCommandSucceeded).value.value,
        isA<TagAssignmentChanged>(),
      );
    }

    // Тег без назначений остаётся доступным для явного назначения.
    repository = await restart();
    expect(_assignmentRows(raw), isEmpty);
    await expectState(repository, tagId, active: [], archived: []);
    expect(
      await repository.execute(
        AssignTag(tagId: tagId, intentionId: archivedAction),
      ),
      isA<TagCommandSucceeded>(),
    );

    repository = await restart();
    expect(
      raw
          .select('''
          SELECT creation_sequence, tag_id, intention_id FROM tag_assignments
        ''')
          .map((row) => row.values.toList()),
      [
        [3, tagId.toCanonicalString(), tagFixtureId(2)],
      ],
    );
    await expectState(
      repository,
      tagId,
      active: [],
      archived: [archivedAction],
    );
  });
}

// По два результата в каждом охвате проверяют продолжения среди назначений
// других тегов.
void _seedNavigationRecipients(sqlite.Database raw) {
  seedTagNavigationLifecycleFixture(raw);
  raw.execute(
    'INSERT INTO intentions (id, title, is_archived, created_at, updated_at) VALUES (?, ?, 1, 106, 206)',
    [tagFixtureId(6), 'Архивное намерение'],
  );
  raw.execute(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
    [tagFixtureId(firstTagNumber), tagFixtureId(6)],
  );
}

void _seedAssignmentRecipients(sqlite.Database raw) {
  seedTagRecipientGraphFixture(raw);
  raw.execute(
    'INSERT INTO intentions (id, title, is_action_ready, created_at, updated_at) VALUES (?, ?, 1, 104, 204)',
    [tagFixtureId(4), 'Удаляемое намерение'],
  );
  raw.execute(
    'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority) VALUES (?, ?, ?, ?, 2)',
    [tagFixtureId(103), tagFixtureId(3), tagFixtureId(4), 'can'],
  );
}

TagId _navigationTagId() =>
    (TagId.decode(tagFixtureId(firstTagNumber)) as TagIdDecodingSuccess).id;

/// Сохранённый граф вне тега: намерения, связь, дневной выбор и шаг пути.
void _seedStoredNavigationGraph(sqlite.Database raw) {
  for (final number in [900, 901]) {
    raw.execute(
      'INSERT INTO intentions (id, title, description, is_action_ready, created_at, updated_at) VALUES (?, ?, ?, 1, 10, 20)',
      [
        tagFixtureId(number),
        'Сохранённое намерение $number',
        '  Точный текст  ',
      ],
    );
  }
  raw.execute(
    'INSERT INTO long_term_relations (creation_sequence, id, source_intention_id, related_intention_id, type, priority) VALUES (47, ?, ?, ?, ?, 2)',
    [tagFixtureId(903), tagFixtureId(900), tagFixtureId(901), 'need'],
  );
  raw.execute(
    'INSERT INTO daily_choices (creation_sequence, id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (63, ?, ?, ?, ?, 1)',
    [tagFixtureId(904), tagFixtureId(900), tagFixtureId(901), '2026-09-25'],
  );
  raw.execute(
    'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
    [tagFixtureId(905), tagFixtureId(904), tagFixtureId(903)],
  );
}

Map<String, List<List<Object?>>> _storedNavigationGraphRows(
  sqlite.Database raw,
) => {
  for (final table in [
    'intentions',
    'intention_titles_fts',
    'long_term_relations',
    'daily_choices',
    'daily_choice_path_steps',
  ])
    table: raw
        .select('SELECT rowid, * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

List<List<Object?>> _tagRows(sqlite.Database db) => db
    .select('SELECT * FROM tags ORDER BY creation_sequence')
    .map((row) => row.values.toList())
    .toList();

List<List<Object?>> _assignmentRows(sqlite.Database db) => db
    .select('SELECT * FROM tag_assignments ORDER BY creation_sequence')
    .map((row) => row.values.toList())
    .toList();

Future<void> _runWorker(
  LocalDatabaseHarness harness,
  String operation, {
  bool killAtReady = false,
  String locale = 'ru',
  int clockYear = 1999,
}) async {
  var directory = File(Platform.resolvedExecutable).parent;
  late final String flutterExecutable;
  while (true) {
    final candidate = File(
      '${directory.path}/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
    );
    if (candidate.existsSync()) {
      flutterExecutable = candidate.path;
      break;
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Не найден Flutter SDK для дочернего процесса.');
    }
    directory = directory.parent;
  }
  final workerPath = File.fromUri(
    Directory.current.uri.resolve(
      'test/support/tag_operation_process_worker.dart',
    ),
  ).path;
  final process = await Process.start(
    flutterExecutable,
    ['test', '--no-pub', '--reporter', 'compact', workerPath],
    workingDirectory: Directory.current.path,
    environment: {
      'DOABLE_TAG_DATABASE_PATH': harness.databaseFile.path,
      'DOABLE_TAG_OPERATION': operation,
      'DOABLE_TAG_LOCALE': locale,
      'DOABLE_TAG_CLOCK_YEAR': '$clockYear',
    },
  );
  final output = StringBuffer();
  final errors = StringBuffer();
  final ready = Completer<int>();
  int? startedPid;
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  process.stdout.transform(utf8.decoder).listen((chunk) {
    output.write(chunk);
    final text = output.toString();
    final started = RegExp(r'DOABLE_TAG_WORKER_STARTED:(\d+)').firstMatch(text);
    if (started != null) startedPid = int.parse(started.group(1)!);
    final stopped = RegExp(r'DOABLE_TAG_WORKER_READY:(\d+)').firstMatch(text);
    if (stopped != null && !ready.isCompleted) {
      ready.complete(int.parse(stopped.group(1)!));
    }
  }, onDone: stdoutDone.complete);
  process.stderr
      .transform(utf8.decoder)
      .listen(errors.write, onDone: stderrDone.complete);
  unawaited(
    process.exitCode.then((code) {
      if (killAtReady && !ready.isCompleted) {
        ready.completeError(
          StateError(
            'Процесс завершился до остановки: $code\n$output\n$errors',
          ),
        );
      }
    }),
  );

  try {
    if (killAtReady) {
      final pid = await ready.future.timeout(const Duration(seconds: 45));
      expect(Process.killPid(pid, ProcessSignal.sigkill), isTrue);
    }
    final code = await process.exitCode.timeout(const Duration(seconds: 60));
    await Future.wait([stdoutDone.future, stderrDone.future]);
    expect(startedPid, isNotNull);
    expect(startedPid, isNot(pid));
    if (killAtReady) {
      expect(code, isNot(0));
    } else {
      expect(code, 0, reason: '$output\n$errors');
      expect(output.toString(), contains('DOABLE_TAG_WORKER_DONE'));
    }
  } finally {
    if (startedPid != null) Process.killPid(startedPid!, ProcessSignal.sigkill);
    process.kill(ProcessSignal.sigkill);
  }
}
