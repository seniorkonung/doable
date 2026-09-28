@Tags(['slow'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

final class _SelectMeasurement {
  const _SelectMeasurement(this.sql, this.arguments, this.rows);

  final String sql;
  final List<Object?> arguments;
  final int rows;
}

final class _CatalogTrace extends LocalDatabaseConnectionObserver {
  final selects = <_SelectMeasurement>[];

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    selects.add(
      _SelectMeasurement(
        statement.statements.single,
        statement.arguments,
        rows.length,
      ),
    );
    return rows;
  }
}

final class _MeasuredSnapshot {
  const _MeasuredSnapshot(
    this.snapshot,
    this.elapsedMicroseconds,
    this.select,
    this.plan,
  );

  final TagCatalogSnapshot snapshot;
  final int elapsedMicroseconds;
  final _SelectMeasurement select;
  final List<String> plan;
}

void main() {
  test(
    'большой каталог читается одним полным снимком без пропусков',
    measureTagCatalogReadCost,
  );
}

Future<void> measureTagCatalogReadCost({
  Future<void> Function(DriftPersonalGraphRepository)? onCatalogReady,
}) async {
  final directory = await Directory.systemTemp.createTemp('doable_tag_cost_');
  final file = File('${directory.path}/catalog.sqlite');
  final trace = _CatalogTrace();
  late sqlite.Database raw;
  final database = AppDatabase(
    observeConfiguredLocalDatabaseConnection(
      openFileBackedLocalDatabase(
        file,
        setup: (connection) => raw = connection,
      ),
      trace,
    ),
  );
  try {
    await database.open();
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      InMemoryDiagnosticsSink(),
    );
    seedTagStorageFixture(raw);

    void seedTo(int count, int current) {
      raw.execute('BEGIN');
      try {
        for (var index = current; index < count; index++) {
          final number = 10000 + index;
          raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
            tagFixtureId(number),
            'Тег ${index.toString().padLeft(6, '0')}',
          ]);
          if (index % 10 == 0) {
            raw.execute(
              'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
              [tagFixtureId(number), tagFixtureId(1)],
            );
          }
        }
        raw.execute('COMMIT');
      } on Object {
        raw.execute('ROLLBACK');
        rethrow;
      }
    }

    Future<_MeasuredSnapshot> read(int count) async {
      trace.selects.clear();
      final watch = Stopwatch()..start();
      final result = await repository.getTagCatalog(
        const TagCatalogBrowseMode(),
      );
      watch.stop();
      expect(result, isA<TagCatalogSuccess>());
      final snapshot = (result as TagCatalogSuccess).value;
      expect(snapshot.items, hasLength(count));
      expect(trace.selects, hasLength(1));
      final select = trace.selects.single;
      final sql = select.sql.toUpperCase();
      expect(sql, contains('FROM TAGS'));
      expect(sql, contains('ORDER BY CREATION_SEQUENCE ASC'));
      expect(sql, isNot(contains('OFFSET')));
      expect(sql, isNot(contains('COUNT(')));
      expect(sql, isNot(contains('TAG_ASSIGNMENTS')));
      expect(sql, isNot(contains('INTENTIONS')));
      expect(sql, isNot(contains('RELATIONS')));
      expect(select.rows, count);
      final plan = [
        for (final row in raw.select(
          'EXPLAIN QUERY PLAN ${select.sql}',
          select.arguments,
        ))
          row['detail'].toString(),
      ];
      expect(plan, isNotEmpty);
      expect(plan.join(' ').toUpperCase(), isNot(contains('USE TEMP B-TREE')));
      return _MeasuredSnapshot(
        snapshot,
        watch.elapsedMicroseconds,
        select,
        plan,
      );
    }

    Future<void> report(int count) async {
      final measured = await read(count);
      final expectedIds = [
        tagFixtureId(firstTagNumber),
        tagFixtureId(lastTagNumber),
        for (var index = 2; index < count; index++) tagFixtureId(10000 + index),
      ];
      expect(
        measured.snapshot.items.map((tag) => tag.id.toCanonicalString()),
        expectedIds,
      );
      expect(
        measured.snapshot.items.map((tag) => tag.id).toSet(),
        hasLength(count),
      );
      final durations = [measured.elapsedMicroseconds];
      for (var repetition = 1; repetition < 5; repetition++) {
        final again = await read(count);
        expect(
          again.snapshot.items.map((tag) => tag.id.toCanonicalString()),
          expectedIds,
        );
        expect(again.select.rows, measured.select.rows);
        expect(again.select.sql, measured.select.sql);
        expect(again.plan, measured.plan);
        durations.add(again.elapsedMicroseconds);
      }
      // Данные измерения не содержат пользовательских названий или id.
      debugPrintSynchronously(
        jsonEncode({
          'kind': 'tag_catalog_snapshot',
          'tags': count,
          'reads': durations.length,
          'selectsPerRead': 1,
          'materializedRowsPerRead': measured.select.rows,
          'elapsedMicroseconds': durations,
          'sql': measured.select.sql,
          'plan': measured.plan,
        }),
      );
    }

    seedTo(1000, 2);
    await report(1000);
    seedTo(10000, 1000);
    await report(10000);
    final sqlitePages =
        raw.select('PRAGMA page_count').single.values.single as int;
    final sqlitePageSize =
        raw.select('PRAGMA page_size').single.values.single as int;
    final assignmentCount =
        raw.select('SELECT COUNT(*) FROM tag_assignments').single.values.single
            as int;
    int bytesIfPresent(File candidate) =>
        candidate.existsSync() ? candidate.lengthSync() : 0;
    debugPrintSynchronously(
      jsonEncode({
        'kind': 'tag_catalog_fixture',
        'tags': 10000,
        'assignments': assignmentCount,
        'sqliteBytes': sqlitePages * sqlitePageSize,
        'dbFileBytes': bytesIfPresent(file),
        'walFileBytes': bytesIfPresent(File('${file.path}-wal')),
        'shmFileBytes': bytesIfPresent(File('${file.path}-shm')),
        'journalMode': raw.select('PRAGMA journal_mode').single.values.single,
        'sqliteVersion': raw
            .select('SELECT sqlite_version()')
            .single
            .values
            .single,
        'platform': Platform.operatingSystem,
        'runtime': Platform.version,
        'buildMode': const bool.fromEnvironment('dart.vm.profile')
            ? 'profile'
            : const bool.fromEnvironment('dart.vm.product')
            ? 'release'
            : 'debug',
      }),
    );
    if (onCatalogReady case final callback?) await callback(repository);
  } finally {
    await database.close();
    await directory.delete(recursive: true);
  }
}
