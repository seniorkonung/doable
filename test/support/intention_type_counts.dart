import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';

/// Отвечает тестовым адаптером на [query] так же, как production-адаптер:
/// первая порция несёт числа типов, только если их просит запрос.
///
/// Числа, которые тест задал в порции сам, остаются как есть. Иначе они
/// выводятся из общего количества и готовности намерений порции:
/// незагруженные совпадения без условия готовности считаются намерениями.
Result<IntentionCatalogPage> answerCatalogQuery(
  IntentionCatalogQuery query,
  Result<IntentionCatalogPage> result,
) => switch (result) {
  ResultSuccess(value: final IntentionCatalogFirstPage page)
      when query.requestsTypeCounts && page.typeCounts == null =>
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: page.items,
        totalCount: page.totalCount,
        typeCounts: _typeCounts(query.readinessFilter, page),
        nextCursor: page.nextCursor,
        revision: page.revision,
      ),
    ),
  _ => result,
};

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
