import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_storage_fixture.dart';

void main() {
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
    final firstPage = (await repository.getTagCatalogPage(
      TagCatalogQuery(pageSize: 1),
    ) as TagCatalogPageSuccess).value;
    final secondPage = (await repository.getTagCatalogPage(
      TagCatalogQuery(pageSize: 1, cursor: firstPage.nextCursor),
    ) as TagCatalogPageSuccess).value;
    expect(
      firstPage.items.single.id.toCanonicalString(),
      tagFixtureId(firstTagNumber),
    );
    expect(secondPage.items.single.id.toCanonicalString(), newId);
    expect(secondPage.nextCursor, isNull);

    final assignments = raw.select('''
      SELECT creation_sequence, tag_id, intention_id, long_term_relation_id
      FROM tag_assignments ORDER BY creation_sequence
    ''');
    expect(assignments.map((row) => row['creation_sequence']), [1, 2, 3, 4]);
    expect(
      assignments.map((row) => row['tag_id']),
      everyElement(tagFixtureId(firstTagNumber)),
    );
    expect(assignments.map((row) => row['intention_id']), [
      tagFixtureId(1),
      tagFixtureId(2),
      null,
      null,
    ]);
    expect(assignments.map((row) => row['long_term_relation_id']), [
      null,
      null,
      tagFixtureId(101),
      tagFixtureId(102),
    ]);
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
      'INSERT INTO tag_assignments (tag_id, intention_id, long_term_relation_id) VALUES (?, ?, ?)',
      [newId, tagFixtureId(1), tagFixtureId(101)],
    );
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
      6,
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
        await repository.getTagCatalogPage(TagCatalogQuery()),
        isA<TagCatalogPageError>().having(
          (result) => result.failure,
          'причина отказа',
          isA<TagCatalogCorruptionFailure>(),
        ),
      );
    }
    expect(await harness.databaseFile.readAsBytes(), corrupted);
  });
}

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
