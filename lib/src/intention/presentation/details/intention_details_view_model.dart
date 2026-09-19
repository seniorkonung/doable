import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../application/intention_command.dart';
import '../../application/intention_catalog.dart';
import '../../application/intention_details.dart' as application;
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
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
Stream<Result<GraphSnapshot<application.IntentionDetails?>>>
_intentionDetailsObservation(
  Ref ref,
  IntentionId intentionId,
  _DetailObservationGeneration generation,
) => ref.watch(personalGraphRepositoryProvider).watchIntention(intentionId);

@riverpod
final class IntentionDetailsViewModel extends _$IntentionDetailsViewModel {
  late IntentionId _intentionId;
  late GraphCommandCoordinator _coordinator;
  late _DetailObservationGeneration _generation;
  late StreamSubscription<IntentionCommandCompletion> _completionSubscription;
  ProviderSubscription<
    AsyncValue<Result<GraphSnapshot<application.IntentionDetails?>>>
  >?
  _observationSubscription;
  IntentionOperationToken? _activeToken;
  GraphRevision? _acceptedRevision;
  var _preserveAuthoritativeStateWhileLoading = false;
  var _isDeleted = false;

  @override
  IntentionDetailsState build(IntentionId intentionId) {
    _intentionId = intentionId;
    _generation = _DetailObservationGeneration.initial;
    _acceptedRevision = null;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _completionSubscription = _coordinator.intentionCompletions.listen(
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
    );
  }

  void cancelEditing() {
    final current = state;
    if (current is! IntentionDetailsLoaded ||
        current.edit == null ||
        _isOperationRunning) {
      return;
    }
    state = current.copyWith(clearEdit: true);
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
    state = current.copyWith(edit: edit.withTitle(value));
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
    state = current.copyWith(edit: edit.withDescription(value));
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
    final start = _coordinator.acceptExisting(
      UpdateIntention(
        id: _intentionId,
        title: edit.title,
        description: description.isEmpty ? null : description,
      ),
      presentationTitle: current.intention.title,
    );
    switch (start) {
      case IntentionCommandAccepted(:final token, :final future):
        _activeToken = token;
        state = current.copyWith(
          isOperationRunning: true,
          edit: edit.withOperation(const OperationRunning<Intention>()),
        );
        unawaited(_finishUpdate(future));
      case IntentionCommandAlreadyRunning():
        state = current.copyWith(isOperationRunning: true);
      case GraphCommandCoordinatorDraining():
        state = current.copyWith(
          edit: edit.withOperation(
            const OperationFailed<Intention>(IntentionUnexpectedFailure()),
          ),
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

  AsyncValue<Result<GraphSnapshot<application.IntentionDetails?>>>
  _startObservation() {
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
    AsyncValue<Result<GraphSnapshot<application.IntentionDetails?>>>
    observation,
  ) {
    if (!ref.mounted || _isDeleted || generation != _generation) {
      return;
    }
    if (observation
            is AsyncLoading<
              Result<GraphSnapshot<application.IntentionDetails?>>
            > &&
        _preserveAuthoritativeStateWhileLoading) {
      return;
    }
    if (observation
        is! AsyncLoading<
          Result<GraphSnapshot<application.IntentionDetails?>>
        >) {
      _preserveAuthoritativeStateWhileLoading = false;
    }
    final current = state;
    final loaded = current is IntentionDetailsLoaded ? current : null;
    final hasNoConfirmedIntention = switch (observation) {
      AsyncData(
        value: ResultSuccess(
          value: GraphSnapshot(value: application.IntentionDetails()),
        ),
      ) =>
        false,
      AsyncLoading<Result<GraphSnapshot<application.IntentionDetails?>>>() ||
      AsyncError<Result<GraphSnapshot<application.IntentionDetails?>>>() ||
      AsyncData<Result<GraphSnapshot<application.IntentionDetails?>>>() => true,
    };
    if (loaded?.edit != null && hasNoConfirmedIntention) {
      return;
    }
    final snapshot = switch (observation) {
      AsyncData(value: ResultSuccess(:final value)) => value,
      AsyncLoading() || AsyncError() || AsyncData() => null,
    };
    if (snapshot != null && !_acceptSnapshotRevision(snapshot.revision)) {
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
    switch (completion.confirmedResult) {
      case ResultSuccess(
            value: ConfirmedGraphResult(
              :final revision,
              value: IntentionSaved(:final intention),
            ),
          )
          when intention.id == _intentionId:
        if (!_acceptSnapshotRevision(revision)) {
          return;
        }
        _advanceGeneration();
        _preserveAuthoritativeStateWhileLoading = true;
        final current = state;
        final loaded = current is IntentionDetailsLoaded ? current : null;
        if (loaded != null) {
          state = loaded.copyWith(
            intention: intention,
            isOperationRunning: _isOperationRunning,
            stateChange: identical(_activeToken, completion.token)
                ? loaded.stateChange
                : null,
            clearStateChange: !identical(_activeToken, completion.token),
          );
        }
        _startObservation();
      case ResultSuccess(
            value: ConfirmedGraphResult(
              :final revision,
              value: IntentionDeleted(:final id),
            ),
          )
          when id == _intentionId:
        _acceptedRevision = revision;
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

      _activeToken = null;
      final current = state;
      final edit = current is IntentionDetailsLoaded ? current.edit : null;
      // Success предъявляет оболочка; просмотр только завершает форму.
      switch (completion.result) {
        case ResultSuccess(value: IntentionSaved(:final intention))
            when intention.id == _intentionId:
          if (current is IntentionDetailsLoaded && edit != null) {
            state = current.copyWith(clearEdit: true);
          }
        case ResultSuccess(value: IntentionSaved() || IntentionDeleted()):
          _failUpdateUnexpectedly();
        case ResultFailure(:final failure):
          if (current is IntentionDetailsLoaded && edit != null) {
            state = current.copyWith(
              edit: edit.withOperation(
                OperationFailed<Intention>(failure),
                failurePresentation: _claimFailure(completion.token),
              ),
            );
          } else {
            // Ошибку негде показать в этой сессии: право сразу у оболочки.
            _coordinator.releaseInitiatorPresentation(completion.token);
          }
      }
      _scheduleGateRefresh();
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

    final start = _coordinator.acceptExisting(
      _commandForStateChange(kind),
      presentationTitle: current.intention.title,
    );
    switch (start) {
      case IntentionCommandAccepted(:final token, :final future):
        _activeToken = token;
        state = current.copyWith(
          isOperationRunning: true,
          stateChange: IntentionDetailsStateChange.running(kind),
        );
        unawaited(_finishStateChange(kind, future));
      case IntentionCommandAlreadyRunning():
        state = current.copyWith(isOperationRunning: true);
      case GraphCommandCoordinatorDraining():
        state = current.copyWith(
          stateChange: IntentionDetailsStateChange.failed(
            kind,
            const IntentionUnexpectedFailure(),
          ),
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

      _activeToken = null;
      final current = state;
      // Success предъявляет оболочка; удаление завершает просмотр через канал
      // согласования данных.
      switch (completion.result) {
        case ResultSuccess(value: IntentionSaved(:final intention))
            when intention.id == _intentionId &&
                kind != IntentionDetailsStateChangeKind.delete:
          if (current is IntentionDetailsLoaded) {
            state = current.copyWith(clearStateChange: true);
          }
        case ResultSuccess(value: IntentionDeleted(:final id))
            when id == _intentionId &&
                kind == IntentionDetailsStateChangeKind.delete:
          break;
        case ResultSuccess(value: IntentionSaved() || IntentionDeleted()):
          _failStateChangeUnexpectedly(kind);
        case ResultFailure(:final failure):
          if (current is IntentionDetailsLoaded) {
            state = current.copyWith(
              stateChange: IntentionDetailsStateChange.failed(
                kind,
                failure,
                failurePresentation: _claimFailure(completion.token),
              ),
            );
          } else {
            // Ошибку негде показать в этой сессии: право сразу у оболочки.
            _coordinator.releaseInitiatorPresentation(completion.token);
          }
      }
      _scheduleGateRefresh();
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

  ExistingIntentionCommand _commandForStateChange(
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

  IntentionInitiatorPresentationClaim? _claimFailure(
    IntentionOperationToken token,
  ) => _coordinator.claimInitiatorFailure(token);

  void _failUpdateUnexpectedly() {
    final current = state;
    final edit = current is IntentionDetailsLoaded ? current.edit : null;
    if (current is IntentionDetailsLoaded && edit != null) {
      state = current.copyWith(
        edit: edit.withOperation(
          const OperationFailed<Intention>(IntentionUnexpectedFailure()),
        ),
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

  bool _acceptSnapshotRevision(GraphRevision revision) {
    final accepted = _acceptedRevision;
    if (accepted != null &&
        revision.compareTo(accepted) == GraphRevisionOrder.older) {
      return false;
    }
    _acceptedRevision = revision;
    return true;
  }

  bool get _isOperationRunning => _coordinator.isRunning(_intentionId);

  IntentionDetailsState _stateFromObservation(
    AsyncValue<Result<GraphSnapshot<application.IntentionDetails?>>>
    observation, {
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
    Result<GraphSnapshot<application.IntentionDetails?>> result,
    bool isOperationRunning, {
    IntentionDetailsLoaded? previousLoaded,
  }) => switch (result) {
    ResultSuccess(
      value: GraphSnapshot(value: final application.IntentionDetails details),
    ) =>
      IntentionDetailsLoaded(
        details: details,
        isOperationRunning: isOperationRunning,
        edit: previousLoaded?.edit,
        stateChange: previousLoaded?.stateChange,
      ),
    ResultSuccess(value: GraphSnapshot(value: null)) =>
      IntentionDetailsNotFound(isOperationRunning: isOperationRunning),
    ResultFailure(failure: IntentionUnavailableFailure()) =>
      IntentionDetailsUnavailable(isOperationRunning: isOperationRunning),
    ResultFailure(failure: IntentionCorruptionFailure()) =>
      IntentionDetailsCorruption(isOperationRunning: isOperationRunning),
    ResultFailure(
      failure: IntentionValidationFailure() ||
          IntentionNotFoundFailure() ||
          IntentionConflictFailure() ||
          IntentionHasBlockingRelationsFailure() ||
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
