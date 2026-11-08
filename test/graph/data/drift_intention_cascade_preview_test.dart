import 'dart:async';
import 'dart:typed_data';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph/data/intention_holding_computation.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/action_seed.dart';
import '../../support/graph_durability_fixture.dart';
import '../../support/graph_seed.dart';
import '../../support/local_database_harness.dart';

/// Граф проверок: главные «Быть здоровым» (1), «Высыпаться» (4) и «Сходить в
/// поход» (5), вспомогательные «Много ходить» (2) и «Хорошая обувь» (3).
/// Связи «нужно»: 101 (1 → 2), 102 (2 → 3), 103 (2 → 4), 104 (5 → 3).
/// Архивированы главное «Старая форма» (6), вспомогательное «Разминка» (7) и
/// связь 105 (6 → 7). «Высыпаться» входит в путь действия.
void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late _HookedDiagnosticsSink diagnostics;
  late _ControlledRunner runner;
  late DriftPersonalGraphRepository repository;

  const titles = {
    1: 'Быть здоровым',
    2: 'Много ходить',
    3: 'Хорошая обувь',
    4: 'Высыпаться',
    5: 'Сходить в поход',
    6: 'Старая форма',
    7: 'Разминка',
  };

  Future<void> insertIntention(
    int number,
    String title, {
    required String kind,
    bool archived = false,
  }) => database.customStatement(
    '''INSERT INTO intentions
       (id, title, kind, is_archived, created_at, updated_at)
       VALUES (?, ?, ?, ?, 1, 1)''',
    [durabilityUuid(number), title, kind, archived ? 1 : 0],
  );

  Future<void> insertRelation(
    int number,
    int source,
    int related, {
    bool archived = false,
  }) => database.customStatement(
    '''INSERT INTO long_term_relations
       (id, source_intention_id, related_intention_id,
        type, priority, is_archived, created_at, updated_at)
       VALUES (?, ?, ?, 'need', 2, ?, 0, 0)''',
    [
      durabilityUuid(number),
      durabilityUuid(source),
      durabilityUuid(related),
      archived ? 1 : 0,
    ],
  );

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    database = await harness.openReadyDatabase();
    await seedGraph(database, () async {
      for (final MapEntry(key: number, value: title) in titles.entries) {
        await insertIntention(
          number,
          title,
          kind: const {2, 3, 7}.contains(number) ? 'supporting' : 'main',
          archived: number >= 6,
        );
      }
      for (final (number, source, related, archived) in [
        (101, 1, 2, false),
        (102, 2, 3, false),
        (103, 2, 4, false),
        (104, 5, 3, false),
        (105, 6, 7, true),
      ]) {
        await insertRelation(number, source, related, archived: archived);
      }
      await insertAction(
        database,
        id: seedActionId(201).toCanonicalString(),
        path: [durabilityUuid(4)],
      );
    });
    diagnostics = _HookedDiagnosticsSink();
    runner = _ControlledRunner();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 11, 8),
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

  Future<CascadePreviewResult> previewIntention(
    int number,
    CascadeOperation operation,
  ) => repository.previewCascade(
    IntentionCascadeSubject(durabilityIntention(number)),
    operation,
  );

  Future<CascadePreviewResult> previewRelation(
    int number,
    CascadeOperation operation,
  ) => repository.previewCascade(
    RelationCascadeSubject(durabilityRelation(number)),
    operation,
  );

  List<int> numbers(List<IntentionId> ids) => [
    for (final id in ids)
      titles.keys.firstWhere((number) => durabilityIntention(number) == id),
  ];

  Map<IntentionId, String> titlesOf(Iterable<int> numbers) => {
    for (final number in numbers) durabilityIntention(number): titles[number]!,
  };

  test('архивирование намерения читает составы обоих вариантов, вопрос и '
      'названия на текущей ревизии', () async {
    final preview = await previewIntention(1, CascadeOperation.archive);

    expect(preview, isA<ArchiveCascadePreview>());
    final archive = preview as ArchiveCascadePreview;
    expect(
      archive.revision.compareTo(await currentRevision()),
      GraphRevisionOrder.same,
    );
    expect(archive.plan.asksQuestion, isTrue);
    expect(numbers(archive.plan.withSupporting.departing), [2]);
    expect(numbers(archive.plan.withSupporting.mainsLosingRelation), [4]);
    expect(numbers(archive.plan.onlyThis.promoted), [2]);
    expect(archive.titles, titlesOf([2, 4]));
    expect(
      [
        for (final event in diagnostics.events)
          if (event case IntentionCascadePreviewDiagnosticsEvent(
            :final stage,
            :final status,
          ))
            (stage, status.runtimeType),
      ],
      [
        for (final stage in IntentionCascadePreviewDiagnosticsStage.values) ...[
          (stage, DiagnosticsStarted),
          (stage, DiagnosticsSucceeded),
        ],
      ],
    );
  });

  test('удаление связи планируется по её участникам', () async {
    final preview = await previewRelation(101, CascadeOperation.delete);

    expect(preview, isA<RelationDeleteCascadePreview>());
    final delete = preview as RelationDeleteCascadePreview;
    expect(delete.plan.asksQuestion, isTrue);
    expect(numbers(delete.plan.withSupporting.departing), [2]);
    expect(numbers(delete.plan.withSupporting.mainsLosingRelation), [1, 4]);
    expect(delete.plan.withSupporting.deletedRelationCount, 3);
    expect(delete.titles, titlesOf([2, 1, 4]));
  });

  test('восстановление намерения читает возвращаемые намерения', () async {
    final preview = await previewIntention(6, CascadeOperation.restore);

    expect(preview, isA<RestoreCascadePreview>());
    final restore = preview as RestoreCascadePreview;
    expect(restore.plan.asksQuestion, isTrue);
    expect(numbers(restore.plan.withSupporting.restored), [7]);
    expect(restore.plan.onlyThis.restored, isEmpty);
    expect(restore.titles, titlesOf([7]));
  });

  test(
    'удаление намерения несёт признак участия в сохранённых путях',
    () async {
      final inPath = await previewIntention(4, CascadeOperation.delete);
      final withoutPaths = await previewIntention(5, CascadeOperation.delete);

      expect(
        inPath,
        isA<IntentionDeleteCascadePreview>().having(
          (preview) => preview.isInActionPath,
          'в пути',
          isTrue,
        ),
      );
      expect(
        withoutPaths,
        isA<IntentionDeleteCascadePreview>().having(
          (preview) => preview.isInActionPath,
          'в пути',
          isFalse,
        ),
      );
    },
  );

  test('намерение, созданное после построения индекса, планируется одно и '
      'без вопроса, а несуществующего предмета нет', () async {
    expect(
      await previewIntention(1, CascadeOperation.archive),
      isA<ArchiveCascadePreview>(),
    );
    final created = await confirm(
      const CreateIntention(title: 'Новое намерение', description: null),
    );
    final subject = IntentionCascadeSubject(
      (created.value as IntentionSaved).intention.id,
    );

    final archive = await repository.previewCascade(
      subject,
      CascadeOperation.archive,
    );
    final delete = await repository.previewCascade(
      subject,
      CascadeOperation.delete,
    );

    expect(runner.calls, 1);
    expect(archive, isA<ArchiveCascadePreview>());
    final archivePlan = (archive as ArchiveCascadePreview).plan;
    expect(archivePlan.asksQuestion, isFalse);
    expect(archivePlan.withSupporting.departing, isEmpty);
    expect(archivePlan.withSupporting.mainsLosingRelation, isEmpty);
    expect(archivePlan.withSupporting.archivedRelationCount, 0);
    expect(delete, isA<IntentionDeleteCascadePreview>());
    final deletePlan = (delete as IntentionDeleteCascadePreview).plan;
    expect(deletePlan.asksQuestion, isFalse);
    expect(deletePlan.withSupporting.departing, isEmpty);
    expect(deletePlan.withSupporting.archivedByInvariant, isEmpty);
    expect(deletePlan.withSupporting.deletedRelationCount, 0);
    expect(delete.titles, isEmpty);
    expect(
      await previewIntention(99, CascadeOperation.archive),
      isA<CascadePreviewSubjectNotFound>(),
    );
    expect(
      await previewRelation(199, CascadeOperation.delete),
      isA<CascadePreviewSubjectNotFound>(),
    );
  });

  test('операция, неприменимая к состоянию предмета, отличима от отсутствия '
      'предмета', () async {
    for (final preview in [
      previewIntention(6, CascadeOperation.archive),
      previewIntention(1, CascadeOperation.restore),
      previewRelation(105, CascadeOperation.archive),
      previewRelation(101, CascadeOperation.restore),
    ]) {
      expect(await preview, isA<CascadePreviewOperationInapplicable>());
    }
    expect(
      diagnostics.events
          .whereType<IntentionCascadePreviewDiagnosticsEvent>()
          .last
          .status,
      isA<DiagnosticsFailed>().having(
        (status) => status.code,
        'категория',
        DiagnosticsFailureCode.validation,
      ),
    );
  });

  test('названия больше одной части читаются целиком', () async {
    // 401 вспомогательное под «Сходить в поход» — на одно больше части.
    await seedGraph(database, () async {
      for (var number = 1001; number <= 1401; number++) {
        await insertIntention(number, 'Намерение $number', kind: 'supporting');
        await insertRelation(number + 10000, 5, number);
      }
    });

    final preview = await previewIntention(5, CascadeOperation.archive);

    expect(preview, isA<ArchiveCascadePreview>());
    final archive = preview as ArchiveCascadePreview;
    expect(archive.plan.withSupporting.departing, hasLength(401));
    expect(archive.titles, hasLength(401));
    expect(archive.titles[durabilityIntention(1401)], 'Намерение 1401');
  });

  test('изменение удержания во время построения индекса даёт устаревший '
      'предпросмотр', () async {
    runner.hold();
    final reading = previewIntention(1, CascadeOperation.archive);
    await runner.entered.future;
    await confirm(ArchiveLongTermRelation(durabilityRelation(104)));
    runner.release();

    expect(await reading, isA<CascadePreviewExpired>());
    expect(
      diagnostics.events
          .whereType<IntentionCascadePreviewDiagnosticsEvent>()
          .last,
      isA<IntentionCascadePreviewDiagnosticsEvent>()
          .having(
            (event) => event.stage,
            'этап',
            IntentionCascadePreviewDiagnosticsStage.holdingIndex,
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
  });

  test('команда, подтверждённая перед чтением названий, даёт устаревший '
      'предпросмотр', () async {
    diagnostics.onEvent = (event) {
      if (event case IntentionCascadePreviewDiagnosticsEvent(
        stage: IntentionCascadePreviewDiagnosticsStage.titles,
        status: DiagnosticsStarted(),
      )) {
        diagnostics.onEvent = null;
        // Команда встаёт в очередь раньше первой части названий.
        unawaited(
          repository.execute(
            UpdateIntention(
              id: durabilityIntention(2),
              title: 'Ходить пешком',
              description: null,
            ),
          ),
        );
      }
    };

    expect(
      await previewIntention(1, CascadeOperation.archive),
      isA<CascadePreviewExpired>(),
    );
    expect(
      diagnostics.events
          .whereType<IntentionCascadePreviewDiagnosticsEvent>()
          .last
          .stage,
      IntentionCascadePreviewDiagnosticsStage.titles,
    );
  });

  test('отказ подсчёта и повреждённое название отличимы между собой и от '
      'ответа без каскада', () async {
    runner.failNext();
    expect(
      await previewIntention(4, CascadeOperation.archive),
      isA<CascadePreviewUnexpected>(),
    );

    await seedGraph(
      database,
      () => database.customStatement(
        'UPDATE intentions SET title = ? WHERE id = ?',
        ['  Много ходить', durabilityUuid(2)],
      ),
    );
    expect(
      await previewIntention(1, CascadeOperation.archive),
      isA<CascadePreviewCorruption>(),
    );
    expect(
      diagnostics.events
          .whereType<IntentionCascadePreviewDiagnosticsEvent>()
          .last,
      isA<IntentionCascadePreviewDiagnosticsEvent>()
          .having(
            (event) => event.stage,
            'этап',
            IntentionCascadePreviewDiagnosticsStage.titles,
          )
          .having(
            (event) => event.status,
            'исход',
            isA<DiagnosticsFailed>().having(
              (status) => status.code,
              'категория',
              DiagnosticsFailureCode.corruption,
            ),
          ),
    );
  });
}

/// Хранит события и по запросу вызывает [onEvent] в момент записи.
final class _HookedDiagnosticsSink implements DiagnosticsSink {
  final List<DiagnosticsEvent> events = [];
  void Function(DiagnosticsEvent event)? onEvent;

  @override
  void record(DiagnosticsEvent event) {
    events.add(event);
    onEvent?.call(event);
  }
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
