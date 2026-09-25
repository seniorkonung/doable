import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart';

import 'generated_schema.dart' as generated;

typedef MigrationOperation = Future<void> Function();

final class IncompatibleLocalDataSchemaException extends UnsupportedError {
  IncompatibleLocalDataSchemaException({
    required this.expectedSchemaVersion,
    required this.detectedSchemaVersion,
  }) : super('Схема локальных данных создана более новой версией приложения.');

  final int expectedSchemaVersion;
  final int detectedSchemaVersion;
}

final class CorruptLocalDataSchemaException implements Exception {
  const CorruptLocalDataSchemaException();
}

MigrationStrategy localDataMigrationStrategy(
  GeneratedDatabase database, {
  DiagnosticsSink? diagnosticsSink,
}) {
  return MigrationStrategy(
    onCreate: (migrator) => _recordMigration(
      diagnosticsSink,
      fromSchemaVersion: 0,
      toSchemaVersion: database.schemaVersion,
      migrate: () async {
        await _verifyNewStorageHasNoSchema(database);
        await runAtomicMigration(
          database,
          targetSchemaVersion: database.schemaVersion,
          migrate: () async {
            for (final schemaObject in database.allSchemaEntities) {
              await migrator.create(schemaObject);
            }
          },
        );
      },
    ),
    onUpgrade: (migrator, from, to) => _recordMigration(
      diagnosticsSink,
      fromSchemaVersion: from,
      toSchemaVersion: to,
      migrate: () async {
        if (from > to) {
          throw IncompatibleLocalDataSchemaException(
            expectedSchemaVersion: to,
            detectedSchemaVersion: from,
          );
        }
        if (from < 1) throw const CorruptLocalDataSchemaException();

        await runAtomicMigration(
          database,
          targetSchemaVersion: to,
          migrate: () => generated.stepByStep(
            from1To2: _migrateFrom1To2,
            from2To3: _migrateFrom2To3,
            from3To4: _migrateFrom3To4,
          )(migrator, from, to),
        );
      },
    ),
    beforeOpen: (details) async {
      await _verifyStoredSchemaVersion(
        database,
        expectedSchemaVersion: details.versionNow,
      );
      await database.customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

Future<void> _migrateFrom1To2(
  Migrator migrator,
  generated.Schema2 schema,
) async {
  await migrator.create(schema.longTermRelations);
  await migrator.create(schema.longTermRelationsSourceGroupOrder);
  await migrator.create(schema.longTermRelationsRelatedGroupOrder);
  await migrator.create(schema.longTermRelationsImmutableIdentity);
  await migrator.create(schema.longTermRelationsActiveParticipantsAfterInsert);
  await migrator.create(schema.longTermRelationsActiveParticipantsAfterUpdate);
  await migrator.create(schema.intentionsArchiveRequiresNoActiveRelations);
}

Future<void> _migrateFrom2To3(
  Migrator migrator,
  generated.Schema3 schema,
) async {
  await migrator.create(schema.dailyChoices);
  await migrator.create(schema.dailyChoicesDateCreationOrder);
  await migrator.create(schema.dailyChoicesSourceDateCreationOrder);
  await migrator.create(schema.dailyChoicesSelectedDateCreationOrder);
  await migrator.create(schema.dailyChoicesSourceRecent);
  await migrator.create(schema.dailyChoicesSelectedRecent);
  await migrator.create(schema.dailyChoicesImmutableIdentity);
  await migrator.create(schema.dailyChoicePathSteps);
  await migrator.create(schema.dailyChoicePathStepsOneRoot);
  await migrator.create(schema.dailyChoicePathStepsOneSuccessor);
  await migrator.create(schema.dailyChoicePathStepsRelation);
  await migrator.create(schema.longTermRelationsProtectDailyChoicePath);
}

Future<void> _migrateFrom3To4(
  Migrator migrator,
  generated.Schema4 schema,
) async {
  await migrator.create(schema.tags);
  await migrator.create(schema.tagsImmutableIdentity);
  await migrator.create(schema.tagAssignments);
  await migrator.create(schema.tagAssignmentsTagOrder);
  await migrator.create(schema.tagAssignmentsIntention);
  await migrator.create(schema.tagAssignmentsLongTermRelation);
  await migrator.create(schema.tagAssignmentsImmutableIdentity);
}

Future<void> _recordMigration(
  DiagnosticsSink? diagnosticsSink, {
  required int fromSchemaVersion,
  required int toSchemaVersion,
  required MigrationOperation migrate,
}) async {
  final stopwatch = Stopwatch()..start();
  recordDiagnosticsSafely(
    diagnosticsSink,
    MigrationDiagnosticsEvent(
      fromSchemaVersion: fromSchemaVersion,
      toSchemaVersion: toSchemaVersion,
      status: const DiagnosticsStarted(),
    ),
  );

  try {
    await migrate();
    recordDiagnosticsSafely(
      diagnosticsSink,
      MigrationDiagnosticsEvent(
        fromSchemaVersion: fromSchemaVersion,
        toSchemaVersion: toSchemaVersion,
        status: DiagnosticsSucceeded(stopwatch.elapsed),
      ),
    );
  } on Object catch (error) {
    recordDiagnosticsSafely(
      diagnosticsSink,
      MigrationDiagnosticsEvent(
        fromSchemaVersion: fromSchemaVersion,
        toSchemaVersion: toSchemaVersion,
        status: DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _migrationFailureCode(error),
        ),
      ),
    );
    rethrow;
  }
}

DiagnosticsFailureCode _migrationFailureCode(Object error) => switch (error) {
  IncompatibleLocalDataSchemaException() =>
    DiagnosticsFailureCode.incompatibleSchema,
  CorruptLocalDataSchemaException() => DiagnosticsFailureCode.corruption,
  _ => DiagnosticsFailureCode.unexpected,
};

Future<void> _verifyNewStorageHasNoSchema(GeneratedDatabase database) async {
  final schemaObjects = await database.customSelect('''
        SELECT name FROM sqlite_schema
        WHERE type IN ('table', 'index', 'trigger', 'view')
          AND name NOT LIKE 'sqlite_%'
      ''').get();

  if (schemaObjects.isNotEmpty) throw const CorruptLocalDataSchemaException();
}

Future<void> _verifyStoredSchemaVersion(
  GeneratedDatabase database, {
  required int expectedSchemaVersion,
}) async {
  final schemaVersion = await database
      .customSelect('PRAGMA user_version')
      .getSingle();
  if (schemaVersion.read<int>('user_version') != expectedSchemaVersion) {
    throw const CorruptLocalDataSchemaException();
  }
}

Future<void> runAtomicMigration(
  GeneratedDatabase database, {
  required int targetSchemaVersion,
  required MigrationOperation migrate,
}) async {
  if (targetSchemaVersion < 1) {
    throw ArgumentError.value(
      targetSchemaVersion,
      'targetSchemaVersion',
      'Целевая версия схемы должна быть положительной.',
    );
  }

  await database.customStatement('PRAGMA foreign_keys = OFF');

  try {
    await database.transaction(() async {
      await migrate();

      final foreignKeyViolations = await database
          .customSelect('PRAGMA foreign_key_check')
          .get();
      if (foreignKeyViolations.isNotEmpty) {
        throw StateError('Проверка внешних ключей после миграции не пройдена.');
      }

      await verifyIntentionTitlesFtsIntegrity(database);
      await database.customStatement(
        'PRAGMA user_version = $targetSchemaVersion',
      );
    });
  } finally {
    await database.customStatement('PRAGMA foreign_keys = ON');
  }
}

Future<void> rebuildIntentionTitlesFts(GeneratedDatabase database) {
  return database.customStatement(
    "INSERT INTO intention_titles_fts(intention_titles_fts) VALUES ('rebuild')",
  );
}
