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

final class _MeasuredPage {
  const _MeasuredPage(
    this.page,
    this.elapsedMicroseconds,
    this.select,
    this.plan,
  );

  final TagCatalogPage page;
  final int elapsedMicroseconds;
  final _SelectMeasurement select;
  final List<String> plan;
}

void main() {
  test(
    'большой каталог читается ограниченными страницами без пропусков',
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

    Future<_MeasuredPage> read(TagCatalogQuery query) async {
      trace.selects.clear();
      final watch = Stopwatch()..start();
      final result = await repository.getTagCatalogPage(query);
      watch.stop();
      expect(result, isA<TagCatalogPageSuccess>());
      final page = (result as TagCatalogPageSuccess).value;
      expect(trace.selects, hasLength(1));
      final select = trace.selects.single;
      final sql = select.sql.toUpperCase();
      expect(sql, contains('FROM TAGS'));
      expect(sql, contains('ORDER BY CREATION_SEQUENCE ASC LIMIT ?'));
      expect(sql, isNot(contains('OFFSET')));
      expect(sql, isNot(contains('COUNT(')));
      expect(sql, isNot(contains('TAG_ASSIGNMENTS')));
      expect(sql, isNot(contains('INTENTIONS')));
      expect(sql, isNot(contains('RELATIONS')));
      expect(select.arguments.last, query.pageSize + 1);
      expect(select.rows, lessThanOrEqualTo(query.pageSize + 1));
      expect(
        select.rows,
        page.items.length + (page.nextCursor == null ? 0 : 1),
      );
      final plan = [
        for (final row in raw.select(
          'EXPLAIN QUERY PLAN ${select.sql}',
          select.arguments,
        ))
          row['detail'].toString(),
      ];
      expect(plan, isNotEmpty);
      expect(plan.join(' ').toUpperCase(), isNot(contains('USE TEMP B-TREE')));
      return _MeasuredPage(page, watch.elapsedMicroseconds, select, plan);
    }

    Future<void> report(
      int count,
      int size,
      String position,
      TagCatalogQuery query,
      _MeasuredPage measured,
    ) async {
      final durations = [measured.elapsedMicroseconds];
      for (var repetition = 1; repetition < 5; repetition++) {
        final again = await read(query);
        expect(
          again.page.items.map((tag) => tag.id),
          measured.page.items.map((tag) => tag.id),
        );
        expect(again.select.rows, measured.select.rows);
        expect(again.select.sql, measured.select.sql);
        expect(again.plan, measured.plan);
        durations.add(again.elapsedMicroseconds);
      }
      // Данные измерения не содержат пользовательских названий или id.
      debugPrintSynchronously(
        jsonEncode({
          'kind': 'tag_catalog_page',
          'tags': count,
          'pageSize': size,
          'position': position,
          'queries': durations.length,
          'materializedRowsPerQuery': measured.select.rows,
          'elapsedMicroseconds': durations,
          'sql': measured.select.sql,
          'plan': measured.plan,
        }),
      );
    }

    Future<void> traverse(int count) async {
      const size = 50;
      final ids = <String>[];
      TagCatalogCursor? cursor;
      var pages = 0;
      var rows = 0;
      var totalMicroseconds = 0;
      do {
        final query = TagCatalogQuery(pageSize: size, cursor: cursor);
        final measured = await read(query);
        pages++;
        rows += measured.select.rows;
        totalMicroseconds += measured.elapsedMicroseconds;
        ids.addAll(
          measured.page.items.map((tag) => tag.id.toCanonicalString()),
        );
        cursor = measured.page.nextCursor;
        if (pages == 1 || pages == (count ~/ size) ~/ 2 || cursor == null) {
          await report(
            count,
            size,
            cursor == null
                ? 'last'
                : pages == 1
                ? 'first'
                : 'middle',
            query,
            measured,
          );
        }
      } while (cursor != null);

      expect(pages, (count / size).ceil());
      expect(rows, count + pages - 1);
      expect(ids, hasLength(count));
      expect(ids.toSet(), hasLength(count));
      expect(ids.take(2), [
        tagFixtureId(firstTagNumber),
        tagFixtureId(lastTagNumber),
      ]);
      expect(ids.skip(2), [
        for (var index = 2; index < count; index++) tagFixtureId(10000 + index),
      ]);
      debugPrintSynchronously(
        jsonEncode({
          'kind': 'tag_catalog_traversal',
          'tags': count,
          'pageSize': size,
          'queries': pages,
          'materializedRows': rows,
          'elapsedMicroseconds': totalMicroseconds,
        }),
      );
    }

    seedTo(1000, 2);
    for (final size in [1, 50, 100]) {
      final query = TagCatalogQuery(pageSize: size);
      await report(1000, size, 'first', query, await read(query));
    }
    await traverse(1000);

    seedTo(10000, 1000);
    for (final size in [1, 50, 100]) {
      final query = TagCatalogQuery(pageSize: size);
      await report(10000, size, 'first', query, await read(query));
    }
    await traverse(10000);
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
