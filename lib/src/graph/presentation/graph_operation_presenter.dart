import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_result.dart';
import '../../long_term_relation/application/long_term_relation_command.dart';
import '../../long_term_relation/presentation/relation_command_failure_message.dart';
import '../../shared/presentation/presentation_frame_evidence.dart';
import '../application/graph_command_coordinator.dart';
import '../application/graph_command_result.dart';

/// Единственный владелец общей поверхности сообщений результатов операций.
///
/// Показывает в [ScaffoldMessenger] не больше одного сообщения, ждёт его
/// закрытия и только затем запрашивает у coordinator следующий результат.
/// Новый результат не снимает текущее сообщение.
final class GraphOperationPresenter extends ConsumerStatefulWidget {
  const GraphOperationPresenter({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<GraphOperationPresenter> createState() =>
      _GraphOperationPresenterState();
}

final class _GraphOperationPresenterState
    extends ConsumerState<GraphOperationPresenter>
    with WidgetsBindingObserver {
  late final GraphCommandCoordinator _coordinator;
  late final GraphAppPresentationRegistration _registration;
  _PresentationSurface? _surface;
  var _isRequesting = false;
  var _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(graphCommandCoordinatorProvider.notifier);
    _registration = _coordinator.registerAppPresentation();
    WidgetsBinding.instance.addObserver(this);
    _requestNext();
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final surface = _surface;
    _surface = null;
    final registration = _registration;
    // Снятие сообщения меняет состояние ScaffoldMessenger, что запрещено при
    // финализации дерева. Поэтому поверхность снимается после кадра, и только
    // затем coordinator возвращает право следующему presenter.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      surface?.remove();
      registration.release();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _requestNext() {
    if (_isDisposed || _isRequesting || _surface != null) {
      return;
    }
    _isRequesting = true;
    unawaited(
      _registration.nextClaim().then((claim) {
        _isRequesting = false;
        if (_isDisposed || claim == null) {
          return;
        }
        _surface = _PresentationSurface(claim);
        _showIfSuitable();
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _showIfSuitable();
    }
  }

  void _showIfSuitable() {
    final surface = _surface;
    if (_isDisposed ||
        !mounted ||
        surface == null ||
        surface.controller != null ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _showIfSuitable());
      return;
    }

    final message = _messageFor(
      AppLocalizations.of(context),
      surface.claim.completion,
    );
    final controller = messenger.showSnackBar(
      SnackBar(
        content: PresentationFrameEvidence<GraphAppPresentationClaim>(
          subject: surface.claim,
          requiresCurrentRoute: false,
          onPresented: (_) => _confirm(surface),
          child: Semantics(
            key: const ValueKey('graph-operation-message'),
            container: true,
            liveRegion: true,
            label: message,
            child: ExcludeSemantics(child: Text(message)),
          ),
        ),
      ),
    );
    surface
      ..messenger = messenger
      ..controller = controller;
    unawaited(controller.closed.then((_) => _handleClosed(surface)));
  }

  void _confirm(_PresentationSurface surface) {
    if (_isDisposed || !identical(_surface, surface) || surface.isConfirmed) {
      return;
    }
    surface.isConfirmed = true;
    _coordinator.confirmPresentation(surface.claim);
  }

  void _handleClosed(_PresentationSurface surface) {
    if (_isDisposed || !identical(_surface, surface)) {
      return;
    }
    surface
      ..messenger = null
      ..controller = null;
    if (surface.isConfirmed) {
      _surface = null;
      _requestNext();
    } else {
      // Сообщение исчезло до доступного кадра: результат ещё не предъявлен.
      _showIfSuitable();
    }
  }
}

/// Текущая поверхность результата; живёт до закрытия сообщения, даже после
/// подтверждения предъявления, и не образует журнал предъявленных tokens.
final class _PresentationSurface {
  _PresentationSurface(this.claim);

  final GraphAppPresentationClaim claim;
  ScaffoldMessengerState? messenger;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? controller;
  var isConfirmed = false;

  void remove() {
    final currentMessenger = messenger;
    messenger = null;
    controller = null;
    if (currentMessenger != null && currentMessenger.mounted) {
      // Presenter — единственный владелец поверхности и держит не больше одного
      // сообщения, поэтому текущее сообщение принадлежит этой регистрации.
      currentMessenger.removeCurrentSnackBar();
    }
  }
}

String _messageFor(
  AppLocalizations localizations,
  GraphCommandCompletion completion,
) => switch (completion) {
  IntentionCommandCompletion() => _intentionMessage(localizations, completion),
  LongTermRelationCommandCompletion() => _relationMessage(
    localizations,
    completion,
  ),
};

String _intentionMessage(
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
    _intentionOutcomeFor(localizations, completion),
  );
}

/// Связь не имеет собственного пользовательского названия, поэтому сообщение
/// опирается только на локализованное обозначение вида операции и её предмета.
String _relationMessage(
  AppLocalizations localizations,
  LongTermRelationCommandCompletion completion,
) {
  final operation = switch (completion.kind) {
    LongTermRelationCommandKind.create => localizations.graphOperationCreate,
    LongTermRelationCommandKind.update => localizations.graphOperationUpdate,
    LongTermRelationCommandKind.archive => localizations.graphOperationArchive,
    LongTermRelationCommandKind.restore => localizations.graphOperationRestore,
    LongTermRelationCommandKind.delete => localizations.graphOperationDelete,
  };
  final target = switch (completion.target) {
    CreatingLongTermRelationOperationTarget() =>
      localizations.graphOperationNewRelation,
    ExistingLongTermRelationOperationTarget() =>
      localizations.graphOperationRelation,
  };
  return localizations.graphOperationMessage(
    operation,
    target,
    _relationOutcomeFor(localizations, completion),
  );
}

String _relationOutcomeFor(
  AppLocalizations localizations,
  LongTermRelationCommandCompletion completion,
) => switch (completion.result) {
  GraphResultSuccess(:final value) => switch ((completion.kind, value)) {
    (LongTermRelationCommandKind.create, LongTermRelationCreated()) =>
      localizations.relationEditorCreated,
    (LongTermRelationCommandKind.create, LongTermRelationUpdated()) =>
      localizations.relationEditorCreateUnexpected,
    (LongTermRelationCommandKind.create, LongTermRelationDeleted()) =>
      localizations.relationEditorCreateUnexpected,
    (LongTermRelationCommandKind.update, LongTermRelationUpdated()) =>
      localizations.relationEditorUpdated,
    (LongTermRelationCommandKind.update, LongTermRelationCreated()) =>
      localizations.relationEditorUpdateUnexpected,
    (LongTermRelationCommandKind.update, LongTermRelationDeleted()) =>
      localizations.relationEditorUpdateUnexpected,
    (LongTermRelationCommandKind.archive, LongTermRelationUpdated()) =>
      localizations.relationArchived,
    (LongTermRelationCommandKind.archive, LongTermRelationCreated()) =>
      localizations.relationArchiveUnexpected,
    (LongTermRelationCommandKind.archive, LongTermRelationDeleted()) =>
      localizations.relationArchiveUnexpected,
    (LongTermRelationCommandKind.restore, LongTermRelationUpdated()) =>
      localizations.relationRestored,
    (LongTermRelationCommandKind.restore, LongTermRelationCreated()) =>
      localizations.relationRestoreUnexpected,
    (LongTermRelationCommandKind.restore, LongTermRelationDeleted()) =>
      localizations.relationRestoreUnexpected,
    (LongTermRelationCommandKind.delete, LongTermRelationDeleted()) =>
      localizations.relationDeleted,
    (LongTermRelationCommandKind.delete, LongTermRelationCreated()) ||
    (
      LongTermRelationCommandKind.delete,
      LongTermRelationUpdated(),
    ) => localizations.relationDeleteUnexpected,
  },
  GraphResultFailure(:final failure) => longTermRelationCommandFailureMessage(
    localizations,
    completion.kind,
    failure,
  ),
};

String _intentionOutcomeFor(
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
    IntentionHasBlockingRelationsFailure() =>
      localizations.editorCreateUnexpected,
    IntentionUnavailableFailure() => localizations.editorCreateUnavailable,
    IntentionCorruptionFailure() => localizations.editorCreateCorruption,
    IntentionNotFoundFailure() ||
    IntentionUnexpectedFailure() => localizations.editorCreateUnexpected,
  },
  IntentionCommandKind.update => switch (failure) {
    IntentionValidationFailure() => localizations.detailsUpdateInvalidInput,
    IntentionNotFoundFailure() => localizations.detailsUpdateNotFound,
    IntentionConflictFailure() => localizations.detailsUpdateConflict,
    IntentionHasBlockingRelationsFailure() =>
      localizations.detailsUpdateUnexpected,
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
    IntentionHasBlockingRelationsFailure() =>
      localizations.detailsStateChangeUnexpected,
    IntentionUnavailableFailure() =>
      localizations.detailsStateChangeUnavailable,
    IntentionCorruptionFailure() => localizations.detailsStateChangeCorruption,
    IntentionUnexpectedFailure() => localizations.detailsStateChangeUnexpected,
  },
  IntentionCommandKind.delete => switch (failure) {
    IntentionValidationFailure() => localizations.detailsDeleteInvalid,
    IntentionNotFoundFailure() => localizations.detailsDeleteNotFound,
    IntentionConflictFailure() => localizations.detailsDeleteConflict,
    IntentionHasBlockingRelationsFailure() =>
      localizations.detailsDeleteBlockedByRelations,
    IntentionUnavailableFailure() => localizations.detailsDeleteUnavailable,
    IntentionCorruptionFailure() => localizations.detailsDeleteCorruption,
    IntentionUnexpectedFailure() => localizations.detailsDeleteUnexpected,
  },
};
