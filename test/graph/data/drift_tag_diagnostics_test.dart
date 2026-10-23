import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/graph_seed.dart';
import '../../support/tag_storage_fixture.dart';
import '../../support/tag_positions.dart';

final class _RecordingSink implements DiagnosticsSink {
  final events = <DiagnosticsEvent>[];
  final messages = <String>[];

  @override
  void record(DiagnosticsEvent event) {
    events.add(event);
    DeveloperDiagnosticsSink(messages.add).record(event);
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

  test('реальные исходы и повреждение чтения оставляют только безопасную диагностику', () async {
    final sink = _RecordingSink();
    final graph = repository(sink);
    const privateName = 'CANARY-название-тега';
    const renamedName = 'CANARY-переименованное';
    const otherName = 'CANARY-другой-тег';
    const privateError = 'CANARY-ошибка-SQL-и-параметр';
    const privateAssignment = 'CANARY-назначение';
    const damagedId = 'CANARY-повреждённый-идентификатор';

    final created = await graph.execute(
      CreateTag(
        name: TagName.fromInput(privateName),
        color: null,
        placement: TagPlacement.first,
      ),
    );
    expect(created, isA<TagCommandSucceeded>());
    final id =
        ((created as TagCommandSucceeded).value.value as TagCreated).tag.id;
    expect((await graph.watchTag(id).first), isA<TagReadSuccess>());
    final renamed = await graph.execute(
      UpdateTag(tagId: id, name: TagName.fromInput(renamedName), color: null),
    );
    expect((renamed as TagCommandSucceeded).value.value, isA<TagUpdated>());
    final recolored = await graph.execute(
      UpdateTag(
        tagId: id,
        name: TagName.fromInput(renamedName),
        color: TagColor.blue,
      ),
    );
    expect((recolored as TagCommandSucceeded).value.value, isA<TagUpdated>());
    final unchanged = await graph.execute(
      UpdateTag(
        tagId: id,
        name: TagName.fromInput(renamedName),
        color: TagColor.blue,
      ),
    );
    expect((unchanged as TagCommandSucceeded).value.value, isA<TagUnchanged>());

    final conflict = await graph.execute(
      CreateTag(
        name: TagName.fromInput('CANARY-ПЕРЕИМЕНОВАННОЕ'),
        color: null,
        placement: TagPlacement.first,
      ),
    );
    expect(
      (conflict as TagCommandFailed).failure,
      isA<TagNameOccupiedFailure>(),
    );
    final conflictEvent = sink.events
        .whereType<TagCommandDiagnosticsEvent>()
        .last;
    expect(
      (conflictEvent.status as DiagnosticsFailed).code,
      DiagnosticsFailureCode.conflict,
    );

    final other = await graph.execute(
      CreateTag(
        name: TagName.fromInput(otherName),
        color: null,
        placement: TagPlacement.first,
      ),
    );
    final otherId =
        ((other as TagCommandSucceeded).value.value as TagCreated).tag.id;
    final moved = await graph.execute(
      MoveTag(tagId: id, placement: TagPlacement.first),
    );
    expect((moved as TagCommandSucceeded).value.value, isA<TagUpdated>());
    expect(
      sink.events.whereType<TagCommandDiagnosticsEvent>().last,
      isA<TagCommandDiagnosticsEvent>()
          .having(
            (event) => event.commandType,
            'вид',
            TagCommandDiagnosticsType.move,
          )
          .having(
            (event) => event.status,
            'исход',
            isA<DiagnosticsSucceeded>(),
          ),
    );
    final updateConflict = await graph.execute(
      UpdateTag(
        tagId: otherId,
        name: TagName.fromInput('CANARY-ПЕРЕИМЕНОВАННОЕ'),
        color: TagColor.green,
      ),
    );
    expect(
      (updateConflict as TagCommandFailed).failure,
      isA<TagNameOccupiedFailure>(),
    );
    expect(await graph.execute(DeleteTag(otherId)), isA<TagCommandSucceeded>());
    // Изменение без записи завершается ещё на этапе проверки.
    expect(
      sink.events.whereType<TagCommandDiagnosticsEvent>().where(
        (event) =>
            event.commandType == TagCommandDiagnosticsType.update &&
            event.status is! DiagnosticsStarted,
      ),
      [
        for (final stage in [
          TagCommandDiagnosticsStage.resultRead,
          TagCommandDiagnosticsStage.resultRead,
          TagCommandDiagnosticsStage.validation,
        ])
          isA<TagCommandDiagnosticsEvent>()
              .having((event) => event.stage, 'этап', stage)
              .having(
                (event) => event.status,
                'исход',
                isA<DiagnosticsSucceeded>(),
              ),
        isA<TagCommandDiagnosticsEvent>().having(
          (event) => event.status,
          'исход',
          isA<DiagnosticsFailed>().having(
            (status) => status.code,
            'код',
            DiagnosticsFailureCode.conflict,
          ),
        ),
      ],
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

    // Схема не проверяет формат идентификатора тега.
    seedRawGraph(raw, () {
      raw.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
        damagedId,
        privateAssignment,
        tagPositionKey(200000),
      ]);
    });
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

    expect(sink.messages, isNotEmpty);
    final recorded = [
      ...sink.events.map((event) => event.toString()),
      ...sink.messages,
    ].join('\n');
    for (final privateValue in [
      privateName,
      renamedName,
      otherName,
      TagColor.blue.code,
      TagColor.green.code,
      privateError,
      privateAssignment,
      damagedId,
      id.toCanonicalString(),
      otherId.toCanonicalString(),
    ]) {
      expect(recorded, isNot(contains(privateValue)));
    }
  });

  test(
    'отказы двух чтений различаются и не раскрывают данные намерения',
    () async {
      seedTagStorageFixture(raw);
      final sink = _RecordingSink();
      final graph = repository(sink);
      final intentionId = (IntentionId.decode(
        tagFixtureId(2),
      ) as IntentionIdDecodingSuccess).id;
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
          (sink.events
                      .whereType<TagAssignmentsReadDiagnosticsEvent>()
                      .last
                      .status
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
    },
  );
}
