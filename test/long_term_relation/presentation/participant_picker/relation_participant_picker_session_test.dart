import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_choice.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart';
import '../../../intention/presentation/catalog/intention_picker_session_test_support.dart';

void main() {
  // Сессия поиска не зависит от описания выбора; выбран случай, где оба
  // ограничения начального запроса отличаются от умолчаний.
  final replaced = testSummary(index: 998);
  final excluded = testSummary(index: 999);
  defineIntentionPickerSessionTests(
    route: RelationParticipantPickerRoute(
      choice: RelationParticipantChoice(
        role: RelationParticipantRole.source,
        flow: const RelationChangeChoiceFlow(
          relationScope: RelationScope.archived,
        ),
        type: LongTermRelationType.need,
        source: RelationParticipantSummary(
          id: replaced.id,
          title: replaced.title,
          archiveState: replaced.archiveState,
        ),
        related: RelationParticipantSummary(
          id: excluded.id,
          title: excluded.title,
          archiveState: excluded.archiveState,
        ),
      ),
    ),
    filterKey: 'participant-picker-filter',
    listKey: 'participant-picker-list',
    scope: IntentionScope.all,
    excludedIntentionId: excluded.id,
    readinessFilter: IntentionReadinessFilter.all,
  );
}
