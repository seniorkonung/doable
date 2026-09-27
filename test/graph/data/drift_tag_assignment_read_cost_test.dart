@Tags(['slow'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignments_page.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

const _tagCount = 1203;

final class _Select {
  const _Select(this.sql, this.arguments, this.rows);

  final String sql;
  final List<Object?> arguments;
  final int rows;
}

final class _Trace extends LocalDatabaseConnectionObserver {
  final selects = <_Select>[];

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    selects.add(
      _Select(statement.statements.single, statement.arguments, rows.length),
    );
    return rows;
  }
}

final class _Page {
  const _Page(this.ids, this.assigned, this.next, this.elapsed, this.selects);

  final List<String> ids;
  final List<bool> assigned;
  final Object? next;
  final int elapsed;
  final List<_Select> selects;
}

void main() {
  test(
    'большие назначения и выбор читаются ограниченными порциями',
    _measureTagAssignmentReadCost,
  );
}

Future<void> _measureTagAssignmentReadCost() async {
  final directory = await Directory.systemTemp.createTemp(
    'doable_assignment_cost_',
  );
  final file = File('${directory.path}/assignments.sqlite');
  final trace = _Trace();
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
    seedLargeTagReadFixture(raw, tagCount: _tagCount);
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 27),
      InMemoryDiagnosticsSink(),
    );
    final intention = IntentionTagTarget(
      (IntentionId.decode(tagFixtureId(1)) as IntentionIdDecodingSuccess).id,
    );
    final relation = LongTermRelationTagTarget(
      (LongTermRelationId.decode(
        tagFixtureId(101),
      ) as LongTermRelationIdDecodingSuccess).id,
    );

    Future<_Page> read(
      TagTarget target,
      int size,
      String kind,
      Object? cursor,
    ) async {
      trace.selects.clear();
      final timer = Stopwatch()..start();
      final List<String> ids;
      final List<bool> assigned;
      final Object? next;
      if (kind == 'assignments') {
        final result = await repository.getTagAssignmentsPage(
          TagAssignmentsQuery(
            target: target,
            pageSize: size,
            cursor: cursor as TagAssignmentsCursor?,
          ),
        );
        expect(result, isA<TagAssignmentsPageSuccess>());
        final page = (result as TagAssignmentsPageSuccess).value;
        ids = [for (final tag in page.items) tag.id.toCanonicalString()];
        assigned = const [];
        next = page.nextCursor;
      } else {
        final result = await repository.getTagCatalogPage(
          TagCatalogQuery(
            pageSize: size,
            mode: TagCatalogSelectionMode(target),
            cursor: cursor as TagCatalogCursor?,
          ),
        );
        expect(result, isA<TagCatalogPageSuccess>());
        final page =
            (result as TagCatalogPageSuccess).value as TagSelectionPage;
        ids = [for (final row in page.rows) row.tag.id.toCanonicalString()];
        assigned = [for (final row in page.rows) row.isAssigned];
        next = page.nextCursor;
      }
      timer.stop();
      final selects = List<_Select>.of(trace.selects);
      expect(selects, hasLength(3));
      expect(selects[0].sql, contains('SELECT 1 FROM'));
      expect(selects[1].sql, contains('LEFT JOIN tags'));
      expect(selects[0].rows, 1);
      expect(selects[1].rows, 0);
      final main = selects[2];
      final sql = main.sql.toUpperCase();
      expect(sql, contains('ORDER BY'));
      expect(sql, contains('LIMIT ?'));
      expect(sql, isNot(contains('OFFSET')));
      expect(sql, isNot(contains('COUNT(')));
      expect(sql, isNot(contains('SELECT *')));
      expect(main.arguments.last, size + 1);
      expect(main.rows, lessThanOrEqualTo(size + 1));
      expect(main.rows, ids.length + (next == null ? 0 : 1));
      expect(ids.length, lessThanOrEqualTo(size));
      if (kind == 'selection') {
        expect(sql, contains('EXISTS(SELECT 1 FROM TAG_ASSIGNMENTS'));
        expect(sql, contains('FROM TAGS T'));
      } else {
        expect(sql, contains('FROM TAG_ASSIGNMENTS A JOIN TAGS T'));
      }
      return _Page(ids, assigned, next, timer.elapsedMicroseconds, selects);
    }

    Future<void> sample(
      TagTarget target,
      int size,
      String kind,
      String position,
      Object? cursor,
      _Page first,
    ) async {
      final durations = <int>[first.elapsed];
      for (var repetition = 1; repetition < 5; repetition++) {
        final again = await read(target, size, kind, cursor);
        expect(again.ids, first.ids);
        expect(again.assigned, first.assigned);
        expect(
          again.selects.map((select) => select.rows),
          first.selects.map((select) => select.rows),
        );
        durations.add(again.elapsed);
      }
      final plans = <List<String>>[
        for (final select in first.selects)
          [
            for (final row in raw.select(
              'EXPLAIN QUERY PLAN ${select.sql}',
              select.arguments,
            ))
              row['detail'].toString(),
          ],
      ];
      expect(plans.every((plan) => plan.isNotEmpty), isTrue);
      debugPrintSynchronously(
        jsonEncode({
          'kind': 'tag_assignment_page',
          'target': target is IntentionTagTarget ? 'intention' : 'relation',
          'read': kind,
          'tags': _tagCount,
          'pageSize': size,
          'position': position,
          'selectsPerPage': first.selects.length,
          'materializedRowsPerSelect': [
            for (final select in first.selects) select.rows,
          ],
          'elapsedMicroseconds': durations,
          'sql': [for (final select in first.selects) select.sql],
          'plans': plans,
        }),
      );
    }

    Future<void> traverse(TagTarget target, int size, String kind) async {
      final expected = [
        for (var index = 0; index < _tagCount; index++)
          if (kind == 'selection' ||
              (target is IntentionTagTarget ? index.isEven : index % 3 == 0))
            tagFixtureId(10000 + index),
      ];
      final pageCount = (expected.length / size).ceil();
      final ids = <String>[];
      final assigned = <bool>[];
      final samples = <String, (Object?, _Page)>{};
      Object? cursor;
      var pages = 0;
      var rows = 0;
      var elapsed = 0;
      do {
        final queryCursor = cursor;
        final page = await read(target, size, kind, cursor);
        pages++;
        rows += page.selects.fold<int>(0, (sum, select) => sum + select.rows);
        elapsed += page.elapsed;
        ids.addAll(page.ids);
        assigned.addAll(page.assigned);
        cursor = page.next;
        if (pages == 1) samples['first'] = (queryCursor, page);
        if (pages == (pageCount / 2).ceil())
          samples['middle'] = (queryCursor, page);
        if (cursor == null) samples['last'] = (queryCursor, page);
      } while (cursor != null);
      expect(pages, pageCount);
      expect(ids, expected);
      expect(ids.toSet(), hasLength(expected.length));
      if (kind == 'selection') {
        expect(assigned, [
          for (var index = 0; index < _tagCount; index++)
            target is IntentionTagTarget ? index.isEven : index % 3 == 0,
        ]);
      }
      expect(rows, expected.length + pages - 1 + pages);
      for (final position in ['first', 'middle', 'last']) {
        final (sampleCursor, page) = samples[position]!;
        await sample(target, size, kind, position, sampleCursor, page);
      }
      debugPrintSynchronously(
        jsonEncode({
          'kind': 'tag_assignment_traversal',
          'target': target is IntentionTagTarget ? 'intention' : 'relation',
          'read': kind,
          'tags': _tagCount,
          'pageSize': size,
          'queries': pages * 3,
          'materializedRows': rows,
          'resultRows': ids.length,
          'elapsedMicroseconds': elapsed,
        }),
      );
    }

    for (final target in [intention, relation]) {
      for (final kind in ['assignments', 'selection']) {
        for (final size in [1, 50, 100]) {
          await traverse(target, size, kind);
        }
      }
    }
    final sqlitePages =
        raw.select('PRAGMA page_count').single.values.single as int;
    final sqlitePageSize =
        raw.select('PRAGMA page_size').single.values.single as int;
    debugPrintSynchronously(
      jsonEncode({
        'kind': 'tag_assignment_read_fixture',
        'tags': _tagCount,
        'assignments': raw
            .select('SELECT COUNT(*) FROM tag_assignments')
            .single
            .values
            .single,
        'sqliteBytes': sqlitePages * sqlitePageSize,
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
  } finally {
    await database.close();
    await directory.delete(recursive: true);
  }
}
