import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap.dart';
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  group('lifecycle постоянного локального хранилища', () {
    test('обычный повторный bootstrap не выполняет полный FTS audit', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);

      final firstDatabase = await harness.openReadyDatabase();
      await _insertIntention(
        firstDatabase,
        id: '018f0b5d-6b2e-7c80-8000-000000000303',
        title: 'Первое намерение для проверки открытия',
        createdAt: 1704412800000000,
        updatedAt: 1704412800000000,
      );
      await _insertIntention(
        firstDatabase,
        id: '018f0b5d-6b2e-7c80-8000-000000000304',
        title: 'Второе намерение для проверки открытия',
        createdAt: 1704499200000000,
        updatedAt: 1704499200000000,
      );
      await harness.closePersistenceObjectGraph();

      final sqlTrace = _SqlTrace();
      final bootstrap = LocalDataBootstrap(
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openFileBackedLocalDatabase(harness.databaseFile),
          sqlTrace,
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
      );
      addTearDown(bootstrap.close);

      expect(await bootstrap.open(), isA<LocalDataReady>());
      final trace = sqlTrace.statements.join('\n').toLowerCase();
      expect(trace, contains('pragma user_version'));
      expect(trace, contains('pragma foreign_keys = on'));
      expect(trace, isNot(contains('sqlite_schema')));
      expect(trace, isNot(contains('sqlite_master')));
      expect(trace, isNot(contains('from intentions')));
      expect(trace, isNot(contains('from intention_titles_fts')));
      expect(trace, isNot(contains('integrity-check')));
    });
  });
}

Future<void> _insertIntention(
  GeneratedDatabase database, {
  required String id,
  required String title,
  String? description,
  bool isActionReady = false,
  bool isArchived = false,
  required int createdAt,
  required int updatedAt,
}) {
  return database.customStatement(
    '''
      INSERT INTO intentions (
        id,
        title,
        description,
        is_action_ready,
        is_archived,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      id,
      title,
      description,
      isActionReady ? 1 : 0,
      isArchived ? 1 : 0,
      createdAt,
      updatedAt,
    ],
  );
}

final class _SqlTrace extends LocalDatabaseConnectionObserver {
  final statements = <String>[];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    statements.addAll(statement.statements);
  }
}
