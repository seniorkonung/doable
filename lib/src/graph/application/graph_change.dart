import '../../action/domain/action.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/relation_counts.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import 'graph_revision.dart';

/// Изменение действия одной ревизии графа с состоянием до и после, по
/// которому потребители находят затронутые даты и намерения пути.
sealed class ActionChange implements GraphChange {
  const ActionChange();

  Action? get before;
  Action? get after;
}

final class ActionCreatedChange extends ActionChange {
  const ActionCreatedChange({required this.revision, required this.action});
  @override
  final GraphRevision revision;
  final Action action;
  @override
  Action? get before => null;
  @override
  Action get after => action;
}

/// Поля действия подтверждённо записаны. При операции без изменений состояния
/// до и после совпадают, а ревизия остаётся прежней.
final class ActionUpdatedChange extends ActionChange {
  const ActionUpdatedChange({
    required this.revision,
    required this.before,
    required this.after,
  });

  @override
  final GraphRevision revision;

  @override
  final Action before;

  @override
  final Action after;
}

final class ActionDeletedChange extends ActionChange {
  const ActionDeletedChange({required this.revision, required this.action});

  @override
  final GraphRevision revision;

  /// Состояние действия перед удалением.
  final Action action;

  @override
  Action get before => action;

  @override
  Action? get after => null;
}

final class IntentionRelationCountsChanged implements GraphChange {
  const IntentionRelationCountsChanged({
    required this.revision,
    required this.intentionId,
    required this.counts,
  });

  @override
  final GraphRevision revision;
  final IntentionId intentionId;
  final RelationCounts counts;
}

/// Изменение «граф заменён»: весь граф заменён одной транзакцией (ADR-0036).
///
/// Его ревизия — первая ревизия новой эпохи: ревизии прежней эпохи
/// сравниваются с ней как [GraphRevisionOrder.differentEpoch].
final class GraphReplaced implements GraphChange {
  const GraphReplaced({required this.revision});

  @override
  final GraphRevision revision;
}

/// Результат подтверждённой замены графа: пакет ревизии новой эпохи из
/// единственного изменения [GraphReplaced].
final class ConfirmedGraphReplacement implements ConfirmedGraphChangePackage {
  ConfirmedGraphReplacement(this.revision)
    : changes = List.unmodifiable([GraphReplaced(revision: revision)]);

  @override
  final GraphRevision revision;
  @override
  final List<GraphChange> changes;
}

sealed class LongTermRelationChange implements GraphChange {
  const LongTermRelationChange();

  LongTermRelationId get id;
  LongTermRelation? get before;
  LongTermRelation? get after;
}

final class LongTermRelationCreatedChange extends LongTermRelationChange {
  const LongTermRelationCreatedChange({
    required this.revision,
    required this.relation,
  });

  @override
  final GraphRevision revision;
  final LongTermRelation relation;

  @override
  LongTermRelationId get id => relation.id;

  @override
  LongTermRelation? get before => null;

  @override
  LongTermRelation get after => relation;
}

enum LongTermRelationChangeValidationFailure { identityMismatch }

final class LongTermRelationChangeValidationException implements Exception {
  const LongTermRelationChangeValidationException(this.failure);

  final LongTermRelationChangeValidationFailure failure;
}

final class LongTermRelationUpdatedChange extends LongTermRelationChange {
  factory LongTermRelationUpdatedChange({
    required GraphRevision revision,
    required LongTermRelation before,
    required LongTermRelation after,
  }) {
    if (before.id != after.id) {
      throw const LongTermRelationChangeValidationException(
        LongTermRelationChangeValidationFailure.identityMismatch,
      );
    }
    return LongTermRelationUpdatedChange._(
      revision: revision,
      before: before,
      after: after,
    );
  }

  const LongTermRelationUpdatedChange._({
    required this.revision,
    required this.before,
    required this.after,
  });

  @override
  final GraphRevision revision;

  @override
  final LongTermRelation before;

  @override
  final LongTermRelation after;

  @override
  LongTermRelationId get id => after.id;
}

final class LongTermRelationUnchangedChange extends LongTermRelationChange {
  const LongTermRelationUnchangedChange({
    required this.revision,
    required this.relation,
  });

  @override
  final GraphRevision revision;

  final LongTermRelation relation;

  @override
  LongTermRelationId get id => relation.id;

  @override
  LongTermRelation get before => relation;

  @override
  LongTermRelation get after => relation;
}

final class LongTermRelationDeletedChange extends LongTermRelationChange {
  const LongTermRelationDeletedChange({
    required this.revision,
    required this.relation,
  });

  @override
  final GraphRevision revision;
  final LongTermRelation relation;

  @override
  LongTermRelationId get id => relation.id;

  @override
  LongTermRelation get before => relation;

  @override
  LongTermRelation? get after => null;
}
