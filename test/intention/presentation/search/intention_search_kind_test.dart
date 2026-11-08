import 'package:doable/l10n/app_localizations_en.dart';
import 'package:doable/l10n/app_localizations_ru.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/search/intention_search_kind.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_pair_probe.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_test_support.dart';

void main() {
  test('каталог: префикс ключей intention-catalog и заголовок каталога', () {
    final kind = IntentionSearchKind.of(const BrowseIntentionCatalog());

    expect(kind, IntentionSearchKind.catalog);
    expect(kind.keyPrefix, 'intention-catalog');
    for (final l10n in [AppLocalizationsRu(), AppLocalizationsEn()]) {
      expect(kind.title(l10n), l10n.appDestinationIntentionGraph);
    }
  });

  test(
    'выбор участника связи: префикс participant-picker и свой заголовок',
    () {
      final kind = IntentionSearchKind.of(
        SelectRelationParticipant(
          session: IntentionSearchSession(),
          pairProbe: RelationPairProbe(
            counterpartId: testSummary(index: 999).id,
            candidateRole: RelationParticipantRole.related,
          ),
        ),
      );

      expect(kind, IntentionSearchKind.relationParticipant);
      expect(kind.keyPrefix, 'participant-picker');
      for (final l10n in [AppLocalizationsRu(), AppLocalizationsEn()]) {
        expect(kind.title(l10n), l10n.participantPickerTitle);
      }
    },
  );
}
