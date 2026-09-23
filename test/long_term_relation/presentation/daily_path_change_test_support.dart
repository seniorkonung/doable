import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';

DailyChoiceChange testDailyPathChange({
  required GraphRevision revision,
  required LongTermRelationId relationId,
  required IntentionId sourceId,
  required IntentionId selectedId,
  required int choiceNumber,
  required bool isCreated,
  required LongTermRelationPermissions permissions,
}) {
  final decoded = DailyChoiceId.decode(
    '018f1400-0000-7000-8000-${choiceNumber.toString().padLeft(12, '0')}',
  );
  final id = switch (decoded) {
    DailyChoiceIdDecodingSuccess(:final id) => id,
    InvalidDailyChoiceIdDecoding() => throw StateError(
      'Некорректный ID выбора.',
    ),
  };
  final choice = DailyChoice(
    id: id,
    sourceIntentionId: sourceId,
    selectedIntentionId: selectedId,
    date: CalendarDate.fromParts(2026, 9, 23),
    description: null,
    isCompleted: false,
  );
  final zeroCounts = RelationCounts(
    activeNeedIncoming: 0,
    activeNeedOutgoing: 0,
    activeCanIncoming: 0,
    activeCanOutgoing: 0,
    archivedNeedIncoming: 0,
    archivedNeedOutgoing: 0,
    archivedCanIncoming: 0,
    archivedCanOutgoing: 0,
  );
  return DailyChoiceChange(
    revision: revision,
    before: isCreated ? null : choice,
    after: isCreated ? choice : null,
    releasedRelationIds: isCreated ? const [] : [relationId],
    occupiedRelationIds: isCreated ? [relationId] : const [],
    intentionCounts: {sourceId: zeroCounts, selectedId: zeroCounts},
    relationPermissions: {relationId: permissions},
  );
}
