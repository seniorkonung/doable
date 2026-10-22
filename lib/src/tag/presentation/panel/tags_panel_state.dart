import '../../../shared/domain/unicode_default_case_folding_17.dart';
import '../../application/tag_command.dart';
import '../../domain/tag.dart';
import '../../domain/tag_color.dart';
import '../../domain/tag_id.dart';
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

/// Отказ чтения каталога панели. Отсутствие намерения отказом панели не
/// является: его представляет [TagsPanelIntentionMissing].
enum TagsPanelReadFailure { unavailable, corruption, unexpected }

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

  final TagsPanelReadFailure failure;
  bool get canRetry => failure == TagsPanelReadFailure.unavailable;
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
  final TagsPanelReadFailure? refreshFailure;

  bool get isEmpty => rows.isEmpty;
  bool get rowsAreCurrent => refreshFailure == null;
  bool get canRetryRefresh =>
      refreshFailure == TagsPanelReadFailure.unavailable;

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

  /// Создание копии тега [tagId]: первое свободное по правилу уникальности
  /// названий «‹название› N» при N от 2, цвет исходного тега и место сразу
  /// после него. Без такого тега в строках — `null`.
  TagCreationProposal? duplicationOf(TagId tagId) {
    final source = rows.where((row) => row.tag.id == tagId).firstOrNull?.tag;
    if (source == null) return null;
    final occupied = {for (final row in rows) row.tag.name.matchingKey};
    // Предложенное название может оказаться длиннее допустимого, поэтому
    // ключ строится без проверки названия по тому же свёртыванию регистра.
    var number = 2;
    while (occupied.contains(
      UnicodeDefaultCaseFolding17.fold('${source.name.value} $number'),
    )) {
      number++;
    }
    return TagCreationProposal(
      name: '${source.name.value} $number',
      color: source.color,
      placement: AfterTagPlacement(source.id),
    );
  }

  TagsPanelLoaded withRows(List<TagsPanelRow> rows) =>
      TagsPanelLoaded(rows, refreshFailure: refreshFailure);

  TagsPanelLoaded withRefreshFailure(TagsPanelReadFailure failure) =>
      TagsPanelLoaded(rows, refreshFailure: failure);
}

final class TagsPanelRow {
  const TagsPanelRow({required this.tag, required this.isMarked});

  final Tag tag;

  /// Отметка контекста: при назначении — тег назначен намерению.
  final bool isMarked;
}

/// Начальные значения листа «Новый тег»: название и цвет можно изменить до
/// создания, а размещение лист отправляет без изменений.
final class TagCreationProposal {
  const TagCreationProposal({
    required this.name,
    required this.color,
    required this.placement,
  });

  final String name;
  final TagColor? color;
  final TagPlacement placement;
}
