import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation_id.dart';
import 'relation_details_state.dart';

part 'relation_details_view_model.g.dart';

/// Поколение наблюдения: повтор делает ответы прежнего чтения непригодными.
final class _RelationObservationGeneration {
  const _RelationObservationGeneration(this.value);

  static const initial = _RelationObservationGeneration(0);

  final int value;

  _RelationObservationGeneration next() =>
      _RelationObservationGeneration(value + 1);

  @override
  bool operator ==(Object other) =>
      other is _RelationObservationGeneration && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

@riverpod
Stream<LongTermRelationReadResult> _relationDetailsObservation(
  Ref ref,
  LongTermRelationId relationId,
  _RelationObservationGeneration generation,
) => ref.watch(personalGraphRepositoryProvider).watchRelation(relationId);

/// Подробные данные одной связи с актуальными участниками.
///
/// Наблюдение перечитывает зависимости самостоятельно, поэтому просмотр не
/// подписывается на весь граф. Запоздалый ответ более старой ревизии или
/// прежнего поколения не отменяет подтверждённые данные.
@riverpod
final class RelationDetailsViewModel extends _$RelationDetailsViewModel {
  late LongTermRelationId _relationId;
  late _RelationObservationGeneration _generation;
  ProviderSubscription<AsyncValue<LongTermRelationReadResult>>?
  _observationSubscription;
  GraphRevision? _acceptedRevision;

  @override
  RelationDetailsState build(LongTermRelationId relationId) {
    _relationId = relationId;
    _generation = _RelationObservationGeneration.initial;
    _acceptedRevision = null;
    ref.onDispose(() {
      _observationSubscription?.close();
    });
    return _stateFromObservation(_startObservation());
  }

  /// Повторяет чтение после устранимого отказа.
  void retry() {
    if (!state.canRetry) {
      return;
    }
    _generation = _generation.next();
    state = _stateFromObservation(_startObservation());
  }

  AsyncValue<LongTermRelationReadResult> _startObservation() {
    _observationSubscription?.close();
    final generation = _generation;
    final subscription = ref.listen(
      _relationDetailsObservationProvider(_relationId, generation),
      (previous, next) => _handleObservation(generation, next),
    );
    _observationSubscription = subscription;
    return subscription.read();
  }

  void _handleObservation(
    _RelationObservationGeneration generation,
    AsyncValue<LongTermRelationReadResult> observation,
  ) {
    if (!ref.mounted || generation != _generation) {
      return;
    }
    if (observation case AsyncData(value: GraphResultSuccess(:final value))) {
      if (!_acceptSnapshotRevision(value.revision)) {
        return;
      }
    }
    state = _stateFromObservation(observation);
  }

  bool _acceptSnapshotRevision(GraphRevision revision) {
    final accepted = _acceptedRevision;
    if (accepted != null &&
        revision.compareTo(accepted) == GraphRevisionOrder.older) {
      return false;
    }
    _acceptedRevision = revision;
    return true;
  }

  RelationDetailsState _stateFromObservation(
    AsyncValue<LongTermRelationReadResult> observation,
  ) => switch (observation) {
    AsyncData(:final value) => _stateFromResult(value),
    AsyncError() => const RelationDetailsUnexpected(),
    AsyncValue<LongTermRelationReadResult>() => const RelationDetailsLoading(),
  };

  RelationDetailsState _stateFromResult(LongTermRelationReadResult result) =>
      switch (result) {
        GraphResultSuccess(value: GraphSnapshot(value: final details?)) =>
          RelationDetailsLoaded(details),
        GraphResultSuccess() => const RelationDetailsNotFound(),
        GraphResultFailure(failure: LongTermRelationReadUnavailableFailure()) =>
          const RelationDetailsUnavailable(),
        GraphResultFailure(failure: LongTermRelationReadCorruptionFailure()) =>
          const RelationDetailsCorruption(),
        GraphResultFailure(failure: LongTermRelationReadUnexpectedFailure()) =>
          const RelationDetailsUnexpected(),
      };
}
