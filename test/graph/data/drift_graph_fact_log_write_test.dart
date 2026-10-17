import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart'
    show AppDatabase, GraphLogPackage;
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

final _now = DateTime.utc(2026, 10, 17, 12, 30, 0, 0, 1);

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    database = await harness.openReadyDatabase();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => _now,
      InMemoryDiagnosticsSink(),
    );
  });

  tearDown(() => harness.dispose());

  Future<List<GraphLogPackage>> packages() => (database.select(
    database.graphLogPackages,
  )..orderBy([(package) => OrderingTerm.asc(package.position)])).get();

  Future<Intention> createIntention(
    String title, {
    IntentionReadiness readiness = IntentionReadiness.notReady,
  }) async => _confirmed<IntentionSaved>(
    await repository.execute(
      CreateIntention.withInitialState(
        title: title,
        description: null,
        readiness: readiness,
        tagIds: const {},
      ),
    ),
  ).intention;

  test('каждый блок записи подтверждает команду одним пакетом фактов со следующей позицией', () async {
    var lastPosition = 0;

    /// Подтверждает [execution] и проверяет, что она дописала ровно один
    /// пакет с фактами видов [factKinds].
    Future<T> expectOnePackage<T>(
      Future<Object> execution,
      List<String> factKinds,
    ) async {
      final value = _confirmed<T>(await execution);
      final stored = await packages();
      expect(stored, hasLength(lastPosition + 1));
      final package = stored.last;
      expect(package.position, lastPosition + 1);
      expect(package.kind, 'change');
      expect(package.formatVersion, GraphFormatVersion.current.number);
      expect(package.recordedAt, _now.microsecondsSinceEpoch);
      expect(package.snapshotId, isNull);
      expect(_factKinds(package), factKinds);
      lastPosition = package.position;
      return value;
    }

    final tag = (await expectOnePackage<TagCreated>(
      repository.execute(CreateTag(TagName.fromInput('Дом'))),
      ['тег'],
    )).tag;
    final source = (await expectOnePackage<IntentionSaved>(
      repository.execute(
        CreateIntention.withInitialState(
          title: 'Изучать язык',
          description: null,
          readiness: IntentionReadiness.notReady,
          tagIds: {tag.id},
        ),
      ),
      ['намерение', 'назначение'],
    )).intention;
    final selected = (await expectOnePackage<IntentionSaved>(
      repository.execute(
        CreateIntention.withInitialState(
          title: 'Читать',
          description: null,
          readiness: IntentionReadiness.ready,
          tagIds: const {},
        ),
      ),
      ['намерение'],
    )).intention;
    final relation = (await expectOnePackage<LongTermRelationCreated>(
      repository.execute(
        CreateLongTermRelation(
          sourceIntentionId: source.id,
          relatedIntentionId: selected.id,
          type: LongTermRelationType.need,
          priority: RelationPriority.p2,
          description: null,
        ),
      ),
      ['связь'],
    )).relation;
    final choice = (await expectOnePackage<DailyChoiceCreated>(
      repository.execute(
        CreateDailyChoice(
          sourceIntentionId: source.id,
          selectedIntentionId: selected.id,
          path: _path(relation.id, source.id, selected.id),
          date: CalendarDate.fromParts(2026, 10, 17),
          description: null,
          isCompleted: false,
        ),
      ),
      ['дневной выбор'],
    )).choice;
    await expectOnePackage<DailyChoiceFieldsUpdated>(
      repository.execute(
        UpdateDailyChoiceFields(
          choiceId: choice.id,
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(true),
          ),
        ),
      ),
      ['дневной выбор'],
    );
    final other = (await expectOnePackage<IntentionSaved>(
      repository.execute(
        CreateIntention.withInitialState(
          title: 'Говорить',
          description: null,
          readiness: IntentionReadiness.ready,
          tagIds: const {},
        ),
      ),
      ['намерение'],
    )).intention;
    final otherRelation = (await expectOnePackage<LongTermRelationCreated>(
      repository.execute(
        CreateLongTermRelation(
          sourceIntentionId: source.id,
          relatedIntentionId: other.id,
          type: LongTermRelationType.need,
          priority: RelationPriority.p2,
          description: null,
        ),
      ),
      ['связь'],
    )).relation;
    await expectOnePackage<DailyChoicePathReplaced>(
      repository.execute(
        ReplaceDailyChoicePath(
          choiceId: choice.id,
          sourceIntentionId: source.id,
          selectedIntentionId: other.id,
          path: _path(otherRelation.id, source.id, other.id),
        ),
      ),
      ['дневной выбор'],
    );
    await expectOnePackage<DailyChoiceDeleted>(
      repository.execute(DeleteDailyChoice(choice.id)),
      ['удаление дневного выбора'],
    );
    await expectOnePackage<BlockingRelationsDeleted>(
      repository.execute(
        DeleteBlockingRelations.longTerm(
          intentionId: source.id,
          relationIds: [relation.id],
        ),
      ),
      ['удаление связи'],
    );
  });

  test('команда без изменений не дописывает пакет', () async {
    final intention = await createIntention('Изучать язык');
    final before = await packages();

    _confirmed<IntentionSaved>(
      await repository.execute(
        UpdateIntention(
          id: intention.id,
          title: intention.title,
          description: intention.description,
        ),
      ),
    );

    expect(await packages(), hasLength(before.length));
  });

  test('прямая запись в таблицу графа отклоняется и после подтверждённой '
      'команды, и после отказа команды', () async {
    Future<void> insertTag() => database.customStatement(
      'INSERT INTO tags (id, name) VALUES (?, ?)',
      ['018f0b5d-6b2e-7c80-8000-000000000021', 'Дом'],
    );
    final bypassRejection = throwsA(
      isA<sqlite.SqliteException>().having(
        (error) => error.message,
        'message',
        'graph write outside the graph write path',
      ),
    );

    final intention = await createIntention('Изучать язык');
    await expectLater(insertTag(), bypassRejection);

    final failed = await repository.execute(
      UpdateIntention(
        id: intention.id,
        title: intention.title,
        description: _descriptionForRecordLength(
          intention,
          graphFormatRecordByteLimit + 1,
        ),
      ),
    );
    expect(failed, isA<ResultFailure<Object?>>());
    await expectLater(insertTag(), bypassRejection);

    expect(await database.select(database.tags).get(), isEmpty);
  });

  group('предел записи', () {
    test(
      'изменение описания с записью ровно на пределе подтверждается',
      () async {
        final intention = await createIntention('Изучать язык');
        final description = _descriptionForRecordLength(
          intention,
          graphFormatRecordByteLimit,
        );

        final saved = _confirmed<IntentionSaved>(
          await repository.execute(
            UpdateIntention(
              id: intention.id,
              title: intention.title,
              description: description,
            ),
          ),
        );

        expect(saved.intention.description, description);
        final package = (await packages()).last;
        final facts = _decodeFacts(package);
        expect(facts, hasLength(1));
        final fact = facts.single as IntentionRecord;
        expect(fact.intention.description, description);
        expect(
          GraphFormatCodec.encode(fact).length,
          graphFormatRecordByteLimit,
        );
      },
    );

    test('изменение описания с записью на байт длиннее предела отклоняется '
        'unexpected без пакета и без изменения базы', () async {
      final intention = await createIntention('Изучать язык');
      final packagesBefore = await packages();
      final rowsBefore = await _intentionRows(database);

      final result = await repository.execute(
        UpdateIntention(
          id: intention.id,
          title: intention.title,
          description: _descriptionForRecordLength(
            intention,
            graphFormatRecordByteLimit + 1,
          ),
        ),
      );

      expect(result, isA<ResultFailure<Object?>>());
      expect(
        (result as ResultFailure<Object?>).failure,
        isA<IntentionUnexpectedFailure>(),
      );
      expect(await packages(), hasLength(packagesBefore.length));
      expect(await _intentionRows(database), rowsBefore);
    });
  });
}

/// Значение подтверждённой команды из её результата [result].
T _confirmed<T>(Object result) {
  expect(result, isA<GraphResultSuccess<Object?, GraphCommandFailure>>());
  final confirmed =
      (result as GraphResultSuccess<Object?, GraphCommandFailure>).value;
  return (confirmed! as ConfirmedGraphResult).value as T;
}

ConfirmedChoicePath _path(
  LongTermRelationId relationId,
  IntentionId sourceId,
  IntentionId relatedId,
) => ConfirmedChoicePath([
  ConfirmedChoicePathStep(
    relationId: relationId,
    sourceIntentionId: sourceId,
    type: LongTermRelationType.need,
    relatedIntentionId: relatedId,
  ),
]);

List<GraphFact> _decodeFacts(GraphLogPackage package) =>
    GraphFormatCodec.decodePackage(
      package.facts!,
      GraphFormatVersion.ofCarrier(package.formatVersion!),
    );

List<String> _factKinds(GraphLogPackage package) => [
  for (final fact in _decodeFacts(package))
    switch (fact) {
      TagRecord() => 'тег',
      IntentionRecord() => 'намерение',
      TagAssignmentRecord() => 'назначение',
      LongTermRelationRecord() => 'связь',
      DailyChoiceRecord() => 'дневной выбор',
      GraphEntityDeletion(:final entity) => switch (entity) {
        TagKey() => 'удаление тега',
        IntentionKey() => 'удаление намерения',
        TagAssignmentKey() => 'удаление назначения',
        LongTermRelationKey() => 'удаление связи',
        DailyChoiceKey() => 'удаление дневного выбора',
      },
    },
];

/// Описание одного-двух графемных кластеров, с которым запись [intention],
/// изменённая в момент [_now], занимает [byteLength] байт UTF-8: каждый
/// комбинирующий знак добавляет два байта, завершающая буква — один.
String _descriptionForRecordLength(Intention intention, int byteLength) {
  final shortest = GraphFormatCodec.encode(
    IntentionRecord(
      Intention(
        id: intention.id,
        title: intention.title,
        description: 'a',
        readiness: intention.readiness,
        archiveState: intention.archiveState,
        createdAt: intention.createdAt,
        updatedAt: IntentionTimestamp(_now),
      ),
    ),
  ).length;
  final missing = byteLength - shortest;
  return 'a${'́' * (missing ~/ 2)}${'b' * (missing % 2)}';
}

Future<List<Map<String, Object?>>> _intentionRows(AppDatabase database) async =>
    [
      for (final row
          in await database
              .customSelect('SELECT * FROM intentions ORDER BY id')
              .get())
        row.data,
    ];
