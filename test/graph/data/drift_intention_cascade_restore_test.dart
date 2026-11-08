import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_holding.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/graph_durability_fixture.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

/// Намерения проверок: «Быть здоровым» (1), «Много ходить» (2), «Хорошая
/// обувь» (3), «Высыпаться» (4), «Сходить в поход» (5), «Плавать» (6). Каждая
/// проверка задаёт вид и архивное состояние намерений и связи «нужно» между
/// ними. Все строки созданы показанием 1.
void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;
  late DateTime now;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    database = await harness.openReadyDatabase(setup: (db) => raw = db);
    diagnostics = InMemoryDiagnosticsSink();
    now = DateTime.utc(2026, 11, 8, 9);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now,
      diagnostics,
    );
  });
  tearDown(() => harness.dispose());

  /// Заполняет граф: намерения как (номер, вид, архивное), связи «нужно» как
  /// (номер, исходное, связанное, архивная).
  void seed({
    required List<(int, String, bool)> intentions,
    required List<(int, int, int, bool)> relations,
  }) {
    seedRawGraph(raw, () {
      for (final (number, kind, archived) in intentions) {
        raw.execute(
          '''INSERT INTO intentions
             (id, title, kind, is_archived, created_at, updated_at)
             VALUES (?, ?, ?, ?, 1, 1)''',
          [durabilityUuid(number), 'Намерение $number', kind, archived ? 1 : 0],
        );
      }
      for (final (number, source, related, archived) in relations) {
        raw.execute(
          '''INSERT INTO long_term_relations
             (id, source_intention_id, related_intention_id,
              type, priority, description, is_archived,
              created_at, updated_at)
             VALUES (?, ?, ?, 'need', 2, ?, ?, 1, 1)''',
          [
            durabilityUuid(number),
            durabilityUuid(source),
            durabilityUuid(related),
            'Описание $number',
            archived ? 1 : 0,
          ],
        );
      }
    });
  }

  Future<CascadePlan<RestoreCascadeComposition>> restorePlan(
    CascadeSubject subject,
  ) async {
    final preview = await repository.previewCurrentCascade(
      subject,
      CascadeOperation.restore,
    );
    expect(preview, isA<RestoreCascadePreview>());
    return (preview as RestoreCascadePreview).plan;
  }

  Future<RestoreIntention> restoreIntention(
    int number, {
    CascadeChoice choice = CascadeChoice.withSupporting,
  }) async {
    final plan = await restorePlan(
      IntentionCascadeSubject(durabilityIntention(number)),
    );
    return RestoreIntention(
      durabilityIntention(number),
      execution: _execution(plan, choice),
    );
  }

  Future<RestoreLongTermRelation> restoreRelation(
    int number, {
    CascadeChoice choice = CascadeChoice.withSupporting,
  }) async {
    final plan = await restorePlan(
      RelationCascadeSubject(durabilityRelation(number)),
    );
    return RestoreLongTermRelation(
      durabilityRelation(number),
      execution: _execution(plan, choice),
    );
  }

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

  RestoreCascadeComposition executedOf(
    ConfirmedGraphResult<GraphCommandOutcome> confirmed,
  ) =>
      confirmed.changes.whereType<CascadeOutcome>().single.executed
          as RestoreCascadeComposition;

  test('каскад восстановления останавливается на главном намерении', () async {
    seed(
      intentions: [
        (1, 'main', true),
        (2, 'supporting', true),
        (3, 'supporting', false),
        (4, 'main', true),
        (5, 'main', false),
      ],
      relations: [
        (101, 1, 2, true),
        (102, 2, 3, true),
        (103, 2, 4, true),
        (104, 5, 3, false),
      ],
    );
    final plan = await restorePlan(
      IntentionCascadeSubject(durabilityIntention(1)),
    );
    expect(plan.asksQuestion, isTrue);
    expect(plan.withSupporting.restored, [durabilityIntention(2)]);
    expect(plan.onlyThis.restored, isEmpty);
    final before = await _graphState(database);

    await confirm(await restoreIntention(1));

    final after = await _graphState(database);
    expect(after.archivedIntentions, {4});
    expect(after.archivedRelations, {103});
    expect(after.kinds, before.kinds);
  });

  test('каскад возвращает и отдельно архивированное вспомогательное', () async {
    seed(
      intentions: [(1, 'main', false), (2, 'supporting', false)],
      relations: [(101, 1, 2, false)],
    );
    await confirm(
      ArchiveIntention(
        durabilityIntention(2),
        execution: CascadeExecution.withSupporting(
          await _archivePlan(repository, 2),
        ),
      ),
    );
    await confirm(
      ArchiveIntention(
        durabilityIntention(1),
        execution: CascadeExecution.withSupporting(
          await _archivePlan(repository, 1),
        ),
      ),
    );
    expect((await _graphState(database)).archivedIntentions, {1, 2});

    await confirm(await restoreIntention(1));

    final after = await _graphState(database);
    expect(after.archivedIntentions, isEmpty);
    expect(after.archivedRelations, isEmpty);
    expect(after.kinds[2], 'supporting');
  });

  test('выбор «только это» возвращает намерение со связями с активными, а '
      'вспомогательные ниже остаются в архиве', () async {
    seed(
      intentions: [
        (1, 'main', true),
        (2, 'supporting', true),
        (4, 'main', false),
      ],
      relations: [(101, 1, 2, true), (103, 1, 4, true)],
    );

    final confirmed = await confirm(
      await restoreIntention(1, choice: CascadeChoice.onlyThis),
    );

    final after = await _graphState(database);
    expect(after.archivedIntentions, {2});
    expect(after.archivedRelations, {101});
    expect(executedOf(confirmed).restored, isEmpty);
  });

  test('вспомогательное без активного намерения выше возвращается главным '
      'со связями с активными', () async {
    seed(
      intentions: [
        (1, 'main', true),
        (2, 'supporting', true),
        (4, 'main', false),
      ],
      relations: [(101, 1, 2, true), (103, 2, 4, true)],
    );
    final plan = await restorePlan(
      IntentionCascadeSubject(durabilityIntention(2)),
    );
    expect(plan.asksQuestion, isFalse);

    final confirmed = await confirm(await restoreIntention(2));

    final after = await _graphState(database);
    expect(after.archivedIntentions, {1});
    expect(after.archivedRelations, {101});
    expect(after.kinds[2], 'main');
    final saved = confirmed.value as IntentionSaved;
    expect(saved.intention.kind, IntentionKind.main);
    expect(saved.catalogMutation.after!.summary.kind, IntentionKind.main);
    expect(executedOf(confirmed).returnedAsMain, durabilityIntention(2));
    expect(
      (await repository.getIntentionHolding({
        durabilityIntention(2),
      }) as IntentionHoldingRead).holdings.values.single,
      IntentionHolding.held,
    );
  });

  test('вид, изменённый в архиве, сохраняется, когда выше есть активное '
      'намерение', () async {
    seed(
      intentions: [(1, 'main', false), (2, 'supporting', true)],
      relations: [(101, 1, 2, true)],
    );

    final confirmed = await confirm(await restoreIntention(2));

    final after = await _graphState(database);
    expect(after.archivedIntentions, isEmpty);
    expect(after.archivedRelations, isEmpty);
    expect(after.kinds[2], 'supporting');
    expect(executedOf(confirmed).returnedAsMain, isNull);
  });

  test('восстановление связи с выбором «только это» возвращает её архивного '
      'участника вспомогательным', () async {
    seed(
      intentions: [
        (1, 'main', false),
        (2, 'supporting', true),
        (3, 'supporting', true),
      ],
      relations: [(101, 1, 2, true), (102, 2, 3, true)],
    );
    final plan = await restorePlan(
      RelationCascadeSubject(durabilityRelation(101)),
    );
    expect(plan.asksQuestion, isTrue);
    expect(plan.withSupporting.restored, [
      durabilityIntention(2),
      durabilityIntention(3),
    ]);

    final confirmed = await confirm(
      await restoreRelation(101, choice: CascadeChoice.onlyThis),
    );

    final after = await _graphState(database);
    expect(after.archivedIntentions, {3});
    expect(after.archivedRelations, {102});
    expect(after.kinds[2], 'supporting');
    final updated = confirmed.value as LongTermRelationUpdated;
    expect(updated.relation.id, durabilityRelation(101));
    expect(updated.relation.scope, RelationScope.active);
    expect(
      confirmed.changes.whereType<IntentionCatalogUpdated>().map(
        (mutation) => _intentionNumber(mutation.after.summary.id),
      ),
      [2],
    );
    final executed = executedOf(confirmed);
    expect(executed.restored, [durabilityIntention(2)]);
    expect(executed.returnedAsMain, isNull);
  });

  test('восстановление связи между архивными участниками возвращает обоих, '
      'а исходного без активного намерения выше — главным', () async {
    seed(
      intentions: [
        (1, 'main', true),
        (2, 'supporting', true),
        (3, 'supporting', true),
      ],
      relations: [(101, 1, 2, true), (102, 2, 3, true)],
    );
    final plan = await restorePlan(
      RelationCascadeSubject(durabilityRelation(102)),
    );
    expect(plan.asksQuestion, isFalse);

    final confirmed = await confirm(await restoreRelation(102));

    final after = await _graphState(database);
    expect(after.archivedIntentions, {1});
    expect(after.archivedRelations, {101});
    expect(after.kinds[2], 'main');
    expect(after.kinds[3], 'supporting');
    expect(executedOf(confirmed).returnedAsMain, durabilityIntention(2));
  });

  test('связь между активными намерениями восстанавливается одна и занимает '
      'прежнее место', () async {
    seed(
      intentions: [(1, 'main', false), (4, 'main', false)],
      relations: [(103, 1, 4, true)],
    );
    final before = await _graphState(database);
    final plan = await restorePlan(
      RelationCascadeSubject(durabilityRelation(103)),
    );
    expect(plan.asksQuestion, isFalse);

    final confirmed = await confirm(await restoreRelation(103));

    final after = await _graphState(database);
    expect(after.archivedRelations, isEmpty);
    expect(after.intentions, before.intentions);
    expect(
      after.relations[103]!.creationSequence,
      before.relations[103]!.creationSequence,
    );
    expect(after.relations[103]!.description, 'Описание 103');
    final updated = confirmed.value as LongTermRelationUpdated;
    expect(updated.relation.priority, updated.before.priority);
    expect(updated.relation.type, updated.before.type);
    expect(confirmed.changes.whereType<IntentionCatalogUpdated>(), isEmpty);
    expect(executedOf(confirmed).restored, isEmpty);
  });

  test('пакет несёт изменения связей, мутации каталога, абсолютные '
      'количества, изменение удержания и исполненный состав', () async {
    // А (1) активно, Б (2) и В (4) — архивные главные.
    seed(
      intentions: [(1, 'main', false), (2, 'main', true), (4, 'main', true)],
      relations: [(101, 1, 2, true), (103, 2, 4, true)],
    );
    now = DateTime.utc(2026, 11, 8, 10, 30);

    final confirmed = await confirm(await restoreIntention(2));

    expect(
      confirmed.changes.map(
        (change) => change.revision.compareTo(confirmed.revision),
      ),
      everyElement(GraphRevisionOrder.same),
    );
    final saved = confirmed.value as IntentionSaved;
    expect(saved.intention.archiveState, IntentionArchiveState.active);
    expect(
      [
        for (final mutation in saved.catalogMutations)
          (
            _intentionNumber(mutation.after!.summary.id),
            mutation.before!.summary.archiveState,
            mutation.after!.summary.archiveState,
          ),
      ],
      [(2, IntentionArchiveState.archived, IntentionArchiveState.active)],
    );
    final relationChanges = confirmed.changes
        .whereType<LongTermRelationUpdatedChange>()
        .toList();
    expect(relationChanges.map((change) => _relationNumber(change.id)), [101]);
    final change = relationChanges.single;
    expect(change.before.scope, RelationScope.archived);
    expect(change.after.scope, RelationScope.active);
    expect(change.after.updatedAt, RelationTimestamp(now));
    expect(change.after.creationSequence, change.before.creationSequence);
    expect(change.after.createdAt, change.before.createdAt);
    final counts = {
      for (final change
          in confirmed.changes.whereType<IntentionRelationCountsChanged>())
        _intentionNumber(change.intentionId): change.counts,
    };
    expect(counts.keys, unorderedEquals([1, 2]));
    for (final MapEntry(key: number, value: packaged) in counts.entries) {
      expect(
        _countsKey(packaged),
        _countsKey(await _readCounts(repository, number)),
        reason: 'Абсолютные количества намерения $number',
      );
    }
    // Связь Б → В с архивным В остаётся архивной.
    expect(_countsKey(counts[2]!), (active: 1, archived: 1));
    expect(_countsKey(counts[1]!), (active: 1, archived: 0));
    expect(
      confirmed.changes.whereType<IntentionHoldingChanged>(),
      hasLength(1),
    );
    final executed = executedOf(confirmed);
    expect(executed.restored, isEmpty);
    expect(executed.restoredRelationCount, 1);
  });

  test('восстановление намерения, чья единственная связь ведёт к архивному '
      'намерению, не меняет количества', () async {
    seed(
      intentions: [(2, 'main', true), (4, 'main', true)],
      relations: [(103, 2, 4, true)],
    );

    final confirmed = await confirm(await restoreIntention(4));

    expect((await _graphState(database)).archivedRelations, {103});
    expect(
      confirmed.changes.whereType<IntentionRelationCountsChanged>().map(
        (change) =>
            (_intentionNumber(change.intentionId), _countsKey(change.counts)),
      ),
      [(4, (active: 0, archived: 1))],
    );
  });

  test('восстановление связи из пути действия возвращает ей доступность '
      'новым путям, а действие не меняется', () async {
    seed(
      intentions: [(1, 'main', false), (4, 'main', false)],
      relations: [(103, 1, 4, true)],
    );
    seedRawGraph(raw, () {
      seedAction(
        raw,
        id: durabilityUuid(201),
        path: [durabilityUuid(1), durabilityUuid(4)],
        description: 'Утром',
        isCompleted: true,
      );
      seedAction(raw, id: durabilityUuid(202), path: [durabilityUuid(1)]);
    });
    final actionBefore = raw.select('SELECT * FROM actions WHERE id = ?', [
      durabilityUuid(201),
    ]).single;
    SetActionPath throughRelation() => SetActionPath(
      actionId: _actionId(202),
      path: ActionPath([durabilityIntention(1), durabilityIntention(4)]),
    );
    expect(
      await repository.execute(throughRelation()),
      isA<GraphCommandFailed>(),
    );

    await confirm(await restoreRelation(103));

    expect(
      await repository.execute(throughRelation()),
      isA<GraphCommandSucceeded>(),
    );
    expect(
      raw.select('SELECT * FROM actions WHERE id = ?', [
        durabilityUuid(201),
      ]).single,
      actionBefore,
    );
  });

  test(
    'одно показание часов команды записывается в каждое восстановленное '
    'намерение, в том числе ставшее главным, и каждую вернувшуюся связь',
    () async {
      seed(
        intentions: [
          (1, 'main', true),
          (2, 'supporting', true),
          (3, 'supporting', true),
          (4, 'main', false),
          (5, 'main', false),
          (6, 'main', true),
        ],
        relations: [
          (101, 1, 2, true),
          (102, 2, 3, true),
          (103, 2, 4, true),
          (105, 5, 6, true),
        ],
      );
      final before = await _graphState(database);
      now = DateTime.utc(2026, 11, 8, 11, 15, 30, 123, 456);

      final confirmed = await confirm(await restoreIntention(2));

      expect(executedOf(confirmed).returnedAsMain, durabilityIntention(2));
      final after = await _graphState(database);
      final stamp = now.microsecondsSinceEpoch;
      for (final number in [2, 3]) {
        expect(after.intentions[number]!.updatedAt, stamp, reason: '$number');
      }
      for (final number in [102, 103]) {
        expect(after.relations[number]!.updatedAt, stamp, reason: '$number');
      }
      for (final number in [1, 4, 5, 6]) {
        expect(after.intentions[number], before.intentions[number]);
      }
      for (final number in [101, 105]) {
        expect(after.relations[number], before.relations[number]);
      }
    },
  );

  test(
    'восстановление связи с архивными участниками записывает одно '
    'показание часов команды в участников, каскад и вернувшиеся связи',
    () async {
      seed(
        intentions: [
          (1, 'main', true),
          (2, 'supporting', true),
          (3, 'supporting', true),
          (4, 'main', false),
          (5, 'main', false),
          (6, 'main', true),
        ],
        relations: [
          (101, 1, 2, true),
          (102, 2, 3, true),
          (103, 2, 4, true),
          (105, 5, 6, true),
        ],
      );
      final before = await _graphState(database);
      now = DateTime.utc(2026, 11, 8, 12, 45, 10, 654, 321);

      await confirm(await restoreRelation(101));

      final after = await _graphState(database);
      final stamp = now.microsecondsSinceEpoch;
      expect(after.archivedIntentions, {6});
      expect(after.archivedRelations, {105});
      for (final number in [1, 2, 3]) {
        expect(after.intentions[number]!.updatedAt, stamp, reason: '$number');
      }
      for (final number in [101, 102, 103]) {
        expect(after.relations[number]!.updatedAt, stamp, reason: '$number');
      }
      for (final number in [4, 5, 6]) {
        expect(after.intentions[number], before.intentions[number]);
      }
      expect(after.relations[105], before.relations[105]);
    },
  );

  test('изменившийся состав даёт конфликт без записи, отличимый в '
      'результате и диагностике', () async {
    seed(
      intentions: [(1, 'main', true), (2, 'supporting', true)],
      relations: [(101, 1, 2, true)],
    );
    final restoration = await restoreIntention(1);
    final relationRestoration = await restoreRelation(101);
    // «Много ходить» вернулось само и больше не возвращается каскадом.
    await confirm(await restoreIntention(2));
    final before = await _graphState(database);
    final revision = await currentRevision();

    final result = await repository.execute(restoration);
    final relationResult = await repository.execute(relationRestoration);

    expect(
      result,
      isA<ResultFailure>().having(
        (failure) => failure.failure,
        'отказ',
        isA<IntentionCascadeConflictFailure>(),
      ),
    );
    expect(
      relationResult,
      isA<GraphCommandFailed>().having(
        (failure) => failure.failure,
        'отказ',
        isA<LongTermRelationCascadeConflictFailure>(),
      ),
    );
    expect(await _graphState(database), before);
    expect(
      (await currentRevision()).compareTo(revision),
      GraphRevisionOrder.same,
    );
    final failures = [
      for (final event in diagnostics.events)
        if (event.status case DiagnosticsFailed(:final code))
          (event.runtimeType, code),
    ];
    expect(failures, [
      (
        IntentionCommandDiagnosticsEvent,
        DiagnosticsFailureCode.cascadeConflict,
      ),
      (
        LongTermRelationCommandDiagnosticsEvent,
        DiagnosticsFailureCode.cascadeConflict,
      ),
    ]);
  });

  test('изменение, не затрагивающее выбранный вариант, не вызывает '
      'конфликта', () async {
    seed(
      intentions: [
        (1, 'main', true),
        (2, 'supporting', true),
        (4, 'main', true),
      ],
      relations: [(101, 1, 2, true)],
    );
    final restoration = await restoreIntention(
      1,
      choice: CascadeChoice.onlyThis,
    );
    await confirm(await restoreIntention(4));

    await confirm(restoration);

    final after = await _graphState(database);
    expect(after.archivedIntentions, {2});
    expect(after.archivedRelations, {101});
  });

  test('ошибка записи не оставляет частичного восстановления', () async {
    seed(
      intentions: [(1, 'main', true), (2, 'supporting', true)],
      relations: [(101, 1, 2, true)],
    );
    final restoration = await restoreIntention(1);
    final before = await _graphState(database);
    // Намерения уже возвращены, когда отказывает запись связей.
    await database.customStatement('''
      CREATE TEMP TRIGGER fail_relation_restore
      AFTER UPDATE OF is_archived ON long_term_relations
      BEGIN
        SELECT RAISE(ABORT, 'сбой записи');
      END''');

    final result = await repository.execute(restoration);

    expect(result, isA<ResultFailure>());
    expect(await _graphState(database), before);
  });
}

/// Предпросмотр архивирования намерения [number] перед его командой.
Future<CascadePlan<ArchiveCascadeComposition>> _archivePlan(
  DriftPersonalGraphRepository repository,
  int number,
) async => (await repository.previewCurrentCascade(
  IntentionCascadeSubject(durabilityIntention(number)),
  CascadeOperation.archive,
) as ArchiveCascadePreview).plan;

CascadeExecution<RestoreCascadeComposition> _execution(
  CascadePlan<RestoreCascadeComposition> plan,
  CascadeChoice choice,
) => CascadeExecution.of(plan, choice);

ActionId _actionId(int number) =>
    (ActionId.decode(durabilityUuid(number)) as ActionIdDecodingSuccess).id;

int _intentionNumber(IntentionId id) => _numberOf(id.toCanonicalString());

int _relationNumber(LongTermRelationId id) => _numberOf(id.toCanonicalString());

int _numberOf(String canonicalId) =>
    int.parse(canonicalId.split('-').last, radix: 16);

typedef _IntentionRow = ({String kind, int archived, int updatedAt});
typedef _RelationRow = ({
  String? description,
  int archived,
  int updatedAt,
  int creationSequence,
});

/// Сохранённые строки намерений и связей с номерами из идентификаторов.
final class _GraphState {
  _GraphState(this.intentions, this.relations);

  final Map<int, _IntentionRow> intentions;
  final Map<int, _RelationRow> relations;

  Map<int, String> get kinds => {
    for (final MapEntry(:key, :value) in intentions.entries) key: value.kind,
  };

  Set<int> get archivedIntentions => {
    for (final MapEntry(:key, :value) in intentions.entries)
      if (value.archived == 1) key,
  };

  Set<int> get archivedRelations => {
    for (final MapEntry(:key, :value) in relations.entries)
      if (value.archived == 1) key,
  };

  @override
  bool operator ==(Object other) =>
      other is _GraphState &&
      _sameMap(intentions, other.intentions) &&
      _sameMap(relations, other.relations);

  @override
  int get hashCode => Object.hash(intentions.length, relations.length);

  @override
  String toString() => '$intentions $relations';
}

bool _sameMap<K, V>(Map<K, V> a, Map<K, V> b) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key] == entry.value);

Future<_GraphState> _graphState(AppDatabase database) async {
  final intentions = <int, _IntentionRow>{};
  for (final row
      in await database
          .customSelect(
            'SELECT id, kind, is_archived, updated_at FROM intentions',
          )
          .get()) {
    intentions[_numberOf(row.read<String>('id'))] = (
      kind: row.read<String>('kind'),
      archived: row.read<int>('is_archived'),
      updatedAt: row.read<int>('updated_at'),
    );
  }
  final relations = <int, _RelationRow>{};
  for (final row in await database.customSelect(
    '''SELECT id, description, is_archived, updated_at, creation_sequence
           FROM long_term_relations''',
  ).get()) {
    relations[_numberOf(row.read<String>('id'))] = (
      description: row.readNullable<String>('description'),
      archived: row.read<int>('is_archived'),
      updatedAt: row.read<int>('updated_at'),
      creationSequence: row.read<int>('creation_sequence'),
    );
  }
  return _GraphState(intentions, relations);
}

Future<RelationCounts> _readCounts(
  DriftPersonalGraphRepository repository,
  int number,
) async =>
    ((await repository.watchIntention(durabilityIntention(number)).first)
            as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
        .value
        .value!
        .relationCounts;

({int active, int archived}) _countsKey(RelationCounts counts) =>
    (active: counts.active, archived: counts.archived);
