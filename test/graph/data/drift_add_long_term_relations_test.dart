import 'dart:async';

import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation;
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;
  late IntentionId pageId;
  late IntentionId firstId;
  late IntentionId secondId;
  late IntentionId thirdId;
  late List<LongTermRelationId> relationIds;
  var clockReadings = 0;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    pageId = _intentionId(_uuid(1));
    firstId = _intentionId(_uuid(2));
    secondId = _intentionId(_uuid(3));
    thirdId = _intentionId(_uuid(4));
    relationIds = [for (var i = 1; i <= 4; i++) _relationId(_uuid(100 + i))];
    for (final (id, title) in [
      (pageId, 'Быть здоровым'),
      (firstId, 'Плавать'),
      (secondId, 'Бегать'),
      (thirdId, 'Высыпаться'),
    ]) {
      await _insertIntention(database, id, title: title);
    }
    clockReadings = 0;
    // Часы идут вперёд при каждом чтении: одно показание пачки возможно, только
    // если команда читает их один раз.
    repository = _repository(
      database,
      diagnostics,
      relationIds,
      () => DateTime.utc(2026, 9, 19).add(Duration(minutes: clockReadings++)),
    );
  });

  tearDown(() => database.close());

  group('успех', () {
    test('исходящая группа создаёт активные связи P4 без описания в порядке набора', () async {
      final revisionBefore = await _revision(repository, pageId);
      final packagesBefore = await _packageCount(database);

      final result = await repository.execute(
        AddLongTermRelations(
          pageIntentionId: pageId,
          group: IntentionRelationGroup.needs,
          candidateIds: [thirdId, firstId, secondId],
        ),
      );

      final confirmed = _confirmed(result);
      final added = confirmed.value as LongTermRelationsAdded;
      expect(
        added.relations.map((relation) => relation.id),
        relationIds.take(3),
      );
      expect(added.relations.map((relation) => relation.relatedIntentionId), [
        thirdId,
        firstId,
        secondId,
      ]);
      for (final relation in added.relations) {
        expect(relation.sourceIntentionId, pageId);
        expect(relation.type, LongTermRelationType.need);
        expect(relation.priority, RelationPriority.p4);
        expect(relation.scope, RelationScope.active);
        expect(relation.createdAt, added.relations.first.createdAt);
        expect(relation.updatedAt, relation.createdAt);
      }
      expect(
        added.relations.map((relation) => relation.creationSequence.value),
        [1, 2, 3],
      );

      final stored = await (database.select(
        database.longTermRelations,
      )..orderBy([(row) => OrderingTerm.asc(row.creationSequence)])).get();
      expect(stored.map((row) => row.id), [
        for (final id in relationIds.take(3)) id.toCanonicalString(),
      ]);
      expect(stored.map((row) => row.description), everyElement(isNull));
      expect(stored.map((row) => row.priority), everyElement(4));
      expect(stored.map((row) => row.isArchived), everyElement(isFalse));
      expect(stored.map((row) => row.createdAt).toSet(), {
        added.relations.first.createdAt.value.microsecondsSinceEpoch,
      });
      expect(stored.map((row) => row.updatedAt), [
        for (final row in stored) row.createdAt,
      ]);

      expect(
        revisionBefore.compareTo(confirmed.revision),
        GraphRevisionOrder.older,
      );
      expect(await _packageCount(database), packagesBefore + 1);
      expect(
        added.changes.map(
          (change) => change.revision.compareTo(confirmed.revision),
        ),
        everyElement(GraphRevisionOrder.same),
      );
      final countChanges = {
        for (final change
            in added.changes.whereType<IntentionRelationCountsChanged>())
          change.intentionId: change.counts,
      };
      expect(countChanges.keys, {pageId, firstId, secondId, thirdId});
      expect(countChanges[pageId]!.activeNeedOutgoing, 3);
      for (final id in [firstId, secondId, thirdId]) {
        expect(countChanges[id]!.activeNeedIncoming, 1);
      }
      expect(
        added.changes.whereType<LongTermRelationCreatedChange>().map(
          (change) => change.id,
        ),
        relationIds.take(3),
      );
      expect(
        diagnostics.events.whereType<LongTermRelationCommandDiagnosticsEvent>(),
        [
          isA<LongTermRelationCommandDiagnosticsEvent>()
              .having(
                (event) => event.commandType,
                'commandType',
                LongTermRelationCommandDiagnosticsType.create,
              )
              .having(
                (event) => event.status,
                'status',
                isA<DiagnosticsSucceeded>(),
              ),
        ],
      );
    });

    test(
      'входящая группа делает намерение страницы связанным участником',
      () async {
        final result = await repository.execute(
          AddLongTermRelations(
            pageIntentionId: pageId,
            group: IntentionRelationGroup.canBeUsedFor,
            candidateIds: [firstId, secondId],
          ),
        );

        final added = _confirmed(result).value as LongTermRelationsAdded;
        expect(added.relations.map((relation) => relation.sourceIntentionId), [
          firstId,
          secondId,
        ]);
        for (final relation in added.relations) {
          expect(relation.relatedIntentionId, pageId);
          expect(relation.type, LongTermRelationType.can);
        }
        final countChanges = {
          for (final change
              in added.changes.whereType<IntentionRelationCountsChanged>())
            change.intentionId: change.counts,
        };
        expect(countChanges[pageId]!.activeCanIncoming, 2);
        expect(countChanges[firstId]!.activeCanOutgoing, 1);
        expect(countChanges[secondId]!.activeCanOutgoing, 1);
      },
    );

    test('обратное направление пару не занимает, а новая связь стоит после прежних', () async {
      await repository.execute(
        AddLongTermRelations(
          pageIntentionId: firstId,
          group: IntentionRelationGroup.needs,
          candidateIds: [pageId],
        ),
      );

      final result = await repository.execute(
        AddLongTermRelations(
          pageIntentionId: pageId,
          group: IntentionRelationGroup.needs,
          candidateIds: [firstId],
        ),
      );

      final added = _confirmed(result).value as LongTermRelationsAdded;
      expect(added.relations.single.creationSequence.value, 2);
      expect(
        await database.select(database.longTermRelations).get(),
        hasLength(2),
      );
    });

    test('цикл через несколько намерений сохраняется целиком', () async {
      final results = [
        await repository.execute(_addCommand(pageId, firstId)),
        await repository.execute(_addCommand(firstId, secondId)),
        await repository.execute(_addCommand(secondId, pageId)),
      ];

      expect(results, everyElement(isA<GraphCommandSucceeded>()));
      expect(
        await database.select(database.longTermRelations).get(),
        hasLength(3),
      );
      expect((await _details(repository, firstId)).relationCounts.active, 2);
    });

    test(
      'одноимённые намерения остаются разными участниками и не меняются',
      () async {
        final namesakeId = _intentionId(_uuid(9));
        await _insertIntention(database, namesakeId, title: 'Быть здоровым');
        final intentionsBefore = await database
            .select(database.intentions)
            .get();

        final result = await repository.execute(
          _addCommand(pageId, namesakeId),
        );

        final added = _confirmed(result).value as LongTermRelationsAdded;
        expect(added.relations.single.sourceIntentionId, pageId);
        expect(added.relations.single.relatedIntentionId, namesakeId);
        expect(
          await database.select(database.intentions).get(),
          intentionsBefore,
        );
      },
    );
  });

  group('пересечение с чтениями и другими командами', () {
    test(
      'перечитывает наблюдения участников и не трогает постороннее намерение',
      () async {
        final pageEvents = <Result<GraphSnapshot<IntentionDetails?>>>[];
        final candidateEvents = <Result<GraphSnapshot<IntentionDetails?>>>[];
        final otherEvents = <Result<GraphSnapshot<IntentionDetails?>>>[];
        final subscriptions = [
          repository.watchIntention(pageId).listen(pageEvents.add),
          repository.watchIntention(firstId).listen(candidateEvents.add),
          repository.watchIntention(secondId).listen(otherEvents.add),
        ];
        await pumpEventQueue(times: 20);
        expect(
          [pageEvents.length, candidateEvents.length, otherEvents.length],
          [1, 1, 1],
        );

        final added =
            _confirmed(await repository.execute(_addCommand(pageId, firstId)))
                    .value
                as LongTermRelationsAdded;
        await pumpEventQueue(times: 20);

        expect(
          [pageEvents.length, candidateEvents.length, otherEvents.length],
          [2, 2, 1],
        );
        final pageSnapshot = _detailsSnapshot(pageEvents.last);
        final candidateSnapshot = _detailsSnapshot(candidateEvents.last);
        expect(pageSnapshot.value!.relationCounts.activeNeedOutgoing, 1);
        expect(candidateSnapshot.value!.relationCounts.activeNeedIncoming, 1);
        expect(
          pageSnapshot.revision.compareTo(added.changes.first.revision),
          GraphRevisionOrder.same,
        );
        expect(
          candidateSnapshot.revision.compareTo(added.changes.first.revision),
          GraphRevisionOrder.same,
        );

        await repository.execute(_addCommand(pageId, firstId));
        await pumpEventQueue(times: 20);
        expect(
          [pageEvents.length, candidateEvents.length, otherEvents.length],
          [2, 2, 1],
        );
        for (final subscription in subscriptions) {
          unawaited(subscription.cancel());
        }
      },
    );

    test(
      'конкурентное создание одной пары подтверждает ровно одну связь',
      () async {
        final results = await Future.wait([
          repository.execute(_addCommand(pageId, firstId)),
          repository.execute(
            _addCommand(pageId, firstId, group: IntentionRelationGroup.canUse),
          ),
        ]);

        expect(results.whereType<GraphCommandSucceeded>(), hasLength(1));
        expect(
          results.whereType<GraphCommandFailed>().single.failure,
          isA<LongTermRelationPairOccupiedFailure>(),
        );
        expect(
          await database.select(database.longTermRelations).get(),
          hasLength(1),
        );
      },
    );

    test('создание перед архивированием попадает в атомарный каскад', () async {
      final creation = repository.execute(_addCommand(pageId, firstId));
      final archival = repository.execute(ArchiveIntention(pageId));

      expect(await creation, isA<GraphCommandSucceeded>());
      expect(await archival, isA<ResultSuccess>());
      final stored = await database
          .select(database.longTermRelations)
          .getSingle();
      expect(stored.isArchived, isTrue);
    });

    test(
      'создание перед удалением сохраняет обе сущности и возвращает конфликт',
      () async {
        final intentionsBefore = await database
            .select(database.intentions)
            .get();

        final creation = repository.execute(_addCommand(pageId, firstId));
        final deletion = repository.execute(DeleteIntention(pageId));

        expect(await creation, isA<GraphCommandSucceeded>());
        expect(
          await deletion,
          isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
              .having(
                (result) => result.failure,
                'failure',
                isA<IntentionHasBlockingRelationsFailure>(),
              ),
        );
        expect(
          await database.select(database.intentions).get(),
          hasLength(intentionsBefore.length),
        );
        expect(
          await database.select(database.longTermRelations).get(),
          hasLength(1),
        );
      },
    );
  });

  group('отказ не оставляет следов', () {
    test('архивная связь занимает пару на последнем месте набора', () async {
      await _seedRelation(
        database,
        relationIds[3],
        source: pageId,
        related: thirdId,
        type: 'can',
        isArchived: true,
      );
      final before = await _snapshotOfGraph(database, repository, pageId);

      final result = await repository.execute(
        AddLongTermRelations(
          pageIntentionId: pageId,
          group: IntentionRelationGroup.needs,
          candidateIds: [firstId, secondId, thirdId],
        ),
      );

      expect(
        _failure(result),
        isA<LongTermRelationPairOccupiedFailure>().having(
          (failure) => failure.existingRelationId,
          'existingRelationId',
          relationIds[3],
        ),
      );
      await _expectGraphUnchanged(database, repository, pageId, before);
      expect(
        diagnostics.events
            .whereType<LongTermRelationCommandDiagnosticsEvent>()
            .last
            .status,
        isA<DiagnosticsFailed>().having(
          (status) => status.code,
          'code',
          DiagnosticsFailureCode.conflict,
        ),
      );
    });

    test(
      'входящая группа проверяет пару в направлении к намерению страницы',
      () async {
        await _seedRelation(
          database,
          relationIds[3],
          source: secondId,
          related: pageId,
          type: 'need',
        );
        final before = await _snapshotOfGraph(database, repository, pageId);

        final result = await repository.execute(
          AddLongTermRelations(
            pageIntentionId: pageId,
            group: IntentionRelationGroup.neededFor,
            candidateIds: [firstId, secondId],
          ),
        );

        expect(
          _failure(result),
          isA<LongTermRelationPairOccupiedFailure>().having(
            (failure) => failure.existingRelationId,
            'existingRelationId',
            relationIds[3],
          ),
        );
        await _expectGraphUnchanged(database, repository, pageId, before);
      },
    );

    test('отсутствующий кандидат называет роль связанного участника', () async {
      final missingId = _intentionId(_uuid(9));
      final before = await _snapshotOfGraph(database, repository, pageId);

      final result = await repository.execute(
        AddLongTermRelations(
          pageIntentionId: pageId,
          group: IntentionRelationGroup.canUse,
          candidateIds: [firstId, missingId],
        ),
      );

      expect(
        _failure(result),
        isA<LongTermRelationParticipantNotFoundFailure>()
            .having(
              (failure) => failure.role,
              'role',
              RelationParticipantRole.related,
            )
            .having((failure) => failure.intentionId, 'intentionId', missingId),
      );
      await _expectGraphUnchanged(database, repository, pageId, before);
    });

    test('архивированный кандидат входящей группы называет роль исходного участника', () async {
      final archivedId = _intentionId(_uuid(9));
      await _insertIntention(
        database,
        archivedId,
        title: 'Архивное',
        isArchived: true,
      );
      final before = await _snapshotOfGraph(database, repository, pageId);

      final result = await repository.execute(
        AddLongTermRelations(
          pageIntentionId: pageId,
          group: IntentionRelationGroup.neededFor,
          candidateIds: [firstId, archivedId],
        ),
      );

      expect(
        _failure(result),
        isA<LongTermRelationParticipantArchivedFailure>()
            .having(
              (failure) => failure.role,
              'role',
              RelationParticipantRole.source,
            )
            .having(
              (failure) => failure.intentionId,
              'intentionId',
              archivedId,
            ),
      );
      await _expectGraphUnchanged(database, repository, pageId, before);
    });

    test('участник архивирован до сохранения', () async {
      await repository.execute(ArchiveIntention(pageId));
      final before = await _snapshotOfGraph(database, repository, pageId);

      final result = await repository.execute(
        AddLongTermRelations(
          pageIntentionId: pageId,
          group: IntentionRelationGroup.needs,
          candidateIds: [firstId, secondId],
        ),
      );

      expect(
        _failure(result),
        isA<LongTermRelationParticipantArchivedFailure>()
            .having(
              (failure) => failure.role,
              'role',
              RelationParticipantRole.source,
            )
            .having((failure) => failure.intentionId, 'intentionId', pageId),
      );
      await _expectGraphUnchanged(database, repository, firstId, before);
    });

    test('участник удалён до сохранения', () async {
      final otherId = _intentionId(_uuid(9));
      await _insertIntention(database, otherId, title: 'Другое');
      await repository.execute(DeleteIntention(pageId));
      final before = await _snapshotOfGraph(database, repository, otherId);

      final result = await repository.execute(
        AddLongTermRelations(
          pageIntentionId: pageId,
          group: IntentionRelationGroup.neededFor,
          candidateIds: [firstId],
        ),
      );

      expect(
        _failure(result),
        isA<LongTermRelationParticipantNotFoundFailure>()
            .having(
              (failure) => failure.role,
              'role',
              RelationParticipantRole.related,
            )
            .having((failure) => failure.intentionId, 'intentionId', pageId),
      );
      await _expectGraphUnchanged(database, repository, otherId, before);
    });

    test('отказ записи второй связи откатывает первую', () async {
      repository = _repository(database, diagnostics, [
        relationIds.first,
        relationIds.first,
      ], () => DateTime.utc(2026, 9, 19));
      final before = await _snapshotOfGraph(database, repository, pageId);

      final result = await repository.execute(
        AddLongTermRelations(
          pageIntentionId: pageId,
          group: IntentionRelationGroup.needs,
          candidateIds: [firstId, secondId],
        ),
      );

      expect(_failure(result), isA<LongTermRelationUnexpectedFailure>());
      await _expectGraphUnchanged(database, repository, pageId, before);
    });
  });
}

AddLongTermRelations _addCommand(
  IntentionId pageId,
  IntentionId candidateId, {
  IntentionRelationGroup group = IntentionRelationGroup.needs,
}) => AddLongTermRelations(
  pageIntentionId: pageId,
  group: group,
  candidateIds: [candidateId],
);

/// Состояние графа, по которому отказ команды доказывает отсутствие следов.
typedef _GraphSnapshot = ({
  List<String> relationIds,
  int packages,
  GraphRevision revision,
});

Future<_GraphSnapshot> _snapshotOfGraph(
  AppDatabase database,
  DriftPersonalGraphRepository repository,
  IntentionId watchedId,
) async => (
  relationIds: [
    for (final row in await database.select(database.longTermRelations).get())
      row.id,
  ],
  packages: await _packageCount(database),
  revision: await _revision(repository, watchedId),
);

Future<void> _expectGraphUnchanged(
  AppDatabase database,
  DriftPersonalGraphRepository repository,
  IntentionId watchedId,
  _GraphSnapshot before,
) async {
  final after = await _snapshotOfGraph(database, repository, watchedId);
  expect(after.relationIds, before.relationIds);
  expect(after.packages, before.packages);
  expect(after.revision.compareTo(before.revision), GraphRevisionOrder.same);
}

Future<int> _packageCount(AppDatabase database) async =>
    (await database.select(database.graphLogPackages).get()).length;

Future<GraphRevision> _revision(
  DriftPersonalGraphRepository repository,
  IntentionId id,
) async =>
    (await repository.watchIntention(id).first
            as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
        .value
        .revision;

Future<IntentionDetails> _details(
  DriftPersonalGraphRepository repository,
  IntentionId id,
) async =>
    (await repository.watchIntention(id).first
            as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
        .value
        .value!;

GraphSnapshot<IntentionDetails?> _detailsSnapshot(
  Result<GraphSnapshot<IntentionDetails?>> result,
) => (result as ResultSuccess<GraphSnapshot<IntentionDetails?>>).value;

ConfirmedGraphResult<LongTermRelationCommandSuccess> _confirmed(
  LongTermRelationCommandResult result,
) {
  expect(result, isA<GraphCommandSucceeded>());
  return (result
          as GraphCommandSucceeded<
            LongTermRelationCommandSuccess,
            LongTermRelationCommandFailure
          >)
      .value;
}

LongTermRelationCommandFailure _failure(LongTermRelationCommandResult result) {
  expect(result, isA<GraphCommandFailed>());
  return (result
          as GraphCommandFailed<
            LongTermRelationCommandSuccess,
            LongTermRelationCommandFailure
          >)
      .failure;
}

DriftPersonalGraphRepository _repository(
  AppDatabase database,
  DiagnosticsSink diagnostics,
  List<LongTermRelationId> ids,
  DateTime Function() now,
) => DriftPersonalGraphRepository(
  database,
  UuidV7IntentionIdGenerator(),
  now,
  diagnostics,
  relationIdGenerator: _DeterministicRelationIdGenerator(ids),
);

Future<void> _insertIntention(
  AppDatabase database,
  IntentionId id, {
  required String title,
  bool isArchived = false,
}) => seedGraph(
  database,
  () => database
      .into(database.intentions)
      .insert(
        IntentionsCompanion.insert(
          id: id.toCanonicalString(),
          title: title,
          isArchived: Value(isArchived),
          createdAt: DateTime.utc(2026, 9, 19).microsecondsSinceEpoch,
          updatedAt: DateTime.utc(2026, 9, 19).microsecondsSinceEpoch,
        ),
      ),
);

Future<void> _seedRelation(
  AppDatabase database,
  LongTermRelationId id, {
  required IntentionId source,
  required IntentionId related,
  required String type,
  bool isArchived = false,
}) => seedGraph(
  database,
  () => database
      .into(database.longTermRelations)
      .insert(
        LongTermRelationsCompanion.insert(
          id: id.toCanonicalString(),
          sourceIntentionId: source.toCanonicalString(),
          relatedIntentionId: related.toCanonicalString(),
          type: type,
          priority: 2,
          isArchived: Value(isArchived),
          createdAt: DateTime.utc(2026, 9, 18).microsecondsSinceEpoch,
          updatedAt: DateTime.utc(2026, 9, 18).microsecondsSinceEpoch,
        ),
      ),
);

final class _DeterministicRelationIdGenerator
    implements LongTermRelationIdGenerator {
  _DeterministicRelationIdGenerator(this._ids);

  final List<LongTermRelationId> _ids;
  var _index = 0;

  @override
  LongTermRelationId generate() => _ids[_index++];
}

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

LongTermRelationId _relationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw ArgumentError.value(
        value,
        'value',
      ),
    };

String _uuid(int value) =>
    '018f0b5d-6b2e-7c80-8000-${value.toString().padLeft(12, '0')}';
