import 'dart:convert';
import 'dart:typed_data';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_relation_count_aggregates.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_seed.dart';

void main() {
  late AppDatabase database;
  late DriftRelationCountAggregates aggregates;

  setUp(() {
    database = AppDatabase(openInMemoryLocalDatabase());
    aggregates = DriftRelationCountAggregates(database);
  });

  tearDown(() => database.close());

  test(
    'возвращает восемь количеств и отдельно считает встречные связи',
    () async {
      const owner = '018f0b5d-6b2e-7c80-8000-000000000001';
      const reverseNeighbor = '018f0b5d-6b2e-7c80-8000-000000000002';
      final otherNeighbors = [
        for (var index = 3; index <= 8; index++)
          '018f0b5d-6b2e-7c80-8000-${index.toString().padLeft(12, '0')}',
      ];
      for (final id in [owner, reverseNeighbor, ...otherNeighbors]) {
        await _insertIntention(database, id);
      }

      final relations = [
        (
          source: owner,
          related: reverseNeighbor,
          type: 'need',
          archived: false,
        ),
        (
          source: reverseNeighbor,
          related: owner,
          type: 'need',
          archived: false,
        ),
        (
          source: owner,
          related: otherNeighbors[0],
          type: 'can',
          archived: false,
        ),
        (
          source: otherNeighbors[1],
          related: owner,
          type: 'can',
          archived: false,
        ),
        (
          source: owner,
          related: otherNeighbors[2],
          type: 'need',
          archived: true,
        ),
        (
          source: otherNeighbors[3],
          related: owner,
          type: 'need',
          archived: true,
        ),
        (
          source: owner,
          related: otherNeighbors[4],
          type: 'can',
          archived: true,
        ),
        (
          source: otherNeighbors[5],
          related: owner,
          type: 'can',
          archived: true,
        ),
      ];
      for (var index = 0; index < relations.length; index++) {
        final relation = relations[index];
        await _insertRelation(
          database,
          id: '018f0b5d-6b2e-7c80-8001-${index.toString().padLeft(12, '0')}',
          sourceId: relation.source,
          relatedId: relation.related,
          type: relation.type,
          isArchived: relation.archived,
        );
      }

      final result = await aggregates.read({_id(owner), _id(reverseNeighbor)});
      final ownerAggregate = result[_id(owner)]!;
      final reverseAggregate = result[_id(reverseNeighbor)]!;

      expect(ownerAggregate.hasIntegrityViolation, isFalse);
      expect([
        ownerAggregate.counts.activeNeedIncoming,
        ownerAggregate.counts.activeNeedOutgoing,
        ownerAggregate.counts.activeCanIncoming,
        ownerAggregate.counts.activeCanOutgoing,
        ownerAggregate.counts.archivedNeedIncoming,
        ownerAggregate.counts.archivedNeedOutgoing,
        ownerAggregate.counts.archivedCanIncoming,
        ownerAggregate.counts.archivedCanOutgoing,
      ], everyElement(1));
      expect(reverseAggregate.hasIntegrityViolation, isFalse);
      expect(reverseAggregate.counts.activeNeedIncoming, 1);
      expect(reverseAggregate.counts.activeNeedOutgoing, 1);
      expect(reverseAggregate.counts.total, 2);
    },
  );

  test('возвращает явные нули для несвязанного намерения', () async {
    const owner = '018f0b5d-6b2e-7c80-8000-000000000011';
    await _insertIntention(database, owner);

    final aggregate = (await aggregates.read({_id(owner)}))[_id(owner)]!;

    expect(aggregate.hasIntegrityViolation, isFalse);
    expect(aggregate.counts.total, 0);
    expect([
      aggregate.counts.activeNeedIncoming,
      aggregate.counts.activeNeedOutgoing,
      aggregate.counts.activeCanIncoming,
      aggregate.counts.activeCanOutgoing,
      aggregate.counts.archivedNeedIncoming,
      aggregate.counts.archivedNeedOutgoing,
      aggregate.counts.archivedCanIncoming,
      aggregate.counts.archivedCanOutgoing,
    ], everyElement(0));
  });

  test(
    'обнаруживает повреждение до фильтрации групп без частичной выдачи',
    () async {
      // Каждое повреждение схема пропускает: формат и тип идентификаторов она
      // не проверяет, а описание связи проверяет только на NUL.
      final owners = <String>[];

      Future<(String, String)> participants(int fixture) async {
        final owner = _uuid(100 + fixture * 2);
        final neighbor = _uuid(101 + fixture * 2);
        await _insertIntention(database, owner);
        await _insertIntention(database, neighbor);
        owners.add(owner);
        return (owner, neighbor);
      }

      final invalidRelationId = await participants(0);
      await _insertRawRelation(
        database,
        id: 'не-uuid',
        sourceId: invalidRelationId.$1,
        relatedId: invalidRelationId.$2,
      );

      final invalidParticipantId = await participants(1);
      const malformedParticipant = 'не-uuid-участника';
      await _insertIntention(database, malformedParticipant);
      await _insertRawRelation(
        database,
        id: _uuid(900),
        sourceId: malformedParticipant,
        relatedId: invalidParticipantId.$1,
      );

      final whitespaceDescription = await participants(2);
      await _insertRawRelation(
        database,
        id: _uuid(905),
        sourceId: whitespaceDescription.$1,
        relatedId: whitespaceDescription.$2,
        description: ' \n\t ',
      );

      final malformedUtf8Description = await participants(3);
      await seedGraph(
        database,
        () => database.customStatement(
          '''
          INSERT INTO long_term_relations (
            id,
            source_intention_id,
            related_intention_id,
            type,
            priority,
            description,
            is_archived,
            created_at,
            updated_at
          ) VALUES (?, ?, ?, 'need', 1, CAST(x'80' AS TEXT), 0, 0, 0)
        ''',
          [
            _uuid(906),
            malformedUtf8Description.$1,
            malformedUtf8Description.$2,
          ],
        ),
      );

      final relationIdStorage = await participants(4);
      await _insertRawRelation(
        database,
        id: Uint8List.fromList(utf8.encode(_uuid(908))),
        sourceId: relationIdStorage.$1,
        relatedId: relationIdStorage.$2,
      );

      final participantIdStorage = await participants(5);
      final blobParticipantId = Uint8List.fromList(utf8.encode(_uuid(909)));
      await _insertRawIntention(database, blobParticipantId);
      await _insertRawRelation(
        database,
        id: _uuid(910),
        sourceId: participantIdStorage.$1,
        relatedId: blobParticipantId,
      );

      final result = await aggregates.read(owners.map(_id));

      for (final owner in owners) {
        expect(
          result[_id(owner)]!.hasIntegrityViolation,
          isTrue,
          reason: 'Ожидалось обнаружение повреждения для $owner.',
        );
      }
    },
  );

  test('ошибка агрегата не выдаёт нули', () async {
    await database.close();
    final fault = _AggregateSelectFault();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        fault,
      ),
    );
    aggregates = DriftRelationCountAggregates(database);
    final source = _uuid(6000);
    final selected = _uuid(6001);
    final relation = _uuid(6002);
    await _insertIntention(database, source);
    await _insertIntention(database, selected);
    await _insertRelation(
      database,
      id: relation,
      sourceId: source,
      relatedId: selected,
      type: 'need',
      isArchived: false,
    );

    await expectLater(aggregates.read([_id(source)]), throwsStateError);
  });
}

IntentionId _id(String value) =>
    (IntentionId.decode(value) as IntentionIdDecodingSuccess).id;

Future<void> _insertIntention(AppDatabase database, String id) => seedGraph(
  database,
  () => database.customStatement(
    '''
        INSERT INTO intentions (id, title, created_at, updated_at)
        VALUES (?, ?, ?, ?)
      ''',
    [id, 'Намерение $id', 1000000, 1000000],
  ),
);

Future<void> _insertRawIntention(AppDatabase database, Object id) => seedGraph(
  database,
  () => database.customStatement(
    '''
        INSERT INTO intentions (id, title, created_at, updated_at)
        VALUES (?, ?, ?, ?)
      ''',
    [id, 'Намерение с raw id', 1000000, 1000000],
  ),
);

Future<void> _insertRelation(
  AppDatabase database, {
  required String id,
  required String sourceId,
  required String relatedId,
  required String type,
  required bool isArchived,
}) => seedGraph(
  database,
  () => database.customStatement(
    '''
    INSERT INTO long_term_relations (
      id,
      source_intention_id,
      related_intention_id,
      type,
      priority,
      is_archived,
      created_at,
      updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, 0, 0)
  ''',
    [id, sourceId, relatedId, type, 1, isArchived ? 1 : 0],
  ),
);

Future<void> _insertRawRelation(
  AppDatabase database, {
  required Object id,
  required Object sourceId,
  required Object relatedId,
  Object? description,
}) => seedGraph(
  database,
  () => database.customStatement(
    '''
    INSERT INTO long_term_relations (
      id,
      source_intention_id,
      related_intention_id,
      type,
      priority,
      description,
      is_archived,
      created_at,
      updated_at
    ) VALUES (?, ?, ?, 'need', 1, ?, 0, 0, 0)
  ''',
    [id, sourceId, relatedId, description],
  ),
);

String _uuid(int suffix) =>
    '018f0b5d-6b2e-7c80-8002-${suffix.toString().padLeft(12, '0')}';

/// Отказывает при чтении агрегатов счётчиков.
final class _AggregateSelectFault extends LocalDatabaseConnectionObserver {
  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    final sql = statement.statements.single;
    if (sql.contains('doable_relation_count_aggregates')) {
      throw StateError('Искусственный отказ агрегата.');
    }
    return rows;
  }
}
