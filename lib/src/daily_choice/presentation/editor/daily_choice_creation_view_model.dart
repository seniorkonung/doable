import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../application/confirmed_choice_path.dart';
import '../../application/daily_choice_command.dart';
import '../../application/daily_choice_result.dart';
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice_description.dart';
import 'daily_choice_creation_state.dart';

part 'daily_choice_creation_view_model.g.dart';

/// Собирает одну явную команду создания и оставляет её coordinator после ухода
/// формы. Второе подтверждение той же формы не создаёт самостоятельный выбор.
@riverpod
final class DailyChoiceCreationViewModel
    extends _$DailyChoiceCreationViewModel {
  late GraphCommandCoordinator _coordinator;
  late DailyChoiceCreationFormKey _formKey;
  DailyChoiceOperationToken? _activeToken;
  DailyChoiceOperationToken? _failureToken;

  @override
  DailyChoiceCreationState build(
    DailyChoiceCreationFormKey formKey,
    ConfirmedChoicePath path,
    CalendarDate date,
  ) {
    _formKey = formKey;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    ref.onDispose(() {
      final active = _activeToken;
      if (active != null) _coordinator.releaseInitiatorPresentation(active);
      _releaseFailure();
    });
    return DailyChoiceCreationState.initial(path: path, date: date);
  }

  void changeDate(CalendarDate value) {
    if (state.date == value) return;
    final next = state.withDate(value);
    _releaseDroppedClaim(next);
    state = next;
  }

  void changeDescription(String value) {
    if (state.description == value) return;
    final next = state.withDescription(value);
    _releaseDroppedClaim(next);
    state = next;
  }

  void changeCompletion(bool value) {
    if (state.isCompleted == value) return;
    final next = state.withCompletion(value);
    _releaseDroppedClaim(next);
    state = next;
  }

  /// Конфликт нельзя снять правкой даты или текста: требуется новый путь,
  /// подтверждённый человеком после актуализации обхода.
  void confirmRefreshedPath(ConfirmedChoicePath path) {
    final next = state.withRefreshedPath(path);
    if (identical(next, state)) return;
    _releaseFailure();
    state = next;
  }

  void submit() {
    if (!state.canSubmit) return;

    final DailyChoiceDescription? description;
    try {
      description = DailyChoiceDescription.fromInput(state.description);
    } on DailyChoiceDescriptionValidationException catch (error) {
      _releaseFailure();
      state = state.withOperation(
        DailyChoiceCreationFailed(
          DailyChoiceCreationDescriptionInvalid(error.failure),
        ),
      );
      return;
    }

    _releaseFailure();
    final path = state.path;
    final start = _coordinator.acceptDailyChoiceCreation(
      _formKey,
      CreateDailyChoice(
        sourceIntentionId: path.steps.first.sourceIntentionId,
        selectedIntentionId: path.steps.last.relatedIntentionId,
        path: path,
        date: state.date,
        description: description,
        isCompleted: state.isCompleted,
      ),
    );
    switch (start) {
      case DailyChoiceCommandAccepted(:final token, :final future):
        _activeToken = token;
        state = state.withOperation(const DailyChoiceCreationSubmitting());
        unawaited(_finish(future));
      case DailyChoiceCommandAlreadyRunning():
        return;
      case GraphCommandCoordinatorDraining():
        state = state.withOperation(
          const DailyChoiceCreationFailed(
            DailyChoiceCreationCommandRejected(DailyChoiceUnexpectedFailure()),
          ),
        );
    }
  }

  void consumeEvent() {
    if (state.event != null) state = state.withoutEvent();
  }

  Future<void> _finish(Future<DailyChoiceCommandCompletion> future) async {
    try {
      final completion = await future;
      if (!ref.mounted || !identical(_activeToken, completion.token)) return;
      _activeToken = null;
      state = switch (completion.result) {
        GraphResultSuccess(value: DailyChoiceCreated(:final choice)) =>
          state.withOperation(
            DailyChoiceCreationSucceeded(choice.id),
            event: DailyChoiceCreationCreated(choice.id),
          ),
        GraphResultSuccess() => state.withOperation(
          const DailyChoiceCreationFailed(
            DailyChoiceCreationCommandRejected(DailyChoiceUnexpectedFailure()),
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
        const DailyChoiceCreationFailed(
          DailyChoiceCreationCommandRejected(DailyChoiceUnexpectedFailure()),
        ),
      );
    }
  }

  DailyChoiceCreationState _failed(
    DailyChoiceOperationToken token,
    DailyChoiceCommandFailure failure,
  ) {
    _failureToken = token;
    return state.withOperation(
      DailyChoiceCreationFailed(DailyChoiceCreationCommandRejected(failure)),
      failurePresentation: _coordinator.claimInitiatorFailure(token),
    );
  }

  void _releaseDroppedClaim(DailyChoiceCreationState next) {
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
