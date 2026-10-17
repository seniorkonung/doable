import 'dart:convert';
import 'dart:io';

import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../test/support/in_memory_diagnostics_sink.dart';
import '../../test/support/intention_catalog_large_fixture.dart';
import '../../test/support/local_database_harness.dart';
import '../support/benchmark.dart';

const _intentions = 50000;

void main() {
  test('бенчмарк каталога намерений: короткие фильтры', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    final database = await harness.openReadyDatabase();
    final preparation = Stopwatch()..start();
    await populateIntentionCatalogFixture(database, _intentions);
    preparation.stop();
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 3),
      InMemoryDiagnosticsSink(),
    );
    stdout.writeln(
      jsonEncode({
        'benchmark': 'intentionCatalog',
        'intentions': _intentions,
        'preparationMs': preparation.elapsedMilliseconds,
        'databaseBytes': harness.databaseFile.lengthSync(),
        'os': Platform.operatingSystem,
        'dart': Platform.version,
        'sqlite': sqlite.sqlite3.version.libVersion,
        'warmups': benchmarkWarmups,
        'repetitions': benchmarkSamples,
      }),
    );
    for (final filter in ['а', 'я', 'аа', 'яя']) {
      final benchmarkCase = 'intentionCatalog/active/shortFilter/$filter';
      if (!benchmarkIncludes(benchmarkCase)) continue;
      final query = IntentionCatalogQuery(
        scope: IntentionScope.active,
        order: IntentionCatalogOrder.createdAtDescending,
        titleFilter: filter,
        pageSize: 100,
      );
      final samples = <Duration>[];
      for (
        var sample = -benchmarkWarmups;
        sample < benchmarkSamples;
        sample++
      ) {
        final watch = Stopwatch()..start();
        final result = await repository.getCatalogPage(query);
        watch.stop();
        expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
        final page = (result as ResultSuccess<IntentionCatalogPage>).value;
        expect(page, isA<IntentionCatalogFirstPage>());
        expect(page.items.length, lessThanOrEqualTo(100));
        expect(
          (page as IntentionCatalogFirstPage).totalCount,
          filter.startsWith('я') ? 0 : _intentions ~/ 2,
        );
        if (sample >= 0) samples.add(watch.elapsed);
      }
      reportBenchmarkBudget(benchmarkCase, 'request', samples, 100);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
