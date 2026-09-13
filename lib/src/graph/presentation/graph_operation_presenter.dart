import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_result.dart';
import '../application/graph_command_coordinator.dart';

final class GraphOperationPresenter extends ConsumerStatefulWidget {
  const GraphOperationPresenter({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<GraphOperationPresenter> createState() =>
      _GraphOperationPresenterState();
}

final class _GraphOperationPresenterState
    extends ConsumerState<GraphOperationPresenter> {
  final _pending = Queue<IntentionAppPresentationClaim>();
  late final GraphCommandCoordinator _coordinator;
  late final StreamSubscription<IntentionCommandCompletion> _subscription;
  late final AppLifecycleListener _lifecycleListener;
  late bool _isVisible;
  var _presentationScheduled = false;

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(graphCommandCoordinatorProvider.notifier);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isVisible =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _handleLifecycleState,
    );
    _subscription = _coordinator.completions.listen(_handleCompletion);
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _handleCompletion(IntentionCommandCompletion completion) {
    unawaited(_claimPresentation(completion));
  }

  Future<void> _claimPresentation(IntentionCommandCompletion completion) async {
    final claim = await _coordinator.claimAppPresentation(completion.token);
    if (!mounted || claim == null) {
      return;
    }
    _pending.addLast(claim);
    _schedulePresentation();
  }

  void _handleLifecycleState(AppLifecycleState state) {
    _isVisible = state == AppLifecycleState.resumed;
    if (_isVisible) {
      _schedulePresentation();
    }
  }

  void _schedulePresentation() {
    if (!_isVisible || _pending.isEmpty || _presentationScheduled) {
      return;
    }
    _presentationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _presentationScheduled = false;
      _presentPending();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _presentPending() {
    if (!mounted || !_isVisible || _pending.isEmpty) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      _schedulePresentation();
      return;
    }

    final localizations = AppLocalizations.of(context);
    while (_isVisible && _pending.isNotEmpty) {
      final claim = _pending.removeFirst();
      final message = _messageFor(localizations, claim.completion);
      messenger.showSnackBar(
        SnackBar(
          content: Semantics(
            key: const ValueKey('graph-operation-message'),
            container: true,
            liveRegion: true,
            label: message,
            child: ExcludeSemantics(child: Text(message)),
          ),
        ),
      );
      _coordinator.confirmPresentation(claim);
    }
  }
}

String _messageFor(
  AppLocalizations localizations,
  IntentionCommandCompletion completion,
) {
  final operation = switch (completion.kind) {
    IntentionCommandKind.create => localizations.graphOperationCreate,
    IntentionCommandKind.update => localizations.graphOperationUpdate,
    IntentionCommandKind.enableReadiness =>
      localizations.graphOperationEnableReadiness,
    IntentionCommandKind.disableReadiness =>
      localizations.graphOperationDisableReadiness,
    IntentionCommandKind.archive => localizations.graphOperationArchive,
    IntentionCommandKind.restore => localizations.graphOperationRestore,
    IntentionCommandKind.delete => localizations.graphOperationDelete,
  };
  final target =
      completion.presentationTitle ??
      switch (completion.target) {
        CreatingIntentionOperationTarget() =>
          localizations.graphOperationNewIntention,
        ExistingIntentionOperationTarget() =>
          localizations.graphOperationIntention,
      };
  return localizations.graphOperationMessage(
    operation,
    target,
    _outcomeFor(localizations, completion),
  );
}

String _outcomeFor(
  AppLocalizations localizations,
  IntentionCommandCompletion completion,
) => switch (completion.result) {
  ResultSuccess(:final value) => _successFor(
    localizations,
    completion.kind,
    value,
  ),
  ResultFailure(:final failure) => _failureFor(
    localizations,
    completion.kind,
    failure,
  ),
};

String _successFor(
  AppLocalizations localizations,
  IntentionCommandKind kind,
  IntentionCommandSuccess success,
) => switch ((kind, success)) {
  (IntentionCommandKind.create, IntentionSaved()) =>
    localizations.editorCreated,
  (IntentionCommandKind.update, IntentionSaved()) => localizations.detailsSaved,
  (IntentionCommandKind.enableReadiness, IntentionSaved()) =>
    localizations.detailsReadinessEnabled,
  (IntentionCommandKind.disableReadiness, IntentionSaved()) =>
    localizations.detailsReadinessDisabled,
  (IntentionCommandKind.archive, IntentionSaved()) =>
    localizations.detailsArchivedSuccess,
  (IntentionCommandKind.restore, IntentionSaved()) =>
    localizations.detailsRestoredSuccess,
  (IntentionCommandKind.delete, IntentionDeleted()) =>
    localizations.detailsDeleted,
  (IntentionCommandKind.create, IntentionDeleted()) =>
    localizations.editorCreateUnexpected,
  (IntentionCommandKind.update, IntentionDeleted()) =>
    localizations.detailsUpdateUnexpected,
  (
    IntentionCommandKind.enableReadiness ||
        IntentionCommandKind.disableReadiness ||
        IntentionCommandKind.archive ||
        IntentionCommandKind.restore,
    IntentionDeleted(),
  ) =>
    localizations.detailsStateChangeUnexpected,
  (IntentionCommandKind.delete, IntentionSaved()) =>
    localizations.detailsDeleteUnexpected,
};

String _failureFor(
  AppLocalizations localizations,
  IntentionCommandKind kind,
  IntentionFailure failure,
) => switch (kind) {
  IntentionCommandKind.create => switch (failure) {
    IntentionValidationFailure() => localizations.editorInvalidInput,
    IntentionConflictFailure() => localizations.editorCreateConflict,
    IntentionUnavailableFailure() => localizations.editorCreateUnavailable,
    IntentionCorruptionFailure() => localizations.editorCreateCorruption,
    IntentionNotFoundFailure() ||
    IntentionUnexpectedFailure() => localizations.editorCreateUnexpected,
  },
  IntentionCommandKind.update => switch (failure) {
    IntentionValidationFailure() => localizations.detailsUpdateInvalidInput,
    IntentionNotFoundFailure() => localizations.detailsUpdateNotFound,
    IntentionConflictFailure() => localizations.detailsUpdateConflict,
    IntentionUnavailableFailure() => localizations.detailsUpdateUnavailable,
    IntentionCorruptionFailure() => localizations.detailsUpdateCorruption,
    IntentionUnexpectedFailure() => localizations.detailsUpdateUnexpected,
  },
  IntentionCommandKind.enableReadiness ||
  IntentionCommandKind.disableReadiness ||
  IntentionCommandKind.archive ||
  IntentionCommandKind.restore => switch (failure) {
    IntentionValidationFailure() => localizations.detailsStateChangeInvalid,
    IntentionNotFoundFailure() => localizations.detailsStateChangeNotFound,
    IntentionConflictFailure() => localizations.detailsStateChangeConflict,
    IntentionUnavailableFailure() =>
      localizations.detailsStateChangeUnavailable,
    IntentionCorruptionFailure() => localizations.detailsStateChangeCorruption,
    IntentionUnexpectedFailure() => localizations.detailsStateChangeUnexpected,
  },
  IntentionCommandKind.delete => switch (failure) {
    IntentionValidationFailure() => localizations.detailsDeleteInvalid,
    IntentionNotFoundFailure() => localizations.detailsDeleteNotFound,
    IntentionConflictFailure() => localizations.detailsDeleteConflict,
    IntentionUnavailableFailure() => localizations.detailsDeleteUnavailable,
    IntentionCorruptionFailure() => localizations.detailsDeleteCorruption,
    IntentionUnexpectedFailure() => localizations.detailsDeleteUnexpected,
  },
};
