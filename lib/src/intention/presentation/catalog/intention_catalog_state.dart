import '../../../graph/application/graph_revision.dart';
import '../../../long_term_relation/application/relation_pair_probe.dart';
import '../../application/intention_catalog.dart';
import '../../application/intention_holding.dart';
import '../../domain/intention_id.dart';

enum IntentionCatalogFilterValidationFailure {
  invalidUnicodeRepertoire,
  tooLong,
}

/// Охват и вид выдачи, которые задаёт назначение поиска.
sealed class IntentionShowParameters {
  const IntentionShowParameters();

  IntentionScope get scope;

  IntentionKindFilter get kind;
}

/// Каталог: охват [scope] и вид [kind] выбирает человек.
final class IntentionShowChosen extends IntentionShowParameters {
  const IntentionShowChosen({required this.scope, required this.kind});

  @override
  final IntentionScope scope;

  @override
  final IntentionKindFilter kind;

  @override
  bool operator ==(Object other) =>
      other is IntentionShowChosen &&
      other.scope == scope &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(IntentionShowChosen, scope, kind);
}

/// Поиск для выбора: активные намерения обоих видов, без выбора человеком.
final class IntentionShowFixed extends IntentionShowParameters {
  const IntentionShowFixed();

  @override
  IntentionScope get scope => IntentionScope.active;

  @override
  IntentionKindFilter get kind => IntentionKindFilter.mainAndSupporting;

  @override
  bool operator ==(Object other) => other is IntentionShowFixed;

  @override
  int get hashCode => (IntentionShowFixed).hashCode;
}

/// Точные числа намерений каждого охвата при одном условии вида.
final class IntentionScopeCounts {
  const IntentionScopeCounts({required this.active, required this.archived});

  final int active;
  final int archived;

  int get all => active + archived;
}

final class IntentionCatalogSelection {
  const IntentionCatalogSelection({
    required this.show,
    required this.titleFilterText,
    this.tagFilter = IntentionTagFilter.empty,
    required this.order,
    required this.filterValidationFailure,
  });

  final IntentionShowParameters show;
  final String titleFilterText;
  final IntentionTagFilter tagFilter;
  final IntentionCatalogOrder order;
  final IntentionCatalogFilterValidationFailure? filterValidationFailure;
}

sealed class IntentionCatalogState {
  const IntentionCatalogState({required this.selection});

  final IntentionCatalogSelection selection;
}

final class IntentionCatalogDebouncing extends IntentionCatalogState {
  const IntentionCatalogDebouncing({required super.selection});
}

final class IntentionCatalogInvalidFilter extends IntentionCatalogState {
  const IntentionCatalogInvalidFilter({required super.selection});
}

sealed class IntentionCatalogConfirmedState extends IntentionCatalogState {
  const IntentionCatalogConfirmedState({
    required super.selection,
    required this.query,
    required this.totalCount,
    required this.counts,
    required this.nextCursor,
    required this.revision,
    this.exactTitleCount,
  });

  final IntentionCatalogQuery query;
  final int totalCount;

  /// Точные числа вида, который запросила выдача.
  final IntentionCatalogCounts counts;
  final IntentionCatalogCursor? nextCursor;
  final GraphRevision revision;
  final int? exactTitleCount;

  /// Название для создания, если активного намерения с ним ещё нет.
  String? get createTitle =>
      exactTitleCount == 0 ? query.titleFilter?.map((value) => value) : null;

  /// Числа обоих видов в текущем охвате при условиях выдачи без условия
  /// вида. Есть тогда и только тогда, когда вид в [selection] выбирается.
  IntentionKindCounts? get kindCounts => switch (counts) {
    IntentionCountsTotalOnly() => null,
    final IntentionCountsByScopeAndKind counts => counts.inScope(query.scope),
  };

  /// Числа охватов при текущем виде и условиях выдачи без условия охвата.
  /// Есть тогда и только тогда, когда охват в [selection] выбирается.
  IntentionScopeCounts? get scopeCounts => switch (counts) {
    IntentionCountsTotalOnly() => null,
    IntentionCountsByScopeAndKind(:final active, :final archived) =>
      IntentionScopeCounts(
        active: active.matching(query.kindFilter),
        archived: archived.matching(query.kindFilter),
      ),
  };
}

final class IntentionCatalogLoaded extends IntentionCatalogConfirmedState {
  IntentionCatalogLoaded({
    required super.selection,
    required super.query,
    required List<IntentionSummary> items,
    required super.totalCount,
    required super.counts,
    required super.nextCursor,
    required super.revision,
    super.exactTitleCount,
    Map<IntentionId, PairOccupant> pairOccupants = const {},
    Map<IntentionId, IntentionHolding> holdings = const {},
    this.continuation = const IntentionCatalogContinuationIdle(),
  }) : items = List.unmodifiable(items),
       pairOccupants = Map.unmodifiable(pairOccupants),
       holdings = Map.unmodifiable(holdings);

  final List<IntentionSummary> items;

  /// Связи, занимающие пары загруженных строк, по идентификатору строки; у
  /// строки без записи пара свободна. Запись принадлежит поиску с пробой пары:
  /// приходит с той же порцией, что и строка, а затем следует за
  /// подтверждёнными фактами о связях; без пробы карта пуста.
  final Map<IntentionId, PairOccupant> pairOccupants;

  /// Удержание загруженных активных вспомогательных строк, прочитанное после
  /// первой порции или последнего изменения удержания. У строки без записи
  /// удержание ещё не получено или его чтение отказало (D5).
  final Map<IntentionId, IntentionHolding> holdings;
  final IntentionCatalogContinuationState continuation;
}

sealed class IntentionCatalogContinuationState {
  const IntentionCatalogContinuationState();
}

final class IntentionCatalogContinuationIdle
    extends IntentionCatalogContinuationState {
  const IntentionCatalogContinuationIdle();
}

final class IntentionCatalogContinuationLoading
    extends IntentionCatalogContinuationState {
  const IntentionCatalogContinuationLoading();
}

final class IntentionCatalogContinuationUnavailable
    extends IntentionCatalogContinuationState {
  const IntentionCatalogContinuationUnavailable();
}

final class IntentionCatalogContinuationCorruption
    extends IntentionCatalogContinuationState {
  const IntentionCatalogContinuationCorruption();
}

final class IntentionCatalogContinuationUnexpected
    extends IntentionCatalogContinuationState {
  const IntentionCatalogContinuationUnexpected();
}

final class IntentionCatalogEmpty extends IntentionCatalogConfirmedState {
  const IntentionCatalogEmpty({
    required super.selection,
    required super.query,
    required super.counts,
    required super.revision,
    super.exactTitleCount,
  }) : super(totalCount: 0, nextCursor: null);

  IntentionScope get scope => query.scope;
}

final class IntentionCatalogUnavailable extends IntentionCatalogState {
  const IntentionCatalogUnavailable({
    required super.selection,
    required this.query,
  });

  final IntentionCatalogQuery query;
}

final class IntentionCatalogCorruption extends IntentionCatalogState {
  const IntentionCatalogCorruption({
    required super.selection,
    required this.query,
  });

  final IntentionCatalogQuery query;
}

final class IntentionCatalogUnexpected extends IntentionCatalogState {
  const IntentionCatalogUnexpected({
    required super.selection,
    required this.query,
  });

  final IntentionCatalogQuery query;
}
