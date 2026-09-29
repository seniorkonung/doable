import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/sqlite_tag_functions.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
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

final class _ReadFault extends LocalDatabaseConnectionObserver {
  Object? failure;
  bool failAssignmentReads = false;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select &&
        (failAssignmentReads ||
            statement.statements.single.contains('FROM tags WHERE id = ?'))) {
      final error = failure;
      if (error != null) throw error;
    }
  }
}

final class _ForeignTaggedCursor implements TaggedIntentionsCursor {}

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late _ReadFault readFault;

  setUp(() async {
    readFault = _ReadFault();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        readFault,
      ),
    );
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

  test(
    'навигация сообщает этап, категорию и длительность без личных данных',
    () async {
      seedTagStorageFixture(raw);
      final sink = _RecordingSink();
      final graph = repository(sink);
      final id = (TagId.decode(
        tagFixtureId(firstTagNumber),
      ) as TagIdDecodingSuccess).id;
      TaggedIntentionsQuery query({TaggedIntentionsCursor? cursor}) =>
          TaggedIntentionsQuery(
            tagId: id,
            scope: TaggedIntentionsScope.active,
            pageSize: 1,
            cursor: cursor,
          );

      expect(
        await graph.getTaggedIntentionsPage(query()),
        isA<TaggedIntentionsPageSuccess>(),
      );
      expect(
        await graph.getTaggedIntentionsPage(
          query(cursor: _ForeignTaggedCursor()),
        ),
        isA<TaggedIntentionsPageError>(),
      );
      final validation = sink.events
          .whereType<TaggedEntitiesPageReadDiagnosticsEvent>()
          .last;
      expect(validation.stage, TagReadDiagnosticsStage.validation);
      expect(
        (validation.status as DiagnosticsFailed).code,
        DiagnosticsFailureCode.validation,
      );

      readFault.failure = sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
        message: 'CANARY-SQL-ошибка',
        causingStatement: 'CANARY-запрос',
        parametersToStatement: [tagFixtureId(firstTagNumber)],
      );
      expect(
        await graph.getTaggedIntentionsPage(query()),
        isA<TaggedIntentionsPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TaggedIntentionsUnavailableFailure>(),
        ),
      );
      final unavailable = sink.events
          .whereType<TaggedEntitiesPageReadDiagnosticsEvent>()
          .last;
      expect(unavailable.stage, TagReadDiagnosticsStage.read);
      expect(
        (unavailable.status as DiagnosticsFailed).code,
        DiagnosticsFailureCode.unavailable,
      );

      readFault.failure = StateError('CANARY-неизвестная-причина');
      expect(
        await graph.getTaggedIntentionsPage(query()),
        isA<TaggedIntentionsPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TaggedIntentionsUnexpectedFailure>(),
        ),
      );
      final unknown = sink.events
          .whereType<TaggedEntitiesPageReadDiagnosticsEvent>()
          .last;
      expect(
        (unknown.status as DiagnosticsFailed).code,
        DiagnosticsFailureCode.unexpected,
      );

      readFault.failure = null;
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(firstTagNumber), tagFixtureId(999)],
      );
      expect(
        await graph.getTaggedIntentionsPage(query()),
        isA<TaggedIntentionsPageError>().having(
          (error) => error.failure,
          'причина',
          isA<TaggedIntentionsCorruptionFailure>(),
        ),
      );
      final corruption = sink.events
          .whereType<TaggedEntitiesPageReadDiagnosticsEvent>()
          .last;
      expect(
        (corruption.status as DiagnosticsFailed).code,
        DiagnosticsFailureCode.corruption,
      );
      final events = sink.events
          .whereType<TaggedEntitiesPageReadDiagnosticsEvent>()
          .toList();
      expect(
        events.where((event) => event.status is DiagnosticsStarted),
        hasLength(5),
      );
      expect(
        events.where((event) => event.status is DiagnosticsSucceeded),
        hasLength(1),
      );
      for (final event in events.where(
        (event) => event.status is DiagnosticsFailed,
      )) {
        expect(
          (event.status as DiagnosticsFailed).duration.isNegative,
          isFalse,
        );
      }
      final recorded = sink.messages.join('\n');
      for (final canary in [
        'CANARY-SQL-ошибка',
        'CANARY-запрос',
        'CANARY-неизвестная-причина',
        tagFixtureId(firstTagNumber),
        tagFixtureId(999),
        tagFixtureId(101),
        tagFixtureId(1),
        'Дом',
        'Намерение 1',
      ]) {
        expect(recorded, isNot(contains(canary)));
      }
    },
  );

  test('отказ приёмника не меняет результат чтения навигации', () async {
    seedTagStorageFixture(raw);
    final sink = _ThrowingSink();
    final graph = repository(sink);
    final id =
        (TagId.decode(tagFixtureId(firstTagNumber)) as TagIdDecodingSuccess).id;
    expect(
      await graph.getTaggedIntentionsPage(
        TaggedIntentionsQuery(tagId: id, scope: TaggedIntentionsScope.active),
      ),
      isA<TaggedIntentionsPageSuccess>(),
    );
    expect(sink.attempts, 2);
  });

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
      await graph.getTagCatalog(const TagCatalogBrowseMode()),
      isA<TagCatalogError>().having(
        (result) => result.failure,
        'причина',
        isA<TagCatalogCorruptionFailure>(),
      ),
    );
    final catalogEvent = sink.events
        .whereType<TagCatalogReadDiagnosticsEvent>()
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
    final target =
        (IntentionId.decode(tagFixtureId(2)) as IntentionIdDecodingSuccess).id;
    const privateError = 'CANARY-SQL-параметр-назначения';

    final missing = await graph.execute(
      RemoveTagAssignment(tagId: missingTag, intentionId: target),
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
    final failed = await graph.execute(
      AssignTag(tagId: tag, intentionId: target),
    );
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

    final assigned = await graph.execute(
      AssignTag(tagId: tag, intentionId: target),
    );
    expect(assigned, isA<TagCommandSucceeded>());
    final assignedEvent = sink.events
        .whereType<TagCommandDiagnosticsEvent>()
        .last;
    expect(assignedEvent.commandType, TagCommandDiagnosticsType.assign);
    expect(assignedEvent.stage, TagCommandDiagnosticsStage.write);
    expect(assignedEvent.status, isA<DiagnosticsSucceeded>());
    final repeated = await graph.execute(
      AssignTag(tagId: tag, intentionId: target),
    );
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
      RemoveTagAssignment(tagId: tag, intentionId: target),
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
    final target =
        (IntentionId.decode(tagFixtureId(2)) as IntentionIdDecodingSuccess).id;

    expect(
      await graph.execute(AssignTag(tagId: tag, intentionId: target)),
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
      await graph.execute(RemoveTagAssignment(tagId: tag, intentionId: target)),
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
      final target = (IntentionId.decode(
        tagFixtureId(1),
      ) as IntentionIdDecodingSuccess).id;
      final missing = (IntentionId.decode(
        tagFixtureId(999),
      ) as IntentionIdDecodingSuccess).id;

      expect(
        await graph.getTagAssignments(target),
        isA<TagAssignmentsSuccess>(),
      );
      expect(
        await graph.getTagCatalog(TagCatalogSelectionMode(target)),
        isA<TagCatalogSuccess>(),
      );
      expect(
        await graph.getTagAssignments(missing),
        isA<TagAssignmentsError>().having(
          (error) => error.failure.category,
          'категория',
          GraphFailureCategory.notFound,
        ),
      );
      final failed = sink.events
          .whereType<TagAssignmentsReadDiagnosticsEvent>()
          .last;
      expect(failed.stage, TagReadDiagnosticsStage.read);
      expect(
        (failed.status as DiagnosticsFailed).code,
        DiagnosticsFailureCode.notFound,
      );
      expect(
        sink.events.whereType<TagCatalogReadDiagnosticsEvent>().last.status,
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
    final target =
        (IntentionId.decode(tagFixtureId(2)) as IntentionIdDecodingSuccess).id;
    expect(await graph.getTagAssignments(target), isA<TagAssignmentsSuccess>());
    expect(
      await graph.getTagCatalog(TagCatalogSelectionMode(target)),
      isA<TagCatalogSuccess>(),
    );
    final tagId =
        (TagId.decode(tagFixtureId(firstTagNumber)) as TagIdDecodingSuccess).id;
    expect(
      await graph.getTagAssignmentStatus(tagId, target),
      isA<TagAssignmentStatusSuccess>(),
    );
    expect(sink.attempts, 6);
  });

  test('отказы трёх чтений различаются и не раскрывают данные пары', () async {
    seedTagStorageFixture(raw);
    final sink = _RecordingSink();
    final graph = repository(sink);
    final intentionId =
        (IntentionId.decode(tagFixtureId(2)) as IntentionIdDecodingSuccess).id;
    final tagId =
        (TagId.decode(tagFixtureId(firstTagNumber)) as TagIdDecodingSuccess).id;
    readFault.failAssignmentReads = true;
    for (final (error, category, code) in [
      (
        sqlite.SqliteException(
          extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
          message: 'CANARY-ошибка-чтения',
          causingStatement: 'CANARY-запрос-чтения',
          parametersToStatement: [tagFixtureId(2)],
        ),
        GraphFailureCategory.unavailable,
        DiagnosticsFailureCode.unavailable,
      ),
      (
        sqlite.SqliteException(
          extendedResultCode: sqlite.SqlError.SQLITE_CORRUPT,
          message: 'CANARY-повреждение',
        ),
        GraphFailureCategory.corruption,
        DiagnosticsFailureCode.corruption,
      ),
      (
        StateError('CANARY-неизвестная-причина'),
        GraphFailureCategory.unexpected,
        DiagnosticsFailureCode.unexpected,
      ),
    ]) {
      readFault.failure = error;
      expect(
        await graph.getTagAssignments(intentionId),
        isA<TagAssignmentsError>().having(
          (result) => result.failure.category,
          'категория',
          category,
        ),
      );
      expect(
        await graph.getTagCatalog(TagCatalogSelectionMode(intentionId)),
        isA<TagCatalogError>().having(
          (result) => result.failure.category,
          'категория',
          category,
        ),
      );
      expect(
        await graph.getTagAssignmentStatus(tagId, intentionId),
        isA<TagAssignmentStatusError>().having(
          (result) => result.failure.category,
          'категория',
          category,
        ),
      );
      for (final event in sink.events.reversed.take(6)) {
        if (event.status case DiagnosticsFailed(
          :final duration,
          code: final failureCode,
        )) {
          expect(duration.isNegative, isFalse);
          expect(failureCode, code);
        }
      }
      expect(
        (sink.events.whereType<TagAssignmentsReadDiagnosticsEvent>().last.status
                as DiagnosticsFailed)
            .code,
        code,
      );
      expect(
        (sink.events.whereType<TagCatalogReadDiagnosticsEvent>().last.status
                as DiagnosticsFailed)
            .code,
        code,
      );
      final statusEvent = sink.events
          .whereType<TagAssignmentStatusReadDiagnosticsEvent>()
          .last;
      expect(statusEvent.stage, TagReadDiagnosticsStage.read);
      expect((statusEvent.status as DiagnosticsFailed).code, code);
    }
    readFault.failure = null;
    expect(
      await graph.getTagAssignments(intentionId),
      isA<TagAssignmentsSuccess>(),
    );
    expect(
      await graph.getTagCatalog(TagCatalogSelectionMode(intentionId)),
      isA<TagCatalogSuccess>(),
    );
    expect(
      await graph.getTagAssignmentStatus(tagId, intentionId),
      isA<TagAssignmentStatusSuccess>(),
    );
    final recorded = [
      ...sink.events.map((event) => event.toString()),
      ...sink.messages,
    ].join('\n');
    for (final value in [
      'CANARY',
      tagFixtureId(2),
      tagFixtureId(firstTagNumber),
      'Дом',
      'Намерение 2',
    ]) {
      expect(recorded, isNot(contains(value)));
    }
  });
}
