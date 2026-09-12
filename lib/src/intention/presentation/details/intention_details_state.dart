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
    required this.intention,
    required super.isOperationRunning,
  });

  final Intention intention;
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
