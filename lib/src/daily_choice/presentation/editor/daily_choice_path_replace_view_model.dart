import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../application/confirmed_choice_path.dart';
import '../../application/daily_choice_command.dart';
import '../../application/daily_choice_details.dart';
import '../../application/daily_choice_result.dart';
import '../../domain/daily_choice_id.dart';
import 'daily_choice_path_replace_state.dart';

/// Черновик замены принадлежит экрану; принятая команда и результат принадлежат
/// общему координатору даже после закрытия модели.
final class DailyChoicePathReplaceViewModel extends ChangeNotifier {
  DailyChoicePathReplaceViewModel(
    this._repository,
    this._coordinator,
    this.choiceId,
  ) {
    _load();
  }

  final PersonalGraphRepository _repository;
  final GraphCommandCoordinator _coordinator;
  final DailyChoiceId choiceId;
  DailyChoicePathReplaceState _state = const DailyChoicePathReplaceLoading();
  DailyChoiceOperationToken? _activeToken;
  DailyChoiceOperationToken? _failureToken;
  int _readGeneration = 0;
  bool _disposed = false;

  DailyChoicePathReplaceState get state => _state;
  bool get isDisposed => _disposed;

  void retryRead() {
    final current = _state;
    if (current is! DailyChoicePathReplaceReadFailed || !current.canRetry) {
      return;
    }
    _setState(const DailyChoicePathReplaceLoading());
    _load();
  }

  void selectPath(ConfirmedChoicePath path) {
    final current = _state;
    final details = switch (current) {
      DailyChoicePathReplaceChoosing(:final details) ||
      DailyChoicePathReplaceReady(:final details) ||
      DailyChoicePathReplaceRejected(:final details) => details,
      _ => null,
    };
    if (details == null) return;
    final proposal = DailyChoicePathReplaceProposal(path);
    _releaseFailure();
    _setState(DailyChoicePathReplaceReady(details, proposal));
  }

  void cancelSelection() {
    final current = _state;
    switch (current) {
      case DailyChoicePathReplaceReady(:final details) ||
          DailyChoicePathReplaceRejected(:final details):
        _releaseFailure();
        _setState(DailyChoicePathReplaceChoosing(details));
      default:
        return;
    }
  }

  void confirm() {
    final current = _state;
    final DailyChoiceDetails details;
    final DailyChoicePathReplaceProposal proposal;
    switch (current) {
      case DailyChoicePathReplaceReady():
        details = current.details;
        proposal = current.proposal;
      case DailyChoicePathReplaceRejected() when current.canRetry:
        details = current.details;
        proposal = current.proposal;
      default:
        return;
    }

    _releaseFailure();
    final start = _coordinator.acceptDailyChoiceReplace(
      ReplaceDailyChoicePath(
        choiceId: choiceId,
        sourceIntentionId: proposal.sourceIntentionId,
        selectedIntentionId: proposal.selectedIntentionId,
        path: proposal.path,
      ),
    );
    switch (start) {
      case DailyChoiceCommandAccepted(:final token, :final future):
        _activeToken = token;
        _setState(DailyChoicePathReplaceSubmitting(details, proposal));
        unawaited(_finish(future));
      case DailyChoiceCommandAlreadyRunning():
        _setState(
          DailyChoicePathReplaceRejected(
            details,
            proposal,
            const DailyChoiceConflictFailure(
              DailyChoiceConflictReason.dependencyChanged,
            ),
          ),
        );
      case GraphCommandCoordinatorDraining():
        _setState(
          DailyChoicePathReplaceRejected(
            details,
            proposal,
            const DailyChoiceUnexpectedFailure(),
          ),
        );
    }
  }

  void _load() {
    final generation = ++_readGeneration;
    unawaited(_read(generation));
  }

  Future<void> _read(int generation) async {
    try {
      final result = await _repository.getDailyChoice(choiceId);
      if (_disposed || generation != _readGeneration) return;
      _setState(switch (result) {
        GraphResultSuccess(:final value) =>
          value.value == null
              ? const DailyChoicePathReplaceNotFound()
              : DailyChoicePathReplaceChoosing(value.value!),
        GraphResultFailure(:final failure) => DailyChoicePathReplaceReadFailed(
          failure,
        ),
      });
    } on Object {
      if (!_disposed && generation == _readGeneration) {
        _setState(
          const DailyChoicePathReplaceReadFailed(
            DailyChoiceReadUnexpectedFailure(),
          ),
        );
      }
    }
  }

  Future<void> _finish(Future<DailyChoiceCommandCompletion> future) async {
    try {
      final completion = await future;
      if (_disposed || !identical(_activeToken, completion.token)) return;
      _activeToken = null;
      final current = _state;
      if (current is! DailyChoicePathReplaceSubmitting) return;
      switch (completion.result) {
        case GraphResultSuccess(value: DailyChoicePathReplaced(:final choice)):
          _setState(DailyChoicePathReplaceSucceeded(choice));
        case GraphResultSuccess():
          _setState(
            DailyChoicePathReplaceRejected(
              current.details,
              current.proposal,
              const DailyChoiceUnexpectedFailure(),
            ),
          );
        case GraphResultFailure(:final failure):
          _failureToken = completion.token;
          final claim = _coordinator.claimInitiatorFailure(completion.token);
          _setState(
            failure is DailyChoiceNotFoundFailure
                ? DailyChoicePathReplaceNotFound(failurePresentation: claim)
                : DailyChoicePathReplaceRejected(
                    current.details,
                    current.proposal,
                    failure,
                    failurePresentation: claim,
                  ),
          );
      }
    } on Object {
      if (_disposed) return;
      final token = _activeToken;
      _activeToken = null;
      if (token != null) _coordinator.releaseInitiatorPresentation(token);
      final current = _state;
      if (current is DailyChoicePathReplaceSubmitting) {
        _setState(
          DailyChoicePathReplaceRejected(
            current.details,
            current.proposal,
            const DailyChoiceUnexpectedFailure(),
          ),
        );
      }
    }
  }

  void _releaseFailure() {
    final token = _failureToken;
    _failureToken = null;
    if (token != null) _coordinator.releaseInitiatorPresentation(token);
  }

  void _setState(DailyChoicePathReplaceState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_readGeneration;
    final token = _activeToken;
    if (token != null) _coordinator.releaseInitiatorPresentation(token);
    _releaseFailure();
    super.dispose();
  }
}
