@Tags(['slow'])
library;

import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
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
  const _MeasuredSnapshot(this.snapshot, this.select);

  final TagCatalogSnapshot snapshot;
  final _SelectMeasurement select;
}

void main() {
  test(
    'большой каталог читается одним полным снимком без пропусков',
    measureTagCatalogReadCost,
  );
}

Future<void> measureTagCatalogReadCost() async {
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
      final result = await repository.getTagCatalog(
        const TagCatalogBrowseMode(),
      );
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
      return _MeasuredSnapshot(snapshot, select);
    }

    Future<void> expectFullSnapshot(int count) async {
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
    }

    seedTo(10000, 2);
    await expectFullSnapshot(10000);
  } finally {
    await database.close();
    await directory.delete(recursive: true);
  }
}
