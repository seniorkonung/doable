import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_options.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../relation_graph_test_support.dart';
import 'relation_details_test_support.dart';

void main() {
  final ru = lookupAppLocalizations(const Locale('ru'));
  const revision = TestGraphRevision(1);

  test('архивирование называет каждое последствие отдельным предложением', () {
    final composition = ArchiveCascadeComposition(
      departing: [testIntentionId(3)],
      promoted: [],
      archivedRelationCount: 0,
    );
    final preview = ArchiveCascadePreview(
      revision: revision,
      plan: CascadePlan(
        withSupporting: composition,
        onlyThis: composition,
        asksQuestion: true,
      ),
      titles: const {},
    );
    expect(
      relationOptions(ru, _loaded(), statePreview: preview).first.hint,
      'Останется в сохранённых путях с отметкой архива. '
      'Вместе со связью в архив уйдут вспомогательные намерения: 1',
    );
  });

  test('восстановление называет каждое последствие отдельным предложением', () {
    final composition = RestoreCascadeComposition(
      restored: [testIntentionId(3)],
      returnedAsMain: null,
      restoredRelationCount: 0,
    );
    final preview = RestoreCascadePreview(
      revision: revision,
      plan: CascadePlan(
        withSupporting: composition,
        onlyThis: composition,
        asksQuestion: true,
      ),
      titles: const {},
    );
    expect(
      relationOptions(
        ru,
        _loaded(scope: RelationScope.archived),
        statePreview: preview,
      ).first.hint,
      'В сохранённых путях больше не отмечена архивной и снова доступна для '
      'новых путей. Вместе со связью вернутся намерения: 1',
    );
  });

  test('удаление называет каждое последствие отдельным предложением', () {
    final composition = DeleteCascadeComposition(
      departing: [testIntentionId(3)],
      promoted: [],
      archivedByInvariant: [testIntentionId(4)],
      mainsLosingRelation: [],
      deletedRelationCount: 1,
    );
    final preview = RelationDeleteCascadePreview(
      revision: revision,
      plan: CascadePlan(
        withSupporting: composition,
        onlyThis: composition,
        asksQuestion: true,
      ),
      titles: const {},
    );
    expect(
      relationOptions(ru, _loaded(), deletePreview: preview).last.hint,
      'В сохранённых путях останется с пометкой «Удалено». '
      'Вместе со связью будут удалены вспомогательные намерения: 1. '
      'В архив уйдут намерения: 1',
    );
  });
}

RelationDetailsLoaded _loaded({RelationScope scope = RelationScope.active}) =>
    RelationDetailsLoaded(
      details: testRelationDetails(
        relationId: testRelationId(1),
        sourceId: testIntentionId(1),
        relatedId: testIntentionId(2),
        scope: scope,
      ),
      revision: const TestGraphRevision(1),
      isOperationRunning: false,
    );
