@Tags(['slow'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

int _measureReferenceCheckVisits(sqlite.Database database, _Select select) {
  var visits = 0;
  database.createFunction(
    functionName: 'measure_assignment_visit',
    function: (_) {
      visits++;
      return 1;
    },
  );
  final measuredSql = select.sql.replaceFirst(
    'AND t.id IS NULL',
    'AND measure_assignment_visit(a.tag_id) = 1 AND t.id IS NULL',
  );
  expect(measuredSql, isNot(select.sql));
  final originalPlan = database
      .select('EXPLAIN QUERY PLAN ${select.sql}', select.arguments)
      .map((row) => row['detail'])
      .toList();
  final measuredPlan = database
      .select('EXPLAIN QUERY PLAN $measuredSql', select.arguments)
      .map((row) => row['detail'])
      .toList();
  expect(measuredPlan, originalPlan);
  expect(database.select(measuredSql, select.arguments), isEmpty);
  return visits;
}

int _measureMainQueryVisits(sqlite.Database database, _Select select) {
  var visits = 0;
  database.createFunction(
    functionName: 'measure_assignment_scan',
    function: (_) {
      visits++;
      return 1;
    },
  );
  final measuredSql = select.sql.replaceFirstMapped(
    RegExp(r'WHERE a\.intention_id = \?'),
    (match) =>
        '${match.group(0)} AND measure_assignment_scan(a.creation_sequence) = 1',
  );
  expect(measuredSql, isNot(select.sql));
  final originalPlan = database
      .select('EXPLAIN QUERY PLAN ${select.sql}', select.arguments)
      .map((row) => row['detail'])
      .toList();
  final measuredPlan = database
      .select('EXPLAIN QUERY PLAN $measuredSql', select.arguments)
      .map((row) => row['detail'])
      .toList();
  expect(measuredPlan, originalPlan);
  expect(
    database.select(measuredSql, select.arguments),
    hasLength(select.rows),
  );
  return visits;
}

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

final class _Snapshot {
  const _Snapshot(this.ids, this.assigned, this.elapsed, this.selects);

  final List<String> ids;
  final List<bool> assigned;
  final int elapsed;
  final List<_Select> selects;
}

void main() {
  for (final tagCount in [203, 1203]) {
    test(
      'назначения и выбор читаются полными снимками при $tagCount тегах',
      () => _measureTagAssignmentReadCost(tagCount),
    );
  }
}

Future<void> _measureTagAssignmentReadCost(int tagCount) async {
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
    seedLargeTagReadFixture(
      raw,
      tagCount: tagCount,
      includeDenseRecipients: true,
    );
    // Посторонние назначения тех же тегов другим намерениям обоих охватов
    // не уменьшают объём, среди которого читаются снимки.
    expect(
      raw.select('SELECT COUNT(*) FROM tag_assignments').single.values.single,
      largeTagReadFixtureAssignmentCount(
        tagCount: tagCount,
        includeDenseRecipients: true,
      ),
    );
    expect(
      raw
          .select('SELECT COUNT(DISTINCT intention_id) FROM tag_assignments')
          .single
          .values
          .single,
      4,
    );
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 27),
      InMemoryDiagnosticsSink(),
    );
    final intention =
        (IntentionId.decode(tagFixtureId(1)) as IntentionIdDecodingSuccess).id;
    final denseIntention =
        (IntentionId.decode(tagFixtureId(2)) as IntentionIdDecodingSuccess).id;

    Future<_Snapshot> read(IntentionId intentionId, String kind) async {
      trace.selects.clear();
      final timer = Stopwatch()..start();
      final List<String> ids;
      final List<bool> assigned;
      if (kind == 'assignments') {
        final result = await repository.getTagAssignments(intentionId);
        expect(result, isA<TagAssignmentsSuccess>());
        final snapshot = (result as TagAssignmentsSuccess).value;
        expect(snapshot.intentionId, intentionId);
        ids = [for (final tag in snapshot.items) tag.id.toCanonicalString()];
        assigned = const [];
      } else {
        final result = await repository.getTagCatalog(
          TagCatalogSelectionMode(intentionId),
        );
        expect(result, isA<TagCatalogSuccess>());
        final snapshot =
            (result as TagCatalogSuccess).value as TagSelectionSnapshot;
        expect(snapshot.intentionId, intentionId);
        ids = [for (final row in snapshot.rows) row.tag.id.toCanonicalString()];
        assigned = [for (final row in snapshot.rows) row.isAssigned];
      }
      timer.stop();
      final selects = List<_Select>.of(trace.selects);
      // Проверка получателя и ссылок имеет постоянную стоимость по числу SQL.
      expect(selects.length, lessThanOrEqualTo(4));
      expect(
        selects.where((select) => select.sql.contains('LEFT JOIN tags')),
        hasLength(1),
      );
      final main = selects.singleWhere(
        (select) => kind == 'assignments'
            ? select.sql.contains('FROM tag_assignments a JOIN tags t')
            : select.sql.contains('FROM tags t'),
      );
      for (final select in selects.where(
        (select) => !identical(select, main),
      )) {
        expect(select.rows, lessThanOrEqualTo(1));
      }
      for (final select in selects) {
        expect(select.sql, isNot(contains('long_term_relation')));
        expect(select.sql, isNot(contains('daily_choice')));
        expect(select.sql, isNot(contains('description')));
        expect(select.sql, isNot(contains('title')));
      }
      final sql = main.sql.toUpperCase();
      expect(sql, contains('ORDER BY'));
      expect(sql, isNot(contains('OFFSET')));
      expect(sql, isNot(contains('COUNT(')));
      expect(sql, isNot(contains('SELECT *')));
      expect(main.rows, ids.length);
      if (kind == 'selection') {
        expect(sql, contains('EXISTS(SELECT 1 FROM TAG_ASSIGNMENTS'));
      }
      return _Snapshot(ids, assigned, timer.elapsedMicroseconds, selects);
    }

    Future<void> sample(
      IntentionId intentionId,
      bool dense,
      String kind,
    ) async {
      final expectedIds = [
        for (var index = 0; index < tagCount; index++)
          if (kind == 'selection' || dense || index.isEven)
            tagFixtureId(10000 + index),
      ];
      final expectedAssigned = [
        for (var index = 0; index < tagCount; index++) dense || index.isEven,
      ];
      final snapshot = await read(intentionId, kind);
      expect(snapshot.ids, expectedIds);
      expect(snapshot.ids.toSet(), hasLength(expectedIds.length));
      if (kind == 'selection') expect(snapshot.assigned, expectedAssigned);
      final durations = [snapshot.elapsed];
      for (var repetition = 1; repetition < 5; repetition++) {
        final again = await read(intentionId, kind);
        expect(again.ids, expectedIds);
        expect(again.assigned, snapshot.assigned);
        expect(again.selects.length, snapshot.selects.length);
        expect(
          again.selects.map((select) => select.rows),
          snapshot.selects.map((select) => select.rows),
        );
        durations.add(again.elapsed);
      }
      final plans = <List<String>>[
        for (final select in snapshot.selects)
          [
            for (final row in raw.select(
              'EXPLAIN QUERY PLAN ${select.sql}',
              select.arguments,
            ))
              row['detail'].toString(),
          ],
      ];
      expect(plans.every((plan) => plan.isNotEmpty), isTrue);
      final main = snapshot.selects.last;
      final mainPlan = plans.last;
      final referenceCheck = snapshot.selects.singleWhere(
        (select) => select.sql.contains('LEFT JOIN tags'),
      );
      final referenceCheckVisits = _measureReferenceCheckVisits(
        raw,
        referenceCheck,
      );
      final assignmentCount = dense ? tagCount : (tagCount + 1) ~/ 2;
      expect(referenceCheckVisits, assignmentCount);
      final mainVisits = kind == 'assignments'
          ? _measureMainQueryVisits(raw, main)
          : null;
      if (kind == 'assignments') {
        const index = 'tag_assignments_intention_order';
        expect(mainPlan.first, contains('SEARCH a USING INDEX $index'));
        expect(mainPlan.join(' '), isNot(contains('USE TEMP B-TREE')));
        expect(mainPlan.join(' '), isNot(contains('SCAN tags')));
        expect(mainVisits, expectedIds.length);
      }
      debugPrintSynchronously(
        jsonEncode({
          'kind': 'tag_assignment_snapshot',
          'recipient': 'intention',
          'density': dense ? 'dense' : 'sparse',
          'read': kind,
          'tags': tagCount,
          'reads': durations.length,
          'selectsPerRead': snapshot.selects.length,
          'materializedRowsPerSelect': [
            for (final select in snapshot.selects) select.rows,
          ],
          'resultRows': snapshot.ids.length,
          'elapsedMicroseconds': durations,
          'mainQueryVisits': mainVisits,
          'referenceCheckRuns': 1,
          'referenceCheckVisits': referenceCheckVisits,
          'sql': [for (final select in snapshot.selects) select.sql],
          'plans': plans,
        }),
      );
    }

    for (final (target, dense) in [
      (intention, false),
      (denseIntention, true),
    ]) {
      for (final kind in ['assignments', 'selection']) {
        await sample(target, dense, kind);
      }
    }
    final sqlitePages =
        raw.select('PRAGMA page_count').single.values.single as int;
    final sqlitePageSize =
        raw.select('PRAGMA page_size').single.values.single as int;
    debugPrintSynchronously(
      jsonEncode({
        'kind': 'tag_assignment_read_fixture',
        'tags': tagCount,
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
