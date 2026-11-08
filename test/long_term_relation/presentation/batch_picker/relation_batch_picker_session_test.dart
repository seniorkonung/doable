import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/relation_pair_probe.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart';
import '../../../intention/presentation/catalog/intention_picker_session_test_support.dart';

void main() {
  final page = testSummary(index: 999);
  defineIntentionPickerSessionTests(
    route: RelationBatchPickerRoute(
      pageIntentionId: page.id,
      pageTitle: page.title,
      group: IntentionRelationGroup.needs,
    ),
    filterKey: 'participant-picker-filter',
    listKey: 'participant-picker-list',
    pairProbe: RelationPairProbe.forGroup(
      intentionId: page.id,
      group: IntentionRelationGroup.needs,
    ),
  );
}
