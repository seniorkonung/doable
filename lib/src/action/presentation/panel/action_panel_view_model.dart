import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../application/action_command.dart';
import '../../application/action_details.dart';
import '../../application/action_result.dart';
import '../../domain/action.dart';
import '../../domain/action_id.dart';
import 'action_panel_state.dart';

/// Живой целый снимок одного действия и запись его изменений; панель владеет
/// подпиской.
final class ActionPanelViewModel extends ChangeNotifier {
  ActionPanelViewModel(this._repository, this._coordinator, this._id) {
    _observe();
  }

  final PersonalGraphRepository _repository;
  final GraphCommandCoordinator _coordinator;
  final ActionId _id;
  StreamSubscription<ActionReadResult>? _subscription;
  GraphRevision? _acceptedRevision;
  int _generation = 0;
  ActionPanelState _state = const ActionPanelLoading();
  ActionPanelOperation _operation = const ActionPanelOperationIdle();
  ActionOperationToken? _activeToken;
  ActionCommandFailure? _completionLock;
  var _awaitsRefresh = false;

  /// Идёт удаление: снимок без действия до его исхода не показывается, а
  /// запоминается в [_missingWhileDeleting].
  var _isDeleting = false;
  var _missingWhileDeleting = false;
  var _disposed = false;

  /// Завершается, когда кончается [ActionPanelOperationAwaitingSnapshot].
  Completer<void>? _snapshotShown;

  ActionPanelState get state => _state;
  ActionPanelOperation get operation => _operation;

  /// Отказ изменения выполнения без явного повтора: флажок недоступен, пока
  /// [refresh] не прочитает действие заново. Без отказа флажок свободен.
  ActionCommandFailure? get completionLock => _completionLock;

  void retry() {
    if (_state is! ActionPanelUnavailable) return;
    _setState(const ActionPanelLoading());
    _observe();
  }

  /// Перечитывает действие. Подтверждённое состояние, показанное после
  /// перечитывания, снимает блокировку флажка; отклонённое изменение заново не
  /// отправляется.
  void refresh() {
    if (_completionLock == null || _state is! ActionPanelLoaded) return;
    _awaitsRefresh = true;
    _observe();
  }

  /// Возвращает успех только собственной подтверждённой записи; новое значение
  /// приходит из подписки. Успех возвращается, когда подписка показала снимок
  /// не старше записи или закончилась иным исходом, а запись, которая ничего не
  /// изменила, завершается сразу.
  Future<bool> change(ActionFieldsPatch patch) async {
    if (!_canStartOperation) return false;
    final completion = await _run(
      _coordinator.acceptActionUpdate(
        UpdateActionFields(actionId: _id, patch: patch),
      ),
      locksCompletionOnFailure: patch.isCompleted is ActionFieldSet<bool>,
    );
    return switch (completion?.result) {
      GraphResultSuccess(value: ActionFieldsUpdated(:final action)) =>
        action.id == _id,
      _ => false,
    };
  }

  /// Возвращает успех только собственной подтверждённой команды удаления.
  ///
  /// Подтверждённое удаление сохраняет прежнее содержимое как
  /// [ActionPanelDeleted]: снимок без действия не должен показать «действия
  /// нет» в закрывающейся панели. После отказа отсутствие действия показано,
  /// только если снимок без него уже пришёл.
  Future<bool> delete() async {
    final state = _state;
    if (!_canStartOperation || state is! ActionPanelLoaded) return false;
    _isDeleting = true;
    final completion = await _run(
      _coordinator.acceptActionDelete(DeleteAction(_id)),
      locksCompletionOnFailure: false,
    );
    final deleted = switch (completion?.result) {
      GraphResultSuccess(value: ActionDeleted(:final action)) =>
        action.id == _id,
      _ => false,
    };
    if (_disposed) return deleted;
    _isDeleting = false;
    final missing = _missingWhileDeleting;
    _missingWhileDeleting = false;
    if (deleted) {
      _stopObserving();
      _setState(ActionPanelDeleted(state.details));
    } else if (missing) {
      _setState(const ActionPanelNotFound());
    }
    return deleted;
  }

  bool get _canStartOperation =>
      _activeToken == null &&
      _operation is! ActionPanelOperationAwaitingSnapshot &&
      _state is ActionPanelLoaded;

  Future<ActionCommandCompletion?> _run(
    ActionCommandStart start, {
    required bool locksCompletionOnFailure,
  }) async {
    switch (start) {
      case ActionCommandAccepted(:final token, :final future):
        _activeToken = token;
        _setOperation(const ActionPanelOperationWriting());
        final completion = await future;
        if (identical(_activeToken, token)) {
          _activeToken = null;
          final next = _operationAfter(completion);
          _lockCompletionAfter(next, locksCompletionOnFailure);
          _setOperation(next);
          if (next is ActionPanelOperationAwaitingSnapshot) {
            await (_snapshotShown = Completer<void>()).future;
          }
        }
        return completion;
      case ActionCommandAlreadyRunning():
        _fail(const ActionConflictFailure(), locksCompletionOnFailure);
      case GraphCommandCoordinatorDraining():
        _fail(const ActionUnexpectedFailure(), locksCompletionOnFailure);
    }
    return null;
  }

  void _fail(ActionCommandFailure failure, bool locksCompletion) {
    final next = ActionPanelOperationFailed(failure);
    _lockCompletionAfter(next, locksCompletion);
    _setOperation(next);
  }

  /// Явный повтор допускает только доказанно временная недоступность; после
  /// любого другого отказа флажок возвращает только перечитанное действие.
  void _lockCompletionAfter(ActionPanelOperation next, bool locksCompletion) {
    if (locksCompletion &&
        next is ActionPanelOperationFailed &&
        next.failure is! ActionUnavailableFailure) {
      _completionLock = next.failure;
    }
  }

  ActionPanelOperation _operationAfter(ActionCommandCompletion completion) =>
      switch (completion.confirmedResult) {
        GraphResultFailure(:final failure) => ActionPanelOperationFailed(
          failure,
          failurePresentation: _coordinator.claimInitiatorFailure(
            completion.token,
          ),
        ),
        GraphResultSuccess(:final value) => switch (value.value) {
          ActionFieldsUpdated(:final action) when action.id == _id =>
            _awaitsSnapshot(value.revision) && !_showsWritten(action)
                ? ActionPanelOperationAwaitingSnapshot(value.revision)
                : const ActionPanelOperationIdle(),
          ActionDeleted(:final action) when action.id == _id =>
            const ActionPanelOperationIdle(),
          _ => const ActionPanelOperationFailed(ActionUnexpectedFailure()),
        },
      };

  /// Записанное значение ещё впереди, только пока показан снимок старше
  /// записи. Снимок другой эпохи, отсутствие действия и отказ чтения
  /// заканчивают ожидание: после них записанное значение может не прийти.
  bool _awaitsSnapshot(GraphRevision required) => switch (_state) {
    ActionPanelLoaded(:final revision) =>
      revision.compareTo(required) == GraphRevisionOrder.older,
    _ => false,
  };

  /// Запись, не изменившая значений, не меняет хранилище, и подписка не
  /// выпустит нового снимка: ждать его незачем.
  bool _showsWritten(Action written) => switch (_state) {
    ActionPanelLoaded(:final details) =>
      details.action.title == written.title &&
          details.action.description == written.description &&
          details.action.date == written.date &&
          details.action.schedule == written.schedule &&
          details.action.priority == written.priority &&
          details.action.isCompleted == written.isCompleted,
    _ => false,
  };

  void _finishAwaitingSnapshot() {
    _operation = const ActionPanelOperationIdle();
    _snapshotShown?.complete();
    _snapshotShown = null;
  }

  /// Передаёт общей поверхности право отказа, который перестал публиковаться.
  /// Право, уже подтверждённое renderer, координатор не возвращает в ожидание.
  void _setOperation(ActionPanelOperation next) {
    _releaseFailure();
    _operation = next;
    notifyListeners();
  }

  void _releaseFailure() {
    if (_operation case ActionPanelOperationFailed(
      failurePresentation: final claim?,
    )) {
      _coordinator.releaseInitiatorClaim(claim);
    }
  }

  void _observe() {
    final generation = ++_generation;
    unawaited(_subscription?.cancel());
    try {
      _subscription = _repository
          .watchAction(_id)
          .listen(
            (result) {
              if (generation != _generation) return;
              switch (result) {
                case GraphResultSuccess(:final value):
                  final revision = value.revision;
                  if (_acceptedRevision != null &&
                      revision.compareTo(_acceptedRevision!) ==
                          GraphRevisionOrder.older) {
                    return;
                  }
                  _acceptedRevision = revision;
                  if (value.value case final details?) {
                    if (_awaitsRefresh) {
                      _awaitsRefresh = false;
                      _completionLock = null;
                    }
                    _setState(ActionPanelLoaded(details, revision));
                  } else if (_isDeleting) {
                    _missingWhileDeleting = true;
                  } else {
                    _setState(const ActionPanelNotFound());
                  }
                case GraphResultFailure(:final failure):
                  _setState(switch (failure) {
                    ActionReadCorruptionFailure() =>
                      const ActionPanelCorruption(),
                    ActionReadUnavailableFailure() =>
                      const ActionPanelUnavailable(),
                    ActionReadUnexpectedFailure() =>
                      const ActionPanelUnexpected(),
                  });
              }
            },
            onError: (Object _, StackTrace _) {
              if (generation == _generation) {
                _setState(const ActionPanelUnexpected());
              }
            },
          );
    } catch (_) {
      _setState(const ActionPanelUnexpected());
    }
  }

  void _stopObserving() {
    ++_generation;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _setState(ActionPanelState next) {
    _state = next;
    if (_operation case ActionPanelOperationAwaitingSnapshot(:final revision)
        when !_awaitsSnapshot(revision)) {
      _finishAwaitingSnapshot();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopObserving();
    final active = _activeToken;
    _activeToken = null;
    if (active != null) _coordinator.releaseInitiatorPresentation(active);
    _releaseFailure();
    _snapshotShown?.complete();
    _snapshotShown = null;
    super.dispose();
  }
}
