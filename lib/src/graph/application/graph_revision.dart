enum GraphRevisionOrder { older, same, newer, differentEpoch }

abstract interface class GraphRevision {
  GraphRevisionOrder compareTo(GraphRevision other);
}

final class GraphSnapshot<T> {
  const GraphSnapshot({required this.value, required this.revision});

  final T value;
  final GraphRevision revision;
}

abstract interface class GraphChange {
  GraphRevision get revision;
}

abstract interface class GraphCommandOutcome {
  Iterable<GraphChange> get changes;
}

enum ConfirmedGraphResultValidationFailure { emptyChanges, revisionMismatch }

final class ConfirmedGraphResultValidationException implements Exception {
  const ConfirmedGraphResultValidationException(this.failure);

  final ConfirmedGraphResultValidationFailure failure;
}

final class ConfirmedGraphResult<T extends GraphCommandOutcome> {
  factory ConfirmedGraphResult({
    required GraphRevision revision,
    required T value,
  }) {
    final immutableChanges = List<GraphChange>.unmodifiable(value.changes);
    if (immutableChanges.isEmpty) {
      throw const ConfirmedGraphResultValidationException(
        ConfirmedGraphResultValidationFailure.emptyChanges,
      );
    }
    final hasMismatchedRevision = immutableChanges.any(
      (change) =>
          revision.compareTo(change.revision) != GraphRevisionOrder.same,
    );
    if (hasMismatchedRevision) {
      throw const ConfirmedGraphResultValidationException(
        ConfirmedGraphResultValidationFailure.revisionMismatch,
      );
    }
    return ConfirmedGraphResult._(
      revision: revision,
      value: value,
      changes: immutableChanges,
    );
  }

  const ConfirmedGraphResult._({
    required this.revision,
    required this.value,
    required this.changes,
  });

  final GraphRevision revision;
  final T value;
  final List<GraphChange> changes;
}
