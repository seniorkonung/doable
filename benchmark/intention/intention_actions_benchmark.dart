import 'dart:convert';
import 'dart:io';

import 'package:doable/src/action/application/intention_actions.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../test/support/in_memory_diagnostics_sink.dart';
import '../../test/support/local_database_harness.dart';
import '../support/benchmark.dart';
import '../support/contribution_statistics_fixture.dart';
import '../support/intention_statistics_fixture.dart';

/// Страниц до продолжения в глубине списка роли.
const _depthPages = 200;

void main() {
  test('бенчмарк вкладки «Действия»: первая страница с числами ролей и '
      'продолжение в глубине списка', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    late sqlite.Database raw;
    final database = await harness.openReadyDatabase(
      setup: (connection) => raw = connection,
    );
    // Намерение входит в путь каждого из 60 действий дня за три года.
    final fixture = IntentionStatisticsFixture(
      IntentionStatisticsProfile.manyBreakdowns,
    );
    final preparation = Stopwatch()..start();
    fixture.populate(raw);
    preparation.stop();
    final intentionId = (IntentionId.decode(
      ContributionStatisticsFixture.id(fixture.intention),
    ) as IntentionIdDecodingSuccess).id;
    final expected = _referenceCounts(
      raw,
      ContributionStatisticsFixture.id(fixture.intention),
    );
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 6, 15),
      InMemoryDiagnosticsSink(),
    );
    stdout.writeln(
      jsonEncode({
        'benchmark': 'intentionActions',
        'preparationMs': preparation.elapsedMilliseconds,
        'databaseBytes': harness.databaseFile.lengthSync(),
        'actions': raw.select('SELECT COUNT(*) AS n FROM actions').single['n'],
        'intentionPathItems': expected.total,
        'pageSize': IntentionActionsQuery.defaultPageSize,
        'depthPages': _depthPages,
        'os': Platform.operatingSystem,
        'dart': Platform.version,
        'sqlite': sqlite.sqlite3.version.libVersion,
        'warmups': benchmarkWarmups,
        'repetitions': benchmarkSamples,
      }),
    );

    Future<IntentionActionsPage> read(
      IntentionActionRole role, [
      IntentionActionsCursor? cursor,
    ]) async {
      final result = await repository.getIntentionActionsPage(
        IntentionActionsQuery(
          intentionId: intentionId,
          role: role,
          cursor: cursor,
        ),
      );
      final page = (result as IntentionActionsPageSuccess).value;
      expect(page.items, hasLength(IntentionActionsQuery.defaultPageSize));
      return page;
    }

    for (final role in IntentionActionRole.values) {
      final firstCase = 'intentionActions/${role.name}/firstPage';
      if (benchmarkIncludes(firstCase)) {
        final samples = <Duration>[];
        for (
          var sample = -benchmarkWarmups;
          sample < benchmarkSamples;
          sample++
        ) {
          final watch = Stopwatch()..start();
          final page = await read(role);
          watch.stop();
          final counts = (page as IntentionActionsFirstPage).counts;
          expect(
            (counts.root, counts.intermediate, counts.terminal, counts.total),
            (
              expected.root,
              expected.intermediate,
              expected.terminal,
              expected.total,
            ),
          );
          if (sample >= 0) samples.add(watch.elapsed);
        }
        reportBenchmarkBudget(firstCase, 'request', samples, 200);
      }

      final continuationCase = 'intentionActions/${role.name}/deepContinuation';
      if (benchmarkIncludes(continuationCase)) {
        var page = await read(role);
        for (var index = 0; index < _depthPages; index++) {
          page = await read(role, page.nextCursor);
        }
        final deepCursor = page.nextCursor!;
        final samples = <Duration>[];
        for (
          var sample = -benchmarkWarmups;
          sample < benchmarkSamples;
          sample++
        ) {
          final watch = Stopwatch()..start();
          await read(role, deepCursor);
          watch.stop();
          if (sample >= 0) samples.add(watch.elapsed);
        }
        reportBenchmarkBudget(continuationCase, 'request', samples, 10);
      }
    }
  });
}

/// Числа ролей по позициям пути, независимо от хранимой роли строки.
({int root, int intermediate, int terminal, int total}) _referenceCounts(
  sqlite.Database raw,
  String intentionId,
) {
  final row = raw
      .select(
        '''SELECT COUNT(*) AS total,
         SUM(p.position = 0) AS root,
         SUM(p.position > 0 AND n.action_id IS NOT NULL) AS intermediate,
         SUM(n.action_id IS NULL) AS terminal
       FROM action_path_items p
       LEFT JOIN action_path_items n
         ON n.action_id = p.action_id AND n.position = p.position + 1
       WHERE p.intention_id = ?''',
        [intentionId],
      )
      .single;
  return (
    root: row['root'] as int,
    intermediate: row['intermediate'] as int,
    terminal: row['terminal'] as int,
    total: row['total'] as int,
  );
}
