import '../domain/long_term_relation.dart';

enum RelationCountsValidationFailure { negativeCount }

enum RelationCountGroup {
  activeNeedIncoming,
  activeNeedOutgoing,
  activeCanIncoming,
  activeCanOutgoing,
  archivedNeedIncoming,
  archivedNeedOutgoing,
  archivedCanIncoming,
  archivedCanOutgoing,
}

final class RelationCountsValidationException implements Exception {
  const RelationCountsValidationException({
    required this.failure,
    required this.group,
  });

  final RelationCountsValidationFailure failure;
  final RelationCountGroup group;
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
      RelationCountGroup.activeNeedIncoming,
    ),
    activeNeedOutgoing: _requireNonNegative(
      activeNeedOutgoing,
      RelationCountGroup.activeNeedOutgoing,
    ),
    activeCanIncoming: _requireNonNegative(
      activeCanIncoming,
      RelationCountGroup.activeCanIncoming,
    ),
    activeCanOutgoing: _requireNonNegative(
      activeCanOutgoing,
      RelationCountGroup.activeCanOutgoing,
    ),
    archivedNeedIncoming: _requireNonNegative(
      archivedNeedIncoming,
      RelationCountGroup.archivedNeedIncoming,
    ),
    archivedNeedOutgoing: _requireNonNegative(
      archivedNeedOutgoing,
      RelationCountGroup.archivedNeedOutgoing,
    ),
    archivedCanIncoming: _requireNonNegative(
      archivedCanIncoming,
      RelationCountGroup.archivedCanIncoming,
    ),
    archivedCanOutgoing: _requireNonNegative(
      archivedCanOutgoing,
      RelationCountGroup.archivedCanOutgoing,
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

  static int _requireNonNegative(int value, RelationCountGroup group) {
    if (value < 0) {
      throw RelationCountsValidationException(
        failure: RelationCountsValidationFailure.negativeCount,
        group: group,
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
