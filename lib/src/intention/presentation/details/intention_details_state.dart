import '../../../graph/application/graph_revision.dart';
import '../../application/intention_details.dart' as application;
import '../../domain/intention.dart';

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
    this.isAwaitingConfirmedSnapshot = false,
  });

  final application.IntentionDetails details;
  final GraphRevision revision;
  Intention get intention => details.intention;

  /// Подтверждённое изменение этого намерения уже опубликовано, а снимок с
  /// ним ещё не принят: показанные поля старше последнего подтверждённого
  /// текста, и правка по ним открываться не должна.
  final bool isAwaitingConfirmedSnapshot;

  IntentionDetailsLoaded copyWith({
    application.IntentionDetails? details,
    GraphRevision? revision,
    bool? isOperationRunning,
    bool? isAwaitingConfirmedSnapshot,
  }) => IntentionDetailsLoaded(
    details: details ?? this.details,
    revision: revision ?? this.revision,
    isOperationRunning: isOperationRunning ?? this.isOperationRunning,
    isAwaitingConfirmedSnapshot:
        isAwaitingConfirmedSnapshot ?? this.isAwaitingConfirmedSnapshot,
  );
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
