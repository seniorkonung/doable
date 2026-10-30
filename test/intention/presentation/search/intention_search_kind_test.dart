import 'package:doable/l10n/app_localizations_en.dart';
import 'package:doable/l10n/app_localizations_ru.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/search/intention_search_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('каталог: префикс ключей intention-catalog и называние типа', () {
    final kind = IntentionSearchKind.of(const BrowseIntentionCatalog());

    expect(kind.keyPrefix, 'intention-catalog');
    expect(kind.namesKind, isTrue);
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
