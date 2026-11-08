import 'dart:convert';
import 'dart:io';

import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_holding.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/benchmark.dart';
import '../support/contribution_statistics_fixture.dart';
import '../../test/support/in_memory_diagnostics_sink.dart';
import '../../test/support/intention_cascade_execution.dart';
import '../../test/support/local_database_harness.dart';

const _supporting = ContributionStatisticsFixture.cascadeSupportingIntentions;
const _relations = ContributionStatisticsFixture.cascadeRelations;

void main() {
  test('бенчмарк каскада намерения', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    late sqlite.Database raw;
    final database = await harness.openReadyDatabase(
      setup: (value) => raw = value,
    );
    final fixture = ContributionStatisticsFixture(
      ContributionStatisticsProfile.longPaths,
    );
    final preparation = Stopwatch()..start();
    fixture
      ..populate(raw)
      ..assignIntentionKinds(raw);
    preparation.stop();
    expect(_scalar(raw, 'SELECT COUNT(*) FROM intentions'), 50000);
    expect(_scalar(raw, 'SELECT COUNT(*) FROM long_term_relations'), 150000);
    // Архивирование и восстановление чередуются на одном подграфе, а каждое
    // удаление получает новый.
    var generation = 0;
    IntentionId hang() => _intention(
      ContributionStatisticsFixture.hangCascadeSubgraph(raw, generation++),
    );
    final toggled = hang();
    _report({
      'intentions': 50000,
      'relations': 150000,
      'subgraphSupportingIntentions': _supporting,
      'subgraphRelations': _relations,
      'preparationMs': preparation.elapsedMilliseconds,
      'samples': benchmarkSamples,
      'warmups': benchmarkWarmups,
    });

    for (final operation in CascadeOperation.values) {
      final benchmarkCase = 'cascade/${operation.name}';
      if (!benchmarkIncludes(benchmarkCase)) continue;
      final previews = <Duration>[];
      final commands = <Duration>[];
      for (
        var sample = -benchmarkWarmups;
        sample < benchmarkSamples;
        sample++
      ) {
        final subject = operation == CascadeOperation.delete ? hang() : toggled;
        // Новое хранилище читает подграф, записанный мимо команд, и
        // начинает со своей ревизии.
        final diagnostics = InMemoryDiagnosticsSink();
        final repository = DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 11, 8),
          diagnostics,
        );
        final archived =
            _scalar(
              raw,
              "SELECT is_archived FROM intentions WHERE id = '${subject.toCanonicalString()}'",
            ) ==
            1;
        if (operation == CascadeOperation.archive && archived) {
          _expectSucceeded(
            await repository.execute(
              await previewedRestoreIntention(repository, subject),
            ),
          );
        } else if (operation == CascadeOperation.restore && !archived) {
          _expectSucceeded(
            await repository.execute(
              await previewedArchiveIntention(repository, subject),
            ),
          );
        }
        expect(
          await repository.getIntentionHolding({subject}),
          isA<IntentionHoldingRead>(),
        );
        final eventsBefore = diagnostics.events.length;

        final previewWatch = Stopwatch()..start();
        final preview = await repository.previewCascade(
          IntentionCascadeSubject(subject),
          operation,
        );
        previewWatch.stop();
        expect(
          diagnostics.events
              .skip(eventsBefore)
              .whereType<IntentionHoldingIndexDiagnosticsEvent>(),
          isEmpty,
          reason: 'предпросмотр читает построенный индекс удержания',
        );
        final command = _command(subject, preview);

        final commandWatch = Stopwatch()..start();
        final result = await repository.execute(command);
        commandWatch.stop();
        _expectSucceeded(result);
        if (sample < 0) continue;
        previews.add(previewWatch.elapsed);
        commands.add(commandWatch.elapsed);
      }
      _report({
        'case': benchmarkCase,
        'previewP95Ms': benchmarkP95(previews),
        'commandP95Ms': benchmarkP95(commands),
      });
      // Бюджеты по образцу статистики: предпросмотр — чтение в общей
      // очереди, команда — одна транзакция записи всего каскада.
      reportBenchmarkBudget(benchmarkCase, 'preview', previews, 100);
      reportBenchmarkBudget(benchmarkCase, 'command', commands, 1250);
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}

/// Команда варианта «со вспомогательными» из [preview], который уносит или
/// возвращает весь подграф.
IntentionCommand _command(IntentionId subject, CascadePreviewResult preview) {
  switch (preview) {
    case ArchiveCascadePreview(:final plan):
      expect(plan.withSupporting.departing, hasLength(_supporting));
      expect(plan.withSupporting.archivedRelationCount, _relations);
      return ArchiveIntention(
        subject,
        execution: CascadeExecution.withSupporting(plan),
      );
    case RestoreCascadePreview(:final plan):
      expect(plan.withSupporting.restored, hasLength(_supporting));
      expect(plan.withSupporting.restoredRelationCount, _relations);
      return RestoreIntention(
        subject,
        execution: CascadeExecution.withSupporting(plan),
      );
    case IntentionDeleteCascadePreview(:final plan):
      expect(plan.withSupporting.departing, hasLength(_supporting));
      expect(plan.withSupporting.deletedRelationCount, _relations);
      expect(plan.withSupporting.archivedByInvariant, isEmpty);
      return DeleteIntention(
        subject,
        execution: CascadeExecution.withSupporting(plan),
      );
    case RelationDeleteCascadePreview() || CascadePreviewFailure():
      fail('Предпросмотр намерения не прочитан: ${preview.runtimeType}');
  }
}

void _expectSucceeded(GraphResult<Object?, GraphCommandFailure> result) =>
    expect(result, isA<GraphResultSuccess<Object?, GraphCommandFailure>>());

IntentionId _intention(String value) =>
    (IntentionId.decode(value) as IntentionIdDecodingSuccess).id;

int _scalar(sqlite.Database database, String sql) =>
    database.select(sql).single.values.single as int;

void _report(Map<String, Object> values) => stdout.writeln(jsonEncode(values));
