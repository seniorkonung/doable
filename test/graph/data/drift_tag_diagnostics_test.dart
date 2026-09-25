import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/sqlite_tag_functions.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

final class _RecordingSink implements DiagnosticsSink {
  final events = <DiagnosticsEvent>[];
  final messages = <String>[];

  @override
  void record(DiagnosticsEvent event) {
    events.add(event);
    DeveloperDiagnosticsSink(messages.add).record(event);
  }
}

final class _ThrowingSink implements DiagnosticsSink {
  var attempts = 0;

  @override
  void record(DiagnosticsEvent event) {
    attempts++;
    throw StateError('CANARY-отказ-приёмника');
  }
}

void main() {
  late AppDatabase database;
  late sqlite.Database raw;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase(setup: (db) => raw = db));
    await database.open();
  });
  tearDown(() => database.close());

  DriftPersonalGraphRepository repository(DiagnosticsSink sink) =>
      DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 25),
        sink,
      );

  test('реальные исходы и повреждение чтения оставляют только безопасную диагностику', () async {
    final sink = _RecordingSink();
    final graph = repository(sink);
    const privateName = 'CANARY-название-тега';
    const renamedName = 'CANARY-переименованное';
    const privateError = 'CANARY-ошибка-SQL-и-параметр';
    const privateKey = 'CANARY-ключ-сопоставления';
    const privateAssignment = 'CANARY-назначение';
    const damagedId = '018f0b5d-6b2e-7c80-8000-000000000123';

    final created = await graph.execute(
      CreateTag(TagName.fromInput(privateName)),
    );
    expect(created, isA<TagCommandSucceeded>());
    final id =
        ((created as TagCommandSucceeded).value.value as TagCreated).tag.id;
    expect((await graph.watchTag(id).first), isA<TagReadSuccess>());
    final renamed = await graph.execute(
      RenameTag(tagId: id, name: TagName.fromInput(renamedName)),
    );
    expect(renamed, isA<TagCommandSucceeded>());

    final conflict = await graph.execute(
      CreateTag(TagName.fromInput('CANARY-ПЕРЕИМЕНОВАННОЕ')),
    );
    expect(
      (conflict as TagCommandFailed).failure,
      isA<TagNameOccupiedFailure>(),
    );
    final conflictEvent = sink.events
        .whereType<TagCommandDiagnosticsEvent>()
        .last;
    expect(conflictEvent.commandType, TagCommandDiagnosticsType.create);
    expect(
      (conflictEvent.status as DiagnosticsFailed).code,
      DiagnosticsFailureCode.conflict,
    );

    raw.execute('''
      CREATE TEMP TRIGGER fail_tag_delete BEFORE DELETE ON tags
      BEGIN SELECT RAISE(ABORT, '$privateError'); END
    ''');
    final failedDelete = await graph.execute(DeleteTag(id));
    expect(
      (failedDelete as TagCommandFailed).failure,
      isA<TagUnexpectedFailure>(),
    );
    final writeEvent = sink.events.whereType<TagCommandDiagnosticsEvent>().last;
    expect(writeEvent.commandType, TagCommandDiagnosticsType.delete);
    expect(writeEvent.stage, TagCommandDiagnosticsStage.write);
    expect(
      (writeEvent.status as DiagnosticsFailed).code,
      DiagnosticsFailureCode.unexpected,
    );
    expect(raw.select('SELECT name FROM tags').single['name'], renamedName);
    raw.execute('DROP TRIGGER fail_tag_delete');

    final deleted = await graph.execute(DeleteTag(id));
    expect(deleted, isA<TagCommandSucceeded>());
    expect(raw.select('SELECT * FROM tags'), isEmpty);
    expect(
      sink.events.whereType<TagCommandDiagnosticsEvent>().last.status,
      isA<DiagnosticsSucceeded>(),
    );

    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      damagedId,
      privateAssignment,
    ]);
    raw.execute('PRAGMA ignore_check_constraints = ON');
    raw.createFunction(
      functionName: tagNameKeyFunctionName,
      argumentCount: const sqlite.AllowedArgumentCount(1),
      deterministic: true,
      directOnly: false,
      function: (_) => privateKey,
    );
    raw.execute('UPDATE tags SET name = ? WHERE id = ?', [
      ' $privateAssignment ',
      damagedId,
    ]);
    final storedId = (TagId.decode(damagedId) as TagIdDecodingSuccess).id;
    expect(
      await graph.watchTag(storedId).first,
      isA<TagReadError>().having(
        (result) => result.failure,
        'причина',
        isA<TagReadCorruptionFailure>(),
      ),
    );
    final detailEvent = sink.events
        .whereType<TagDetailReadDiagnosticsEvent>()
        .last;
    expect(
      (detailEvent.status as DiagnosticsFailed).code,
      DiagnosticsFailureCode.corruption,
    );
    expect(
      await graph.getTagCatalogPage(TagCatalogQuery()),
      isA<TagCatalogPageError>().having(
        (result) => result.failure,
        'причина',
        isA<TagCatalogCorruptionFailure>(),
      ),
    );
    final catalogEvent = sink.events
        .whereType<TagCatalogPageReadDiagnosticsEvent>()
        .last;
    expect(
      (catalogEvent.status as DiagnosticsFailed).code,
      DiagnosticsFailureCode.corruption,
    );

    expect(
      sink.events
          .whereType<TagCommandDiagnosticsEvent>()
          .where((event) => event.status is DiagnosticsSucceeded)
          .length,
      3,
    );
    expect(sink.messages, isNotEmpty);
    final recorded = [
      ...sink.events.map((event) => event.toString()),
      ...sink.messages,
    ].join('\n');
    for (final privateValue in [
      privateName,
      renamedName,
      privateError,
      privateKey,
      privateAssignment,
      damagedId,
      id.toCanonicalString(),
    ]) {
      expect(recorded, isNot(contains(privateValue)));
    }
  });

  test('отказ приёмника не меняет результат и не повторяет запись', () async {
    final sink = _ThrowingSink();
    final graph = repository(sink);
    final created = await graph.execute(CreateTag(TagName.fromInput('Личное')));
    expect(created, isA<TagCommandSucceeded>());
    final conflict = await graph.execute(
      CreateTag(TagName.fromInput('ЛИЧНОЕ')),
    );
    expect(
      (conflict as TagCommandFailed).failure,
      isA<TagNameOccupiedFailure>(),
    );
    expect(sink.attempts, 4);
    expect(raw.select('SELECT id FROM tags'), hasLength(1));
  });
}
