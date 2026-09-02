import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart';

import 'generated_schema.dart' as generated;

typedef MigrationOperation = Future<void> Function();
typedef InitialSchemaObjectCreated = Future<void> Function();

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
  InitialSchemaObjectCreated? onInitialSchemaObjectCreated,
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
              await onInitialSchemaObjectCreated?.call();
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
          migrate: () => generated.stepByStep()(migrator, from, to),
        );
      },
    ),
    beforeOpen: (_) async {
      await database.customStatement('PRAGMA foreign_keys = ON');
      await _verifyStoredSchema(database);
    },
  );
}

Future<void> _recordMigration(
  DiagnosticsSink? diagnosticsSink, {
  required int fromSchemaVersion,
  required int toSchemaVersion,
  required MigrationOperation migrate,
}) async {
  final stopwatch = Stopwatch()..start();
  diagnosticsSink?.record(
    MigrationDiagnosticsEvent(
      fromSchemaVersion: fromSchemaVersion,
      toSchemaVersion: toSchemaVersion,
      status: const DiagnosticsStarted(),
    ),
  );

  try {
    await migrate();
    diagnosticsSink?.record(
      MigrationDiagnosticsEvent(
        fromSchemaVersion: fromSchemaVersion,
        toSchemaVersion: toSchemaVersion,
        status: DiagnosticsSucceeded(stopwatch.elapsed),
      ),
    );
  } on Object catch (error) {
    diagnosticsSink?.record(
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

Future<void> _verifyStoredSchema(GeneratedDatabase database) async {
  try {
    final schemaObjects = await database.customSelect('''
          SELECT name FROM sqlite_schema
          WHERE type IN ('table', 'index', 'trigger')
        ''').get();
    final names = schemaObjects.map((row) => row.read<String>('name')).toSet();

    if (!names.containsAll(_requiredSchemaObjects)) {
      throw const CorruptLocalDataSchemaException();
    }
    await verifyIntentionTitlesFtsIntegrity(database);
  } on CorruptLocalDataSchemaException {
    rethrow;
  } on Object {
    throw const CorruptLocalDataSchemaException();
  }
}

const _requiredSchemaObjects = {
  'intentions',
  'intention_titles_fts',
  'intentions_fts_after_insert',
  'intentions_fts_after_update_title_search_key',
  'intentions_fts_after_delete',
  'intentions_active_created_at_asc_id_asc',
  'intentions_active_created_at_desc_id_asc',
  'intentions_active_updated_at_asc_id_asc',
  'intentions_active_updated_at_desc_id_asc',
  'intentions_archived_created_at_asc_id_asc',
  'intentions_archived_created_at_desc_id_asc',
  'intentions_archived_updated_at_asc_id_asc',
  'intentions_archived_updated_at_desc_id_asc',
  'intentions_all_created_at_asc_id_asc',
  'intentions_all_created_at_desc_id_asc',
  'intentions_all_updated_at_asc_id_asc',
  'intentions_all_updated_at_desc_id_asc',
};

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
