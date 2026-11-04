import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../application/daily_choice_command.dart';
import '../../application/daily_choice_details.dart';
import '../../application/daily_choice_result.dart';
import '../../domain/daily_choice_id.dart';
import 'daily_choice_details_state.dart';

/// Живой целый снимок одного выбора и запись его изменений; экран владеет
/// подпиской.
final class DailyChoiceDetailsViewModel extends ChangeNotifier {
  DailyChoiceDetailsViewModel(this._repository, this._coordinator, this._id) {
    _observe();
  }

  final PersonalGraphRepository _repository;
  final GraphCommandCoordinator _coordinator;
  final DailyChoiceId _id;
  StreamSubscription<DailyChoiceReadResult>? _subscription;
  GraphRevision? _acceptedRevision;
  int _generation = 0;
  DailyChoiceDetailsState _state = const DailyChoiceDetailsLoading();
  _Command? _command;
  DailyChoiceDetailsOperation _operation =
      const DailyChoiceDetailsOperationIdle();

  /// Завершается, когда кончается [DailyChoiceDetailsOperationAwaitingSnapshot].
  Completer<void>? _snapshotShown;

  DailyChoiceDetailsState get state => _state;
  DailyChoiceDetailsOperation get operation => _operation;

  void retry() {
    if (_state is! DailyChoiceDetailsUnavailable) return;
    _setState(const DailyChoiceDetailsLoading());
    _observe();
  }

  /// Возвращает успех только собственной подтверждённой записи; новое значение
  /// приходит из подписки. Успех возвращается, когда подписка показала снимок
  /// не старше записи или закончилась иным исходом.
  Future<bool> change(DailyChoiceFieldsPatch patch) async {
    if (!_canStartOperation) return false;
    final completion = await _run(
      _coordinator.acceptDailyChoiceUpdate(
        UpdateDailyChoiceFields(choiceId: _id, patch: patch),
      ),
      _Change.new,
    );
    return switch (completion?.result) {
      GraphResultSuccess(value: DailyChoiceFieldsUpdated(:final choice)) =>
        choice.id == _id,
      _ => false,
    };
  }

  /// Возвращает успех только собственной принятой команды удаления.
  ///
  /// Снимок без выбора до исхода команды не показан, а после подтверждения
  /// состояние становится [DailyChoiceDetailsDeleted].
  Future<bool> delete() async {
    if (!_canStartOperation) return false;
    final completion = await _run(
      _coordinator.acceptDailyChoiceDelete(DeleteDailyChoice(_id)),
      _Deletion.new,
    );
    return switch (completion?.result) {
      GraphResultSuccess(value: DailyChoiceDeleted(:final choice)) =>
        choice.id == _id,
      _ => false,
    };
  }

  bool get _canStartOperation =>
      _command == null &&
      _operation is! DailyChoiceDetailsOperationAwaitingSnapshot &&
      _state is DailyChoiceDetailsLoaded;

  Future<DailyChoiceCommandCompletion?> _run(
    DailyChoiceCommandStart start,
    _Command Function(DailyChoiceOperationToken token) command,
  ) async {
    switch (start) {
      case DailyChoiceCommandAccepted(:final token, :final future):
        _command = command(token);
        _setOperation(const DailyChoiceDetailsOperationWriting());
        final completion = await future;
        final finished = _command;
        if (finished != null && identical(finished.token, token)) {
          _command = null;
          _applyOutcome(finished, completion);
          final next = _operationAfter(completion);
          _setOperation(next);
          if (next is DailyChoiceDetailsOperationAwaitingSnapshot) {
            await (_snapshotShown = Completer<void>()).future;
          }
        }
        return completion;
      case DailyChoiceCommandAlreadyRunning():
        _setOperation(
          const DailyChoiceDetailsOperationFailed(
            DailyChoiceConflictFailure(
              DailyChoiceConflictReason.dependencyChanged,
            ),
          ),
        );
      case GraphCommandCoordinatorDraining():
        _setOperation(
          const DailyChoiceDetailsOperationFailed(
            DailyChoiceUnexpectedFailure(),
          ),
        );
    }
    return null;
  }

  /// Показывает исход удаления: подтверждённое удаление сохраняет прежнее
  /// содержимое, а иначе проявляется отложенный снимок без выбора.
  void _applyOutcome(
    _Command command,
    DailyChoiceCommandCompletion completion,
  ) {
    switch ((command, completion.result)) {
      case (
            _Deletion() || _DeletionChoiceMissing(),
            GraphResultSuccess(value: DailyChoiceDeleted(:final choice)),
          )
          when choice.id == _id:
        _stopObserving();
        if (_state case DailyChoiceDetailsLoaded(:final details)) {
          _setState(DailyChoiceDetailsDeleted(details));
        }
      case (_DeletionChoiceMissing(), _):
        _setState(const DailyChoiceDetailsNotFound());
      case (_Change() || _Deletion(), _):
        break;
    }
  }

  DailyChoiceDetailsOperation _operationAfter(
    DailyChoiceCommandCompletion completion,
  ) => switch (completion.confirmedResult) {
    GraphResultFailure(:final failure) => DailyChoiceDetailsOperationFailed(
      failure,
      failurePresentation: _coordinator.claimInitiatorFailure(completion.token),
    ),
    GraphResultSuccess(:final value) => switch (value.value) {
      DailyChoiceFieldsUpdated(:final choice) when choice.id == _id =>
        _awaitsSnapshot(value.revision)
            ? DailyChoiceDetailsOperationAwaitingSnapshot(value.revision)
            : const DailyChoiceDetailsOperationIdle(),
      DailyChoiceDeleted(:final choice) when choice.id == _id =>
        const DailyChoiceDetailsOperationIdle(),
      _ => const DailyChoiceDetailsOperationFailed(
        DailyChoiceUnexpectedFailure(),
      ),
    },
  };

  /// Записанное значение ещё впереди, только пока показан снимок старше
  /// записи. Снимок другой эпохи, отсутствие выбора и отказ чтения
  /// заканчивают ожидание: после них записанное значение может не прийти.
  bool _awaitsSnapshot(GraphRevision required) => switch (_state) {
    DailyChoiceDetailsLoaded(:final revision) =>
      revision.compareTo(required) == GraphRevisionOrder.older,
    _ => false,
  };

  void _finishAwaitingSnapshot() {
    _operation = const DailyChoiceDetailsOperationIdle();
    _snapshotShown?.complete();
    _snapshotShown = null;
  }

  /// Передаёт общей поверхности право отказа, который перестал публиковаться.
  /// Право, уже подтверждённое renderer, координатор не возвращает в ожидание.
  void _setOperation(DailyChoiceDetailsOperation next) {
    _releaseFailure();
    _operation = next;
    notifyListeners();
  }

  void _releaseFailure() {
    if (_operation case DailyChoiceDetailsOperationFailed(
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
          .watchDailyChoice(_id)
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
                  switch ((value.value, _command)) {
                    case (final details?, _):
                      _setState(DailyChoiceDetailsLoaded(details, revision));
                    case (null, _Deletion(:final token)):
                      _command = _DeletionChoiceMissing(token);
                    case (null, _DeletionChoiceMissing()):
                      break;
                    case (null, _Change() || null):
                      _setState(const DailyChoiceDetailsNotFound());
                  }
                case GraphResultFailure(:final failure):
                  _setState(switch (failure) {
                    DailyChoiceReadCorruptionFailure() =>
                      const DailyChoiceDetailsCorruption(),
                    DailyChoiceReadUnavailableFailure() =>
                      const DailyChoiceDetailsUnavailable(),
                    DailyChoiceReadUnexpectedFailure() =>
                      const DailyChoiceDetailsUnexpected(),
                  });
              }
            },
            onError: (Object _, StackTrace _) {
              if (generation == _generation) {
                _setState(const DailyChoiceDetailsUnexpected());
              }
            },
          );
    } catch (_) {
      _setState(const DailyChoiceDetailsUnexpected());
    }
  }

  void _stopObserving() {
    ++_generation;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _setState(DailyChoiceDetailsState next) {
    _state = next;
    if (_operation
        case DailyChoiceDetailsOperationAwaitingSnapshot(:final revision)
        when !_awaitsSnapshot(revision)) {
      _finishAwaitingSnapshot();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _stopObserving();
    final active = _command;
    _command = null;
    if (active != null) _coordinator.releaseInitiatorPresentation(active.token);
    _releaseFailure();
    _snapshotShown?.complete();
    _snapshotShown = null;
    super.dispose();
  }
}

/// Принятая команда модели до её исхода.
sealed class _Command {
  const _Command(this.token);

  final DailyChoiceOperationToken token;
}

final class _Change extends _Command {
  const _Change(super.token);
}

/// Удаление выбора, до исхода которого снимок без выбора не приходил.
final class _Deletion extends _Command {
  const _Deletion(super.token);
}

/// Удаление выбора, во время которого пришёл снимок без выбора. Он показан,
/// только если удаление не подтвердится.
final class _DeletionChoiceMissing extends _Command {
  const _DeletionChoiceMissing(super.token);
}
