import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../application/intention_command.dart';
import '../../application/intention_catalog.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../operation/operation_state.dart';
import 'intention_editor_state.dart';

part 'intention_editor_view_model.g.dart';

@riverpod
final class IntentionEditorViewModel extends _$IntentionEditorViewModel {
  late GraphCommandCoordinator _coordinator;
  late IntentionCreationFormKey _formKey;
  IntentionOperationToken? _activeToken;
  IntentionOperationToken? _failureToken;

  @override
  IntentionEditorState build(IntentionCreationFormKey formKey) {
    _formKey = formKey;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    ref.onDispose(() {
      final activeToken = _activeToken;
      if (activeToken != null) {
        _coordinator.releaseInitiatorPresentation(activeToken);
      }
      _releaseFailurePresentation();
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

    final description = state.description;
    final start = _coordinator.acceptCreation(
      _formKey,
      CreateIntention(
        title: state.title,
        description: description.isEmpty ? null : description,
      ),
    );
    switch (start) {
      case IntentionCommandAccepted(:final token, :final future):
        _releaseFailurePresentation();
        _activeToken = token;
        state = state.withOperation(const OperationRunning<Intention>());
        unawaited(_finish(future));
      case IntentionCommandAlreadyRunning():
        return;
      case GraphCommandCoordinatorDraining():
        state = state.withOperation(
          const OperationFailed<Intention>(IntentionUnexpectedFailure()),
        );
    }
  }

  void consumeEvent() {
    if (state.event != null) {
      state = state.withoutEvent();
    }
  }

  Future<void> _finish(Future<IntentionCommandCompletion> future) async {
    try {
      final completion = await future;
      if (!ref.mounted || !identical(_activeToken, completion.token)) {
        return;
      }

      _activeToken = null;
      // Success предъявляет оболочка; форма получает его только для закрытия.
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
          failurePresentation: _claimFailure(completion.token),
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

  IntentionInitiatorPresentationClaim? _claimFailure(
    IntentionOperationToken token,
  ) {
    final claim = _coordinator.claimInitiatorFailure(token);
    if (claim != null) {
      _failureToken = token;
    }
    return claim;
  }

  void _releaseFailurePresentation() {
    final token = _failureToken;
    _failureToken = null;
    if (token != null) {
      _coordinator.releaseInitiatorPresentation(token);
    }
  }
}
