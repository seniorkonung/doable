import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

const publishedIntentionSchemaVersion = 1;
const publishedRelationSchemaVersion = 2;

typedef SchemaFixtureSeed = void Function(sqlite.Database database);

/// Создаёт файловую фикстуру опубликованной схемы намерений версии 1.
///
/// Это намеренно низкоуровневая тестовая граница: схема восстанавливается из
/// зафиксированного snapshot, а каноническая настройка применяется до первого
/// schema statement. Обычные тестовые подключения по-прежнему создаются через
/// [ConfiguredLocalDatabaseConnection].
Future<void> createSchemaV1Fixture(
  File databaseFile, {
  SchemaFixtureSeed? seed,
}) => _createSchemaFixture(
  databaseFile,
  version: publishedIntentionSchemaVersion,
  seed: seed,
);

/// Создаёт файловую фикстуру опубликованной схемы графа версии 2.
Future<void> createSchemaV2Fixture(
  File databaseFile, {
  SchemaFixtureSeed? seed,
}) => _createSchemaFixture(
  databaseFile,
  version: publishedRelationSchemaVersion,
  seed: seed,
);

Future<void> _createSchemaFixture(
  File databaseFile, {
  required int version,
  SchemaFixtureSeed? seed,
}) async {
  if (await databaseFile.exists() && await databaseFile.length() != 0) {
    throw StateError(
      'Фикстура схемы $version требует новый пустой SQLite-файл.',
    );
  }

  await databaseFile.parent.create(recursive: true);
  final database = sqlite.sqlite3.open(databaseFile.path);
  composeDoableSqliteConnectionSetup(null)(database);

  try {
    database.execute('BEGIN IMMEDIATE');
    try {
      for (final statement in await _schemaStatements(version)) {
        database.execute(statement);
      }
      database.execute('PRAGMA user_version = $version');
      seed?.call(database);
      database.execute('COMMIT');
    } on Object {
      database.execute('ROLLBACK');
      rethrow;
    }
  } finally {
    database.close();
  }
}

Future<List<String>> _schemaStatements(int version) async {
  final snapshotFile = File.fromUri(
    Directory.current.uri.resolve('drift_schemas/drift_schema_v$version.json'),
  );
  final decoded = jsonDecode(await snapshotFile.readAsString());
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Snapshot схемы $version не является JSON-объектом.');
  }

  final fixedSql = decoded['fixed_sql'];
  if (fixedSql is! List<Object?> || fixedSql.isEmpty) {
    throw FormatException('Snapshot схемы $version не содержит fixed_sql.');
  }

  final statements = <String>[];
  for (final entry in fixedSql) {
    if (entry is! Map<String, Object?> ||
        entry['name'] is! String ||
        entry['sql'] is! List<Object?>) {
      throw FormatException('Некорректная запись fixed_sql схемы $version.');
    }

    final name = entry['name']! as String;
    final dialects = entry['sql']! as List<Object?>;
    String? sqliteStatement;
    for (final dialect in dialects) {
      if (dialect case <String, Object?>{
        'dialect': 'sqlite',
        'sql': final String statement,
      }) {
        if (sqliteStatement != null) {
          throw FormatException(
            'Объект $name содержит несколько SQLite-определений.',
          );
        }
        sqliteStatement = statement;
      }
    }

    if (sqliteStatement == null) {
      throw FormatException('Объект $name не содержит SQLite-определения.');
    }
    statements.add(sqliteStatement);
  }

  return statements;
}
