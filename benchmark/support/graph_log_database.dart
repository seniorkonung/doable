import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/data/local/app_database.dart'
    show LocalDatabaseConnectionObserver;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../test/support/in_memory_diagnostics_sink.dart';
import '../../test/support/local_database_harness.dart';
import 'benchmark.dart';
import 'graph_log_fixture.dart';
import 'graph_log_memory_worker.dart';

/// Граф в пропорциях профиля решения 15 дизайна в файловой базе с базовым
/// снимком позиции 0.
final class GraphLogDatabase {
  GraphLogDatabase._(this.harness, this.raw, this.repository, this.fixture)
    : snapshots = GraphSnapshotStore.directoryIn(harness.temporaryDirectory);

  static Future<GraphLogDatabase> prepare(
    int entities, {
    int hubRelations = 0,
    LocalDatabaseConnectionObserver? observer,
  }) async {
    final harness = await LocalDatabaseHarness.fileBacked();
    late sqlite.Database raw;
    final database = await harness.openReadyDatabase(
      setup: (connection) => raw = connection,
      observer: observer,
    );
    final fixture = GraphLogFixture(entities, hubRelations: hubRelations);
    final graph = GraphLogDatabase._(
      harness,
      raw,
      DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => now,
        InMemoryDiagnosticsSink(),
      ),
      fixture,
    );
    final preparation = Stopwatch()..start();
    fixture.populate(raw);
    // Снимок базы — состояние на позиции 0, с которого начинается лог.
    final snapshot = await Zone.root.run(
      GraphSnapshotStore(
        log: graph.repository,
        directory: graph.snapshots,
        clock: () => now,
        diagnosticsSink: InMemoryDiagnosticsSink(),
      ).rebuildSnapshot,
    );
    preparation.stop();
    stdout.writeln(
      jsonEncode({
        'benchmark': 'graphLogFixture',
        'entities': entities,
        'tags': fixture.tags,
        'intentions': fixture.intentions,
        'tagAssignments': fixture.tagAssignments,
        'longTermRelations': fixture.longTermRelations,
        'dailyChoices': fixture.dailyChoices,
        'hubRelations': hubRelations,
        'preparationMs': preparation.elapsedMilliseconds,
        'databaseBytes': harness.databaseFile.lengthSync(),
        'snapshotBytes': snapshot.byteSize,
        'environment': Platform.operatingSystem,
        'dart': Platform.version,
        'sqlite': sqlite.sqlite3.version.libVersion,
        'warmups': benchmarkWarmups,
        'repetitions': benchmarkSamples,
      }),
    );
    return graph;
  }

  /// Показание часов репозитория, снимков и операций над графом.
  static final now = DateTime.utc(2026, 10, 17, 12);

  final LocalDatabaseHarness harness;
  final sqlite.Database raw;
  final DriftPersonalGraphRepository repository;
  final GraphLogFixture fixture;
  final Directory snapshots;

  /// Номер следующей правки: каждая правка затрагивает новую сущность.
  var _edits = 0;

  /// Подтверждает [count] команд, каждая из которых пишет один пакет:
  /// правки названий намерений и описаний дневных выборов поочерёдно, а с
  /// [longDescriptions] — описания намерений на пределе графем.
  Future<void> confirmEdits(int count, {bool longDescriptions = false}) async {
    final before = await repository.readCurrentPosition();
    final results = await Zone.root.run(() async {
      final results = <Object>[];
      for (var index = 0; index < count; index++) {
        final edit = _edits++;
        results.add(
          await repository.execute(
            _edit(edit, longDescription: longDescriptions),
          ),
        );
      }
      return results;
    });
    expect(results, everyElement(isA<GraphCommandSucceeded>()));
    expect(await repository.readCurrentPosition(), before + count);
  }

  GraphCommand<GraphCommandOutcome, GraphCommandFailure> _edit(
    int edit, {
    required bool longDescription,
  }) {
    if (longDescription) {
      final intention = edit % fixture.intentions;
      return UpdateIntention(
        id: fixture.intentionId(intention),
        title: fixture.intentionTitle(intention),
        description: _longDescription(edit),
      );
    }
    final entity = edit ~/ 2;
    if (edit.isEven) {
      final intention = entity % fixture.intentions;
      return UpdateIntention(
        id: fixture.intentionId(intention),
        title: '${fixture.intentionTitle(intention)} · правка $edit',
        description: fixture.intentionDescription(intention),
      );
    }
    return UpdateDailyChoiceFields(
      choiceId: fixture.dailyChoiceId(entity % fixture.dailyChoices),
      patch: DailyChoiceFieldsPatch(
        description: DailyChoiceDescriptionSet(
          DailyChoiceDescription.fromInput('Правка $edit')!,
        ),
      ),
    );
  }

  /// Память операции [operation] в отдельном процессе над этой базой.
  Future<GraphLogMemory> measureMemory(GraphLogMemoryOperation operation) =>
      measureGraphLogMemory(
        operation,
        harness.databaseFile,
        snapshots: snapshots,
      );

  Future<void> dispose() => harness.dispose();
}

/// Описание намерения на пределе графем из русского текста.
String _longDescription(int edit) {
  final text = StringBuffer();
  while (text.length < IntentionText.maxDescriptionLength) {
    text.write('Шаг $edit: подробно описать, зачем он нужен и как понять, ');
  }
  return '${text.toString().substring(0, IntentionText.maxDescriptionLength - 1)}.';
}
