import '../domain/long_term_relation.dart';

enum RelationCountsValidationFailure { negativeCount }

final class RelationCountsValidationException implements Exception {
  const RelationCountsValidationException({
    required this.failure,
    required this.scope,
    required this.type,
    required this.direction,
  });

  final RelationCountsValidationFailure failure;
  final RelationScope scope;
  final LongTermRelationType type;
  final RelationDirection direction;
}

final class RelationCounts {
  factory RelationCounts({
    required int activeNeedIncoming,
    required int activeNeedOutgoing,
    required int activeCanIncoming,
    required int activeCanOutgoing,
    required int archivedNeedIncoming,
    required int archivedNeedOutgoing,
    required int archivedCanIncoming,
    required int archivedCanOutgoing,
  }) => RelationCounts._(
    activeNeedIncoming: _requireNonNegative(
      activeNeedIncoming,
      scope: RelationScope.active,
      type: LongTermRelationType.need,
      direction: RelationDirection.incoming,
    ),
    activeNeedOutgoing: _requireNonNegative(
      activeNeedOutgoing,
      scope: RelationScope.active,
      type: LongTermRelationType.need,
      direction: RelationDirection.outgoing,
    ),
    activeCanIncoming: _requireNonNegative(
      activeCanIncoming,
      scope: RelationScope.active,
      type: LongTermRelationType.can,
      direction: RelationDirection.incoming,
    ),
    activeCanOutgoing: _requireNonNegative(
      activeCanOutgoing,
      scope: RelationScope.active,
      type: LongTermRelationType.can,
      direction: RelationDirection.outgoing,
    ),
    archivedNeedIncoming: _requireNonNegative(
      archivedNeedIncoming,
      scope: RelationScope.archived,
      type: LongTermRelationType.need,
      direction: RelationDirection.incoming,
    ),
    archivedNeedOutgoing: _requireNonNegative(
      archivedNeedOutgoing,
      scope: RelationScope.archived,
      type: LongTermRelationType.need,
      direction: RelationDirection.outgoing,
    ),
    archivedCanIncoming: _requireNonNegative(
      archivedCanIncoming,
      scope: RelationScope.archived,
      type: LongTermRelationType.can,
      direction: RelationDirection.incoming,
    ),
    archivedCanOutgoing: _requireNonNegative(
      archivedCanOutgoing,
      scope: RelationScope.archived,
      type: LongTermRelationType.can,
      direction: RelationDirection.outgoing,
    ),
  );

  const RelationCounts._({
    required this.activeNeedIncoming,
    required this.activeNeedOutgoing,
    required this.activeCanIncoming,
    required this.activeCanOutgoing,
    required this.archivedNeedIncoming,
    required this.archivedNeedOutgoing,
    required this.archivedCanIncoming,
    required this.archivedCanOutgoing,
  });

  final int activeNeedIncoming;
  final int activeNeedOutgoing;
  final int activeCanIncoming;
  final int activeCanOutgoing;
  final int archivedNeedIncoming;
  final int archivedNeedOutgoing;
  final int archivedCanIncoming;
  final int archivedCanOutgoing;

  int get activeNeed =>
      _forType(scope: RelationScope.active, type: LongTermRelationType.need);

  int get activeCan =>
      _forType(scope: RelationScope.active, type: LongTermRelationType.can);

  int get archivedNeed =>
      _forType(scope: RelationScope.archived, type: LongTermRelationType.need);

  int get archivedCan =>
      _forType(scope: RelationScope.archived, type: LongTermRelationType.can);

  int get active => activeNeed + activeCan;

  int get archived => archivedNeed + archivedCan;

  int get total => active + archived;

  int forGroup({
    required RelationScope scope,
    required LongTermRelationType type,
    required RelationDirection direction,
  }) => switch ((scope, type, direction)) {
    (
      RelationScope.active,
      LongTermRelationType.need,
      RelationDirection.incoming,
    ) =>
      activeNeedIncoming,
    (
      RelationScope.active,
      LongTermRelationType.need,
      RelationDirection.outgoing,
    ) =>
      activeNeedOutgoing,
    (
      RelationScope.active,
      LongTermRelationType.can,
      RelationDirection.incoming,
    ) =>
      activeCanIncoming,
    (
      RelationScope.active,
      LongTermRelationType.can,
      RelationDirection.outgoing,
    ) =>
      activeCanOutgoing,
    (
      RelationScope.archived,
      LongTermRelationType.need,
      RelationDirection.incoming,
    ) =>
      archivedNeedIncoming,
    (
      RelationScope.archived,
      LongTermRelationType.need,
      RelationDirection.outgoing,
    ) =>
      archivedNeedOutgoing,
    (
      RelationScope.archived,
      LongTermRelationType.can,
      RelationDirection.incoming,
    ) =>
      archivedCanIncoming,
    (
      RelationScope.archived,
      LongTermRelationType.can,
      RelationDirection.outgoing,
    ) =>
      archivedCanOutgoing,
  };

  int _forType({
    required RelationScope scope,
    required LongTermRelationType type,
  }) =>
      forGroup(
        scope: scope,
        type: type,
        direction: RelationDirection.incoming,
      ) +
      forGroup(scope: scope, type: type, direction: RelationDirection.outgoing);

  static int _requireNonNegative(
    int value, {
    required RelationScope scope,
    required LongTermRelationType type,
    required RelationDirection direction,
  }) {
    if (value < 0) {
      throw RelationCountsValidationException(
        failure: RelationCountsValidationFailure.negativeCount,
        scope: scope,
        type: type,
        direction: direction,
      );
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is RelationCounts &&
      other.activeNeedIncoming == activeNeedIncoming &&
      other.activeNeedOutgoing == activeNeedOutgoing &&
      other.activeCanIncoming == activeCanIncoming &&
      other.activeCanOutgoing == activeCanOutgoing &&
      other.archivedNeedIncoming == archivedNeedIncoming &&
      other.archivedNeedOutgoing == archivedNeedOutgoing &&
      other.archivedCanIncoming == archivedCanIncoming &&
      other.archivedCanOutgoing == archivedCanOutgoing;

  @override
  int get hashCode => Object.hash(
    activeNeedIncoming,
    activeNeedOutgoing,
    activeCanIncoming,
    activeCanOutgoing,
    archivedNeedIncoming,
    archivedNeedOutgoing,
    archivedCanIncoming,
    archivedCanOutgoing,
  );
}

sealed class RelationCountsState {
  const RelationCountsState();
}

final class UnknownRelationCounts extends RelationCountsState {
  const UnknownRelationCounts();
}

final class ConfirmedRelationCounts extends RelationCountsState {
  const ConfirmedRelationCounts(this.counts);

  final RelationCounts counts;
}
