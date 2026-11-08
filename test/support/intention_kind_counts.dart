import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_pair_probe.dart';

/// Отвечает тестовым адаптером на [query] так же, как production-адаптер:
/// первая порция несёт числа того вида, который просит запрос, а порция
/// запроса с пробой пары несёт карту занимающих связей, без пробы — не несёт.
///
/// Числа, которые тест задал в порции сам, остаются как есть. Иначе они
/// выводятся из общего количества и вида намерений порции: незагруженные
/// совпадения без условия вида считаются главными. Число охвата и вида
/// запроса равно общему количеству порции, второй охват пуст, а охват «все»
/// считается активным. Карта, которую тест не задал, пуста: ни одна пара не
/// занята.
Result<IntentionCatalogPage> answerCatalogQuery(
  IntentionCatalogQuery query,
  Result<IntentionCatalogPage> result,
) => switch (result) {
  ResultSuccess(value: final page) => ResultSuccess(_answer(query, page)),
  _ => result,
};

IntentionCatalogPage _answer(
  IntentionCatalogQuery query,
  IntentionCatalogPage page,
) {
  final pairOccupants =
      page.pairOccupants ??
      (query.pairProbe == null ? null : const <IntentionId, PairOccupant>{});
  return switch (page) {
    IntentionCatalogFirstPage() => IntentionCatalogFirstPage(
      items: page.items,
      totalCount: page.totalCount,
      counts:
          page.counts is IntentionCountsTotalOnly &&
              query.counting != IntentionCatalogCounting.totalOnly
          ? _counts(query, page)
          : page.counts,
      nextCursor: page.nextCursor,
      revision: page.revision,
      pairOccupants: pairOccupants,
      exactTitleCount: page.exactTitleCount,
    ),
    IntentionCatalogContinuationPage() => IntentionCatalogContinuationPage(
      items: page.items,
      nextCursor: page.nextCursor,
      revision: page.revision,
      pairOccupants: pairOccupants,
    ),
  };
}

IntentionCatalogCounts _counts(
  IntentionCatalogQuery query,
  IntentionCatalogFirstPage page,
) {
  final inScope = _kindCounts(query.kindFilter, page);
  return switch (query.counting) {
    IntentionCatalogCounting.totalOnly => const IntentionCountsTotalOnly(),
    IntentionCatalogCounting.byScopeAndKind => switch (query.scope) {
      IntentionScope.archived => IntentionCountsByScopeAndKind(
        active: IntentionKindCounts(main: 0, supporting: 0),
        archived: inScope,
      ),
      IntentionScope.active ||
      IntentionScope.all => IntentionCountsByScopeAndKind(
        active: inScope,
        archived: IntentionKindCounts(main: 0, supporting: 0),
      ),
    },
  };
}

IntentionKindCounts _kindCounts(
  IntentionKindFilter kindFilter,
  IntentionCatalogFirstPage page,
) {
  final supporting = switch (kindFilter) {
    IntentionKindFilter.mainOnly => 0,
    IntentionKindFilter.supportingOnly => page.totalCount,
    IntentionKindFilter.mainAndSupporting =>
      page.items.where((item) => item.kind == IntentionKind.supporting).length,
  };
  return IntentionKindCounts(
    main: page.totalCount - supporting,
    supporting: supporting,
  );
}
