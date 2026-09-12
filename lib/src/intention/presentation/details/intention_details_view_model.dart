import 'package:riverpod_annotation/riverpod_annotation.dart';

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
final class _DetailObservationGenerationController
    extends _$DetailObservationGenerationController {
  @override
  _DetailObservationGeneration build(IntentionId intentionId) =>
      _DetailObservationGeneration.initial;

  void advance() {
    state = state.next();
  }
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

  @override
  IntentionDetailsState build(IntentionId intentionId) {
    _intentionId = intentionId;
    final generation = ref.watch(
      _detailObservationGenerationControllerProvider(intentionId),
    );
    final observation = ref.watch(
      _intentionDetailsObservationProvider(intentionId, generation),
    );
    final isOperationRunning = ref
        .watch(intentionCommandCoordinatorProvider.notifier)
        .isRunning(intentionId);
    return observation.when(
      data: (result) => _stateFromResult(result, isOperationRunning),
      error: (_, _) =>
          IntentionDetailsUnexpected(isOperationRunning: isOperationRunning),
      loading: () =>
          IntentionDetailsLoading(isOperationRunning: isOperationRunning),
    );
  }

  void retry() {
    if (state is! IntentionDetailsUnavailable) {
      return;
    }
    ref
        .read(
          _detailObservationGenerationControllerProvider(_intentionId).notifier,
        )
        .advance();
  }

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
