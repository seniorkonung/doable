import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/sqlite_tag_functions.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_assignments_page.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/tag_storage_fixture.dart';

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

  test('назначение и снятие сообщают безопасные этапы и коды отказа', () async {
    seedTagStorageFixture(raw);
    final sink = _RecordingSink();
    final graph = repository(sink);
    final tag =
        (TagId.decode(tagFixtureId(lastTagNumber)) as TagIdDecodingSuccess).id;
    final missingTag =
        (TagId.decode(tagFixtureId(999)) as TagIdDecodingSuccess).id;
    final target = IntentionTagTarget(
      (IntentionId.decode(tagFixtureId(2)) as IntentionIdDecodingSuccess).id,
    );
    const privateError = 'CANARY-SQL-параметр-назначения';

    final missing = await graph.execute(
      RemoveTagAssignment(tagId: missingTag, target: target),
    );
    expect((missing as TagCommandFailed).failure, isA<TagNotFoundFailure>());
    final missingEvent = sink.events
        .whereType<TagCommandDiagnosticsEvent>()
        .last;
    expect(
      missingEvent.commandType,
      TagCommandDiagnosticsType.removeAssignment,
    );
    expect(missingEvent.stage, TagCommandDiagnosticsStage.validation);
    expect(
      (missingEvent.status as DiagnosticsFailed).code,
      DiagnosticsFailureCode.notFound,
    );

    raw.execute('''
      CREATE TEMP TRIGGER fail_assignment BEFORE INSERT ON tag_assignments
      BEGIN SELECT RAISE(ABORT, '$privateError'); END
    ''');
    final failed = await graph.execute(AssignTag(tagId: tag, target: target));
    expect((failed as TagCommandFailed).failure, isA<TagUnexpectedFailure>());
    final writeEvent = sink.events.whereType<TagCommandDiagnosticsEvent>().last;
    expect(writeEvent.commandType, TagCommandDiagnosticsType.assign);
    expect(writeEvent.stage, TagCommandDiagnosticsStage.write);
    expect(
      (writeEvent.status as DiagnosticsFailed).code,
      DiagnosticsFailureCode.unexpected,
    );
    expect(
      raw.select(
        'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
        [tagFixtureId(lastTagNumber), tagFixtureId(2)],
      ),
      isEmpty,
    );
    raw.execute('DROP TRIGGER fail_assignment');

    final assigned = await graph.execute(AssignTag(tagId: tag, target: target));
    expect(assigned, isA<TagCommandSucceeded>());
    final assignedEvent = sink.events
        .whereType<TagCommandDiagnosticsEvent>()
        .last;
    expect(assignedEvent.commandType, TagCommandDiagnosticsType.assign);
    expect(assignedEvent.stage, TagCommandDiagnosticsStage.write);
    expect(assignedEvent.status, isA<DiagnosticsSucceeded>());
    final repeated = await graph.execute(AssignTag(tagId: tag, target: target));
    expect(
      (repeated as TagCommandSucceeded).value.value,
      isA<TagAssignmentUnchanged>(),
    );
    final repeatEvent = sink.events
        .whereType<TagCommandDiagnosticsEvent>()
        .last;
    expect(repeatEvent.stage, TagCommandDiagnosticsStage.validation);
    expect(repeatEvent.status, isA<DiagnosticsSucceeded>());

    final removed = await graph.execute(
      RemoveTagAssignment(tagId: tag, target: target),
    );
    expect(removed, isA<TagCommandSucceeded>());
    final removedEvent = sink.events
        .whereType<TagCommandDiagnosticsEvent>()
        .last;
    expect(
      removedEvent.commandType,
      TagCommandDiagnosticsType.removeAssignment,
    );
    expect(removedEvent.stage, TagCommandDiagnosticsStage.write);
    expect(removedEvent.status, isA<DiagnosticsSucceeded>());
    final diagnostics = [
      ...sink.events.map((event) => event.toString()),
      ...sink.messages,
    ].join('\n');
    for (final value in [
      privateError,
      tagFixtureId(lastTagNumber),
      tagFixtureId(2),
    ]) {
      expect(diagnostics, isNot(contains(value)));
    }
  });

  test('отказ диагностики не меняет назначение и снятие', () async {
    seedTagStorageFixture(raw);
    final sink = _ThrowingSink();
    final graph = repository(sink);
    final tag =
        (TagId.decode(tagFixtureId(lastTagNumber)) as TagIdDecodingSuccess).id;
    final target = IntentionTagTarget(
      (IntentionId.decode(tagFixtureId(2)) as IntentionIdDecodingSuccess).id,
    );

    expect(
      await graph.execute(AssignTag(tagId: tag, target: target)),
      isA<TagCommandSucceeded>(),
    );
    expect(
      raw.select(
        'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
        [tagFixtureId(lastTagNumber), tagFixtureId(2)],
      ),
      hasLength(1),
    );
    expect(
      await graph.execute(RemoveTagAssignment(tagId: tag, target: target)),
      isA<TagCommandSucceeded>(),
    );
    expect(
      raw.select(
        'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
        [tagFixtureId(lastTagNumber), tagFixtureId(2)],
      ),
      isEmpty,
    );
    expect(sink.attempts, 4);
  });

  test(
    'чтения назначений сохраняют безопасные этапы и категории причин',
    () async {
      seedTagStorageFixture(raw);
      final sink = _RecordingSink();
      final graph = repository(sink);
      final target = IntentionTagTarget(
        (IntentionId.decode(tagFixtureId(1)) as IntentionIdDecodingSuccess).id,
      );
      final missing = IntentionTagTarget(
        (IntentionId.decode(
          tagFixtureId(999),
        ) as IntentionIdDecodingSuccess).id,
      );

      expect(
        await graph.getTagAssignmentsPage(TagAssignmentsQuery(target: target)),
        isA<TagAssignmentsPageSuccess>(),
      );
      expect(
        await graph.getTagCatalogPage(
          TagCatalogQuery(mode: TagCatalogSelectionMode(target)),
        ),
        isA<TagCatalogPageSuccess>(),
      );
      expect(
        await graph.getTagAssignmentsPage(TagAssignmentsQuery(target: missing)),
        isA<TagAssignmentsPageError>().having(
          (error) => error.failure.category,
          'категория',
          GraphFailureCategory.notFound,
        ),
      );
      final failed = sink.events
          .whereType<TagAssignmentsPageReadDiagnosticsEvent>()
          .last;
      expect(failed.stage, TagReadDiagnosticsStage.read);
      expect(
        (failed.status as DiagnosticsFailed).code,
        DiagnosticsFailureCode.notFound,
      );
      expect(
        sink.events.whereType<TagCatalogPageReadDiagnosticsEvent>().last.status,
        isA<DiagnosticsSucceeded>(),
      );
      final recorded = sink.messages.join('\n');
      for (final privateValue in [
        tagFixtureId(1),
        tagFixtureId(999),
        'Намерение 1',
      ]) {
        expect(recorded, isNot(contains(privateValue)));
      }
    },
  );

  test('отказ приёмника не меняет результат чтений назначений', () async {
    seedTagStorageFixture(raw);
    final sink = _ThrowingSink();
    final graph = repository(sink);
    final target = LongTermRelationTagTarget(
      (LongTermRelationId.decode(
        tagFixtureId(101),
      ) as LongTermRelationIdDecodingSuccess).id,
    );
    expect(
      await graph.getTagAssignmentsPage(TagAssignmentsQuery(target: target)),
      isA<TagAssignmentsPageSuccess>(),
    );
    expect(
      await graph.getTagCatalogPage(
        TagCatalogQuery(mode: TagCatalogSelectionMode(target)),
      ),
      isA<TagCatalogPageSuccess>(),
    );
    expect(sink.attempts, 4);
  });
}
