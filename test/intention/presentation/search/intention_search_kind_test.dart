import 'package:doable/l10n/app_localizations_en.dart';
import 'package:doable/l10n/app_localizations_ru.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/search/intention_search_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final session = IntentionSearchSession();
  final purposes = <(String, IntentionCatalogPurpose, String, bool)>[
    ('каталог', const BrowseIntentionCatalog(), 'intention-catalog', true),
    (
      'выбор действия',
      SelectDailyChoiceAction(session: session),
      'daily-choice-action',
      false,
    ),
    (
      'выбор исходного намерения',
      SelectDailyChoiceSource(session: session),
      'daily-choice-source',
      true,
    ),
    (
      'выбор участника',
      SelectRelationParticipant(
        selectionContext: RelationParticipantSelectionContext.activeRelation,
        session: session,
      ),
      'participant-picker',
      true,
    ),
  ];

  for (final (name, purpose, keyPrefix, namesKind) in purposes) {
    test('$name: префикс ключей $keyPrefix и называние типа $namesKind', () {
      final kind = IntentionSearchKind.of(purpose);

      expect(kind.keyPrefix, keyPrefix);
      expect(kind.namesKind, namesKind);
    });
  }

  test('четыре назначения не делят префикс ключей', () {
    final prefixes = {
      for (final (_, purpose, _, _) in purposes)
        IntentionSearchKind.of(purpose).keyPrefix,
    };

    expect(prefixes, hasLength(purposes.length));
  });

  test('каталог берёт существующие тексты каталога', () {
    final kind = IntentionSearchKind.of(const BrowseIntentionCatalog());

    for (final l10n in [AppLocalizationsRu(), AppLocalizationsEn()]) {
      expect(kind.title(l10n), l10n.appDestinationIntentionGraph);
      expect(kind.loading(l10n), l10n.catalogLoading);
      expect(kind.loadingMore(l10n), l10n.intentionPickerLoadingMoreIntentions);
      expect(kind.unavailable(l10n), l10n.catalogUnavailable);
      expect(kind.corruption(l10n), l10n.catalogCorruption);
      expect(kind.unexpected(l10n), l10n.catalogUnexpectedFailure);
    }
  });
}
