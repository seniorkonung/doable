import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/migrations/migration_strategy.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/schema_v1_fixture.dart';

const _nextSchemaVersion = AppDatabase.currentSchemaVersion + 1;

void main() {
  test(
    'атомарная миграция откатывает схему, данные и маркер версии после ошибки',
    () async {
      final database = AppDatabase(openInMemoryLocalDatabase());
      addTearDown(database.close);

      await _insertIntention(database);

      await expectLater(
        runAtomicMigration(
          database,
          targetSchemaVersion: _nextSchemaVersion,
          migrate: () async {
            await database.customStatement(
              'ALTER TABLE intentions ADD COLUMN migration_probe TEXT',
            );
            await database.customStatement(
              'UPDATE intentions SET migration_probe = ?',
              ['частично изменённые данные'],
            );
            throw const _InjectedMigrationFailure();
          },
        ),
        throwsA(isA<_InjectedMigrationFailure>()),
      );

      final columns = await database
          .customSelect('PRAGMA table_info(intentions)')
          .get();
      final intention = await database
          .customSelect('SELECT title FROM intentions')
          .getSingle();
      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();

      expect(
        columns.map((column) => column.read<String>('name')),
        isNot(contains('migration_probe')),
      );
      expect(intention.read<String>('title'), 'Сохранённое намерение');
      expect(
        version.read<int>('user_version'),
        AppDatabase.currentSchemaVersion,
      );

      await runAtomicMigration(
        database,
        targetSchemaVersion: _nextSchemaVersion,
        migrate: () async {},
      );

      final retriedVersion = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(retriedVersion.read<int>('user_version'), _nextSchemaVersion);
      expect(database.schemaVersion, AppDatabase.currentSchemaVersion);
    },
  );

  test('контур инъекции ошибки закрывает неуспешное соединение', () async {
    final harness = _FailedMigrationConnectionHarness();
    addTearDown(harness.closeIfNeeded);

    await expectLater(
      harness.run(() {
        return runAtomicMigration(
          harness.database,
          targetSchemaVersion: _nextSchemaVersion,
          migrate: () async => throw const _InjectedMigrationFailure(),
        );
      }),
      throwsA(isA<_InjectedMigrationFailure>()),
    );

    expect(harness.isClosed, isTrue);
  });

  group('диагностика перехода схемы 1 → 3', () {
    test(
      'ошибка получателя до миграции не препятствует подтверждению',
      () async {
        final diagnostics = _SelectivelyThrowingDiagnosticsSink(
          (event) => event.status is DiagnosticsStarted,
        );

        final database = await _openSchema1WithDiagnostics(diagnostics);

        await _expectCurrentSchema(database);
        expect(
          diagnostics.attemptedEvents.map((event) => event.status.runtimeType),
          [DiagnosticsStarted, DiagnosticsSucceeded],
        );
      },
    );

    test('ошибка получателя после миграции не меняет её исход', () async {
      final diagnostics = _SelectivelyThrowingDiagnosticsSink(
        (event) => event.status is DiagnosticsSucceeded,
      );

      final database = await _openSchema1WithDiagnostics(diagnostics);

      await _expectCurrentSchema(database);
      expect(
        diagnostics.attemptedEvents.map((event) => event.status.runtimeType),
        [DiagnosticsStarted, DiagnosticsSucceeded],
      );
    });
  });
}

Future<AppDatabase> _openSchema1WithDiagnostics(
  DiagnosticsSink diagnostics,
) async {
  final temporaryDirectory = await Directory.systemTemp.createTemp(
    'doable_diagnostics_migration_',
  );
  addTearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });
  final databaseFile = File('${temporaryDirectory.path}/doable.sqlite');
  await createSchemaV1Fixture(databaseFile);
  final database = AppDatabase(
    openFileBackedLocalDatabase(databaseFile),
    diagnosticsSink: diagnostics,
  );
  addTearDown(database.close);
  await database.open();
  return database;
}

Future<void> _expectCurrentSchema(AppDatabase database) async {
  final version = await database
      .customSelect('PRAGMA user_version')
      .getSingle();
  final relationTable = await database
      .customSelect(
        "SELECT name FROM sqlite_schema "
        "WHERE type = 'table' AND name = 'long_term_relations'",
      )
      .getSingleOrNull();
  expect(version.read<int>('user_version'), AppDatabase.currentSchemaVersion);
  expect(relationTable?.read<String>('name'), 'long_term_relations');
}

Future<void> _insertIntention(AppDatabase database) {
  return database.customStatement(
    '''
      INSERT INTO intentions (
        id, title, created_at, updated_at
      ) VALUES (?, ?, ?, ?)
    ''',
    [
      '018f0b5d-6b2e-7c80-8000-000000000201',
      'Сохранённое намерение',
      1000000,
      1000000,
    ],
  );
}

final class _InjectedMigrationFailure implements Exception {
  const _InjectedMigrationFailure();
}

final class _SelectivelyThrowingDiagnosticsSink implements DiagnosticsSink {
  _SelectivelyThrowingDiagnosticsSink(this._shouldThrow);

  final bool Function(DiagnosticsEvent event) _shouldThrow;
  final List<DiagnosticsEvent> attemptedEvents = [];

  @override
  void record(DiagnosticsEvent event) {
    attemptedEvents.add(event);
    if (_shouldThrow(event)) {
      throw StateError('CANARY-diagnostics-sink-failure');
    }
  }
}

final class _FailedMigrationConnectionHarness {
  _FailedMigrationConnectionHarness()
    : database = AppDatabase(openInMemoryLocalDatabase());

  final AppDatabase database;
  var isClosed = false;

  Future<void> run(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object {
      await database.close();
      isClosed = true;
      rethrow;
    }
  }

  Future<void> closeIfNeeded() async {
    if (!isClosed) {
      await database.close();
      isClosed = true;
    }
  }
}
