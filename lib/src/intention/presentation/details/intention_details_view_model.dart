import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../application/intention_repository.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
import '../operation/intention_command_coordinator.dart';
import '../operation/intention_repository_provider.dart';
import 'intention_details_state.dart';

part 'intention_details_view_model.g.dart';

final class _DetailObservationGeneration {
  const _DetailObservationGeneration(this.value);

  static const initial = _DetailObservationGeneration(0);

  final int value;

  _DetailObservationGeneration next() =>
      _DetailObservationGeneration(value + 1);

  @override
  bool operator ==(Object other) =>
      other is _DetailObservationGeneration && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

@riverpod
Stream<Result<Intention?>> _intentionDetailsObservation(
  Ref ref,
  IntentionId intentionId,
  _DetailObservationGeneration generation,
) => ref.watch(intentionRepositoryProvider).watchById(intentionId);

@riverpod
final class IntentionDetailsViewModel extends _$IntentionDetailsViewModel {
  late IntentionId _intentionId;
  late IntentionCommandCoordinator _coordinator;
  late _DetailObservationGeneration _generation;
  late StreamSubscription<IntentionCommandCompletion> _completionSubscription;
  ProviderSubscription<AsyncValue<Result<Intention?>>>?
  _observationSubscription;
  var _preserveAuthoritativeStateWhileLoading = false;
  var _isDeleted = false;

  @override
  IntentionDetailsState build(IntentionId intentionId) {
    _intentionId = intentionId;
    _generation = _DetailObservationGeneration.initial;
    _coordinator = ref.watch(intentionCommandCoordinatorProvider.notifier);
    _completionSubscription = _coordinator.completions.listen(
      _handleCompletion,
    );
    ref.onDispose(() {
      _observationSubscription?.close();
      unawaited(_completionSubscription.cancel());
    });

    final initialObservation = _startObservation();
    return _stateFromObservation(initialObservation);
  }

  void retry() {
    if (state is! IntentionDetailsUnavailable) {
      return;
    }
    _advanceGeneration();
    _preserveAuthoritativeStateWhileLoading = false;
    state = _stateFromObservation(_startObservation());
  }

  AsyncValue<Result<Intention?>> _startObservation() {
    _observationSubscription?.close();
    final generation = _generation;
    final subscription = ref.listen(
      _intentionDetailsObservationProvider(_intentionId, generation),
      (previous, next) => _handleObservation(generation, next),
    );
    _observationSubscription = subscription;
    return subscription.read();
  }

  void _handleObservation(
    _DetailObservationGeneration generation,
    AsyncValue<Result<Intention?>> observation,
  ) {
    if (!ref.mounted || _isDeleted || generation != _generation) {
      return;
    }
    if (observation is AsyncLoading<Result<Intention?>> &&
        _preserveAuthoritativeStateWhileLoading) {
      return;
    }
    if (observation is! AsyncLoading<Result<Intention?>>) {
      _preserveAuthoritativeStateWhileLoading = false;
    }
    state = _stateFromObservation(observation);
  }

  void _handleCompletion(IntentionCommandCompletion completion) {
    if (!ref.mounted || _isDeleted) {
      return;
    }
    switch (completion.result) {
      case ResultSuccess(value: IntentionSaved(:final intention))
          when intention.id == _intentionId:
        _advanceGeneration();
        _preserveAuthoritativeStateWhileLoading = true;
        state = IntentionDetailsLoaded(
          intention: intention,
          isOperationRunning: _isOperationRunning,
        );
        _startObservation();
      case ResultSuccess(value: IntentionDeleted(:final id))
          when id == _intentionId:
        _advanceGeneration();
        _isDeleted = true;
        _observationSubscription?.close();
        _observationSubscription = null;
        state = const IntentionDetailsDeleted();
      case ResultSuccess() || ResultFailure():
        return;
    }
  }

  void _advanceGeneration() {
    _generation = _generation.next();
  }

  bool get _isOperationRunning => _coordinator.isRunning(_intentionId);

  IntentionDetailsState _stateFromObservation(
    AsyncValue<Result<Intention?>> observation,
  ) => observation.when(
    data: (result) => _stateFromResult(result, _isOperationRunning),
    error: (_, _) =>
        IntentionDetailsUnexpected(isOperationRunning: _isOperationRunning),
    loading: () =>
        IntentionDetailsLoading(isOperationRunning: _isOperationRunning),
  );

  IntentionDetailsState _stateFromResult(
    Result<Intention?> result,
    bool isOperationRunning,
  ) => switch (result) {
    ResultSuccess(value: final Intention intention) => IntentionDetailsLoaded(
      intention: intention,
      isOperationRunning: isOperationRunning,
    ),
    ResultSuccess(value: null) => IntentionDetailsNotFound(
      isOperationRunning: isOperationRunning,
    ),
    ResultFailure(failure: IntentionUnavailableFailure()) =>
      IntentionDetailsUnavailable(isOperationRunning: isOperationRunning),
    ResultFailure(failure: IntentionCorruptionFailure()) =>
      IntentionDetailsCorruption(isOperationRunning: isOperationRunning),
    ResultFailure(
      failure: IntentionValidationFailure() ||
          IntentionNotFoundFailure() ||
          IntentionConflictFailure() ||
          IntentionUnexpectedFailure(),
    ) =>
      IntentionDetailsUnexpected(isOperationRunning: isOperationRunning),
  };
}
