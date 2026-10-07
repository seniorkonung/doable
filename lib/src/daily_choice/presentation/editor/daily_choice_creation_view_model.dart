import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../application/confirmed_choice_path.dart';
import '../../application/daily_choice_command.dart';
import '../../application/daily_choice_result.dart';
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice_description.dart';
import '../daily_choice_creation_flow_session.dart';
import 'daily_choice_creation_state.dart';

part 'daily_choice_creation_view_model.g.dart';

/// Собирает явную команду создания и сохраняет её принятие и результат в общей
/// сессии потока. Координатор выполняет запись независимо от жизни формы.
@riverpod
final class DailyChoiceCreationViewModel
    extends _$DailyChoiceCreationViewModel {
  late GraphCommandCoordinator _coordinator;
  late DailyChoiceCreationFlowSession _session;
  DailyChoiceOperationToken? _activeToken;
  DailyChoiceOperationToken? _failureToken;

  @override
  DailyChoiceCreationState build(
    DailyChoiceCreationFlowSession session,
    ConfirmedChoicePath path,
    CalendarDate date,
  ) {
    _session = session;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    ref.onDispose(() {
      final active = _activeToken;
      if (active != null) _coordinator.releaseInitiatorPresentation(active);
      _releaseFailure();
    });
    return DailyChoiceCreationState.initial(path: path, date: date);
  }

  void changeDate(CalendarDate value) {
    if (!ref.mounted || !_session.canContinue) return;
    if (state.date == value) return;
    final next = state.withDate(value);
    _releaseDroppedClaim(next);
    state = next;
  }

  void changeDescription(String value) {
    if (!ref.mounted || !_session.canContinue) return;
    if (state.description == value) return;
    final next = state.withDescription(value);
    _releaseDroppedClaim(next);
    state = next;
  }

  void changeCompletion(bool value) {
    if (!ref.mounted || !_session.canContinue) return;
    if (state.isCompleted == value) return;
    final next = state.withCompletion(value);
    _releaseDroppedClaim(next);
    state = next;
  }

  /// Конфликт нельзя снять правкой даты или текста: требуется новый путь,
  /// подтверждённый человеком после актуализации обхода. Возвращает признак
  /// принятия пути, чтобы экран показывал только отправляемые шаги.
  bool confirmRefreshedPath(ConfirmedChoicePath path) {
    if (!ref.mounted || !_session.canContinue) return false;
    final next = state.withRefreshedPath(path);
    if (identical(next, state)) return false;
    _releaseFailure();
    state = next;
    return true;
  }

  void submit() {
    if (!ref.mounted || !_session.canContinue || !state.canSubmit) return;

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
    final command = CreateDailyChoice(
      sourceIntentionId: path.steps.first.sourceIntentionId,
      selectedIntentionId: path.steps.last.relatedIntentionId,
      path: path,
      date: state.date,
      description: description,
      isCompleted: state.isCompleted,
    );
    final start = _session.acceptSubmission(
      (formKey) => _coordinator.acceptDailyChoiceCreation(formKey, command),
    );
    switch (start) {
      case DailyChoiceCommandAccepted(:final token, :final future):
        _activeToken = token;
        state = state.withOperation(const DailyChoiceCreationSubmitting());
        unawaited(_finish(future));
      case DailyChoiceCommandAlreadyRunning():
      case null:
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
    final session = _session;
    try {
      final completion = await future;
      // Результат принадлежит потоку; mounted ограничивает только доступ к Ref.
      // https://pub.dev/documentation/riverpod/3.4.2/riverpod/Ref/mounted.html
      session.recordCompletion(completion);
      if (!ref.mounted || !identical(_activeToken, completion.token)) return;
      _activeToken = null;
      if (session.state is DailyChoiceCreationFlowLeft) {
        _coordinator.releaseInitiatorPresentation(completion.token);
        return;
      }
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
