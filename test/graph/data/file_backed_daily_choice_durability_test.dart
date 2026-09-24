import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/local_database_harness.dart';

void main() {
  test(
    'полное повторное открытие сохраняет выборы, шаги и зависимости',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      var database = await harness.openReadyDatabase();
      await seedDurabilityGraph(database);
      for (final (choice, firstStep) in [(201, 301), (202, 303)]) {
        expect(
          await durabilityRepository(
            database,
            choiceNumber: choice,
            firstStepNumber: firstStep,
          ).execute(durabilityCreate()),
          isA<GraphCommandSucceeded>(),
        );
      }
      final confirmed = await durabilityState(database);
      await harness.closePersistenceObjectGraph();

      database = await harness.openReadyDatabase();
      expect(await durabilityState(database), confirmed);
      final choices = await durabilityRows(database, 'daily_choices');
      expect(choices.map((row) => row['id']), [
        durabilityUuid(201),
        durabilityUuid(202),
      ]);
      expect(choices.map((row) => row['creation_sequence']), [1, 2]);
      expect(choices.map((row) => row['choice_date']), [
        '2026-09-23',
        '2026-09-23',
      ]);
      expect(choices.map((row) => row['description']), [
        '  Выбор\nдня  ',
        '  Выбор\nдня  ',
      ]);
      expect(choices.map((row) => row['is_completed']), [1, 1]);
      final steps = await durabilityRows(database, 'daily_choice_path_steps');
      expect(steps.map((row) => row['id']), [
        durabilityUuid(301),
        durabilityUuid(302),
        durabilityUuid(303),
        durabilityUuid(304),
      ]);
      expect(steps.map((row) => row['previous_step_id']), [
        null,
        durabilityUuid(301),
        null,
        durabilityUuid(303),
      ]);
      final repository = durabilityRepository(database);
      for (final number in [201, 202]) {
        final result = await repository.getDailyChoice(
          durabilityChoice(number),
        );
        expect(result, isA<DailyChoiceReadSuccess>());
        final details = (result as DailyChoiceReadSuccess).value.value!;
        expect(details.choice.date, CalendarDate.fromParts(2026, 9, 23));
        expect(details.path.map((step) => step.relation.id), [
          durabilityRelation(101),
          durabilityRelation(102),
        ]);
      }
      final relation = await repository
          .watchRelation(durabilityRelation(101))
          .first;
      expect(
        (relation as LongTermRelationReadSuccess)
            .value
            .value!
            .permissions
            .canDelete,
        isFalse,
      );
      expect(await _sourceChoiceCount(repository), 2);
      await _expectIntegrity(database);

      expect(
        await repository.execute(DeleteDailyChoice(durabilityChoice(202))),
        isA<GraphCommandSucceeded>(),
      );
      await harness.closePersistenceObjectGraph();
      database = await harness.openReadyDatabase();
      expect(
        await durabilityRepository(
          database,
          choiceNumber: 203,
          firstStepNumber: 305,
        ).execute(durabilityCreate()),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        (await durabilityRows(
          database,
          'daily_choices',
        )).map((row) => (row['id'], row['creation_sequence'])),
        [(durabilityUuid(201), 1), (durabilityUuid(203), 3)],
      );
      await _expectIntegrity(database);
    },
  );

  for (final operation in _DailyOperation.values) {
    for (final stopPoint in _StopPoint.values) {
      test(
        'завершение процесса ${operation.description} ${stopPoint.description} сохраняет целый результат',
        () async {
          final harness = await LocalDatabaseHarness.fileBacked();
          addTearDown(harness.dispose);
          var database = await harness.openReadyDatabase();
          await seedDurabilityGraph(database);
          if (operation != _DailyOperation.create &&
              operation != _DailyOperation.bottomCreate) {
            expect(
              await durabilityRepository(database).execute(durabilityCreate()),
              isA<GraphCommandSucceeded>(),
            );
          }
          final before = await durabilityState(database);
          await harness.closePersistenceObjectGraph();

          await _killWorkerAt(harness, operation, stopPoint);

          database = await harness.openReadyDatabase();
          if (stopPoint == _StopPoint.beforeCommit) {
            expect(await durabilityState(database), before);
          } else {
            await _expectCommittedOperation(database, operation);
          }
          await _expectIntegrity(database);
          final repository = durabilityRepository(database);
          final choice = await repository.getDailyChoice(
            durabilityChoice(
              operation == _DailyOperation.create ||
                      operation == _DailyOperation.bottomCreate
                  ? 203
                  : 201,
            ),
          );
          expect(choice, isA<DailyChoiceReadSuccess>());
          final present = stopPoint == _StopPoint.beforeCommit
              ? operation != _DailyOperation.create &&
                    operation != _DailyOperation.bottomCreate
              : operation != _DailyOperation.delete &&
                    operation != _DailyOperation.mixedDelete;
          expect(
            (choice as DailyChoiceReadSuccess).value.value != null,
            present,
          );
          expect(await _sourceChoiceCount(repository), present ? 1 : 0);
          final isReplaced =
              operation == _DailyOperation.replace &&
              stopPoint == _StopPoint.afterCommit;
          if (present) {
            final details = choice.value.value!;
            expect(
              details.path.map((step) => step.relation.id),
              isReplaced
                  ? [durabilityRelation(103)]
                  : [durabilityRelation(101), durabilityRelation(102)],
            );
            expect(
              details.choice.date,
              operation == _DailyOperation.update &&
                      stopPoint == _StopPoint.afterCommit
                  ? CalendarDate.fromParts(2027, 1, 2)
                  : CalendarDate.fromParts(2026, 9, 23),
            );
          }
          final relation = await repository
              .watchRelation(durabilityRelation(101))
              .first;
          expect(
            (relation as LongTermRelationReadSuccess)
                .value
                .value!
                .permissions
                .canDelete,
            !present || isReplaced,
          );
        },
        timeout: Timeout.none,
      );
    }
  }
}

Future<void> _expectCommittedOperation(
  AppDatabase database,
  _DailyOperation operation,
) async {
  final choices = await durabilityRows(database, 'daily_choices');
  final steps = await durabilityRows(database, 'daily_choice_path_steps');
  final relations = await durabilityRows(database, 'long_term_relations');
  switch (operation) {
    case _DailyOperation.create || _DailyOperation.bottomCreate:
      expect(choices, hasLength(1));
      expect(choices.single['id'], durabilityUuid(203));
      expect(choices.single['choice_date'], '2026-09-23');
      expect(steps.map((row) => row['id']), [
        durabilityUuid(311),
        durabilityUuid(312),
      ]);
    case _DailyOperation.update:
      expect(choices.single['choice_date'], '2027-01-02');
      expect(choices.single['description'], '  Изменено  ');
      expect(choices.single['is_completed'], 0);
      expect(steps.map((row) => row['id']), [
        durabilityUuid(301),
        durabilityUuid(302),
      ]);
    case _DailyOperation.replace:
      expect(choices.single['selected_intention_id'], durabilityUuid(4));
      expect(choices.single['choice_date'], '2026-09-23');
      expect(choices.single['is_completed'], 1);
      expect(steps.single['id'], durabilityUuid(313));
      expect(steps.single['long_term_relation_id'], durabilityUuid(103));
    case _DailyOperation.delete:
      expect(choices, isEmpty);
      expect(steps, isEmpty);
      expect(relations, hasLength(4));
    case _DailyOperation.mixedDelete:
      expect(choices, isEmpty);
      expect(steps, isEmpty);
      expect(
        relations.map((row) => row['id']),
        isNot(contains(durabilityUuid(104))),
      );
      expect(relations, hasLength(3));
  }
}

Future<void> _expectIntegrity(AppDatabase database) async {
  expect(
    await database.customSelect('PRAGMA foreign_key_check').get(),
    isEmpty,
  );
  expect(
    (await database.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
      'foreign_keys',
    ),
    1,
  );
}

Future<int> _sourceChoiceCount(DriftPersonalGraphRepository repository) async {
  final result = await repository.getRelationCounts(durabilityIntention(1));
  return (result as ResultSuccess<GraphSnapshot<RelationCounts>>)
      .value
      .value
      .dailySource;
}

Future<void> _killWorkerAt(
  LocalDatabaseHarness harness,
  _DailyOperation operation,
  _StopPoint stopPoint,
) async {
  final executable = _findFlutterExecutable();
  final workerPath = File.fromUri(
    Directory.current.uri.resolve(
      'test/support/graph_operation_process_worker.dart',
    ),
  ).path;
  final process = await Process.start(
    executable,
    ['test', '--no-pub', '--reporter', 'compact', workerPath],
    workingDirectory: Directory.current.path,
    environment: {
      'DOABLE_GRAPH_OPERATION': operation.environmentValue,
      'DOABLE_GRAPH_STOP_POINT': stopPoint.environmentValue,
      'DOABLE_GRAPH_DATABASE_PATH': harness.databaseFile.path,
      'TZ': 'Pacific/Honolulu',
    },
  );
  final output = StringBuffer();
  final errors = StringBuffer();
  final ready = Completer<int>();
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  int? startedWorkerPid;
  process.stdout.transform(utf8.decoder).listen((chunk) {
    output.write(chunk);
    final started = RegExp(r'DOABLE_GRAPH_WORKER_STARTED:(\d+)')
        .firstMatch(output.toString());
    if (started != null) startedWorkerPid = int.parse(started.group(1)!);
    final match = RegExp(r'DOABLE_GRAPH_WORKER_READY:(\d+)')
        .firstMatch(output.toString());
    if (match != null && !ready.isCompleted) {
      ready.complete(int.parse(match.group(1)!));
    }
  }, onDone: stdoutDone.complete);
  process.stderr
      .transform(utf8.decoder)
      .listen(errors.write, onDone: stderrDone.complete);
  unawaited(
    process.exitCode.then((code) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError(
            'Рабочий процесс завершился до ${stopPoint.name}: '
            '$code\n$output\n$errors',
          ),
        );
      }
    }),
  );
  var killed = false;
  try {
    final workerPid = await ready.future.timeout(const Duration(minutes: 2));
    killed = Process.killPid(workerPid, ProcessSignal.sigkill);
    expect(killed, isTrue);
  } finally {
    if (!killed) {
      final workerPid = startedWorkerPid;
      if (workerPid != null) Process.killPid(workerPid, ProcessSignal.sigkill);
      process.kill(ProcessSignal.sigkill);
    }
  }
  expect(await process.exitCode.timeout(const Duration(seconds: 15)), isNot(0));
  await Future.wait([stdoutDone.future, stderrDone.future]);
}

String _findFlutterExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate = File(
      '${directory.path}/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
    );
    if (candidate.existsSync()) return candidate.path;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Flutter SDK не найден.');
    }
    directory = parent;
  }
}

enum _DailyOperation {
  create('daily_create', 'создания выбора'),
  bottomCreate('daily_bottom_create', 'создания нижнего выбора'),
  update('daily_update', 'изменения выбора'),
  replace('daily_replace', 'замены пути'),
  delete('daily_delete', 'удаления выбора'),
  mixedDelete('daily_mixed_delete', 'смешанного удаления');

  const _DailyOperation(this.environmentValue, this.description);
  final String environmentValue;
  final String description;
}

enum _StopPoint {
  beforeCommit('before_commit', 'до commit'),
  afterCommit('after_commit', 'после commit');

  const _StopPoint(this.environmentValue, this.description);
  final String environmentValue;
  final String description;
}
