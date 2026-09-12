import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/presentation/exclusive_operation.dart';
import '../../application/intention_command.dart';
import '../../application/intention_repository.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../operation/intention_command_coordinator.dart';
import '../operation/operation_state.dart';
import 'intention_editor_state.dart';

part 'intention_editor_view_model.g.dart';

@riverpod
final class IntentionEditorViewModel extends _$IntentionEditorViewModel {
  final _submission = ExclusiveOperation<IntentionCommandCompletion>();
  late IntentionCommandCoordinator _coordinator;
  IntentionOperationToken? _activeToken;

  @override
  IntentionEditorState build(IntentionEditorSession session) {
    _coordinator = ref.watch(intentionCommandCoordinatorProvider.notifier);
    ref.onDispose(() {
      final token = _activeToken;
      if (token != null) {
        _coordinator.releaseInitiatorPresentation(token);
      }
    });
    return const IntentionEditorState.initial();
  }

  void changeTitle(String value) {
    if (state.title != value) {
      state = state.withTitle(value);
    }
  }

  void changeDescription(String value) {
    if (state.description != value) {
      state = state.withDescription(value);
    }
  }

  void submit() {
    if (!state.canSubmit) {
      return;
    }

    final started = _submission.start(_acceptCurrentValues);
    switch (started) {
      case ExclusiveOperationAlreadyRunning<IntentionCommandCompletion>():
        return;
      case ExclusiveOperationAccepted<IntentionCommandCompletion>(
        :final future,
      ):
        state = state.withOperation(const OperationRunning<Intention>());
        unawaited(_finish(future));
    }
  }

  void consumeEvent() {
    if (state.event != null) {
      state = state.withoutEvent();
    }
  }

  Future<IntentionCommandCompletion> _acceptCurrentValues() {
    final description = state.description;
    final start = _coordinator.accept(
      CreateIntention(
        title: state.title,
        description: description.isEmpty ? null : description,
      ),
    );
    return switch (start) {
      IntentionCommandAccepted(:final token, :final future) => () {
        _activeToken = token;
        return future;
      }(),
      IntentionCommandAlreadyRunning() ||
      IntentionCommandCoordinatorDraining() => Future.error(
        StateError('Coordinator не принял создание намерения.'),
      ),
    };
  }

  Future<void> _finish(Future<IntentionCommandCompletion> future) async {
    try {
      final completion = await future;
      if (!ref.mounted || !identical(_activeToken, completion.token)) {
        return;
      }

      final claim = _coordinator.claimInitiator(completion.token);
      if (claim == null) {
        return;
      }
      _activeToken = null;
      try {
        state = switch (completion.result) {
          ResultSuccess(value: IntentionSaved(:final intention)) =>
            state.withOperation(
              OperationSucceeded<Intention>(intention),
              event: const IntentionEditorCreated(),
            ),
          ResultSuccess(value: IntentionDeleted()) => state.withOperation(
            const OperationFailed<Intention>(IntentionUnexpectedFailure()),
          ),
          ResultFailure(:final failure) => state.withOperation(
            OperationFailed<Intention>(failure),
          ),
        };
      } finally {
        _coordinator.confirmPresentation(claim);
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
      state = state.withOperation(
        const OperationFailed<Intention>(IntentionUnexpectedFailure()),
      );
    }
  }
}
