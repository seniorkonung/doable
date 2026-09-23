import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';

CreateDailyChoice reconciliationCreateCommand(
  DailyChoice choice,
  LongTermRelationId pathRelationId,
) => CreateDailyChoice(
  sourceIntentionId: choice.sourceIntentionId,
  selectedIntentionId: choice.selectedIntentionId,
  path: ConfirmedChoicePath([
    ConfirmedChoicePathStep(
      relationId: pathRelationId,
      sourceIntentionId: choice.sourceIntentionId,
      type: LongTermRelationType.need,
      relatedIntentionId: choice.selectedIntentionId,
    ),
  ]),
  date: choice.date,
  description: choice.description,
  isCompleted: choice.isCompleted,
);

DailyChoiceCommandResult reconciliationChoiceCreated({
  required DailyChoice choice,
  required LongTermRelationId pathRelationId,
  required GraphRevision revision,
  required Map<IntentionId, RelationCounts> counts,
}) {
  final stepId = switch (ChoicePathStepId.decode(
    '018f0003-0000-7000-8000-000000000001',
  )) {
    ChoicePathStepIdDecodingSuccess(:final id) => id,
    InvalidChoicePathStepIdDecoding() => throw StateError(
      'Некорректный ID шага.',
    ),
  };
  final change = DailyChoiceChange(
    revision: revision,
    before: null,
    after: choice,
    releasedRelationIds: const [],
    occupiedRelationIds: [pathRelationId],
    intentionCounts: counts,
    relationPermissions: {
      pathRelationId: const LongTermRelationPermissions.referencedByDailyPath(),
    },
  );
  return GraphCommandSucceeded<
    DailyChoiceCommandSuccess,
    DailyChoiceCommandFailure
  >(
    ConfirmedGraphResult(
      revision: revision,
      value: DailyChoiceCreated(
        choice: choice,
        path: StoredChoicePath([
          ChoicePathStep(
            id: stepId,
            dailyChoiceId: choice.id,
            relationId: pathRelationId,
            previousStepId: null,
          ),
        ]),
        changes: [change],
      ),
    ),
  );
}

DailyChoice reconciliationChoice({
  required IntentionId source,
  required IntentionId selected,
}) {
  final id = switch (DailyChoiceId.decode(
    '018f0002-0000-7000-8000-000000000001',
  )) {
    DailyChoiceIdDecodingSuccess(:final id) => id,
    InvalidDailyChoiceIdDecoding() => throw StateError(
      'Некорректный ID выбора.',
    ),
  };
  return DailyChoice(
    id: id,
    sourceIntentionId: source,
    selectedIntentionId: selected,
    date: CalendarDate.fromParts(2026, 9, 23),
    description: null,
    isCompleted: false,
  );
}

DailyChoiceCommandResult reconciliationChoiceDeleted({
  required DailyChoice choice,
  required LongTermRelationId pathRelationId,
  required GraphRevision revision,
  required Map<IntentionId, RelationCounts> counts,
}) {
  final change = DailyChoiceChange(
    revision: revision,
    before: choice,
    after: null,
    releasedRelationIds: [pathRelationId],
    occupiedRelationIds: const [],
    intentionCounts: counts,
    relationPermissions: {
      pathRelationId: const LongTermRelationPermissions.unrestricted(),
    },
  );
  return GraphCommandSucceeded<
    DailyChoiceCommandSuccess,
    DailyChoiceCommandFailure
  >(
    ConfirmedGraphResult(
      revision: revision,
      value: DailyChoiceDeleted(choice: choice, changes: [change]),
    ),
  );
}
