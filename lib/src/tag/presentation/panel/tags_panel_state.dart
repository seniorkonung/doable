import '../../application/tag_catalog.dart';
import '../../domain/tag.dart';
import '../catalog/tag_catalog_filter.dart';

/// Состояние одного открытия панели: каталог и поиск меняются независимо,
/// поэтому чтения и повторы сохраняют поиск.
final class TagsPanelState {
  const TagsPanelState({
    required this.catalog,
    this.search = TagsPanelSearch.initial,
  });

  final TagsPanelCatalog catalog;
  final TagsPanelSearch search;

  TagsPanelState withCatalog(TagsPanelCatalog catalog) =>
      TagsPanelState(catalog: catalog, search: search);

  TagsPanelState withSearch(TagsPanelSearch search) =>
      TagsPanelState(catalog: catalog, search: search);
}

/// Применённый поиск панели.
final class TagsPanelSearch {
  const TagsPanelSearch({required this.filter, required this.inputIsInvalid});

  static const initial = TagsPanelSearch(
    filter: TagCatalogFilter.empty,
    inputIsInvalid: false,
  );

  /// Последний корректный фильтр: некорректный ввод его не меняет.
  final TagCatalogFilter filter;

  /// Текущий ввод не применён, и результаты соответствуют [filter].
  final bool inputIsInvalid;
}

sealed class TagsPanelCatalog {
  const TagsPanelCatalog();
}

final class TagsPanelLoading extends TagsPanelCatalog {
  const TagsPanelLoading();
}

/// Отказ первоначального чтения. Повтор предлагается только для доказанно
/// устранимой недоступности.
final class TagsPanelLoadFailure extends TagsPanelCatalog {
  const TagsPanelLoadFailure(this.failure);

  final TagCatalogReadFailure failure;
  bool get canRetry => failure is TagCatalogUnavailableFailure;
}

/// Намерения, для которого открыта панель, больше нет.
final class TagsPanelIntentionMissing extends TagsPanelCatalog {
  const TagsPanelIntentionMissing();
}

/// Полный каталог в ручном порядке с отметками текущего контекста.
///
/// Во время фонового перечитывания строки остаются актуальными. Отказ
/// обновления сохраняет их неактуальными до успешного чтения.
final class TagsPanelLoaded extends TagsPanelCatalog {
  TagsPanelLoaded(List<TagsPanelRow> rows, {this.refreshFailure})
    : rows = List.unmodifiable(rows);

  final List<TagsPanelRow> rows;
  final TagCatalogReadFailure? refreshFailure;

  bool get isEmpty => rows.isEmpty;
  bool get rowsAreCurrent => refreshFailure == null;
  bool get canRetryRefresh => refreshFailure is TagCatalogUnavailableFailure;

  /// Совпавшие с [filter] строки в ручном порядке.
  List<TagsPanelRow> rowsMatching(TagCatalogFilter filter) => [
    for (final row in rows)
      if (filter.matches(row.tag.name)) row,
  ];

  /// Название, создание тега с которым предлагается первой строкой: непустой
  /// [filter], которому не совпадает целиком ни одно название. Иначе `null`.
  String? proposedTagName(TagCatalogFilter filter) =>
      filter.isEmpty || rows.any((row) => filter.matchesWhole(row.tag.name))
      ? null
      : filter.query;

  TagsPanelLoaded withRows(List<TagsPanelRow> rows) =>
      TagsPanelLoaded(rows, refreshFailure: refreshFailure);

  TagsPanelLoaded withRefreshFailure(TagCatalogReadFailure failure) =>
      TagsPanelLoaded(rows, refreshFailure: failure);
}

final class TagsPanelRow {
  const TagsPanelRow({required this.tag, required this.isMarked});

  final Tag tag;

  /// Отметка контекста: при назначении — тег назначен намерению.
  final bool isMarked;
}
