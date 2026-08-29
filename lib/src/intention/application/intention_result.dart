import '../domain/intention.dart';
import '../domain/intention_id.dart';

sealed class Result<T> {
  const Result();

  const factory Result.success(T value) = ResultSuccess<T>;
  const factory Result.failure(IntentionRepositoryFailure failure) =
      ResultFailure<T>;
}

final class ResultSuccess<T> extends Result<T> {
  const ResultSuccess(this.value);

  final T value;
}

final class ResultFailure<T> extends Result<T> {
  const ResultFailure(this.failure);

  final IntentionRepositoryFailure failure;
}

sealed class IntentionCommandSuccess {
  const IntentionCommandSuccess();
}

final class IntentionSaved extends IntentionCommandSuccess {
  const IntentionSaved(this.intention);

  final Intention intention;
}

final class IntentionDeleted extends IntentionCommandSuccess {
  const IntentionDeleted(this.id);

  final IntentionId id;
}

sealed class IntentionRepositoryFailure {
  const IntentionRepositoryFailure();
}

enum IntentionValidationFailureCode {
  emptyTitle,
  titleTooLong,
  descriptionTooLong,
}

final class IntentionValidationFailure extends IntentionRepositoryFailure {
  const IntentionValidationFailure(this.code);

  final IntentionValidationFailureCode code;
}

final class IntentionNotFoundFailure extends IntentionRepositoryFailure {
  const IntentionNotFoundFailure(this.id);

  final IntentionId id;
}

final class IntentionConflictFailure extends IntentionRepositoryFailure {
  const IntentionConflictFailure();
}

final class IntentionUnavailableFailure extends IntentionRepositoryFailure {
  const IntentionUnavailableFailure();
}

final class IntentionCorruptionFailure extends IntentionRepositoryFailure {
  const IntentionCorruptionFailure();
}
