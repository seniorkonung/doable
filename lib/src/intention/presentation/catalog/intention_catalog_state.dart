import '../../application/intention_repository.dart';

enum IntentionCatalogCreateOutcome {
  succeeded,
  validation,
  conflict,
  unavailable,
  corruption,
  unexpected,
}

final class IntentionCatalogPresentationEvent {
  const IntentionCatalogPresentationEvent.create(this.createOutcome);

  final IntentionCatalogCreateOutcome createOutcome;
}

enum IntentionCatalogFilterValidationFailure {
  invalidUnicodeRepertoire,
  tooLong,
}

final class IntentionCatalogSelection {
  const IntentionCatalogSelection({
    required this.scope,
    required this.titleFilterText,
    required this.order,
    required this.filterValidationFailure,
  });

  static const initial = IntentionCatalogSelection(
    scope: IntentionScope.active,
    titleFilterText: '',
    order: IntentionCatalogOrder.createdAtDescending,
    filterValidationFailure: null,
  );

  final IntentionScope scope;
  final String titleFilterText;
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
    required this.nextCursor,
    required this.revision,
  });

  final IntentionCatalogQuery query;
  final int totalCount;
  final IntentionCatalogCursor? nextCursor;
  final IntentionCatalogRevision revision;
}

final class IntentionCatalogLoaded extends IntentionCatalogConfirmedState {
  IntentionCatalogLoaded({
    required super.selection,
    required super.query,
    required List<IntentionSummary> items,
    required super.totalCount,
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

final class IntentionCatalogContinuationValidation
    extends IntentionCatalogContinuationState {
  const IntentionCatalogContinuationValidation();
}

final class IntentionCatalogContinuationRecovering
    extends IntentionCatalogContinuationState {
  const IntentionCatalogContinuationRecovering();
}

final class IntentionCatalogRecoveryUnavailable
    extends IntentionCatalogContinuationState {
  const IntentionCatalogRecoveryUnavailable();
}

final class IntentionCatalogRecoveryCorruption
    extends IntentionCatalogContinuationState {
  const IntentionCatalogRecoveryCorruption();
}

final class IntentionCatalogRecoveryUnexpected
    extends IntentionCatalogContinuationState {
  const IntentionCatalogRecoveryUnexpected();
}

final class IntentionCatalogEmpty extends IntentionCatalogConfirmedState {
  const IntentionCatalogEmpty({
    required super.selection,
    required super.query,
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
