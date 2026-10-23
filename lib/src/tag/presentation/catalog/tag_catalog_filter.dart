import '../../../shared/domain/unicode_default_case_folding_17.dart';
import '../../../shared/domain/unicode_text.dart';
import '../../domain/tag_name.dart';

/// Проверенный поисковый запрос либо типизированный отказ проверки.
sealed class TagCatalogFilterResult {
  const TagCatalogFilterResult();
}

/// Буквальный поиск по названию тега без учёта регистра Unicode 17.0.0.
final class TagCatalogFilter extends TagCatalogFilterResult {
  const TagCatalogFilter._(this.query, this._matchingKey);

  static const empty = TagCatalogFilter._('', '');

  /// Проверяет исходный ввод до преобразования регистра, не исправляя его,
  /// и отбрасывает окружающие пробелы по правилу названия тега. Пустой после
  /// этого запрос не сужает список; внутренние пробелы и длина сохраняются.
  static TagCatalogFilterResult fromInput(String input) {
    try {
      UnicodeText.ensureValidScalarValuesWithoutNul(input);
    } on InvalidUnicodeTextException {
      return const TagCatalogFilterInvalidUnicode();
    }

    final query = TagName.trimSurroundingWhitespace(input);
    return TagCatalogFilter._(query, UnicodeDefaultCaseFolding17.fold(query));
  }

  /// Применённый запрос в исходном регистре без окружающих пробелов.
  final String query;
  final String _matchingKey;

  bool get isEmpty => _matchingKey.isEmpty;

  bool matches(TagName name) =>
      isEmpty || name.matchingKey.contains(_matchingKey);

  /// Название совпадает с запросом по правилу уникальности названий тегов.
  bool matchesWhole(TagName name) => name.matchingKey == _matchingKey;
}

/// Ввод содержит NUL или непарный UTF-16 surrogate и не может быть фильтром.
final class TagCatalogFilterInvalidUnicode extends TagCatalogFilterResult {
  const TagCatalogFilterInvalidUnicode();
}
