import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/doable_schema_verifier.dart';

void main() {
  test(
    'схема 1 после обновления совпадает с новой установкой версии 2',
    () async {
      final snapshot = jsonDecode(
        File('drift_schemas/drift_schema_v1.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final entities = (snapshot['fixed_sql'] as List)
          .cast<Map<String, dynamic>>();
      final database = AppDatabase(
        openInMemoryLocalDatabase(
          setup: (raw) {
            configureDoableSqliteConnection(raw);
            for (final entity in entities) {
              final statements = (entity['sql'] as List)
                  .cast<Map<String, dynamic>>();
              for (final statement in statements) {
                if (statement['dialect'] == 'sqlite') {
                  raw.execute(statement['sql'] as String);
                }
              }
            }
            raw.execute('PRAGMA user_version = 1');
          },
        ),
      );
      addTearDown(database.close);

      await database.open();

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 2);
      await verifyDoableDatabaseSchema(database);
    },
  );

  test('сохраняемая схема не ссылается на функции проверки связей', () async {
    final database = AppDatabase(openInMemoryLocalDatabase());
    addTearDown(database.close);

    final references = await database.customSelect('''
      SELECT name
      FROM sqlite_schema
      WHERE sql LIKE '%doable_relation_%'
    ''').get();

    expect(references, isEmpty);
  });
}
