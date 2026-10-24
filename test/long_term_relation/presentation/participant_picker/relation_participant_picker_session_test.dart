import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart';
import '../../../intention/presentation/catalog/intention_picker_session_test_support.dart';

void main() {
  // Сессия поиска не зависит от контекста связи и исключения; выбран случай,
  // где оба ограничения начального запроса отличаются от умолчаний.
  const context = RelationParticipantSelectionContext.archivedRelation;
  final excluded = testSummary(index: 999).id;
  defineIntentionPickerSessionTests(
    route: RelationParticipantPickerRoute(
      excludedIntentionId: excluded,
      selectionContext: context,
    ),
    filterKey: 'participant-picker-filter',
    listKey: 'participant-picker-list',
    scope: context.catalogScope,
    excludedIntentionId: excluded,
    readinessFilter: IntentionReadinessFilter.all,
  );
}
