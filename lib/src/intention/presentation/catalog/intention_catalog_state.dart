import '../../../graph/application/graph_revision.dart';
import '../../application/intention_catalog.dart';

enum IntentionCatalogFilterValidationFailure {
  invalidUnicodeRepertoire,
  tooLong,
}

/// Тип намерения, которым поиск ограничивает выдачу.
enum IntentionTypeChoice { all, intentions, actions }

/// Доступность выбора типа намерения, которую задаёт назначение поиска.
sealed class IntentionTypeAvailability {
  const IntentionTypeAvailability();
}

/// Тип выбирается человеком; [selected] — выбранный тип.
final class IntentionTypeOpen extends IntentionTypeAvailability {
  const IntentionTypeOpen(this.selected);

  final IntentionTypeChoice selected;

  @override
  bool operator ==(Object other) =>
      other is IntentionTypeOpen && other.selected == selected;

  @override
  int get hashCode => Object.hash(IntentionTypeOpen, selected);
}

/// Назначение поиска закрепляет тип за действиями.
final class IntentionTypePinnedToActions extends IntentionTypeAvailability {
  const IntentionTypePinnedToActions();

  @override
  bool operator ==(Object other) => other is IntentionTypePinnedToActions;

  @override
  int get hashCode => (IntentionTypePinnedToActions).hashCode;
}

/// Назначение поиска выбор типа не предлагает.
final class IntentionTypeNotOffered extends IntentionTypeAvailability {
  const IntentionTypeNotOffered();

  @override
  bool operator ==(Object other) => other is IntentionTypeNotOffered;

  @override
  int get hashCode => (IntentionTypeNotOffered).hashCode;
}

final class IntentionCatalogSelection {
  const IntentionCatalogSelection({
    required this.scope,
    required this.type,
    required this.titleFilterText,
    this.tagFilter = IntentionTagFilter.empty,
    required this.order,
    required this.filterValidationFailure,
  });

  final IntentionScope scope;
  final IntentionTypeAvailability type;
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
    required this.typeCounts,
    required this.nextCursor,
    required this.revision,
  });

  final IntentionCatalogQuery query;
  final int totalCount;

  /// Точные числа обоих типов при условиях выдачи без условия готовности.
  /// Есть тогда и только тогда, когда тип в [selection] открыт.
  final IntentionTypeCounts? typeCounts;
  final IntentionCatalogCursor? nextCursor;
  final GraphRevision revision;
}

final class IntentionCatalogLoaded extends IntentionCatalogConfirmedState {
  IntentionCatalogLoaded({
    required super.selection,
    required super.query,
    required List<IntentionSummary> items,
    required super.totalCount,
    required super.typeCounts,
    required super.nextCursor,
    required super.revision,
    this.continuation = const IntentionCatalogContinuationIdle(),
  }) : items = List.unmodifiable(items);

  final List<IntentionSummary> items;
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
    required super.typeCounts,
    required super.revision,
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
