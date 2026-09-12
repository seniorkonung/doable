import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../application/intention_command.dart';
import '../../application/intention_repository.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
import '../operation/intention_command_coordinator.dart';
import '../operation/intention_repository_provider.dart';
import '../operation/operation_state.dart';
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
  IntentionOperationToken? _activeToken;
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
      final token = _activeToken;
      if (token != null) {
        _coordinator.releaseInitiatorPresentation(token);
      }
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

  void beginEditing() {
    final current = state;
    if (current is! IntentionDetailsLoaded ||
        current.edit != null ||
        _isOperationRunning) {
      return;
    }
    state = current.copyWith(
      edit: IntentionDetailsEdit.fromIntention(current.intention),
      clearStateChange: true,
      clearEvent: true,
    );
  }

  void cancelEditing() {
    final current = state;
    if (current is! IntentionDetailsLoaded ||
        current.edit == null ||
        _isOperationRunning) {
      return;
    }
    state = current.copyWith(clearEdit: true, clearEvent: true);
  }

  void changeTitle(String value) {
    final current = state;
    final edit = current is IntentionDetailsLoaded ? current.edit : null;
    if (current is! IntentionDetailsLoaded ||
        edit == null ||
        edit.title == value ||
        _isOperationRunning) {
      return;
    }
    state = current.copyWith(edit: edit.withTitle(value), clearEvent: true);
  }

  void changeDescription(String value) {
    final current = state;
    final edit = current is IntentionDetailsLoaded ? current.edit : null;
    if (current is! IntentionDetailsLoaded ||
        edit == null ||
        edit.description == value ||
        _isOperationRunning) {
      return;
    }
    state = current.copyWith(
      edit: edit.withDescription(value),
      clearEvent: true,
    );
  }

  void saveChanges() {
    final current = state;
    final edit = current is IntentionDetailsLoaded ? current.edit : null;
    if (current is! IntentionDetailsLoaded ||
        edit == null ||
        !edit.canSubmit ||
        _isOperationRunning) {
      return;
    }

    final description = edit.description;
    final start = _coordinator.accept(
      UpdateIntention(
        id: _intentionId,
        title: edit.title,
        description: description.isEmpty ? null : description,
      ),
    );
    switch (start) {
      case IntentionCommandAccepted(:final token, :final future):
        _activeToken = token;
        state = current.copyWith(
          isOperationRunning: true,
          edit: edit.withOperation(const OperationRunning<Intention>()),
          clearEvent: true,
        );
        unawaited(_finishUpdate(future));
      case IntentionCommandAlreadyRunning():
        state = current.copyWith(isOperationRunning: true);
      case IntentionCommandCoordinatorDraining():
        state = current.copyWith(
          edit: edit.withOperation(
            const OperationFailed<Intention>(IntentionUnexpectedFailure()),
          ),
          clearEvent: true,
        );
    }
  }

  void enableReadiness() =>
      _startStateChange(IntentionDetailsStateChangeKind.enableReadiness);

  void disableReadiness() =>
      _startStateChange(IntentionDetailsStateChangeKind.disableReadiness);

  void archive() => _startStateChange(IntentionDetailsStateChangeKind.archive);

  void restore() => _startStateChange(IntentionDetailsStateChangeKind.restore);

  void delete() => _startStateChange(IntentionDetailsStateChangeKind.delete);

  void retryStateChange() {
    final current = state;
    final stateChange = current is IntentionDetailsLoaded
        ? current.stateChange
        : null;
    if (stateChange == null || !stateChange.canRetry) {
      return;
    }
    _startStateChange(stateChange.kind);
  }

  void consumeEvent() {
    final current = state;
    if (current is IntentionDetailsLoaded && current.event != null) {
      state = current.copyWith(clearEvent: true);
    }
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
    final current = state;
    final loaded = current is IntentionDetailsLoaded ? current : null;
    final hasNoConfirmedIntention = switch (observation) {
      AsyncData(value: ResultSuccess(value: Intention())) => false,
      AsyncLoading<Result<Intention?>>() ||
      AsyncError<Result<Intention?>>() ||
      AsyncData<Result<Intention?>>() => true,
    };
    if (loaded?.edit != null && hasNoConfirmedIntention) {
      return;
    }
    state = _stateFromObservation(observation, previousLoaded: loaded);
  }

  void _handleCompletion(IntentionCommandCompletion completion) {
    if (!ref.mounted || _isDeleted) {
      return;
    }
    if (state.isOperationRunning) {
      _scheduleGateRefresh();
    }
    switch (completion.result) {
      case ResultSuccess(value: IntentionSaved(:final intention))
          when intention.id == _intentionId:
        _advanceGeneration();
        _preserveAuthoritativeStateWhileLoading = true;
        final current = state;
        final loaded = current is IntentionDetailsLoaded ? current : null;
        state = IntentionDetailsLoaded(
          intention: intention,
          isOperationRunning: _isOperationRunning,
          edit: loaded?.edit,
          stateChange: identical(_activeToken, completion.token)
              ? loaded?.stateChange
              : null,
          event: loaded?.event,
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

  Future<void> _finishUpdate(Future<IntentionCommandCompletion> future) async {
    try {
      final completion = await future;
      if (!ref.mounted || !identical(_activeToken, completion.token)) {
        return;
      }

      final claim = _coordinator.claimInitiator(completion.token);
      if (claim == null) {
        _activeToken = null;
        _failUpdateUnexpectedly();
        _scheduleGateRefresh();
        return;
      }
      _activeToken = null;
      try {
        final current = state;
        final edit = current is IntentionDetailsLoaded ? current.edit : null;
        if (current is IntentionDetailsLoaded && edit != null) {
          state = switch (completion.result) {
            ResultSuccess(value: IntentionSaved(:final intention))
                when intention.id == _intentionId =>
              current.copyWith(
                clearEdit: true,
                event: const IntentionDetailsSaved(),
              ),
            ResultSuccess(value: IntentionSaved() || IntentionDeleted()) =>
              current.copyWith(
                edit: edit.withOperation(
                  const OperationFailed<Intention>(
                    IntentionUnexpectedFailure(),
                  ),
                ),
                clearEvent: true,
              ),
            ResultFailure(:final failure) => current.copyWith(
              edit: edit.withOperation(OperationFailed<Intention>(failure)),
              clearEvent: true,
            ),
          };
        }
      } finally {
        _coordinator.confirmPresentation(claim);
        _scheduleGateRefresh();
      }
    } on Object {
      if (!ref.mounted) {
        return;
      }
      final token = _activeToken;
      _activeToken = null;
      if (token != null) {
        _coordinator.releaseInitiatorPresentation(token);
      }
      _failUpdateUnexpectedly();
      _scheduleGateRefresh();
    }
  }

  void _startStateChange(IntentionDetailsStateChangeKind kind) {
    final current = state;
    if (current is! IntentionDetailsLoaded ||
        current.edit != null ||
        _isOperationRunning ||
        !_isStateChangeApplicable(current.intention, kind)) {
      return;
    }

    final start = _coordinator.accept(_commandForStateChange(kind));
    switch (start) {
      case IntentionCommandAccepted(:final token, :final future):
        _activeToken = token;
        state = current.copyWith(
          isOperationRunning: true,
          stateChange: IntentionDetailsStateChange.running(kind),
          clearEvent: true,
        );
        unawaited(_finishStateChange(kind, future));
      case IntentionCommandAlreadyRunning():
        state = current.copyWith(isOperationRunning: true);
      case IntentionCommandCoordinatorDraining():
        state = current.copyWith(
          stateChange: IntentionDetailsStateChange.failed(
            kind,
            const IntentionUnexpectedFailure(),
          ),
          clearEvent: true,
        );
    }
  }

  Future<void> _finishStateChange(
    IntentionDetailsStateChangeKind kind,
    Future<IntentionCommandCompletion> future,
  ) async {
    try {
      final completion = await future;
      if (!ref.mounted || !identical(_activeToken, completion.token)) {
        return;
      }

      final claim = _coordinator.claimInitiator(completion.token);
      if (claim == null) {
        _activeToken = null;
        _failStateChangeUnexpectedly(kind);
        _scheduleGateRefresh();
        return;
      }
      _activeToken = null;
      try {
        final current = state;
        if (current is IntentionDetailsLoaded) {
          state = switch (completion.result) {
            ResultSuccess(value: IntentionSaved(:final intention))
                when intention.id == _intentionId &&
                    kind != IntentionDetailsStateChangeKind.delete =>
              current.copyWith(
                clearStateChange: true,
                event: _successEventFor(kind),
              ),
            ResultSuccess(value: IntentionSaved() || IntentionDeleted()) =>
              current.copyWith(
                stateChange: IntentionDetailsStateChange.failed(
                  kind,
                  const IntentionUnexpectedFailure(),
                ),
                clearEvent: true,
              ),
            ResultFailure(:final failure) => current.copyWith(
              stateChange: IntentionDetailsStateChange.failed(kind, failure),
              clearEvent: true,
            ),
          };
        }
      } finally {
        _coordinator.confirmPresentation(claim);
        _scheduleGateRefresh();
      }
    } on Object {
      if (!ref.mounted) {
        return;
      }
      final token = _activeToken;
      _activeToken = null;
      if (token != null) {
        _coordinator.releaseInitiatorPresentation(token);
      }
      _failStateChangeUnexpectedly(kind);
      _scheduleGateRefresh();
    }
  }

  IntentionCommand _commandForStateChange(
    IntentionDetailsStateChangeKind kind,
  ) => switch (kind) {
    IntentionDetailsStateChangeKind.enableReadiness => EnableIntentionReadiness(
      _intentionId,
    ),
    IntentionDetailsStateChangeKind.disableReadiness =>
      DisableIntentionReadiness(_intentionId),
    IntentionDetailsStateChangeKind.archive => ArchiveIntention(_intentionId),
    IntentionDetailsStateChangeKind.restore => RestoreIntention(_intentionId),
    IntentionDetailsStateChangeKind.delete => DeleteIntention(_intentionId),
  };

  bool _isStateChangeApplicable(
    Intention intention,
    IntentionDetailsStateChangeKind kind,
  ) => switch (kind) {
    IntentionDetailsStateChangeKind.enableReadiness =>
      intention.readiness == IntentionReadiness.notReady,
    IntentionDetailsStateChangeKind.disableReadiness =>
      intention.readiness == IntentionReadiness.ready,
    IntentionDetailsStateChangeKind.archive =>
      intention.archiveState == IntentionArchiveState.active,
    IntentionDetailsStateChangeKind.restore =>
      intention.archiveState == IntentionArchiveState.archived,
    IntentionDetailsStateChangeKind.delete => true,
  };

  IntentionDetailsEvent _successEventFor(
    IntentionDetailsStateChangeKind kind,
  ) => switch (kind) {
    IntentionDetailsStateChangeKind.enableReadiness =>
      const IntentionDetailsReadinessEnabled(),
    IntentionDetailsStateChangeKind.disableReadiness =>
      const IntentionDetailsReadinessDisabled(),
    IntentionDetailsStateChangeKind.archive => const IntentionDetailsArchived(),
    IntentionDetailsStateChangeKind.restore => const IntentionDetailsRestored(),
    IntentionDetailsStateChangeKind.delete => throw StateError(
      'Физическое удаление завершает подробный просмотр без success event.',
    ),
  };

  void _failUpdateUnexpectedly() {
    final current = state;
    final edit = current is IntentionDetailsLoaded ? current.edit : null;
    if (current is IntentionDetailsLoaded && edit != null) {
      state = current.copyWith(
        edit: edit.withOperation(
          const OperationFailed<Intention>(IntentionUnexpectedFailure()),
        ),
        clearEvent: true,
      );
    }
  }

  void _failStateChangeUnexpectedly(IntentionDetailsStateChangeKind kind) {
    final current = state;
    if (current is IntentionDetailsLoaded) {
      state = current.copyWith(
        stateChange: IntentionDetailsStateChange.failed(
          kind,
          const IntentionUnexpectedFailure(),
        ),
        clearEvent: true,
      );
    }
  }

  void _scheduleGateRefresh() {
    unawaited(
      Future<void>.microtask(() {}).then((_) {
        if (ref.mounted && !_isDeleted) {
          final isRunning = _isOperationRunning;
          if (state.isOperationRunning != isRunning) {
            state = _withOperationRunning(state, isRunning);
          }
        }
      }),
    );
  }

  void _advanceGeneration() {
    _generation = _generation.next();
  }

  bool get _isOperationRunning => _coordinator.isRunning(_intentionId);

  IntentionDetailsState _stateFromObservation(
    AsyncValue<Result<Intention?>> observation, {
    IntentionDetailsLoaded? previousLoaded,
  }) => observation.when(
    data: (result) => _stateFromResult(
      result,
      _isOperationRunning,
      previousLoaded: previousLoaded,
    ),
    error: (_, _) =>
        IntentionDetailsUnexpected(isOperationRunning: _isOperationRunning),
    loading: () =>
        IntentionDetailsLoading(isOperationRunning: _isOperationRunning),
  );

  IntentionDetailsState _stateFromResult(
    Result<Intention?> result,
    bool isOperationRunning, {
    IntentionDetailsLoaded? previousLoaded,
  }) => switch (result) {
    ResultSuccess(value: final Intention intention) => IntentionDetailsLoaded(
      intention: intention,
      isOperationRunning: isOperationRunning,
      edit: previousLoaded?.edit,
      stateChange: previousLoaded?.stateChange,
      event: previousLoaded?.event,
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

  IntentionDetailsState _withOperationRunning(
    IntentionDetailsState current,
    bool isOperationRunning,
  ) => switch (current) {
    IntentionDetailsLoading() => IntentionDetailsLoading(
      isOperationRunning: isOperationRunning,
    ),
    IntentionDetailsLoaded() => current.copyWith(
      isOperationRunning: isOperationRunning,
    ),
    IntentionDetailsNotFound() => IntentionDetailsNotFound(
      isOperationRunning: isOperationRunning,
    ),
    IntentionDetailsUnavailable() => IntentionDetailsUnavailable(
      isOperationRunning: isOperationRunning,
    ),
    IntentionDetailsCorruption() => IntentionDetailsCorruption(
      isOperationRunning: isOperationRunning,
    ),
    IntentionDetailsUnexpected() => IntentionDetailsUnexpected(
      isOperationRunning: isOperationRunning,
    ),
    IntentionDetailsDeleted() => current,
  };
}
