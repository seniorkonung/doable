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
  test('бенчмарк каталога намерений: короткие фильтры, подсчёт и порядок по названию', () async {
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
    for (final counting in [
      IntentionCatalogCounting.totalOnly,
      IntentionCatalogCounting.byScopeAndType,
    ]) {
      final benchmarkCase =
          'intentionCatalog/active/counting/${counting.name}/firstPage';
      if (!benchmarkIncludes(benchmarkCase)) continue;
      final query = IntentionCatalogQuery(
        scope: IntentionScope.active,
        order: IntentionCatalogOrder.createdAtDescending,
        titleFilter: null,
        pageSize: 100,
        counting: counting,
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
        final page = _successfulPage(result) as IntentionCatalogFirstPage;
        expect(page.items, hasLength(100));
        _expectHalfArchivedCounts(page, counting);
        if (sample >= 0) samples.add(watch.elapsed);
      }
      reportBenchmarkBudget(benchmarkCase, 'request', samples, 100);
    }
    for (final order in [
      IntentionCatalogOrder.titleAscending,
      IntentionCatalogOrder.titleDescending,
    ]) {
      final firstQuery = IntentionCatalogQuery(
        scope: IntentionScope.active,
        order: order,
        titleFilter: null,
        pageSize: 100,
      );
      final firstCase =
          'intentionCatalog/active/title/${order.direction.name}/firstPage';
      if (benchmarkIncludes(firstCase)) {
        final samples = <Duration>[];
        for (
          var sample = -benchmarkWarmups;
          sample < benchmarkSamples;
          sample++
        ) {
          final watch = Stopwatch()..start();
          final result = await repository.getCatalogPage(firstQuery);
          watch.stop();
          final page = _successfulPage(result) as IntentionCatalogFirstPage;
          expect(page.items, hasLength(100));
          expect(page.totalCount, _intentions ~/ 2);
          if (sample >= 0) samples.add(watch.elapsed);
        }
        reportBenchmarkBudget(firstCase, 'request', samples, 100);
      }
      final continuationCase =
          'intentionCatalog/active/title/${order.direction.name}/continuation';
      if (benchmarkIncludes(continuationCase)) {
        final firstPage = _successfulPage(
          await repository.getCatalogPage(firstQuery),
        );
        final continuationQuery = IntentionCatalogQuery(
          scope: IntentionScope.active,
          order: order,
          titleFilter: null,
          pageSize: 100,
          cursor: firstPage.nextCursor,
        );
        final samples = <Duration>[];
        for (
          var sample = -benchmarkWarmups;
          sample < benchmarkSamples;
          sample++
        ) {
          final watch = Stopwatch()..start();
          final result = await repository.getCatalogPage(continuationQuery);
          watch.stop();
          final page = _successfulPage(result);
          expect(page, isA<IntentionCatalogContinuationPage>());
          expect(page.items, hasLength(100));
          if (sample >= 0) samples.add(watch.elapsed);
        }
        reportBenchmarkBudget(continuationCase, 'request', samples, 100);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Набор наполовину в архиве и без действий: общее количество активного охвата
/// равно половине набора, матрица даёт половину в каждом охвате.
void _expectHalfArchivedCounts(
  IntentionCatalogFirstPage page,
  IntentionCatalogCounting counting,
) {
  expect(page.totalCount, _intentions ~/ 2);
  switch (page.counts) {
    case IntentionCountsTotalOnly():
      expect(counting, IntentionCatalogCounting.totalOnly);
    case IntentionCountsByType():
      fail('Бенчмарк не запрашивает числа типов одного охвата');
    case IntentionCountsByScopeAndType(:final active, :final archived):
      expect(counting, IntentionCatalogCounting.byScopeAndType);
      expect(active.all, _intentions ~/ 2);
      expect(active.actions, 0);
      expect(archived.all, _intentions ~/ 2);
      expect(archived.actions, 0);
  }
}

IntentionCatalogPage _successfulPage(Result<IntentionCatalogPage> result) {
  expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
  return (result as ResultSuccess<IntentionCatalogPage>).value;
}
