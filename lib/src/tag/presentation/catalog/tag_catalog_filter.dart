import '../../../shared/domain/unicode_default_case_folding_17.dart';
import '../../../shared/domain/unicode_text.dart';
import '../../domain/tag_name.dart';

/// Проверенный поисковый запрос либо типизированный отказ проверки.
sealed class TagCatalogFilterResult {
  const TagCatalogFilterResult();
}

/// Буквальный поиск по названию тега без учёта регистра Unicode 17.0.0.
final class TagCatalogFilter extends TagCatalogFilterResult {
  const TagCatalogFilter._(this._matchingKey);

  /// Проверяет исходный ввод до преобразования регистра, не исправляя его.
  /// Пустая строка допустима; пробелы и длина запроса сохраняют свой смысл.
  static TagCatalogFilterResult fromInput(String input) {
    try {
      UnicodeText.ensureValidScalarValuesWithoutNul(input);
    } on InvalidUnicodeTextException {
      return const TagCatalogFilterInvalidUnicode();
    }

    return TagCatalogFilter._(UnicodeDefaultCaseFolding17.fold(input));
  }

  final String _matchingKey;

  bool get isEmpty => _matchingKey.isEmpty;

  bool matches(TagName name) =>
      isEmpty || name.matchingKey.contains(_matchingKey);
}

/// Ввод содержит NUL или непарный UTF-16 surrogate и не может быть фильтром.
final class TagCatalogFilterInvalidUnicode extends TagCatalogFilterResult {
  const TagCatalogFilterInvalidUnicode();
}
