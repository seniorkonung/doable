import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation;
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart'
    show IntentionArchiveState, IntentionReadiness;
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/shared/domain/text_preview.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;
  late IntentionId ownerId;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    repository = _repository(database, diagnostics);
    ownerId = _intentionId(_uuid(1));
    await _insertIntention(database, ownerId, title: 'Владелец группы');
  });

  tearDown(() => database.close());

  test(
    'группа отбирает только свои связи по охвату, типу и направлению',
    () async {
      var fixture = 10;
      for (final scope in RelationScope.values) {
        for (final type in LongTermRelationType.values) {
          for (final direction in RelationDirection.values) {
            final participantId = _intentionId(_uuid(fixture));
            await _insertIntention(
              database,
              participantId,
              title: 'Участник $fixture',
            );
            await _insertRelation(
              database,
              id: _relationId(_uuid(100 + fixture)),
              ownerId: ownerId,
              participantId: participantId,
              type: type,
              direction: direction,
              scope: scope,
              priority: RelationPriority.p2,
              description: fixture.isEven ? 'Описание $fixture' : null,
            );
            fixture++;
          }
        }
      }

      // Остальные семь групп отличаются от каждой запрошенной хотя бы одним
      // признаком, поэтому одна связь в выдаче подтверждает все три отбора.
      for (final (scope, type, direction) in [
        (
          RelationScope.active,
          LongTermRelationType.need,
          RelationDirection.outgoing,
        ),
        (
          RelationScope.archived,
          LongTermRelationType.can,
          RelationDirection.incoming,
        ),
      ]) {
        final result = await repository.getRelationGroupPage(
          RelationGroupQuery(
            intentionId: ownerId,
            type: type,
            direction: direction,
            scope: scope,
            pageSize: 100,
          ),
        );

        final page = _page(result) as RelationGroupFirstPage;
        expect(page.items, hasLength(1));
        expect(page.nextCursor, isNull);
        expect(page.counts.total, 8);
        expect(
          page.counts.forGroup(scope: scope, type: type, direction: direction),
          1,
        );
        final summary = page.items.single;
        expect(summary.relation.type, type);
        expect(summary.relation.scope, scope);
        expect(
          direction == RelationDirection.outgoing
              ? summary.relation.sourceIntentionId
              : summary.relation.relatedIntentionId,
          ownerId,
        );
      }
    },
  );

  test(
    'отдаёт соседа с готовностью и началом описания без владельца группы',
    () async {
      final longDescription = 'я' * (TextPreview.maxLength + 1);
      for (final direction in RelationDirection.values) {
        final base = direction == RelationDirection.outgoing ? 10 : 20;
        final readyNeighbor = _intentionId(_uuid(base));
        final plainNeighbor = _intentionId(_uuid(base + 1));
        final longNeighbor = _intentionId(_uuid(base + 2));
        final archivedNeighbor = _intentionId(_uuid(base + 3));
        await _insertIntention(
          database,
          readyNeighbor,
          title: 'Готовый сосед $base',
          isActionReady: true,
        );
        await _insertIntention(
          database,
          plainNeighbor,
          title: 'Сосед без описания $base',
        );
        await _insertIntention(
          database,
          longNeighbor,
          title: 'Сосед с длинным описанием $base',
        );
        await _insertIntention(
          database,
          archivedNeighbor,
          title: 'Архивный сосед $base',
          isArchived: true,
        );
        for (final (index, participantId, scope, description) in [
          (
            0,
            readyNeighbor,
            RelationScope.active,
            '  Начало\n\n  описания\tсвязи  ',
          ),
          (1, plainNeighbor, RelationScope.active, null),
          (2, longNeighbor, RelationScope.active, longDescription),
          (3, archivedNeighbor, RelationScope.archived, 'Архивная связь'),
        ]) {
          await _insertRelation(
            database,
            id: _relationId(_uuid(100 + base + index)),
            ownerId: ownerId,
            participantId: participantId,
            type: LongTermRelationType.need,
            direction: direction,
            scope: scope,
            priority: RelationPriority.values[index],
            description: description,
          );
        }

        RelationGroupQuery query(
          RelationScope scope,
          RelationGroupCursor? cursor,
        ) => RelationGroupQuery(
          intentionId: ownerId,
          type: LongTermRelationType.need,
          direction: direction,
          scope: scope,
          pageSize: 2,
          cursor: cursor,
        );
        final first = _page(
          await repository.getRelationGroupPage(
            query(RelationScope.active, null),
          ),
        ) as RelationGroupFirstPage;
        final continuation = _page(
          await repository.getRelationGroupPage(
            query(RelationScope.active, first.nextCursor),
          ),
        ) as RelationGroupContinuationPage;
        final archived = _page(
          await repository.getRelationGroupPage(
            query(RelationScope.archived, null),
          ),
        ) as RelationGroupFirstPage;

        final entries = [...first.items, ...continuation.items];
        expect(first.items, hasLength(2));
        expect(continuation.nextCursor, isNull);
        expect(entries.map((entry) => entry.neighbor.id), [
          readyNeighbor,
          plainNeighbor,
          longNeighbor,
        ]);
        expect(entries.map((entry) => entry.neighbor.title), [
          'Готовый сосед $base',
          'Сосед без описания $base',
          'Сосед с длинным описанием $base',
        ]);
        expect(entries.map((entry) => entry.neighbor.readiness), [
          IntentionReadiness.ready,
          IntentionReadiness.notReady,
          IntentionReadiness.notReady,
        ]);
        expect(
          entries.map((entry) => entry.neighbor.archiveState),
          everyElement(IntentionArchiveState.active),
        );
        expect(entries.map((entry) => entry.descriptionPreview?.text), [
          'Начало описания связи',
          null,
          'я' * TextPreview.maxLength,
        ]);
        expect(archived.items.single.neighbor.id, archivedNeighbor);
        expect(
          archived.items.single.neighbor.archiveState,
          IntentionArchiveState.archived,
        );
        // Владелец группы не попадает в строку: соседом всегда служит
        // другой участник связи.
        expect(
          [...entries, ...archived.items].map((entry) => entry.neighbor.id),
          isNot(contains(ownerId)),
        );
      }
    },
  );

  test(
    'продолжает по приоритету и последовательности без пропусков и повторов',
    () async {
      final fixtures = [
        (RelationPriority.p2, 10),
        (RelationPriority.p1, 11),
        (RelationPriority.p2, 12),
        (RelationPriority.p1, 13),
        (RelationPriority.p3, 14),
      ];
      for (final (priority, fixture) in fixtures) {
        final participantId = _intentionId(_uuid(fixture));
        await _insertIntention(
          database,
          participantId,
          title: 'Участник $fixture',
        );
        await _insertRelation(
          database,
          id: _relationId(_uuid(100 + fixture)),
          ownerId: ownerId,
          participantId: participantId,
          type: LongTermRelationType.need,
          direction: RelationDirection.outgoing,
          scope: RelationScope.active,
          priority: priority,
        );
      }

      final items = <int>[];
      RelationGroupCursor? cursor;
      var reads = 0;
      do {
        final page = _page(
          await repository.getRelationGroupPage(
            RelationGroupQuery(
              intentionId: ownerId,
              type: LongTermRelationType.need,
              direction: RelationDirection.outgoing,
              scope: RelationScope.active,
              pageSize: 2,
              cursor: cursor,
            ),
          ),
        );
        reads++;
        items.addAll(switch (page) {
          RelationGroupFirstPage(:final items) ||
          RelationGroupContinuationPage(
            :final items,
          ) => items.map((item) => item.relation.creationSequence.value),
          DailyChoiceGroupFirstPage() || DailyChoiceGroupContinuationPage() =>
            throw StateError('Ожидалась группа долговременных связей.'),
        });
        if (reads == 1) {
          expect((page as RelationGroupFirstPage).counts.activeNeedOutgoing, 5);
        } else {
          expect(page, isA<RelationGroupContinuationPage>());
        }
        cursor = page.nextCursor;
      } while (cursor != null);

      expect(items, [2, 4, 1, 3, 5]);
      expect(items.toSet(), hasLength(5));
      expect(reads, 3);
      expect(
        diagnostics.events
            .whereType<RelationGroupPageReadDiagnosticsEvent>()
            .where((event) => event.status is! DiagnosticsStarted),
        [
          isA<RelationGroupPageReadDiagnosticsEvent>()
              .having((event) => event.isContinuation, 'продолжение', isFalse)
              .having(
                (event) => event.status,
                'статус',
                isA<DiagnosticsSucceeded>(),
              ),
          isA<RelationGroupPageReadDiagnosticsEvent>()
              .having((event) => event.isContinuation, 'продолжение', isTrue)
              .having(
                (event) => event.status,
                'статус',
                isA<DiagnosticsSucceeded>(),
              ),
          isA<RelationGroupPageReadDiagnosticsEvent>()
              .having((event) => event.isContinuation, 'продолжение', isTrue)
              .having(
                (event) => event.status,
                'статус',
                isA<DiagnosticsSucceeded>(),
              ),
        ],
      );
    },
  );

  test('возвращает истёкший снимок после новой ревизии и эпохи', () async {
    await _insertSingleActiveNeedRelation(database, ownerId);
    final first = _page(
      await repository.getRelationGroupPage(_query(ownerId, pageSize: 1)),
    );
    final cursor = first.nextCursor!;

    await repository.execute(EnableIntentionReadiness(ownerId));
    final changedRevision = await repository.getRelationGroupPage(
      _query(ownerId, pageSize: 1, cursor: cursor),
    );
    final changedEpoch = await _repository(
      database,
      diagnostics,
    ).getRelationGroupPage(_query(ownerId, pageSize: 1, cursor: cursor));

    expect(_failure(changedRevision), isA<RelationGroupSnapshotExpired>());
    expect(_failure(changedEpoch), isA<RelationGroupSnapshotExpired>());
    expect(
      diagnostics.events.whereType<RelationGroupPageReadDiagnosticsEvent>(),
      contains(
        isA<RelationGroupPageReadDiagnosticsEvent>()
            .having(
              (event) => event.requiresNewSnapshot,
              'requiresNewSnapshot',
              isTrue,
            )
            .having(
              (event) => event.status,
              'status',
              isA<DiagnosticsFailed>(),
            ),
      ),
    );
  });

  test('различает отсутствующего владельца и повреждение строки', () async {
    final missing = await repository.getRelationGroupPage(
      _query(_intentionId(_uuid(999)), pageSize: 10),
    );

    final participantId = _intentionId(_uuid(10));
    await _insertIntention(database, participantId, title: 'Участник');
    await _insertRelation(
      database,
      id: _relationId(_uuid(110)),
      ownerId: ownerId,
      participantId: participantId,
      type: LongTermRelationType.need,
      direction: RelationDirection.outgoing,
      scope: RelationScope.active,
      priority: RelationPriority.p1,
    );
    await seedGraph(
      database,
      () => database.customStatement(
        'UPDATE intentions SET title = ? WHERE id = ?',
        ['   ', participantId.toCanonicalString()],
      ),
    );
    final corrupted = await repository.getRelationGroupPage(
      _query(ownerId, pageSize: 10),
    );

    expect(
      _failure(missing),
      isA<RelationGroupIntentionNotFoundFailure>().having(
        (failure) => failure.intentionId,
        'intentionId',
        _intentionId(_uuid(999)),
      ),
    );
    expect(_failure(corrupted), isA<RelationGroupCorruptionFailure>());
  });
}

RelationGroupQuery _query(
  IntentionId intentionId, {
  required int pageSize,
  RelationGroupCursor? cursor,
}) => RelationGroupQuery(
  intentionId: intentionId,
  type: LongTermRelationType.need,
  direction: RelationDirection.outgoing,
  scope: RelationScope.active,
  pageSize: pageSize,
  cursor: cursor,
);

Future<void> _insertSingleActiveNeedRelation(
  AppDatabase database,
  IntentionId ownerId,
) async {
  for (final fixture in [10, 11]) {
    final participantId = _intentionId(_uuid(fixture));
    await _insertIntention(database, participantId, title: 'Участник $fixture');
    await _insertRelation(
      database,
      id: _relationId(_uuid(100 + fixture)),
      ownerId: ownerId,
      participantId: participantId,
      type: LongTermRelationType.need,
      direction: RelationDirection.outgoing,
      scope: RelationScope.active,
      priority: RelationPriority.p1,
    );
  }
}

Future<void> _insertIntention(
  AppDatabase database,
  IntentionId id, {
  required String title,
  bool isActionReady = false,
  bool isArchived = false,
}) => seedGraph(
  database,
  () => database
      .into(database.intentions)
      .insert(
        IntentionsCompanion.insert(
          id: id.toCanonicalString(),
          title: title,
          isActionReady: Value(isActionReady),
          isArchived: Value(isArchived),
          createdAt: DateTime.utc(2026, 9, 20).microsecondsSinceEpoch,
          updatedAt: DateTime.utc(2026, 9, 20).microsecondsSinceEpoch,
        ),
      ),
);

Future<void> _insertRelation(
  AppDatabase database, {
  required LongTermRelationId id,
  required IntentionId ownerId,
  required IntentionId participantId,
  required LongTermRelationType type,
  required RelationDirection direction,
  required RelationScope scope,
  required RelationPriority priority,
  String? description,
}) => seedGraph(
  database,
  () => database
      .into(database.longTermRelations)
      .insert(
        LongTermRelationsCompanion.insert(
          id: id.toCanonicalString(),
          sourceIntentionId:
              (direction == RelationDirection.outgoing
                      ? ownerId
                      : participantId)
                  .toCanonicalString(),
          relatedIntentionId:
              (direction == RelationDirection.outgoing
                      ? participantId
                      : ownerId)
                  .toCanonicalString(),
          type: switch (type) {
            LongTermRelationType.need => 'need',
            LongTermRelationType.can => 'can',
          },
          priority: switch (priority) {
            RelationPriority.p1 => 1,
            RelationPriority.p2 => 2,
            RelationPriority.p3 => 3,
            RelationPriority.p4 => 4,
          },
          description: Value(description),
          isArchived: Value(scope == RelationScope.archived),
        ),
      ),
);

DriftPersonalGraphRepository _repository(
  AppDatabase database,
  DiagnosticsSink diagnostics,
) => DriftPersonalGraphRepository(
  database,
  UuidV7IntentionIdGenerator(),
  () => DateTime.utc(2026, 9, 20),
  diagnostics,
);

RelationGroupPage _page(RelationGroupPageResult result) {
  expect(result, isA<RelationGroupPageSuccess>());
  return (result as RelationGroupPageSuccess).value;
}

RelationGroupReadFailure _failure(RelationGroupPageResult result) {
  expect(result, isA<RelationGroupPageFailure>());
  return (result as RelationGroupPageFailure).failure;
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
