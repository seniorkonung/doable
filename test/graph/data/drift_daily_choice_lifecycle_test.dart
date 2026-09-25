import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';
IntentionId _intention(int number) =>
    (IntentionId.decode(_uuid(number)) as IntentionIdDecodingSuccess).id;
LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  _uuid(number),
) as LongTermRelationIdDecodingSuccess).id;
DailyChoiceId _choice(int number) =>
    (DailyChoiceId.decode(_uuid(number)) as DailyChoiceIdDecodingSuccess).id;

void main() {
  late AppDatabase database;
  late PersonalGraphRepository repository;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      InMemoryDiagnosticsSink(),
    );
    for (var number = 1; number <= 4; number++) {
      await database.customStatement(
        '''INSERT INTO intentions
           (id, title, is_action_ready, is_archived, created_at, updated_at)
           VALUES (?, ?, ?, 0, 1, 1)''',
        [_uuid(number), 'Намерение $number', number >= 3 ? 1 : 0],
      );
    }
    for (final (number, source, selected) in [
      (101, 1, 2),
      (102, 2, 3),
      (103, 1, 4),
    ]) {
      await database.customStatement(
        '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id,
            type, priority, is_archived)
           VALUES (?, ?, ?, 'need', 2, 0)''',
        [_uuid(number), _uuid(source), _uuid(selected)],
      );
    }
  });
  tearDown(() => database.close());

  ConfirmedChoicePath path(List<(int, int, int)> links) => ConfirmedChoicePath([
    for (final (relation, source, selected) in links)
      ConfirmedChoicePathStep(
        relationId: _relation(relation),
        sourceIntentionId: _intention(source),
        type: LongTermRelationType.need,
        relatedIntentionId: _intention(selected),
      ),
  ]);

  Future<GraphSnapshot<DailyChoiceDetails?>> read(DailyChoiceId id) async =>
      (await repository.getDailyChoice(id) as DailyChoiceReadSuccess).value;

  Future<GraphSnapshot<LongTermRelationDetails?>> relation(int number) async =>
      (await repository.watchRelation(_relation(number)).first
              as LongTermRelationReadSuccess)
          .value;

  test('проводит целый цикл выбора через прикладную границу', () async {
    final originalPath = path([(101, 1, 2), (102, 2, 3)]);
    final replacementPath = path([(103, 1, 4)]);
    final date = CalendarDate.fromParts(2026, 9, 23);
    final description = DailyChoiceDescription.fromInput(
      '  Осмысленный выбор  ',
    );
    var revision = (await read(_choice(999))).revision;

    Future<ConfirmedGraphResult<DailyChoiceCommandSuccess>> commit(
      DailyChoiceCommand command,
    ) async {
      final result = await repository.execute(command);
      expect(result, isA<GraphCommandSucceeded>());
      final confirmed =
          (result
                  as GraphCommandSucceeded<
                    DailyChoiceCommandSuccess,
                    DailyChoiceCommandFailure
                  >)
              .value;
      expect(confirmed.changes, hasLength(1));
      expect(
        confirmed.changes.single.revision.compareTo(confirmed.revision),
        GraphRevisionOrder.same,
      );
      expect(confirmed.revision.compareTo(revision), GraphRevisionOrder.newer);
      revision = confirmed.revision;
      expect(
        (await read(_choice(999))).revision.compareTo(revision),
        GraphRevisionOrder.same,
      );
      return confirmed;
    }

    CreateDailyChoice create() => CreateDailyChoice(
      sourceIntentionId: _intention(1),
      selectedIntentionId: _intention(3),
      path: originalPath,
      date: date,
      description: description,
      isCompleted: true,
    );

    final first = (await commit(create())).value as DailyChoiceCreated;
    final firstId = first.choice.id;
    final firstRead = await read(firstId);
    expect(firstRead.revision.compareTo(revision), GraphRevisionOrder.same);
    expect(firstRead.value!.path.map((step) => step.relation.id), [
      _relation(101),
      _relation(102),
    ]);
    final firstRelation = await relation(101);
    expect(firstRelation.revision.compareTo(revision), GraphRevisionOrder.same);
    expect(firstRelation.value!.permissions.canDelete, isFalse);

    final duplicate = (await commit(create())).value as DailyChoiceCreated;
    final duplicateId = duplicate.choice.id;
    expect(duplicateId, isNot(firstId));
    expect((await read(duplicateId)).value!.choice.isCompleted, isTrue);

    final updated =
        (await commit(
              UpdateDailyChoiceFields(
                choiceId: firstId,
                patch: DailyChoiceFieldsPatch(
                  date: DailyChoiceFieldSet(CalendarDate.fromParts(2027, 1, 2)),
                  isCompleted: const DailyChoiceFieldSet(false),
                ),
              ),
            )).value
            as DailyChoiceFieldsUpdated;
    expect(updated.choice.isCompleted, isFalse);
    expect((await read(duplicateId)).value!.choice.date, date);
    expect((await read(duplicateId)).value!.choice.isCompleted, isTrue);

    final unchanged = await repository.execute(
      UpdateDailyChoiceFields(
        choiceId: firstId,
        patch: const DailyChoiceFieldsPatch(),
      ),
    );
    expect(unchanged, isA<GraphCommandSucceeded>());
    expect(
      (unchanged as GraphCommandSucceeded).value.revision.compareTo(revision),
      GraphRevisionOrder.same,
    );

    final rejected = await repository.execute(
      ReplaceDailyChoicePath(
        choiceId: firstId,
        sourceIntentionId: _intention(1),
        selectedIntentionId: _intention(4),
        path: originalPath,
      ),
    );
    expect(rejected, isA<GraphCommandFailed>());
    expect(
      (await read(firstId)).revision.compareTo(revision),
      GraphRevisionOrder.same,
    );

    final replaced =
        (await commit(
              ReplaceDailyChoicePath(
                choiceId: firstId,
                sourceIntentionId: _intention(1),
                selectedIntentionId: _intention(4),
                path: replacementPath,
              ),
            )).value
            as DailyChoicePathReplaced;
    final replacementRead = await read(firstId);
    expect(
      replacementRead.revision.compareTo(revision),
      GraphRevisionOrder.same,
    );
    expect(replacementRead.value!.path.map((step) => step.relation.id), [
      _relation(103),
    ]);
    expect(replaced.choice.date, CalendarDate.fromParts(2027, 1, 2));
    expect(replaced.choice.description, description);
    expect(replaced.choice.isCompleted, isFalse);
    expect((await relation(101)).value!.permissions.canDelete, isFalse);
    final replacementRelation = await relation(103);
    expect(
      replacementRelation.revision.compareTo(revision),
      GraphRevisionOrder.same,
    );
    expect(replacementRelation.value!.permissions.canDelete, isFalse);
    expect(
      (replaced.changes.single as DailyChoiceChange)
          .intentionCounts[_intention(3)]!
          .dailySelected,
      1,
    );

    await commit(DeleteDailyChoice(firstId));
    expect((await read(firstId)).value, isNull);
    expect((await read(duplicateId)).value!.path, hasLength(2));
    expect((await relation(101)).value!.permissions.canDelete, isFalse);
    expect((await relation(103)).value!.permissions.canDelete, isTrue);

    await commit(DeleteDailyChoice(duplicateId));
    expect((await read(duplicateId)).value, isNull);
    expect((await relation(101)).value!.permissions.canDelete, isTrue);
    expect((await relation(102)).value!.permissions.canDelete, isTrue);
    expect(
      (await repository.getRelationCounts(
        _intention(1),
      ) as GraphResultSuccess).value.value.dailySource,
      0,
    );
  });
}
