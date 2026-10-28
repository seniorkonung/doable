import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../application/intention_details.dart' as application;
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../operation/operation_state.dart';

sealed class IntentionDetailsState {
  const IntentionDetailsState({required this.isOperationRunning});

  final bool isOperationRunning;
}

final class IntentionDetailsLoading extends IntentionDetailsState {
  const IntentionDetailsLoading({required super.isOperationRunning});
}

final class IntentionDetailsLoaded extends IntentionDetailsState {
  const IntentionDetailsLoaded({
    required this.details,
    required this.revision,
    required super.isOperationRunning,
    this.stateChange,
  });

  final application.IntentionDetails details;
  final GraphRevision revision;
  Intention get intention => details.intention;
  final IntentionDetailsStateChange? stateChange;

  IntentionDetailsLoaded copyWith({
    application.IntentionDetails? details,
    GraphRevision? revision,
    bool? isOperationRunning,
    IntentionDetailsStateChange? stateChange,
    bool clearStateChange = false,
  }) => IntentionDetailsLoaded(
    details: details ?? this.details,
    revision: revision ?? this.revision,
    isOperationRunning: isOperationRunning ?? this.isOperationRunning,
    stateChange: clearStateChange ? null : stateChange ?? this.stateChange,
  );
}

enum IntentionDetailsStateChangeKind {
  enableReadiness,
  disableReadiness,
  archive,
  restore,
  delete,
}

final class IntentionDetailsStateChange {
  const IntentionDetailsStateChange.running(this.kind)
    : operation = const OperationRunning<Intention>(),
      failurePresentation = null;

  IntentionDetailsStateChange.failed(
    this.kind,
    IntentionFailure failure, {
    this.failurePresentation,
  }) : operation = OperationFailed<Intention>(failure);

  final IntentionDetailsStateChangeKind kind;
  final OperationState<Intention> operation;

  /// Право открытого просмотра предъявить ошибку перехода по видимому кадру.
  final GraphInitiatorPresentationClaim? failurePresentation;

  bool get canRetry => switch (operation) {
    OperationFailed<Intention>(failure: IntentionUnavailableFailure()) => true,
    OperationIdle<Intention>() ||
    OperationRunning<Intention>() ||
    OperationSucceeded<Intention>() ||
    OperationFailed<Intention>() => false,
  };
}

final class IntentionDetailsNotFound extends IntentionDetailsState {
  const IntentionDetailsNotFound({required super.isOperationRunning});
}

final class IntentionDetailsUnavailable extends IntentionDetailsState {
  const IntentionDetailsUnavailable({required super.isOperationRunning});
}

final class IntentionDetailsCorruption extends IntentionDetailsState {
  const IntentionDetailsCorruption({required super.isOperationRunning});
}

final class IntentionDetailsUnexpected extends IntentionDetailsState {
  const IntentionDetailsUnexpected({required super.isOperationRunning});
}

final class IntentionDetailsDeleted extends IntentionDetailsState {
  const IntentionDetailsDeleted() : super(isOperationRunning: false);
}
