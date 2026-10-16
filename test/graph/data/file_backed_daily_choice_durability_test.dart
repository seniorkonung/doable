import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/local_database_harness.dart';

void main() {
  test(
    'повторное открытие сохраняет создание, замену пути и независимые правки',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      var database = await harness.openReadyDatabase();
      await seedDurabilityGraph(database);
      final schedule = DailyChoiceTime(hour: 18, minute: 0);
      for (final (choice, firstStep) in [(201, 301), (202, 303)]) {
        expect(
          await durabilityRepository(
            database,
            choiceNumber: choice,
            firstStepNumber: firstStep,
          ).execute(
            durabilityCreate(
              schedule: schedule,
              priority: DailyChoicePriority.p2,
            ),
          ),
          isA<GraphCommandSucceeded>(),
        );
      }
      final confirmed = await durabilityState(database);
      await harness.closePersistenceObjectGraph();

      database = await harness.openReadyDatabase();
      expect(await durabilityState(database), confirmed);
      final choices = await durabilityRows(database, 'daily_choices');
      expect(choices.map((row) => row['id']), [
        durabilityUuid(201),
        durabilityUuid(202),
      ]);
      expect(choices.map((row) => row['creation_sequence']), [1, 2]);
      expect(choices.map((row) => row['choice_date']), [
        '2026-09-23',
        '2026-09-23',
      ]);
      expect(choices.map((row) => row['description']), [
        '  Выбор\nдня  ',
        '  Выбор\nдня  ',
      ]);
      expect(choices.map((row) => row['is_completed']), [1, 1]);
      expect(choices.map((row) => row['scheduled_minute']), [1080, 1080]);
      expect(choices.map((row) => row['priority']), [2, 2]);
      final steps = await durabilityRows(database, 'daily_choice_path_steps');
      expect(steps.map((row) => row['id']), [
        durabilityUuid(301),
        durabilityUuid(302),
        durabilityUuid(303),
        durabilityUuid(304),
      ]);
      expect(steps.map((row) => row['previous_step_id']), [
        null,
        durabilityUuid(301),
        null,
        durabilityUuid(303),
      ]);
      final repository = durabilityRepository(database, firstStepNumber: 401);
      for (final number in [201, 202]) {
        final result = await repository.getDailyChoice(
          durabilityChoice(number),
        );
        expect(result, isA<DailyChoiceReadSuccess>());
        final details = (result as DailyChoiceReadSuccess).value.value!;
        expect(details.choice.id, durabilityChoice(number));
        expect(details.choice.date, CalendarDate.fromParts(2026, 9, 23));
        expect(details.choice.schedule, schedule);
        expect(details.choice.priority, DailyChoicePriority.p2);
        expect(details.choice.description!.value, '  Выбор\nдня  ');
        expect(details.choice.isCompleted, isTrue);
        expect(details.path.map((step) => step.relation.id), [
          durabilityRelation(101),
          durabilityRelation(102),
        ]);
      }
      final relation = await repository
          .watchRelation(durabilityRelation(101))
          .first;
      expect(
        (relation as LongTermRelationReadSuccess)
            .value
            .value!
            .permissions
            .canDelete,
        isFalse,
      );
      expect(await _sourceChoiceCount(repository), 2);
      await _expectIntegrity(database);

      for (final (command, expectedSchedule, expectedPriority) in [
        (
          ReplaceDailyChoicePath(
            choiceId: durabilityChoice(201),
            sourceIntentionId: durabilityIntention(1),
            selectedIntentionId: durabilityIntention(4),
            path: durabilityPath([103]),
          ),
          schedule,
          DailyChoicePriority.p2,
        ),
        (
          UpdateDailyChoiceFields(
            choiceId: durabilityChoice(201),
            patch: const DailyChoiceFieldsPatch(
              priority: DailyChoiceFieldSet(DailyChoicePriority.p1),
            ),
          ),
          schedule,
          DailyChoicePriority.p1,
        ),
        (
          UpdateDailyChoiceFields(
            choiceId: durabilityChoice(201),
            patch: const DailyChoiceFieldsPatch(
              schedule: DailyChoiceFieldSet(DailyChoiceAllDay()),
            ),
          ),
          const DailyChoiceAllDay(),
          DailyChoicePriority.p1,
        ),
      ]) {
        expect(await repository.execute(command), isA<GraphCommandSucceeded>());
        final result = await repository.getDailyChoice(durabilityChoice(201));
        final details = (result as DailyChoiceReadSuccess).value.value!;
        expect(details.choice.schedule, expectedSchedule);
        expect(details.choice.priority, expectedPriority);
        expect(details.choice.id, durabilityChoice(201));
        expect(details.choice.date, durabilityChoiceDate);
        expect(details.choice.description!.value, '  Выбор\nдня  ');
        expect(details.choice.isCompleted, isTrue);
        expect(details.choice.sourceIntentionId, durabilityIntention(1));
        expect(details.choice.selectedIntentionId, durabilityIntention(4));
        expect(details.path.map((step) => step.relation.id), [
          durabilityRelation(103),
        ]);
      }

      expect(
        await repository.execute(DeleteDailyChoice(durabilityChoice(202))),
        isA<GraphCommandSucceeded>(),
      );
      final edited = await durabilityState(database);
      await harness.closePersistenceObjectGraph();
      database = await harness.openReadyDatabase();
      expect(await durabilityState(database), edited);
      final reopened = await durabilityRepository(database)
          .getDailyChoice(durabilityChoice(201));
      final details = (reopened as DailyChoiceReadSuccess).value.value!;
      expect(details.choice.id, durabilityChoice(201));
      expect(details.choice.date, durabilityChoiceDate);
      expect(details.choice.description!.value, '  Выбор\nдня  ');
      expect(details.choice.isCompleted, isTrue);
      expect(details.choice.schedule, const DailyChoiceAllDay());
      expect(details.choice.priority, DailyChoicePriority.p1);
      expect(details.choice.sourceIntentionId, durabilityIntention(1));
      expect(details.choice.selectedIntentionId, durabilityIntention(4));
      expect(details.path.map((step) => step.relation.id), [
        durabilityRelation(103),
      ]);
      expect(
        await durabilityRepository(
          database,
          choiceNumber: 203,
          firstStepNumber: 305,
        ).execute(durabilityCreate()),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        (await durabilityRows(
          database,
          'daily_choices',
        )).map((row) => (row['id'], row['creation_sequence'])),
        [(durabilityUuid(201), 1), (durabilityUuid(203), 3)],
      );
      await _expectIntegrity(database);
    },
  );
}

Future<void> _expectIntegrity(AppDatabase database) async {
  expect(
    await database.customSelect('PRAGMA foreign_key_check').get(),
    isEmpty,
  );
  expect(
    (await database.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
      'foreign_keys',
    ),
    1,
  );
}

Future<int> _sourceChoiceCount(DriftPersonalGraphRepository repository) async {
  final result = await repository.getRelationCounts(durabilityIntention(1));
  return (result as ResultSuccess<GraphSnapshot<RelationCounts>>)
      .value
      .value
      .dailySource;
}
