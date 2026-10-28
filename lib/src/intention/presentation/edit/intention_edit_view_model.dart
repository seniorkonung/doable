import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../application/intention_catalog.dart';
import '../../application/intention_command.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
import '../details/intention_details_state.dart';
import '../details/intention_details_view_model.dart';
import '../operation/operation_state.dart';
import 'intention_edit_state.dart';

part 'intention_edit_view_model.g.dart';

/// Экранная сессия изменения названия и описания намерения по ключу формы.
///
/// Сессия получает сохранённые тексты из подробных данных на момент открытия:
/// экран открывается только над полученными подробными данными, пока для
/// намерения не выполняется изменяющая команда, поэтому снимок не
/// согласуется с результатом ранее начатой операции.
///
/// Принятое сохранение удерживает координатор: освобождение сессии его не
/// отменяет, а поздний отказ переходит общей поверхности. Пока отказ
/// действует, сессия публикует право его предъявления; право, которое
/// состояние перестало публиковать, и право выполняющегося сохранения при
/// освобождении сессия передаёт общей поверхности.
@riverpod
final class IntentionEditViewModel extends _$IntentionEditViewModel {
  late IntentionId _intentionId;
  late GraphCommandCoordinator _coordinator;
  IntentionOperationToken? _activeToken;

  /// Право отказа, которое публикует текущее состояние сессии.
  GraphInitiatorPresentationClaim? _publishedFailureClaim;

  @override
  IntentionEditState build(
    IntentionEditFormKey formKey,
    IntentionId intentionId,
  ) {
    _intentionId = intentionId;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    final intention = switch (ref.read(
      intentionDetailsViewModelProvider(intentionId),
    )) {
      IntentionDetailsLoaded(:final intention) => intention,
      IntentionDetailsLoading() ||
      IntentionDetailsNotFound() ||
      IntentionDetailsUnavailable() ||
      IntentionDetailsCorruption() ||
      IntentionDetailsUnexpected() ||
      IntentionDetailsDeleted() => throw StateError(
        'Экран изменения открывается только над полученными подробными '
        'данными намерения.',
      ),
    };
    final completions = _coordinator.completions.listen(_handleCompletion);
    listenSelf((_, next) => _publishFailureClaim(next.failurePresentation));
    ref.onDispose(() {
      unawaited(completions.cancel());
      final token = _activeToken;
      if (token != null) {
        _coordinator.releaseInitiatorPresentation(token);
      }
      _publishFailureClaim(null);
    });
    return IntentionEditState.opened(
      intention,
      isIntentionBusy: _coordinator.isRunning(intentionId),
    );
  }

  void changeTitle(String value) {
    if (state.acceptsDraftChanges && state.title != value) {
      state = state.withTitle(value);
    }
  }

  void changeDescription(String value) {
    if (state.acceptsDraftChanges && state.description != value) {
      state = state.withDescription(value);
    }
  }

  void save() {
    final current = state;
    if (!current.canSave) {
      return;
    }

    final description = current.description;
    final start = _coordinator.acceptExisting(
      UpdateIntention(
        id: _intentionId,
        title: current.title,
        description: description.isEmpty ? null : description,
      ),
      presentationTitle: current.savedTitle,
    );
    switch (start) {
      case IntentionCommandAccepted(:final token, :final future):
        _activeToken = token;
        state = current.withOperation(const OperationRunning<Intention>());
        unawaited(_finish(future));
      case IntentionCommandAlreadyRunning():
        state = current.withIntentionBusy(true);
      case GraphCommandCoordinatorDraining():
        state = current.withOperation(
          const OperationFailed<Intention>(IntentionUnexpectedFailure()),
        );
    }
  }

  /// Решает запрос ухода от стрелки и системного «назад».
  IntentionEditCloseDecision requestClose() => state.closeDecision;

  Future<void> _finish(Future<IntentionCommandCompletion> future) async {
    try {
      final completion = await future;
      if (!ref.mounted || !identical(_activeToken, completion.token)) {
        return;
      }

      _activeToken = null;
      // Успех закрывает экран без сообщения.
      state = switch (completion.result) {
        ResultSuccess(value: IntentionSaved(:final intention))
            when intention.id == _intentionId =>
          state.withOperation(OperationSucceeded<Intention>(intention)),
        ResultSuccess(value: IntentionSaved() || IntentionDeleted()) =>
          state.withOperation(
            const OperationFailed<Intention>(IntentionUnexpectedFailure()),
          ),
        ResultFailure(:final failure) => state.withOperation(
          OperationFailed<Intention>(failure),
          failurePresentation: _coordinator.claimInitiatorFailure(
            completion.token,
          ),
        ),
      };
    } on Object {
      if (!ref.mounted) {
        return;
      }
      final token = _activeToken;
      _activeToken = null;
      if (token != null) {
        _coordinator.releaseInitiatorPresentation(token);
      }
      state = state.withOperation(
        const OperationFailed<Intention>(IntentionUnexpectedFailure()),
      );
    }
  }

  /// Завершение любой команды могло снять занятость намерения.
  void _handleCompletion(GraphCommandCompletion _) {
    if (!ref.mounted) {
      return;
    }
    final isBusy = _coordinator.isRunning(_intentionId);
    if (state.isIntentionBusy != isBusy) {
      state = state.withIntentionBusy(isBusy);
    }
  }

  /// Учитывает право отказа, которое публикует состояние, и передаёт общей
  /// поверхности прежнее право, переставшее публиковаться. Право, уже
  /// подтверждённое renderer, координатор повторно не выдаёт.
  void _publishFailureClaim(GraphInitiatorPresentationClaim? claim) {
    final previous = _publishedFailureClaim;
    _publishedFailureClaim = claim;
    if (previous != null && !identical(previous, claim)) {
      _coordinator.releaseInitiatorClaim(previous);
    }
  }
}
