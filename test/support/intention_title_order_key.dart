import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:doable/src/intention/domain/intention_text.dart';

/// Ключ порядка названия, который тестовый адаптер строит из поисковой
/// проекции названия, как production-адаптер — из сохранённой проекции.
IntentionTitleOrderKey testTitleOrderKey(String title) =>
    IntentionTitleOrderKey.fromSearchProjection(
      titleSearchKey(IntentionText.normalizeTitle(title)),
    );
