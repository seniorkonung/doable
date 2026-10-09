import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart';
import '../../../intention/presentation/catalog/intention_picker_session_test_support.dart';

void main() {
  for (final context in RelationParticipantSelectionContext.values) {
    for (final excluded in [null, testSummary(index: 999).id]) {
      group('Контекст ${context.name}, исключение: ${excluded != null}', () {
        defineIntentionPickerSessionTests(
          route: excluded == null
              ? RelationParticipantPickerRoute(selectionContext: context)
              : RelationParticipantPickerRoute(
                  excludedIntentionId: excluded,
                  selectionContext: context,
                ),
          filterKey: 'participant-picker-filter-field',
          listKey: 'participant-picker-list',
          scope: context.catalogScope,
          excludedIntentionId: excluded,
          readinessFilter: IntentionReadinessFilter.all,
        );
      });
    }
  }
}
