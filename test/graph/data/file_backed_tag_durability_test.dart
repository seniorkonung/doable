@Tags(['flutter_process'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_storage_fixture.dart';
import '../../support/tagged_intention_ids.dart';

void main() {
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

  test('Теги сохраняются после полного перезапуска: чтение, ручной порядок, правка цвета, перестановка, назначение архивированному действию, выдача по тегу и снятие', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    late sqlite.Database raw;
    await harness.openReadyDatabase(setup: (db) => raw = db);
    seedTagRecipientGraphFixture(raw);
    // Архивированное действие участвует в выполненном дневном выборе.
    seedRawGraph(raw, () {
      raw.execute(
        'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, 1)',
        [tagFixtureId(203), tagFixtureId(1), tagFixtureId(2), '2026-09-24'],
      );
      raw.execute(
        'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
        [tagFixtureId(204), tagFixtureId(203), tagFixtureId(102)],
      );
    });
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
    // Тег, созданный позже, стоит в ручном порядке первым до перестановки.
    late final TagId laterTagId;

    Future<void> expectState(
      DriftPersonalGraphRepository repository,
      TagId tagId, {
      required TagColor? color,
      required bool movedFirst,
      required List<IntentionId> active,
      required List<IntentionId> archived,
    }) async {
      final catalog = (await repository.getTagCatalog(
        const TagCatalogBrowseMode(),
      ) as TagCatalogSuccess).value;
      final later = (laterTagId, 'Работа', null);
      final moved = (tagId, 'Дом', color);
      expect(
        catalog.items.map((tag) => (tag.id, tag.name.value, tag.color)),
        movedFirst ? [moved, later] : [later, moved],
      );
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
        (IntentionScope.active, active),
        (IntentionScope.archived, archived),
      ]) {
        expect(
          await readTaggedIntentionIds(repository, tagId, scope),
          expected.toSet(),
        );
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
      CreateTag(
        name: TagName.fromInput('Дом'),
        color: null,
        placement: TagPlacement.first,
      ),
    );
    final tagId =
        ((created as TagCommandSucceeded).value.value as TagCreated).tag.id;
    final later = await repository.execute(
      CreateTag(
        name: TagName.fromInput('Работа'),
        color: null,
        placement: TagPlacement.first,
      ),
    );
    laterTagId =
        ((later as TagCommandSucceeded).value.value as TagCreated).tag.id;
    await expectState(
      repository,
      tagId,
      color: null,
      movedFirst: false,
      active: [],
      archived: [],
    );

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
      color: null,
      movedFirst: false,
      active: [activeAction],
      archived: [archivedAction],
    );

    expect(
      (await repository.execute(
        UpdateTag(
          tagId: tagId,
          name: TagName.fromInput('Дом'),
          color: TagColor.blue,
        ),
      ) as TagCommandSucceeded).value.value,
      isA<TagUpdated>(),
    );
    // Стоящий вторым тег переставлен в начало.
    expect(
      (await repository.execute(
        MoveTag(tagId: tagId, placement: TagPlacement.first),
      ) as TagCommandSucceeded).value.value,
      isA<TagUpdated>(),
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
    await expectState(
      repository,
      tagId,
      color: TagColor.blue,
      movedFirst: true,
      active: [],
      archived: [],
    );
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
      color: TagColor.blue,
      movedFirst: true,
      active: [],
      archived: [archivedAction],
    );
  });
}

void _seedAssignmentRecipients(sqlite.Database raw) {
  seedTagRecipientGraphFixture(raw);
  seedRawGraph(raw, () {
    raw.execute(
      'INSERT INTO intentions (id, title, is_action_ready, created_at, updated_at) VALUES (?, ?, 1, 104, 204)',
      [tagFixtureId(4), 'Удаляемое намерение'],
    );
    raw.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority) VALUES (?, ?, ?, ?, 2)',
      [tagFixtureId(103), tagFixtureId(3), tagFixtureId(4), 'can'],
    );
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
