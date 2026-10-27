import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../daily_choice/presentation/daily_choice_command_failure_message.dart';
import '../../data_transfer/presentation/graph_import_failure_message.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_result.dart';
import '../../long_term_relation/application/long_term_relation_command.dart';
import '../../long_term_relation/presentation/relation_command_failure_message.dart';
import '../../shared/presentation/presentation_frame_evidence.dart';
import '../../tag/presentation/tag_failure_message.dart';
import '../application/graph_command_coordinator.dart';
import '../application/graph_command_result.dart';
import 'graph_operation_message_plan.dart';

/// Единственный владелец общей поверхности сообщений результатов операций.
///
/// Показывает в [ScaffoldMessenger] не больше одного сообщения, ждёт его
/// закрытия и только затем запрашивает у coordinator следующий результат.
/// Новый результат не снимает текущее сообщение.
///
/// Сообщение рисуется в каждом корневом `Scaffold` под [ScaffoldMessenger].
/// Лист, показанный `showDoableSheet` с `hostsMessages`, держит собственный
/// `Scaffold`, и сообщение появляется над его нижней частью. У прочих листов и у диалога своего `Scaffold` нет,
/// поэтому сообщение остаётся на странице под ними. Предъявленным оно считается только на верхнем маршруте: до закрытия
/// перекрывшего маршрута результат ждёт, а обычное время показа отсчитывается
/// с первого кадра, в котором сообщение видно.
///
/// Что предъявлять, решает coordinator: ручная копия и операции тегов
/// приходят сюда только отказом (ADR-0016).
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
    surface?.cancelDisplayTimer();
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
  Widget build(BuildContext context) {
    final theme = SnackBarTheme.of(context);
    // Клавиатура сокращает область Scaffold: плавающее сообщение может
    // выйти за её пределы. Тема меняет размещение и уже показанного сообщения.
    // https://api.flutter.dev/flutter/material/ScaffoldMessengerState/showSnackBar.html
    return SnackBarTheme(
      data: theme.copyWith(
        behavior: MediaQuery.viewInsetsOf(context).bottom > 0
            ? SnackBarBehavior.fixed
            : theme.behavior,
      ),
      child: widget.child,
    );
  }

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

    final localizations = AppLocalizations.of(context);
    final plan = planGraphOperationMessage(
      surface.claim.completions,
      (completion) => _messageFor(localizations, completion),
    );
    final message = plan.otherCount == 0
        ? plan.message.text
        : localizations.graphOperationMessageWithOthers(
            plan.message.text,
            plan.otherCount,
          );
    final action = plan.message.action;
    surface.plan = plan;
    final controller = messenger.showSnackBar(
      SnackBar(
        dismissDirection: DismissDirection.horizontal,
        // Время показа отсчитывает presenter: таймер ScaffoldMessenger над
        // навигатором идёт и тогда, когда сообщение перекрыто листом или
        // диалогом. Действие показ не продлевает, в том числе при экранном
        // дикторе.
        persist: true,
        onVisible: () => _handleEntered(surface, plan),
        action: action == null
            ? null
            : SnackBarAction(label: action.label, onPressed: action.onPressed),
        content: PresentationFrameEvidence<GraphOperationMessagePlan>(
          subject: plan,
          onPresented: (shownPlan) => _confirm(surface, shownPlan),
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

  /// Появление сообщения завершилось; `onVisible` приходит от каждого
  /// `Scaffold`, показывающего сообщение.
  void _handleEntered(
    _PresentationSurface surface,
    GraphOperationMessagePlan plan,
  ) {
    if (_isDisposed ||
        !identical(_surface, surface) ||
        !identical(surface.plan, plan) ||
        surface.isEntered) {
      return;
    }
    surface.isEntered = true;
    // Видимое приложение с фокусом подтверждает сообщение ещё во время
    // появления. Неподтверждённое к его концу сообщение не видно на верхнем
    // маршруте, например под листом или диалогом, и время показа начнётся
    // с его предъявления.
    if (surface.isConfirmed || !_isResumed) {
      _startDisplayTimer(surface);
    }
  }

  void _startDisplayTimer(_PresentationSurface surface) {
    surface.displayTimer = Timer(
      _displayDuration,
      () => _handleDisplayTimeout(surface),
    );
  }

  void _handleDisplayTimeout(_PresentationSurface surface) {
    if (_isDisposed || !identical(_surface, surface)) {
      return;
    }
    surface.displayTimer = null;
    if (!surface.isConfirmed && _isResumed) {
      // Сообщение не видно на верхнем маршруте и ждёт закрытия маршрута,
      // который его перекрыл.
      return;
    }
    // Сообщение, не подтверждённое в приложении без фокуса, закрывается и
    // показывается снова по возвращении фокуса.
    final messenger = surface.messenger;
    if (messenger != null && messenger.mounted) {
      messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.timeout);
    }
  }

  bool get _isResumed =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _confirm(_PresentationSurface surface, GraphOperationMessagePlan plan) {
    if (_isDisposed ||
        !identical(_surface, surface) ||
        !identical(surface.plan, plan) ||
        surface.isConfirmed) {
      return;
    }
    surface.isConfirmed = true;
    _coordinator.confirmAppPresentation(surface.claim, plan.coveredTokens);
    if (surface.isEntered && surface.displayTimer == null) {
      // Перекрывший маршрут закрыт: сообщение видно обычное время с этого
      // кадра.
      _startDisplayTimer(surface);
    }
  }

  void _handleClosed(_PresentationSurface surface) {
    if (_isDisposed || !identical(_surface, surface)) {
      return;
    }
    surface
      ..cancelDisplayTimer()
      ..plan = null
      ..messenger = null
      ..controller = null
      ..isEntered = false;
    if (surface.isConfirmed) {
      _surface = null;
      _requestNext();
    } else {
      // Сообщение исчезло до доступного кадра: результат ещё не предъявлен.
      _showIfSuitable();
    }
  }
}

/// Обычное время показа сообщения — время показа [SnackBar] по умолчанию.
const _displayDuration = Duration(milliseconds: 4000);

/// Текущая поверхность результата; живёт до закрытия сообщения, даже после
/// подтверждения предъявления, и не образует журнал предъявленных tokens.
final class _PresentationSurface {
  _PresentationSurface(this.claim);

  final GraphAppPresentationClaim claim;
  GraphOperationMessagePlan? plan;
  ScaffoldMessengerState? messenger;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? controller;
  var isConfirmed = false;

  /// Появление текущего сообщения завершилось.
  var isEntered = false;

  /// Отсчёт времени показа; `null`, пока отсчёт не начат или уже завершён.
  Timer? displayTimer;

  void cancelDisplayTimer() {
    displayTimer?.cancel();
    displayTimer = null;
  }

  void remove() {
    final currentMessenger = messenger;
    messenger = null;
    controller = null;
    plan = null;
    if (currentMessenger != null && currentMessenger.mounted) {
      // Presenter — единственный владелец поверхности и держит не больше одного
      // сообщения, поэтому текущее сообщение принадлежит этой регистрации.
      currentMessenger.removeCurrentSnackBar();
    }
  }
}

GraphOperationMessage _messageFor(
  AppLocalizations localizations,
  GraphPresentableCompletion completion,
) => switch (completion) {
  IntentionCommandCompletion() => GraphOperationMessage(
    _intentionMessage(localizations, completion),
  ),
  LongTermRelationCommandCompletion() => GraphOperationMessage(
    _relationMessage(localizations, completion),
  ),
  DailyChoiceCommandCompletion() => GraphOperationMessage(
    _dailyChoiceMessage(localizations, completion),
  ),
  TagCommandFailedCompletion() => GraphOperationMessage(
    _tagFailureMessage(localizations, completion),
  ),
  GraphExportCompletion() => _exportMessage(localizations, completion),
  GraphBackupRestoreCompletion() => GraphOperationMessage(
    _backupRestoreMessage(localizations, completion),
  ),
  GraphImportCompletion() => GraphOperationMessage(
    _importMessage(localizations, completion),
  ),
  GraphManualBackupFailedCompletion() => GraphOperationMessage(
    localizations.dataManualBackupFailed,
  ),
};

String _backupRestoreMessage(
  AppLocalizations localizations,
  GraphBackupRestoreCompletion completion,
) => switch (completion.result) {
  GraphBackupRestored() => localizations.dataBackupRestored,
  GraphBackupRestoreFailed() => localizations.dataBackupRestoreFailed,
  GraphBackupRestoreStorageFull() => localizations.dataReplacementStorageFull,
};

/// Отказ импорта показывается здесь без действия: исправить его можно из
/// строки «Импорт данных».
String _importMessage(
  AppLocalizations localizations,
  GraphImportCompletion completion,
) => switch (completion.result) {
  GraphImported() => localizations.dataImported,
  GraphImportFailed(:final failure) => graphImportFailureMessage(
    localizations,
    failure,
  ),
};

GraphOperationMessage _exportMessage(
  AppLocalizations localizations,
  GraphExportCompletion completion,
) {
  GraphOperationMessage withRetry(String text) => GraphOperationMessage(
    text,
    action: GraphOperationMessageAction(
      label: localizations.commonRetry,
      onPressed: completion.retry,
    ),
  );
  return switch (completion.outcome) {
    GraphExportOutcome.succeeded => GraphOperationMessage(
      localizations.dataExportSaved,
    ),
    GraphExportOutcome.failed => withRetry(localizations.dataExportFailed),
    GraphExportOutcome.existingFile => withRetry(
      localizations.dataExportExistingFile,
    ),
  };
}

String _tagFailureMessage(
  AppLocalizations localizations,
  TagCommandFailedCompletion completion,
) => localizations.graphOperationMessage(
  switch (completion.kind) {
    TagCommandKind.create => localizations.graphOperationCreate,
    TagCommandKind.update => localizations.graphOperationUpdate,
    TagCommandKind.delete => localizations.graphOperationDelete,
    TagCommandKind.move => localizations.graphOperationMoveTag,
    TagCommandKind.assign => localizations.graphOperationAssignTag,
    TagCommandKind.removeAssignment =>
      localizations.graphOperationRemoveTagAssignment,
  },
  switch (completion.kind) {
    TagCommandKind.assign || TagCommandKind.removeAssignment =>
      localizations.graphOperationTagAssignment,
    _ => localizations.graphOperationTag,
  },
  switch (completion.kind) {
    TagCommandKind.assign || TagCommandKind.removeAssignment =>
      tagAssignmentFailureMessage(localizations, completion.failure),
    _ => tagFailureMessage(localizations, completion.failure),
  },
);

String _dailyChoiceMessage(
  AppLocalizations localizations,
  DailyChoiceCommandCompletion completion,
) => localizations.graphOperationMessage(
  switch (completion.kind) {
    DailyChoiceCommandKind.create => localizations.graphOperationCreate,
    DailyChoiceCommandKind.update ||
    DailyChoiceCommandKind.replace => localizations.graphOperationUpdate,
    DailyChoiceCommandKind.delete => localizations.graphOperationDelete,
  },
  localizations.graphOperationDailyChoice,
  switch (completion.result) {
    GraphResultSuccess() => switch (completion.kind) {
      DailyChoiceCommandKind.create => localizations.dailyChoiceCreated,
      DailyChoiceCommandKind.update => localizations.dailyChoiceUpdated,
      DailyChoiceCommandKind.replace => localizations.dailyChoicePathReplaced,
      DailyChoiceCommandKind.delete => localizations.dailyChoiceDeleted,
    },
    GraphResultFailure(:final failure) => dailyChoiceCommandFailureMessage(
      localizations,
      failure,
    ),
  },
);

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
