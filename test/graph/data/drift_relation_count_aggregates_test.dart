import 'dart:convert';
import 'dart:typed_data';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_relation_count_aggregates.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

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
    'считает обе прямые дневные роли, не приписывая их середине пути',
    () async {
      final source = _uuid(3000);
      final middle = _uuid(3001);
      final selected = _uuid(3002);
      for (final id in [source, middle, selected]) {
        await _insertIntention(database, id);
      }
      final firstRelation = _uuid(3010);
      final secondRelation = _uuid(3011);
      await _insertRelation(
        database,
        id: firstRelation,
        sourceId: source,
        relatedId: middle,
        type: 'need',
        isArchived: false,
      );
      await _insertRelation(
        database,
        id: secondRelation,
        sourceId: middle,
        relatedId: selected,
        type: 'can',
        isArchived: false,
      );

      for (var index = 0; index < 3; index++) {
        final choice = _uuid(3020 + index);
        await _insertDailyChoice(
          database,
          id: choice,
          sourceId: source,
          selectedId: selected,
          completed: index.isEven,
        );
        await _insertStep(
          database,
          id: _uuid(3030 + index * 2),
          choiceId: choice,
          relationId: firstRelation,
        );
        await _insertStep(
          database,
          id: _uuid(3031 + index * 2),
          choiceId: choice,
          relationId: secondRelation,
          previousId: _uuid(3030 + index * 2),
        );
      }
      await database.customStatement(
        'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
        [firstRelation],
      );

      final counts = await aggregates.read([
        _id(source),
        _id(middle),
        _id(selected),
      ]);
      expect(counts[_id(source)]!.counts.dailySource, 3);
      expect(counts[_id(source)]!.counts.dailySelected, 0);
      expect(counts[_id(middle)]!.counts.dailyTotal, 0);
      expect(counts[_id(selected)]!.counts.dailySource, 0);
      expect(counts[_id(selected)]!.counts.dailySelected, 3);
      expect(counts[_id(middle)]!.counts.total, 2);

      final permissions = await aggregates.readPermissions([
        _relationId(firstRelation),
        _relationId(secondRelation),
      ]);
      for (final value in permissions.values) {
        expect(
          value.restriction,
          LongTermRelationPermissionRestriction.referencedByDailyPath,
        );
        expect(value.canDelete, isFalse);
        expect(value.canChangeMeaning, isFalse);
        expect(value.canEditDescriptionAndPriority, isTrue);
        expect(value.canChangeArchiveState, isTrue);
      }

      await database.customStatement('DELETE FROM daily_choices WHERE id = ?', [
        _uuid(3020),
      ]);
      expect(
        (await aggregates.readPermissions([
          _relationId(firstRelation),
        ]))[_relationId(firstRelation)]!.canDelete,
        isFalse,
      );
      for (var index = 1; index < 3; index++) {
        await database.customStatement(
          'DELETE FROM daily_choices WHERE id = ?',
          [_uuid(3020 + index)],
        );
      }
      expect(
        (await aggregates.readPermissions([
          _relationId(firstRelation),
        ]))[_relationId(firstRelation)]!.canDelete,
        isTrue,
      );
    },
  );

  test(
    'обнаруживает повреждение до фильтрации групп без частичной выдачи',
    () async {
      await database.customStatement('PRAGMA ignore_check_constraints = ON');
      await database.customStatement('PRAGMA foreign_keys = OFF');
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

      final invalidType = await participants(2);
      await _insertRawRelation(
        database,
        id: _uuid(901),
        sourceId: invalidType.$1,
        relatedId: invalidType.$2,
        type: 'other',
      );

      final invalidPriorityStorage = await participants(3);
      await _insertRawRelation(
        database,
        id: _uuid(902),
        sourceId: invalidPriorityStorage.$1,
        relatedId: invalidPriorityStorage.$2,
        priority: Uint8List.fromList([1]),
      );

      final invalidArchiveStorage = await participants(4);
      await _insertRawRelation(
        database,
        id: _uuid(903),
        sourceId: invalidArchiveStorage.$1,
        relatedId: invalidArchiveStorage.$2,
        isArchived: Uint8List.fromList([0]),
      );

      final invalidSequence = await participants(5);
      await _insertRawRelation(
        database,
        creationSequence: -1,
        id: _uuid(904),
        sourceId: invalidSequence.$1,
        relatedId: invalidSequence.$2,
      );

      final whitespaceDescription = await participants(6);
      await _insertRawRelation(
        database,
        id: _uuid(905),
        sourceId: whitespaceDescription.$1,
        relatedId: whitespaceDescription.$2,
        description: ' \n\t ',
      );

      final malformedUtf8Description = await participants(7);
      await database.customStatement(
        '''
          INSERT INTO long_term_relations (
            id,
            source_intention_id,
            related_intention_id,
            type,
            priority,
            description,
            is_archived
          ) VALUES (?, ?, ?, 'need', 1, CAST(x'80' AS TEXT), 0)
        ''',
        [_uuid(906), malformedUtf8Description.$1, malformedUtf8Description.$2],
      );

      final missingParticipant = await participants(8);
      await database.customStatement('DELETE FROM intentions WHERE id = ?', [
        missingParticipant.$2,
      ]);
      await _insertRawRelation(
        database,
        id: _uuid(907),
        sourceId: missingParticipant.$1,
        relatedId: missingParticipant.$2,
        isArchived: 1,
      );

      final relationIdStorage = await participants(9);
      await _insertRawRelation(
        database,
        id: Uint8List.fromList(utf8.encode(_uuid(908))),
        sourceId: relationIdStorage.$1,
        relatedId: relationIdStorage.$2,
      );

      final participantIdStorage = await participants(10);
      final blobParticipantId = Uint8List.fromList(utf8.encode(_uuid(909)));
      await _insertRawIntention(database, blobParticipantId);
      await _insertRawRelation(
        database,
        id: _uuid(910),
        sourceId: participantIdStorage.$1,
        relatedId: blobParticipantId,
      );

      final typeStorage = await participants(11);
      await _insertRawRelation(
        database,
        id: _uuid(911),
        sourceId: typeStorage.$1,
        relatedId: typeStorage.$2,
        type: Uint8List.fromList(utf8.encode('need')),
      );

      final descriptionStorage = await participants(12);
      await _insertRawRelation(
        database,
        id: _uuid(912),
        sourceId: descriptionStorage.$1,
        relatedId: descriptionStorage.$2,
        description: Uint8List.fromList(utf8.encode('Описание')),
      );

      final invalidParticipantState = await participants(13);
      await _insertRawRelation(
        database,
        id: _uuid(913),
        sourceId: invalidParticipantState.$1,
        relatedId: invalidParticipantState.$2,
      );
      await database.customStatement(
        'UPDATE intentions SET is_archived = 2 WHERE id = ?',
        [invalidParticipantState.$2],
      );

      final archivedActiveParticipant = await participants(14);
      await _insertRawRelation(
        database,
        id: _uuid(914),
        sourceId: archivedActiveParticipant.$1,
        relatedId: archivedActiveParticipant.$2,
      );
      await database.customStatement(
        'DROP TRIGGER intentions_archive_requires_no_active_relations',
      );
      await database.customStatement(
        'UPDATE intentions SET is_archived = 1 WHERE id = ?',
        [archivedActiveParticipant.$2],
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

  test('агрегирует внутри SQLite и использует индексы обоих направлений', () async {
    await database.close();
    final trace = _AggregateSelectTrace();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        trace,
      ),
    );
    aggregates = DriftRelationCountAggregates(database);
    const firstOwner = '018f0b5d-6b2e-7c80-8000-000000000021';
    const secondOwner = '018f0b5d-6b2e-7c80-8000-000000000022';
    await _insertIntention(database, firstOwner);
    await _insertIntention(database, secondOwner);
    for (var index = 0; index < 24; index++) {
      final neighbor = _uuid(1000 + index);
      await _insertIntention(database, neighbor);
      await _insertRelation(
        database,
        id: _uuid(2000 + index),
        sourceId: index.isEven ? firstOwner : neighbor,
        relatedId: index.isEven ? neighbor : secondOwner,
        type: index % 3 == 0 ? 'can' : 'need',
        isArchived: index % 5 == 0,
      );
    }
    await database.transaction(() async {
      for (var index = 0; index < 160; index++) {
        final choiceId = _uuid(4000 + index);
        await _insertDailyChoice(
          database,
          id: choiceId,
          sourceId: firstOwner,
          selectedId: _uuid(1000),
          completed: index.isEven,
        );
        await _insertStep(
          database,
          id: _uuid(5000 + index),
          choiceId: choiceId,
          relationId: _uuid(2000),
        );
      }
    });

    final result = await aggregates.read({_id(firstOwner), _id(secondOwner)});
    final aggregateSelect = trace.selects.singleWhere(
      (entry) => entry.statement.statements.single.contains(
        'doable_relation_count_aggregates',
      ),
    );

    expect(result, hasLength(2));
    expect(result[_id(firstOwner)]!.counts.dailySource, 160);
    expect(aggregateSelect.rowCount, 2);
    expect(aggregateSelect.statement.arguments, hasLength(2));

    final plan = await database
        .customSelect(
          'EXPLAIN QUERY PLAN ${aggregateSelect.statement.statements.single}',
          variables: [
            for (final argument in aggregateSelect.statement.arguments)
              Variable.withString(argument! as String),
          ],
        )
        .get();
    final details = plan.map((row) => row.read<String>('detail'));

    expect(
      details,
      contains(contains('long_term_relations_source_group_order')),
    );
    expect(
      details,
      contains(contains('long_term_relations_related_group_order')),
    );
    expect(details, contains(contains('daily_choices_source_recent')));
    expect(details, contains(contains('daily_choices_selected_recent')));

    final relationId = _relationId(_uuid(2000));
    final permissions = await aggregates.readPermissions([relationId]);
    expect(permissions[relationId]!.canDelete, isFalse);
    final permissionSelect = trace.selects.singleWhere(
      (entry) => entry.statement.statements.single.contains(
        'doable_daily_path_permissions',
      ),
    );
    expect(permissionSelect.rowCount, 1);
    final permissionPlan = await database
        .customSelect(
          'EXPLAIN QUERY PLAN ${permissionSelect.statement.statements.single}',
          variables: [Variable.withString(relationId.toCanonicalString())],
        )
        .get();
    expect(
      permissionPlan.map((row) => row.read<String>('detail')),
      contains(contains('daily_choice_path_steps_relation')),
    );
  });

  test('ошибка агрегата не выдаёт нули или свободное разрешение', () async {
    await database.close();
    final trace = _AggregateSelectTrace(
      failCounts: true,
      failPermissions: true,
    );
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        trace,
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
    await expectLater(
      aggregates.readPermissions([_relationId(relation)]),
      throwsStateError,
    );
  });
}

IntentionId _id(String value) =>
    (IntentionId.decode(value) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relationId(String value) =>
    (LongTermRelationId.decode(value) as LongTermRelationIdDecodingSuccess).id;

Future<void> _insertIntention(AppDatabase database, String id) =>
    database.customStatement(
      '''
        INSERT INTO intentions (id, title, created_at, updated_at)
        VALUES (?, ?, ?, ?)
      ''',
      [id, 'Намерение $id', 1000000, 1000000],
    );

Future<void> _insertRawIntention(AppDatabase database, Object id) =>
    database.customStatement(
      '''
        INSERT INTO intentions (id, title, created_at, updated_at)
        VALUES (?, ?, ?, ?)
      ''',
      [id, 'Намерение с raw id', 1000000, 1000000],
    );

Future<void> _insertRelation(
  AppDatabase database, {
  required String id,
  required String sourceId,
  required String relatedId,
  required String type,
  required bool isArchived,
}) => database.customStatement(
  '''
    INSERT INTO long_term_relations (
      id,
      source_intention_id,
      related_intention_id,
      type,
      priority,
      is_archived
    ) VALUES (?, ?, ?, ?, ?, ?)
  ''',
  [id, sourceId, relatedId, type, 1, isArchived ? 1 : 0],
);

Future<void> _insertDailyChoice(
  AppDatabase database, {
  required String id,
  required String sourceId,
  required String selectedId,
  required bool completed,
}) => database.customStatement(
  '''
    INSERT INTO daily_choices
      (id, source_intention_id, selected_intention_id, choice_date, is_completed)
    VALUES (?, ?, ?, '2026-09-23', ?)
  ''',
  [id, sourceId, selectedId, completed ? 1 : 0],
);

Future<void> _insertStep(
  AppDatabase database, {
  required String id,
  required String choiceId,
  required String relationId,
  String? previousId,
}) => database.customStatement(
  '''
    INSERT INTO daily_choice_path_steps
      (id, daily_choice_id, long_term_relation_id, previous_step_id)
    VALUES (?, ?, ?, ?)
  ''',
  [id, choiceId, relationId, previousId],
);

Future<void> _insertRawRelation(
  AppDatabase database, {
  int? creationSequence,
  required Object id,
  required Object sourceId,
  required Object relatedId,
  Object type = 'need',
  Object priority = 1,
  Object? description,
  Object isArchived = 0,
}) => database.customStatement(
  '''
    INSERT INTO long_term_relations (
      ${creationSequence == null ? '' : 'creation_sequence,'}
      id,
      source_intention_id,
      related_intention_id,
      type,
      priority,
      description,
      is_archived
    ) VALUES (
      ${creationSequence == null ? '' : '?,'}
      ?, ?, ?, ?, ?, ?, ?
    )
  ''',
  [
    ?creationSequence,
    id,
    sourceId,
    relatedId,
    type,
    priority,
    description,
    isArchived,
  ],
);

String _uuid(int suffix) =>
    '018f0b5d-6b2e-7c80-8002-${suffix.toString().padLeft(12, '0')}';

final class _AggregateSelectTrace extends LocalDatabaseConnectionObserver {
  _AggregateSelectTrace({
    this.failCounts = false,
    this.failPermissions = false,
  });

  final bool failCounts;
  final bool failPermissions;
  final selects = <({LocalDatabaseSqlStatement statement, int rowCount})>[];

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    final sql = statement.statements.single;
    if ((failCounts && sql.contains('doable_relation_count_aggregates')) ||
        (failPermissions && sql.contains('doable_daily_path_permissions'))) {
      throw StateError('Искусственный отказ агрегата.');
    }
    selects.add((statement: statement, rowCount: rows.length));
    return rows;
  }
}
