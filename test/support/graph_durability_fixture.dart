import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'graph_seed.dart';
import 'in_memory_diagnostics_sink.dart';

String durabilityUuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

IntentionId durabilityIntention(int number) => (IntentionId.decode(
  durabilityUuid(number),
) as IntentionIdDecodingSuccess).id;

LongTermRelationId durabilityRelation(int number) => (LongTermRelationId.decode(
  durabilityUuid(number),
) as LongTermRelationIdDecodingSuccess).id;

DriftPersonalGraphRepository durabilityRepository(AppDatabase database) =>
    DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      InMemoryDiagnosticsSink(),
    );

Future<void> seedDurabilityGraph(AppDatabase database) =>
    seedGraph(database, () async {
      for (var number = 1; number <= 5; number++) {
        await database.customStatement(
          '''INSERT INTO intentions
         (id, title, kind, is_archived, created_at, updated_at)
         VALUES (?, ?, 'main', 0, 1, 1)''',
          [durabilityUuid(number), 'Намерение $number'],
        );
      }
      for (final (number, source, related, type) in [
        (101, 1, 2, 'need'),
        (102, 2, 3, 'can'),
        (103, 1, 4, 'need'),
        (104, 1, 5, 'can'),
      ]) {
        await database.customStatement(
          '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id,
          type, priority, is_archived, created_at, updated_at)
         VALUES (?, ?, ?, ?, 2, 0, 0, 0)''',
          [
            durabilityUuid(number),
            durabilityUuid(source),
            durabilityUuid(related),
            type,
          ],
        );
      }
    });

Future<List<Map<String, Object?>>> durabilityRows(
  AppDatabase database,
  String table,
) async => [
  for (final row
      in await database
          .customSelect('SELECT * FROM $table ORDER BY rowid')
          .get())
    Map<String, Object?>.from(row.data),
];

/// Полное содержимое SQLite-файла [databaseFile]: версия схемы, объекты
/// схемы и строки всех таблиц, включая служебные.
///
/// Файл читается отдельным соединением, поэтому снимок можно получить и пока
/// приложение держит хранилище открытым. Равенство двух снимков означает, что
/// между ними не изменились ни сохранённые записи, ни схема и ничего нового
/// в хранилище не записано.
Map<String, Object?> durabilityFileState(File databaseFile) {
  final database = sqlite.sqlite3.open(databaseFile.path);
  try {
    final schema = [
      for (final row in database.select(
        'SELECT type, name, tbl_name, sql FROM sqlite_master '
        'ORDER BY type, name',
      ))
        Map<String, Object?>.of(row),
    ];
    return {
      'версия схемы': database.select('PRAGMA user_version').single.values,
      'схема': schema,
      for (final object in schema)
        if (object['type'] == 'table')
          'таблица ${object['name']}': [
            for (final row in database.select(
              'SELECT * FROM "${object['name']}"',
            ))
              Map<String, Object?>.of(row),
          ]..sort((a, b) => '$a'.compareTo('$b')),
    };
  } finally {
    database.close();
  }
}
