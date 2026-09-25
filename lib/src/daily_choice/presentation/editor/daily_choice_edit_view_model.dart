import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../application/daily_choice_command.dart';
import '../../application/daily_choice_result.dart';
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice.dart';
import '../../domain/daily_choice_description.dart';
import 'daily_choice_edit_state.dart';

part 'daily_choice_edit_view_model.g.dart';

@riverpod
final class DailyChoiceEditViewModel extends _$DailyChoiceEditViewModel {
  late GraphCommandCoordinator _coordinator;
  DailyChoiceOperationToken? _activeToken;
  DailyChoiceOperationToken? _failureToken;

  @override
  DailyChoiceEditState build(DailyChoice original) {
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    ref.onDispose(() {
      final active = _activeToken;
      if (active != null) _coordinator.releaseInitiatorPresentation(active);
      _releaseFailure();
    });
    return DailyChoiceEditState.initial(original);
  }

  void changeDate(CalendarDate value) {
    final next = state.withDate(value);
    if (state.date == value && identical(state.operation, next.operation)) {
      return;
    }
    _releaseDroppedClaim(next);
    state = next;
  }

  void changeDescription(String value) {
    final next = state.withDescription(value);
    if (state.description == value &&
        identical(state.operation, next.operation)) {
      return;
    }
    _releaseDroppedClaim(next);
    state = next;
  }

  void changeCompletion(bool value) {
    if (state.isCompleted == value) return;
    final next = state.withCompletion(value);
    _releaseDroppedClaim(next);
    state = next;
  }

  void submit() {
    if (!state.canSubmit) return;
    final DailyChoiceFieldsPatch? patch;
    try {
      patch = state.toPatch();
    } on DailyChoiceDescriptionValidationException catch (error) {
      _releaseFailure();
      state = state.withOperation(
        DailyChoiceEditFailed(DailyChoiceEditDescriptionInvalid(error.failure)),
      );
      return;
    }
    if (patch == null) {
      state = state.withOperation(const DailyChoiceEditSucceeded());
      return;
    }

    _releaseFailure();
    final start = _coordinator.acceptDailyChoiceUpdate(
      UpdateDailyChoiceFields(choiceId: state.original.id, patch: patch),
    );
    switch (start) {
      case DailyChoiceCommandAccepted(:final token, :final future):
        _activeToken = token;
        state = state.withOperation(const DailyChoiceEditSubmitting());
        unawaited(_finish(future));
      case DailyChoiceCommandAlreadyRunning():
        state = state.withOperation(
          const DailyChoiceEditFailed(
            DailyChoiceEditCommandRejected(
              DailyChoiceConflictFailure(
                DailyChoiceConflictReason.dependencyChanged,
              ),
            ),
          ),
        );
      case GraphCommandCoordinatorDraining():
        state = state.withOperation(
          const DailyChoiceEditFailed(
            DailyChoiceEditCommandRejected(DailyChoiceUnexpectedFailure()),
          ),
        );
    }
  }

  Future<void> _finish(Future<DailyChoiceCommandCompletion> future) async {
    try {
      final completion = await future;
      if (!ref.mounted || !identical(_activeToken, completion.token)) return;
      _activeToken = null;
      state = switch (completion.result) {
        GraphResultSuccess(value: DailyChoiceFieldsUpdated()) =>
          state.withOperation(const DailyChoiceEditSucceeded()),
        GraphResultSuccess() => state.withOperation(
          const DailyChoiceEditFailed(
            DailyChoiceEditCommandRejected(DailyChoiceUnexpectedFailure()),
          ),
        ),
        GraphResultFailure(:final failure) => _failed(
          completion.token,
          failure,
        ),
      };
    } on Object {
      if (!ref.mounted) return;
      final token = _activeToken;
      _activeToken = null;
      if (token != null) _coordinator.releaseInitiatorPresentation(token);
      state = state.withOperation(
        const DailyChoiceEditFailed(
          DailyChoiceEditCommandRejected(DailyChoiceUnexpectedFailure()),
        ),
      );
    }
  }

  DailyChoiceEditState _failed(
    DailyChoiceOperationToken token,
    DailyChoiceCommandFailure failure,
  ) {
    _failureToken = token;
    return state.withOperation(
      DailyChoiceEditFailed(DailyChoiceEditCommandRejected(failure)),
      failurePresentation: _coordinator.claimInitiatorFailure(token),
    );
  }

  void _releaseDroppedClaim(DailyChoiceEditState next) {
    if (state.failurePresentation != null && next.failurePresentation == null) {
      _releaseFailure();
    }
  }

  void _releaseFailure() {
    final token = _failureToken;
    _failureToken = null;
    if (token != null) _coordinator.releaseInitiatorPresentation(token);
  }
}
