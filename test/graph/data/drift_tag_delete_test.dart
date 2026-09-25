import 'dart:async';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

TagId _tagId(int number) =>
    (TagId.decode(_uuid(number)) as TagIdDecodingSuccess).id;

final class _StatementProbe extends LocalDatabaseConnectionObserver {
  final statements = <String>[];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    statements.addAll(statement.statements);
  }
}

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  @override
  void record(DiagnosticsEvent event) => throw StateError('Сбой диагностики');
}

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _StatementProbe probe;

  setUp(() async {
    probe = _StatementProbe();
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        probe,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      diagnostics,
    );
  });
  tearDown(() => database.close());

  Future<GraphRevision> currentRevision() async =>
      (await repository.getTagCatalogPage(
        TagCatalogQuery(),
      ) as TagCatalogPageSuccess).value.revision;

  Map<String, List<List<Object?>>> retainedGraph() => {
    for (final table in [
      'intentions',
      'intention_titles_fts',
      'long_term_relations',
      'daily_choices',
      'daily_choice_path_steps',
    ])
      table: raw
          .select('SELECT * FROM $table ORDER BY rowid')
          .map((row) => row.values.toList())
          .toList(),
  };

  Map<String, List<List<Object?>>> fullGraph() => {
    ...retainedGraph(),
    for (final table in ['tags', 'tag_assignments'])
      table: raw
          .select('SELECT * FROM $table ORDER BY rowid')
          .map((row) => row.values.toList())
          .toList(),
  };

  test('удаление по id охватывает назначения за пределами страницы и сохраняет граф', () async {
    for (var i = 1; i <= 105; i++) {
      raw.execute(
        'INSERT INTO intentions (id, title, description, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [_uuid(i), 'Намерение $i', 'Описание $i', 1, i.isEven ? 1 : 0, i, i],
      );
    }
    raw.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
      [_uuid(201), _uuid(1), _uuid(3), 'need', 2, 1],
    );
    raw.execute(
      'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
      [_uuid(202), _uuid(1), _uuid(3), '2026-09-25', 0],
    );
    raw.execute(
      'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
      [_uuid(203), _uuid(202), _uuid(201)],
    );
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      _uuid(301),
      'Дом',
    ]);
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      _uuid(302),
      'Работа',
    ]);
    for (var i = 1; i <= 104; i++) {
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [_uuid(301), _uuid(i)],
      );
    }
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
      [_uuid(301), _uuid(201)],
    );
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [_uuid(302), _uuid(105)],
    );
    // Назначение после подготовки подтверждения тоже входит в удаление.
    final id = _tagId(301);
    final before = retainedGraph();
    final revision = await currentRevision();
    final watched = StreamIterator(repository.watchTag(id));
    addTearDown(watched.cancel);
    expect(await watched.moveNext(), isTrue);
    expect((watched.current as TagReadSuccess).value.value!.id, id);
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [_uuid(301), _uuid(105)],
    );
    probe.statements.clear();

    final result = await repository.execute(DeleteTag(id));
    expect(result, isA<TagCommandSucceeded>());
    final confirmed = (result as TagCommandSucceeded).value;
    expect(confirmed.value, isA<TagDeleted>());
    expect((confirmed.value as TagDeleted).tagId, id);
    expect(confirmed.value.changes.length, 1);
    expect(confirmed.value.changes.single, isA<TagDeletedChange>());
    expect(confirmed.revision.compareTo(revision), GraphRevisionOrder.newer);
    expect(await watched.moveNext(), isTrue);
    final watchedAfter = (watched.current as TagReadSuccess).value;
    expect(watchedAfter.value, isNull);
    expect(
      watchedAfter.revision.compareTo(confirmed.revision),
      GraphRevisionOrder.same,
    );
    expect(
      raw.select('SELECT * FROM tags WHERE id = ?', [_uuid(301)]),
      isEmpty,
    );
    expect(
      raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
        _uuid(301),
      ]),
      isEmpty,
    );
    expect(
      raw.select('SELECT * FROM tags WHERE id = ?', [_uuid(302)]),
      hasLength(1),
    );
    expect(raw.select('SELECT * FROM tag_assignments'), hasLength(1));
    expect(retainedGraph(), before);
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    expect(
      probe.statements.where((sql) => sql.contains('FROM tag_assignments')),
      isEmpty,
    );
    expect(
      probe.statements.where((sql) => sql.contains('FROM intentions')),
      isEmpty,
    );
    expect(
      diagnostics.events.whereType<TagCommandDiagnosticsEvent>().last,
      isA<TagCommandDiagnosticsEvent>()
          .having(
            (event) => event.commandType,
            'команда',
            TagCommandDiagnosticsType.delete,
          )
          .having(
            (event) => event.status,
            'результат',
            isA<DiagnosticsSucceeded>(),
          ),
    );
  });

  test('отказ внутри каскада откатывает весь граф без новой ревизии', () async {
    for (var i = 1; i <= 2; i++) {
      raw.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [_uuid(i), 'Намерение $i', 0, i - 1, i, i],
      );
    }
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      _uuid(401),
      'Дом',
    ]);
    for (var i = 1; i <= 2; i++) {
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [_uuid(401), _uuid(i)],
      );
    }
    raw.execute('''
      CREATE TEMP TRIGGER fail_tag_cascade
      AFTER DELETE ON tag_assignments
      WHEN OLD.tag_id = '${_uuid(401)}'
      BEGIN
        SELECT RAISE(ABORT, 'injected cascade failure');
      END
    ''');
    final before = fullGraph();
    final revision = await currentRevision();

    final result = await repository.execute(DeleteTag(_tagId(401)));
    expect(result, isA<TagCommandFailed>());
    expect((result as TagCommandFailed).failure, isA<TagUnexpectedFailure>());
    expect(fullGraph(), before);
    expect(
      (await currentRevision()).compareTo(revision),
      GraphRevisionOrder.same,
    );
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    expect(
      diagnostics.events.whereType<TagCommandDiagnosticsEvent>().last,
      isA<TagCommandDiagnosticsEvent>()
          .having(
            (event) => event.commandType,
            'команда',
            TagCommandDiagnosticsType.delete,
          )
          .having(
            (event) => event.stage,
            'этап',
            TagCommandDiagnosticsStage.write,
          )
          .having(
            (event) => event.status,
            'результат',
            isA<DiagnosticsFailed>(),
          ),
    );
  });

  test('устаревший id не удаляет новый одноимённый тег', () async {
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      _uuid(501),
      'Дом',
    ]);
    final deleted = await repository.execute(DeleteTag(_tagId(501)));
    expect(deleted, isA<TagCommandSucceeded>());
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      _uuid(502),
      'Дом',
    ]);
    final revision = await currentRevision();

    final result = await repository.execute(DeleteTag(_tagId(501)));
    expect(result, isA<TagCommandFailed>());
    expect(
      (result as TagCommandFailed).failure,
      isA<TagNotFoundFailure>().having(
        (failure) => failure.tagId,
        'id',
        _tagId(501),
      ),
    );
    expect(raw.select('SELECT id FROM tags').single['id'], _uuid(502));
    expect(
      (await currentRevision()).compareTo(revision),
      GraphRevisionOrder.same,
    );
  });

  test('сбой диагностики не меняет подтверждённое удаление', () async {
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      _uuid(601),
      'Дом',
    ]);
    final withBrokenDiagnostics = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      _ThrowingDiagnosticsSink(),
    );
    final result = await withBrokenDiagnostics.execute(DeleteTag(_tagId(601)));
    expect(result, isA<TagCommandSucceeded>());
    expect(raw.select('SELECT * FROM tags'), isEmpty);
  });
}
