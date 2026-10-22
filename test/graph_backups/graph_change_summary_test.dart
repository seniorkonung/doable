import 'dart:io';

import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_change_summary.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/tag_positions.dart';

void main() {
  group('сводка изменений по фактам пакетов', () {
    test('сущность, изменённая дважды с возвратом к прежнему значению, '
        'считается одним изменением', () {
      final tally = GraphChangeTally(after: 0)
        ..add(
          GraphHistoryChange(
            position: 1,
            facts: [GraphEntityChanged(_intention(1, 'Бегать по утрам'))],
          ),
        )
        ..add(
          GraphHistoryChange(
            position: 2,
            facts: [GraphEntityChanged(_intention(1, 'Бегать'))],
          ),
        );

      expect(_shown(tally.summary), (added: 0, changed: 1, deleted: 0));
    });

    test('первый факт сущности говорит, была ли она до диапазона, а '
        'последний — есть ли она после', () {
      final tally = GraphChangeTally(after: 0)
        ..add(
          GraphHistoryChange(
            position: 1,
            facts: [
              GraphEntityCreated(_tag(1, 'Дом')),
              GraphEntityCreated(_tag(2, 'Дача')),
              GraphEntityChanged(_relation(1, from: 1, to: 2)),
              GraphEntityChanged(_dailyChoice(1, from: 1, to: 2, through: 1)),
            ],
          ),
        )
        ..add(
          GraphHistoryChange(
            position: 2,
            facts: [
              GraphEntityChanged(_tag(1, 'Дом и сад')),
              GraphEntityDeleted(TagKey(_tagId(2))),
              GraphEntityDeleted(LongTermRelationKey(_relationId(1))),
              GraphEntityChanged(_dailyChoice(1, from: 1, to: 2, through: 1)),
            ],
          ),
        );

      expect(_shown(tally.summary), (added: 1, changed: 1, deleted: 1));
    });

    test('снятие и повторное назначение тега и назначение другого тега '
        'считаются одним изменением намерения, а не изменениями тегов', () {
      final tally = GraphChangeTally(after: 0)
        ..add(
          GraphHistoryChange(
            position: 1,
            facts: [_unassigned(tag: 1, intention: 1)],
          ),
        )
        ..add(
          GraphHistoryChange(
            position: 2,
            facts: [
              GraphEntityCreated(_assignment(tag: 1, intention: 1)),
              GraphEntityCreated(_assignment(tag: 2, intention: 1)),
            ],
          ),
        );

      expect(_shown(tally.summary), (added: 0, changed: 1, deleted: 0));
    });

    test('назначения созданного намерения не делают его изменённым, а '
        'назначения удалённого — не мешают считать его удалённым', () {
      final tally = GraphChangeTally(after: 0)
        ..add(
          GraphHistoryChange(
            position: 1,
            facts: [
              GraphEntityCreated(_intention(1, 'Бегать')),
              GraphEntityCreated(_assignment(tag: 1, intention: 1)),
            ],
          ),
        )
        ..add(
          GraphHistoryChange(
            position: 2,
            facts: [
              GraphEntityDeleted(IntentionKey(_intentionId(2))),
              _unassigned(tag: 1, intention: 2),
            ],
          ),
        );

      expect(_shown(tally.summary), (added: 1, changed: 0, deleted: 1));
    });

    test('каскадное архивирование намерения считает изменёнными намерение и '
        'каждую его связь', () {
      final tally = GraphChangeTally(after: 0)
        ..add(
          GraphHistoryChange(
            position: 1,
            facts: [
              GraphEntityChanged(_intention(2, 'Бегать', archived: true)),
              GraphEntityChanged(
                _relation(1, from: 1, to: 2, scope: RelationScope.archived),
              ),
              GraphEntityChanged(
                _relation(2, from: 2, to: 3, scope: RelationScope.archived),
              ),
            ],
          ),
        );

      expect(_shown(tally.summary), (added: 0, changed: 3, deleted: 0));
    });

    test('пакет «сброс» в диапазоне даёт признак замены вместо чисел, в том '
        'числе после продолжения сводки', () {
      final tally = GraphChangeTally(after: 0)
        ..add(
          GraphHistoryChange(
            position: 1,
            facts: [GraphEntityCreated(_tag(1, 'Дом'))],
          ),
        )
        ..add(const GraphHistoryReset(position: 2));
      expect(_shown(tally.summary), _replaced);

      tally.add(
        GraphHistoryChange(
          position: 3,
          facts: [GraphEntityCreated(_tag(2, 'Дача'))],
        ),
      );

      expect(_shown(tally.summary), _replaced);
      expect(tally.position, 3);
    });

    test('сводка, продолженная пакетами после конца диапазона, учитывает '
        'факты диапазона', () {
      final tally = GraphChangeTally(after: 4)
        ..add(
          GraphHistoryChange(
            position: 5,
            facts: [
              GraphEntityCreated(_tag(1, 'Дом')),
              GraphEntityChanged(_intention(1, 'Бегать')),
            ],
          ),
        );
      expect(_shown(tally.summary), (added: 1, changed: 1, deleted: 0));
      expect(tally.position, 5);

      tally.add(
        GraphHistoryChange(
          position: 6,
          facts: [GraphEntityDeleted(TagKey(_tagId(1)))],
        ),
      );

      expect(_shown(tally.summary), (added: 0, changed: 1, deleted: 0));
      expect(tally.position, 6);
    });

    test('пакет не после конца сводки отклоняется, а сводка не меняется', () {
      final tally = GraphChangeTally(after: 5);

      expect(
        () => tally.add(
          GraphHistoryChange(
            position: 5,
            facts: [GraphEntityCreated(_tag(1, 'Дом'))],
          ),
        ),
        throwsStateError,
      );
      expect(_shown(tally.summary), (added: 0, changed: 0, deleted: 0));
      expect(tally.position, 5);
    });
  });

  group('сводка изменений по пакетам чтения истории', () {
    late LocalDatabaseHarness harness;
    late DriftPersonalGraphRepository repository;
    late GraphSnapshotStore store;
    late Directory snapshots;

    setUp(() async {
      harness = await LocalDatabaseHarness.fileBacked();
      var now = DateTime.utc(2026, 10, 18, 9);
      DateTime clock() => now = now.add(const Duration(seconds: 1));
      repository = DriftPersonalGraphRepository(
        await harness.openReadyDatabase(),
        UuidV7IntentionIdGenerator(),
        clock,
        InMemoryDiagnosticsSink(),
      );
      snapshots = Directory.fromUri(
        harness.temporaryDirectory.uri.resolve('graph_snapshots/'),
      );
      store = GraphSnapshotStore(
        log: repository,
        directory: snapshots,
        clock: clock,
        diagnosticsSink: InMemoryDiagnosticsSink(),
      );
    });

    tearDown(() => harness.dispose());

    Future<T> confirm<T extends GraphCommandOutcome>(
      GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
    ) async {
      final result = await repository.execute(command);
      final confirmed =
          (result as GraphResultSuccess<Object?, GraphCommandFailure>).value!
              as ConfirmedGraphResult;
      return confirmed.value as T;
    }

    Future<GraphChangeSummary> summaryAfter(int position) =>
        store.readHistory((history) async {
          final current = await history.readCurrentPosition();
          final tally = await GraphChangeTally.ofRange(
            history,
            after: position,
            upTo: current,
          );
          return tally.summary;
        });

    test('правка описания намерения, удаление тега без назначений и создание '
        'другого тега дают «1 добавлено, 1 изменено, 1 удалено»', () async {
      final running = (await confirm<IntentionSaved>(
        const CreateIntention(title: 'Бегать', description: 'По утрам'),
      )).intention;
      final home = (await confirm<TagCreated>(
        CreateTag(
          name: TagName.fromInput('Дом'),
          color: null,
          placement: TagPlacement.first,
        ),
      )).tag;
      final previous = await repository.readCurrentPosition();

      await confirm<IntentionSaved>(
        UpdateIntention(
          id: running.id,
          title: 'Бегать',
          description: 'По вечерам',
        ),
      );
      await confirm<TagDeleted>(DeleteTag(home.id));
      await confirm<TagCreated>(
        CreateTag(
          name: TagName.fromInput('Работа'),
          color: null,
          placement: TagPlacement.first,
        ),
      );

      expect(_shown(await summaryAfter(previous)), (
        added: 1,
        changed: 1,
        deleted: 1,
      ));
    });

    test(
      'изменённый байт снимка на начале диапазона сводку не меняет',
      () async {
        await confirm<TagCreated>(
          CreateTag(
            name: TagName.fromInput('Дом'),
            color: null,
            placement: TagPlacement.first,
          ),
        );
        final snapshot = await store.writeSnapshot(1);
        final file = File.fromUri(snapshots.uri.resolve(snapshot.fileName));
        final bytes = await file.readAsBytes();
        bytes[bytes.length ~/ 2] ^= 0xff;
        await file.writeAsBytes(bytes);
        await confirm<TagCreated>(
          CreateTag(
            name: TagName.fromInput('Дача'),
            color: null,
            placement: TagPlacement.first,
          ),
        );
        await expectLater(
          () async => (await store.readStateAt(2)).records.drain<void>(),
          throwsA(isA<GraphSnapshotCorruption>()),
        );

        expect(_shown(await summaryAfter(1)), (
          added: 1,
          changed: 0,
          deleted: 0,
        ));
      },
    );
  });
}

const _replaced = 'Данные заменены';

/// Сводка так, как её показывает список копий: числа или признак замены.
Object _shown(GraphChangeSummary summary) => switch (summary) {
  GraphChangeCounts(:final added, :final changed, :final deleted) => (
    added: added,
    changed: changed,
    deleted: deleted,
  ),
  GraphDataReplaced() => _replaced,
};

final _createdAt = DateTime.utc(2026, 10, 1, 7);

TagRecord _tag(int number, String name) => TagRecord(
  Tag(
    id: _tagId(number),
    name: TagName.fromStored(name),
    color: null,
    position: tagPositionAt(number),
  ),
);

IntentionRecord _intention(int number, String title, {bool archived = false}) =>
    IntentionRecord(
      Intention(
        id: _intentionId(number),
        title: title,
        description: null,
        readiness: IntentionReadiness.ready,
        archiveState: archived
            ? IntentionArchiveState.archived
            : IntentionArchiveState.active,
        createdAt: IntentionTimestamp(_createdAt),
        updatedAt: IntentionTimestamp(_createdAt),
      ),
    );

TagAssignmentRecord _assignment({required int tag, required int intention}) =>
    TagAssignmentRecord(
      TagAssignment(tagId: _tagId(tag), intentionId: _intentionId(intention)),
    );

GraphEntityDeleted _unassigned({required int tag, required int intention}) =>
    GraphEntityDeleted(
      TagAssignmentKey(
        TagAssignment(tagId: _tagId(tag), intentionId: _intentionId(intention)),
      ),
    );

LongTermRelationRecord _relation(
  int number, {
  required int from,
  required int to,
  RelationScope scope = RelationScope.active,
}) => LongTermRelationRecord(
  id: _relationId(number),
  sourceIntentionId: _intentionId(from),
  relatedIntentionId: _intentionId(to),
  type: LongTermRelationType.need,
  priority: RelationPriority.p2,
  description: null,
  scope: scope,
);

DailyChoiceRecord _dailyChoice(
  int number, {
  required int from,
  required int to,
  required int through,
}) {
  final id = _dailyChoiceId(number);
  return DailyChoiceRecord(
    choice: DailyChoice(
      id: id,
      sourceIntentionId: _intentionId(from),
      selectedIntentionId: _intentionId(to),
      date: CalendarDate.fromParts(2026, 10, 2),
      description: null,
      isCompleted: false,
    ),
    path: StoredChoicePath([
      ChoicePathStep(
        id: _stepId(number),
        dailyChoiceId: id,
        relationId: _relationId(through),
        previousStepId: null,
      ),
    ]),
  );
}

TagId _tagId(int number) =>
    (TagId.decode(_uuid('7b0e2f4c', number)) as TagIdDecodingSuccess).id;

IntentionId _intentionId(int number) => (IntentionId.decode(
  _uuid('1f6c7a2e', number),
) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relationId(int number) => (LongTermRelationId.decode(
  _uuid('2a3b4c5d', number),
) as LongTermRelationIdDecodingSuccess).id;

DailyChoiceId _dailyChoiceId(int number) => (DailyChoiceId.decode(
  _uuid('3c4d5e6f', number),
) as DailyChoiceIdDecodingSuccess).id;

ChoicePathStepId _stepId(int number) => (ChoicePathStepId.decode(
  _uuid('4d5e6f7a', number),
) as ChoicePathStepIdDecodingSuccess).id;

String _uuid(String prefix, int number) =>
    '$prefix-1d3a-4c5e-8f60-0a1b2c3d4e${number.toString().padLeft(2, '0')}';
