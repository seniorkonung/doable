import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_test_support.dart';

void main() {
  for (final (name, purpose)
      in <(String, IntentionCatalogPurpose Function(IntentionSearchSession))>[
        ('действие', (session) => SelectDailyChoiceAction(session: session)),
        ('основание', (session) => SelectDailyChoiceSource(session: session)),
        (
          'участник связи',
          (session) => SelectRelationParticipant(
            excludedIntentionId: testSummary(index: 1).id,
            selectionContext:
                RelationParticipantSelectionContext.activeRelation,
            session: session,
          ),
        ),
      ]) {
    test('$name: один токен сохраняет ключ, новый изолирует поиск', () {
      final session = IntentionSearchSession();
      final first = purpose(session);
      final sameSession = purpose(session);
      final anotherSession = purpose(IntentionSearchSession());

      expect(first, sameSession);
      expect(first.hashCode, sameSession.hashCode);
      expect(first, isNot(anotherSession));
      expect({first: 'своя выдача'}[sameSession], 'своя выдача');
      expect({first: 'своя выдача'}[anotherSession], isNull);
    });
  }

  test('один токен не объединяет разные назначения поиска', () {
    final session = IntentionSearchSession();
    expect(
      SelectDailyChoiceAction(session: session),
      isNot(SelectDailyChoiceSource(session: session)),
    );
    expect(const BrowseIntentionCatalog(), const BrowseIntentionCatalog());
  });
}
