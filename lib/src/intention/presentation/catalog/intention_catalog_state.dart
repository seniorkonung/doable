import '../../application/intention_repository.dart';

sealed class IntentionCatalogState {
  const IntentionCatalogState({required this.query});

  final IntentionCatalogQuery query;
}

sealed class IntentionCatalogConfirmedState extends IntentionCatalogState {
  const IntentionCatalogConfirmedState({
    required super.query,
    required this.totalCount,
    required this.nextCursor,
    required this.revision,
  });

  final int totalCount;
  final IntentionCatalogCursor? nextCursor;
  final IntentionCatalogRevision revision;
}

final class IntentionCatalogLoaded extends IntentionCatalogConfirmedState {
  IntentionCatalogLoaded({
    required super.query,
    required List<IntentionSummary> items,
    required super.totalCount,
    required super.nextCursor,
    required super.revision,
  }) : items = List.unmodifiable(items);

  final List<IntentionSummary> items;
}

final class IntentionCatalogEmpty extends IntentionCatalogConfirmedState {
  const IntentionCatalogEmpty({required super.query, required super.revision})
    : super(totalCount: 0, nextCursor: null);

  IntentionScope get scope => query.scope;
}

final class IntentionCatalogUnavailable extends IntentionCatalogState {
  const IntentionCatalogUnavailable({required super.query});
}

final class IntentionCatalogCorruption extends IntentionCatalogState {
  const IntentionCatalogCorruption({required super.query});
}

final class IntentionCatalogUnexpected extends IntentionCatalogState {
  const IntentionCatalogUnexpected({required super.query});
}
