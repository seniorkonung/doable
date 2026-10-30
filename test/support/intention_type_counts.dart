import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';

/// Отвечает тестовым адаптером на [query] так же, как production-адаптер:
/// первая порция несёт числа того вида, который просит запрос.
///
/// Числа, которые тест задал в порции сам, остаются как есть. Иначе они
/// выводятся из общего количества и готовности намерений порции:
/// незагруженные совпадения без условия готовности считаются намерениями.
/// Число охвата и готовности запроса при подсчёте по охватам и типам равно
/// общему количеству порции, второй охват пуст, а охват «все» считается
/// активным.
Result<IntentionCatalogPage> answerCatalogQuery(
  IntentionCatalogQuery query,
  Result<IntentionCatalogPage> result,
) => switch (result) {
  ResultSuccess(value: final IntentionCatalogFirstPage page)
      when page.counts is IntentionCountsTotalOnly &&
          query.counting != IntentionCatalogCounting.totalOnly =>
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: page.items,
        totalCount: page.totalCount,
        counts: _counts(query, page),
        nextCursor: page.nextCursor,
        revision: page.revision,
      ),
    ),
  _ => result,
};

IntentionCatalogCounts _counts(
  IntentionCatalogQuery query,
  IntentionCatalogFirstPage page,
) {
  final inScope = _typeCounts(query.readinessFilter, page);
  return switch (query.counting) {
    IntentionCatalogCounting.totalOnly => const IntentionCountsTotalOnly(),
    IntentionCatalogCounting.byType => IntentionCountsByType(inScope),
    IntentionCatalogCounting.byScopeAndType => switch (query.scope) {
      IntentionScope.archived => IntentionCountsByScopeAndType(
        active: IntentionTypeCounts(all: 0, actions: 0),
        archived: inScope,
      ),
      IntentionScope.active ||
      IntentionScope.all => IntentionCountsByScopeAndType(
        active: inScope,
        archived: IntentionTypeCounts(all: 0, actions: 0),
      ),
    },
  };
}

IntentionTypeCounts _typeCounts(
  IntentionReadinessFilter readinessFilter,
  IntentionCatalogFirstPage page,
) => switch (readinessFilter) {
  IntentionReadinessFilter.all => IntentionTypeCounts(
    all: page.totalCount,
    actions: page.items
        .where((item) => item.readiness == IntentionReadiness.ready)
        .length,
  ),
  IntentionReadinessFilter.readyOnly => IntentionTypeCounts(
    all: page.totalCount,
    actions: page.totalCount,
  ),
  IntentionReadinessFilter.notReadyOnly => IntentionTypeCounts(
    all: page.totalCount,
    actions: 0,
  ),
};
