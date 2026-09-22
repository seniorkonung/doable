import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
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
  late GraphCommandCoordinator _coordinator;
  late _RelationObservationGeneration _generation;
  late StreamSubscription<GraphCommandCompletion> _completionSubscription;
  ProviderSubscription<AsyncValue<LongTermRelationReadResult>>?
  _observationSubscription;
  GraphRevision? _acceptedRevision;
  var _isTerminated = false;

  @override
  RelationDetailsState build(LongTermRelationId relationId) {
    _relationId = relationId;
    _generation = _RelationObservationGeneration.initial;
    _acceptedRevision = null;
    _isTerminated = false;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _completionSubscription = _coordinator.completions.listen(
      _handleCompletion,
    );
    ref.onDispose(() {
      _observationSubscription?.close();
      unawaited(_completionSubscription.cancel());
    });
    return _stateFromObservation(_startObservation());
  }

  /// Повторяет чтение после устранимого отказа.
  void retry() {
    if (!state.canRetry) {
      return;
    }
    _generation = _generation.next();
    final current = state;
    if (current is RelationDetailsLoaded) {
      state = current.copyWith(
        isOperationRunning: _isOperationRunning,
        refreshStatus: const RelationDetailsRefreshing(),
      );
      _startObservation();
      return;
    }
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
    if (!ref.mounted || _isTerminated || generation != _generation) {
      return;
    }
    if (observation case AsyncData(value: GraphResultSuccess(:final value))) {
      if (!_acceptSnapshotRevision(value.revision)) {
        return;
      }
    }
    final current = state;
    state = _stateFromObservation(
      observation,
      previousLoaded: current is RelationDetailsLoaded ? current : null,
    );
  }

  void _handleCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted || _isTerminated) {
      return;
    }
    if (completion
        case LongTermRelationCommandCompletion(
          target: ExistingLongTermRelationOperationTarget(:final relationId),
        )
        when relationId == _relationId) {
      _scheduleGateRefresh();
      if (completion.confirmedResult case GraphResultSuccess(:final value)) {
        if (!_advanceRevisionBarrier(value.revision)) {
          return;
        }
        _generation = _generation.next();
        final current = state;
        state = switch (current) {
          RelationDetailsLoaded() => current.copyWith(
            isOperationRunning: _isOperationRunning,
            refreshStatus: const RelationDetailsRefreshing(),
          ),
          _ => RelationDetailsLoading(isOperationRunning: _isOperationRunning),
        };
        _startObservation();
      }
    }
  }

  bool _advanceRevisionBarrier(GraphRevision revision) {
    final accepted = _acceptedRevision;
    if (accepted != null) {
      final order = revision.compareTo(accepted);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return false;
      }
    }
    // Завершение задаёт только барьер: поля связи и участников по-прежнему
    // публикуются исключительно полным снимком watchRelation.
    _acceptedRevision = revision;
    return true;
  }

  void _scheduleGateRefresh() {
    unawaited(
      Future<void>.microtask(() {}).then((_) {
        if (!ref.mounted || _isTerminated) {
          return;
        }
        final isRunning = _isOperationRunning;
        if (state.isOperationRunning != isRunning) {
          state = _withOperationRunning(state, isRunning);
        }
      }),
    );
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
    AsyncValue<LongTermRelationReadResult> observation, {
    RelationDetailsLoaded? previousLoaded,
  }) => switch (observation) {
    AsyncData(:final value) => _stateFromResult(
      value,
      previousLoaded: previousLoaded,
    ),
    AsyncError() when previousLoaded != null => previousLoaded.copyWith(
      isOperationRunning: _isOperationRunning,
      refreshStatus: const RelationDetailsRefreshUnexpected(),
    ),
    AsyncError() => RelationDetailsUnexpected(
      isOperationRunning: _isOperationRunning,
    ),
    AsyncValue<LongTermRelationReadResult>() when previousLoaded != null =>
      previousLoaded.copyWith(
        isOperationRunning: _isOperationRunning,
        refreshStatus: const RelationDetailsRefreshing(),
      ),
    AsyncValue<LongTermRelationReadResult>() => RelationDetailsLoading(
      isOperationRunning: _isOperationRunning,
    ),
  };

  RelationDetailsState _stateFromResult(
    LongTermRelationReadResult result, {
    RelationDetailsLoaded? previousLoaded,
  }) => switch (result) {
    GraphResultSuccess(value: GraphSnapshot(value: final details?)) =>
      RelationDetailsLoaded(
        details: details,
        isOperationRunning: _isOperationRunning,
      ),
    GraphResultSuccess() => _terminateAsNotFound(),
    GraphResultFailure(failure: LongTermRelationReadUnavailableFailure()) =>
      previousLoaded?.copyWith(
            isOperationRunning: _isOperationRunning,
            refreshStatus: const RelationDetailsRefreshUnavailable(),
          ) ??
          RelationDetailsUnavailable(isOperationRunning: _isOperationRunning),
    GraphResultFailure(failure: LongTermRelationReadCorruptionFailure()) =>
      previousLoaded?.copyWith(
            isOperationRunning: _isOperationRunning,
            refreshStatus: const RelationDetailsRefreshCorruption(),
          ) ??
          RelationDetailsCorruption(isOperationRunning: _isOperationRunning),
    GraphResultFailure(failure: LongTermRelationReadUnexpectedFailure()) =>
      previousLoaded?.copyWith(
            isOperationRunning: _isOperationRunning,
            refreshStatus: const RelationDetailsRefreshUnexpected(),
          ) ??
          RelationDetailsUnexpected(isOperationRunning: _isOperationRunning),
  };

  RelationDetailsNotFound _terminateAsNotFound() {
    _isTerminated = true;
    _observationSubscription?.close();
    _observationSubscription = null;
    unawaited(_completionSubscription.cancel());
    return RelationDetailsNotFound(isOperationRunning: _isOperationRunning);
  }

  bool get _isOperationRunning => _coordinator.isRelationRunning(_relationId);

  RelationDetailsState _withOperationRunning(
    RelationDetailsState current,
    bool isOperationRunning,
  ) => switch (current) {
    RelationDetailsLoading() => RelationDetailsLoading(
      isOperationRunning: isOperationRunning,
    ),
    RelationDetailsLoaded() => current.copyWith(
      isOperationRunning: isOperationRunning,
    ),
    RelationDetailsNotFound() => current,
    RelationDetailsUnavailable() => RelationDetailsUnavailable(
      isOperationRunning: isOperationRunning,
    ),
    RelationDetailsCorruption() => RelationDetailsCorruption(
      isOperationRunning: isOperationRunning,
    ),
    RelationDetailsUnexpected() => RelationDetailsUnexpected(
      isOperationRunning: isOperationRunning,
    ),
  };
}
