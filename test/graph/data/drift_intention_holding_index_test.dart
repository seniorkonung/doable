import 'dart:async';
import 'dart:typed_data';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph/data/intention_holding_computation.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_holding.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/action_seed.dart';
import '../../support/graph_durability_fixture.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/intention_cascade_execution.dart';
import '../../support/local_database_harness.dart';

/// Граф проверок: главные 1 и 4, цепочка вспомогательных 1 → 2 → 3,
/// вспомогательное 5 под главным 1, вспомогательные 6 и 7 нужны только друг
/// другу, а архивное вспомогательное 8 связано с 1 архивной связью.
/// Связи: 101 (1 → 2), 102 (2 → 3), 103 (1 → 4), 104 (1 → 5), 105 (6 → 7),
/// 106 (7 → 6), 107 (1 → 8, архивная).
void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late _ControlledRunner runner;
  late DriftPersonalGraphRepository repository;
  late DriftPersonalGraphRepository previews;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    database = await harness.openReadyDatabase();
    await seedDurabilityGraph(database);
    await seedGraph(database, () async {
      for (final (number, archived) in [(6, 0), (7, 0), (8, 1)]) {
        await database.customStatement(
          '''INSERT INTO intentions
             (id, title, kind, is_archived, created_at, updated_at)
             VALUES (?, ?, 'supporting', ?, 1, 1)''',
          [durabilityUuid(number), 'Намерение $number', archived],
        );
      }
      await database.customStatement(
        '''UPDATE intentions SET kind = 'supporting' WHERE id IN (?, ?, ?)''',
        [durabilityUuid(2), durabilityUuid(3), durabilityUuid(5)],
      );
      for (final (number, source, related, archived) in [
        (105, 6, 7, 0),
        (106, 7, 6, 0),
        (107, 1, 8, 1),
      ]) {
        await database.customStatement(
          '''INSERT INTO long_term_relations
             (id, source_intention_id, related_intention_id,
              type, priority, is_archived, created_at, updated_at)
             VALUES (?, ?, ?, 'need', 2, ?, 0, 0)''',
          [
            durabilityUuid(number),
            durabilityUuid(source),
            durabilityUuid(related),
            archived,
          ],
        );
      }
      await insertAction(
        database,
        id: seedActionId(201).toCanonicalString(),
        path: [durabilityUuid(1), durabilityUuid(2)],
      );
    });
    diagnostics = InMemoryDiagnosticsSink();
    runner = _ControlledRunner();
    // Отдельный репозиторий читает предпросмотр команд, не прогревая индекс
    // удержания и не обращаясь к счётчику проверяемого репозитория.
    previews = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 11, 7),
      diagnostics,
    );
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 11, 7),
      diagnostics,
      intentionHoldingRunner: runner.run,
    );
  });
  tearDown(() => harness.dispose());

  Future<ConfirmedGraphResult<GraphCommandOutcome>> confirm(
    GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
  ) async {
    final result = await repository.execute(command);
    expect(result, isA<GraphCommandSucceeded>());
    return (result as GraphCommandSucceeded).value;
  }

  Future<GraphRevision> currentRevision() async =>
      ((await repository.watchIntention(durabilityIntention(1)).first)
              as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
          .value
          .revision;

  Future<Map<int, IntentionHolding>> holdings(Iterable<int> numbers) async {
    final result = await repository.getIntentionHolding({
      for (final number in numbers) durabilityIntention(number),
    });
    expect(result, isA<IntentionHoldingRead>());
    final read = result as IntentionHoldingRead;
    expect(
      read.revision.compareTo(await currentRevision()),
      GraphRevisionOrder.same,
    );
    return {
      for (final number in numbers)
        number: read.holdings[durabilityIntention(number)]!,
    };
  }

  test('удержание читается по идентификаторам на текущей ревизии', () async {
    expect(await holdings([1, 2, 3, 4, 5, 6, 7, 8]), {
      1: IntentionHolding.held,
      2: IntentionHolding.held,
      3: IntentionHolding.held,
      4: IntentionHolding.held,
      5: IntentionHolding.held,
      6: IntentionHolding.notHeld,
      7: IntentionHolding.notHeld,
      8: IntentionHolding.notHeld,
    });
    expect(runner.calls, 1);
    expect(
      [
        for (final event in diagnostics.events)
          if (event case IntentionHoldingIndexDiagnosticsEvent(
            :final stage,
            :final status,
          ))
            (stage, status.runtimeType),
      ],
      [
        (IntentionHoldingIndexDiagnosticsStage.intentions, DiagnosticsStarted),
        (
          IntentionHoldingIndexDiagnosticsStage.intentions,
          DiagnosticsSucceeded,
        ),
        (IntentionHoldingIndexDiagnosticsStage.relations, DiagnosticsStarted),
        (IntentionHoldingIndexDiagnosticsStage.relations, DiagnosticsSucceeded),
        (IntentionHoldingIndexDiagnosticsStage.computation, DiagnosticsStarted),
        (
          IntentionHoldingIndexDiagnosticsStage.computation,
          DiagnosticsSucceeded,
        ),
      ],
    );
  });

  test('граф больше порции чтения читается целиком', () async {
    // Цепочка вспомогательных 1001 → … → 2030 под главным 1 длиннее порции
    // и намерений, и связей; удержание её конца требует всех порций.
    await seedGraph(database, () async {
      for (var number = 1001; number <= 2030; number++) {
        await database.customStatement(
          '''INSERT INTO intentions
             (id, title, kind, is_archived, created_at, updated_at)
             VALUES (?, ?, 'supporting', 0, 1, 1)''',
          [durabilityUuid(number), 'Намерение $number'],
        );
        await database.customStatement(
          '''INSERT INTO long_term_relations
             (id, source_intention_id, related_intention_id,
              type, priority, is_archived, created_at, updated_at)
             VALUES (?, ?, ?, 'need', 2, 0, 0, 0)''',
          [
            durabilityUuid(number + 10000),
            durabilityUuid(number == 1001 ? 1 : number - 1),
            durabilityUuid(number),
          ],
        );
      }
    });

    expect(await holdings([2030, 6]), {
      2030: IntentionHolding.held,
      6: IntentionHolding.notHeld,
    });
  });

  test('одновременные чтения ждут одно построение', () async {
    runner.hold();
    final first = repository.getIntentionHolding({durabilityIntention(6)});
    final second = repository.getIntentionHolding({durabilityIntention(2)});
    await runner.entered.future;
    runner.release();

    expect(
      (await first as IntentionHoldingRead).holdings.values.single,
      IntentionHolding.notHeld,
    );
    expect(
      (await second as IntentionHoldingRead).holdings.values.single,
      IntentionHolding.held,
    );
    expect(runner.calls, 1);
  });

  test('создание намерений, их текст, теги и действия не сбрасывают индекс, '
      'а ответ относится к новой ревизии', () async {
    await holdings([2]);
    final created = await confirm(
      const CreateIntention(title: 'Новое намерение', description: null),
    );
    final tag = await confirm(
      CreateTag(
        name: TagName.fromInput('Дом'),
        color: null,
        placement: TagPlacement.first,
      ),
    );
    final packages = [
      created,
      await confirm(
        UpdateIntention(
          id: durabilityIntention(2),
          title: 'Название',
          description: 'Описание',
        ),
      ),
      tag,
      await confirm(
        AssignTag(
          tagId: (tag.value as TagCreated).tag.id,
          intentionId: durabilityIntention(2),
        ),
      ),
      await confirm(
        UpdateActionFields(
          actionId: seedActionId(201),
          patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
        ),
      ),
      await confirm(DeleteAction(seedActionId(201))),
    ];

    for (final package in packages) {
      expect(package.changes, isNot(contains(isA<IntentionHoldingChanged>())));
    }
    final createdId = (created.value as IntentionSaved).intention.id;
    final read = await repository.getIntentionHolding({
      createdId,
      durabilityIntention(2),
      durabilityIntention(6),
    }) as IntentionHoldingRead;
    expect(read.holdings, {
      createdId: IntentionHolding.held,
      durabilityIntention(2): IntentionHolding.held,
      durabilityIntention(6): IntentionHolding.notHeld,
    });
    expect(
      read.revision.compareTo(await currentRevision()),
      GraphRevisionOrder.same,
    );
    expect(runner.calls, 1);
  });

  for (final (name, command, expected)
      in <
        (
          String,
          Future<GraphCommand<GraphCommandOutcome, GraphCommandFailure>>
          Function(),
          Map<int, IntentionHolding>,
        )
      >[
        (
          'создание связи',
          () async => AddLongTermRelations(
            pageIntentionId: durabilityIntention(4),
            group: IntentionRelationGroup.needs,
            candidateIds: [durabilityIntention(6)],
          ),
          {6: IntentionHolding.held, 7: IntentionHolding.held},
        ),
        (
          'изменение связи',
          () async => UpdateLongTermRelation(
            relationId: durabilityRelation(101),
            patch: const LongTermRelationPatch(
              priority: LongTermRelationFieldSet(RelationPriority.p4),
            ),
          ),
          {2: IntentionHolding.held, 3: IntentionHolding.held},
        ),
        (
          'архивирование связи',
          () => previewedArchiveRelation(previews, durabilityRelation(101)),
          {2: IntentionHolding.notHeld, 3: IntentionHolding.notHeld},
        ),
        (
          'удаление связи',
          () => previewedDeleteRelation(previews, durabilityRelation(102)),
          {2: IntentionHolding.held, 3: IntentionHolding.notHeld},
        ),
        (
          'смена вида',
          () async =>
              ChangeIntentionKind(durabilityIntention(6), IntentionKind.main),
          {6: IntentionHolding.held, 7: IntentionHolding.held},
        ),
        (
          'архивирование намерения',
          () => previewedArchiveIntention(previews, durabilityIntention(2)),
          {2: IntentionHolding.notHeld, 3: IntentionHolding.notHeld},
        ),
      ]) {
    test(
      '$name сбрасывает индекс, и пакет несёт изменение удержания',
      () async {
        await holdings(expected.keys);
        final confirmed = await confirm(await command());

        expect(
          confirmed.changes
              .whereType<IntentionHoldingChanged>()
              .single
              .revision
              .compareTo(confirmed.revision),
          GraphRevisionOrder.same,
        );
        expect(await holdings(expected.keys), expected);
        expect(runner.calls, 2);
      },
    );
  }

  Future<CascadePlan<ArchiveCascadeComposition>> archivePlan(
    CascadeSubject subject,
  ) async => (await previews.previewCurrentCascade(
    subject,
    CascadeOperation.archive,
  ) as ArchiveCascadePreview).plan;

  test('архивирование намерения меняет состав и удержание по варианту, '
      'переданному командой', () async {
    final plan = await archivePlan(
      IntentionCascadeSubject(durabilityIntention(2)),
    );
    expect(plan.withSupporting.departing, [durabilityIntention(3)]);
    expect(plan.onlyThis.promoted, [durabilityIntention(3)]);
    expect(await holdings([2, 3]), {
      2: IntentionHolding.held,
      3: IntentionHolding.held,
    });

    final onlyThis = await confirm(
      ArchiveIntention(
        durabilityIntention(2),
        execution: CascadeExecution(
          choice: CascadeChoice.onlyThis,
          expected: plan.onlyThis,
        ),
      ),
    );

    final executed =
        onlyThis.changes.whereType<CascadeOutcome>().single.executed
            as ArchiveCascadeComposition;
    expect(executed.departing, isEmpty);
    expect(executed.promoted, [durabilityIntention(3)]);
    // «3» стало главным и удерживает само себя, а архивное «2» — нет.
    expect(await holdings([2, 3]), {
      2: IntentionHolding.notHeld,
      3: IntentionHolding.held,
    });
    expect(runner.calls, 2);
  });

  test('восстановление связи и намерения сбрасывает индекс', () async {
    // «7» становится главным и удерживает «6» связью 106.
    final plan = await archivePlan(
      RelationCascadeSubject(durabilityRelation(105)),
    );
    expect(await holdings([6]), {6: IntentionHolding.notHeld});
    await confirm(
      ArchiveLongTermRelation(
        durabilityRelation(105),
        execution: CascadeExecution(
          choice: CascadeChoice.onlyThis,
          expected: plan.onlyThis,
        ),
      ),
    );
    expect(await holdings([6]), {6: IntentionHolding.held});
    final restored = await confirm(
      await previewedRestoreRelation(previews, durabilityRelation(105)),
    );
    expect(restored.changes, contains(isA<IntentionHoldingChanged>()));
    expect(await holdings([6]), {6: IntentionHolding.held});

    await confirm(
      await previewedArchiveIntention(previews, durabilityIntention(4)),
    );
    expect(await holdings([4]), {4: IntentionHolding.notHeld});
    final restoredIntention = await confirm(
      await previewedRestoreIntention(previews, durabilityIntention(4)),
    );
    expect(restoredIntention.changes, contains(isA<IntentionHoldingChanged>()));
    expect(await holdings([4]), {4: IntentionHolding.held});
    expect(runner.calls, 5);
  });

  test('удаление намерения сбрасывает индекс', () async {
    final created = await confirm(
      const CreateIntention(title: 'Новое намерение', description: null),
    );
    await holdings([2]);
    final deleted = await confirm(
      await previewedDeleteIntention(
        previews,
        (created.value as IntentionSaved).intention.id,
      ),
    );

    expect(deleted.changes, contains(isA<IntentionHoldingChanged>()));
    await holdings([2]);
    expect(runner.calls, 2);
  });

  test('команда без изменений не сбрасывает индекс', () async {
    await holdings([2]);
    for (final command
        in <
          Future<GraphCommand<GraphCommandOutcome, GraphCommandFailure>>
          Function()
        >[
          () async => UpdateLongTermRelation(
            relationId: durabilityRelation(101),
            patch: const LongTermRelationPatch(),
          ),
          () async => ChangeIntentionKind(
            durabilityIntention(2),
            IntentionKind.supporting,
          ),
          () async => givenArchiveIntention(durabilityIntention(8)),
        ]) {
      expect(
        (await confirm(await command())).changes,
        isNot(contains(isA<IntentionHoldingChanged>())),
      );
    }
    await holdings([2]);
    expect(runner.calls, 1);
  });

  test('построенный для устаревшей ревизии результат отбрасывается', () async {
    // Предпросмотр команды читается до удержания построения индекса.
    final archival = await previewedArchiveRelation(
      previews,
      durabilityRelation(101),
    );
    runner.hold();
    final reading = repository.getIntentionHolding({durabilityIntention(2)});
    await runner.entered.future;
    await confirm(archival);
    runner.release();

    expect(await reading, isA<IntentionHoldingExpired>());
    expect(
      diagnostics.events
          .whereType<IntentionHoldingIndexDiagnosticsEvent>()
          .last,
      isA<IntentionHoldingIndexDiagnosticsEvent>()
          .having(
            (event) => event.stage,
            'этап',
            IntentionHoldingIndexDiagnosticsStage.computation,
          )
          .having(
            (event) => event.status,
            'исход',
            isA<DiagnosticsFailed>().having(
              (status) => status.code,
              'категория',
              DiagnosticsFailureCode.conflict,
            ),
          ),
    );
    expect(await holdings([2]), {2: IntentionHolding.notHeld});
  });

  test('отказ построения отличим от «не удерживается», пишется в диагностику '
      'и не запоминается', () async {
    runner.failNext();

    expect(
      await repository.getIntentionHolding({durabilityIntention(6)}),
      isA<IntentionHoldingFailed>(),
    );
    expect(
      diagnostics.events
          .whereType<IntentionHoldingIndexDiagnosticsEvent>()
          .last,
      isA<IntentionHoldingIndexDiagnosticsEvent>()
          .having(
            (event) => event.stage,
            'этап',
            IntentionHoldingIndexDiagnosticsStage.computation,
          )
          .having(
            (event) => event.status,
            'исход',
            isA<DiagnosticsFailed>().having(
              (status) => status.code,
              'категория',
              DiagnosticsFailureCode.unexpected,
            ),
          ),
    );
    expect(await holdings([6]), {6: IntentionHolding.notHeld});
    expect(runner.calls, 2);
  });
}

/// Считает построения индекса и по запросу задерживает или проваливает
/// подсчёт, сохраняя настоящий результат.
final class _ControlledRunner {
  var calls = 0;
  var _fail = false;
  Completer<void>? _gate;
  final entered = Completer<void>();

  void hold() => _gate = Completer<void>();

  void release() {
    _gate!.complete();
    _gate = null;
  }

  void failNext() => _fail = true;

  Future<Uint8List> run(IntentionHoldingGraph graph) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    await _gate?.future;
    if (_fail) {
      _fail = false;
      throw StateError('Подсчёт отказал');
    }
    return computeIntentionHolding(graph);
  }
}
