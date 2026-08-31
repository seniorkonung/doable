import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:drift/drift.dart';

import 'generated_schema.dart' as generated;

typedef MigrationOperation = Future<void> Function();

MigrationStrategy localDataMigrationStrategy(GeneratedDatabase database) {
  return MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from >= to) {
        throw UnsupportedError(
          'Понижение версии схемы локальных данных не поддерживается.',
        );
      }

      await runAtomicMigration(
        database,
        targetSchemaVersion: to,
        migrate: () => generated.stepByStep()(migrator, from, to),
      );
    },
    beforeOpen: (_) => database.customStatement('PRAGMA foreign_keys = ON'),
  );
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
