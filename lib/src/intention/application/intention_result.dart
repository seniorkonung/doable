import '../domain/intention.dart';
import '../domain/intention_id.dart';

sealed class Result<T> {
  const Result();
}

final class ResultSuccess<T> extends Result<T> {
  const ResultSuccess(this.value);

  final T value;
}

final class ResultFailure<T> extends Result<T> {
  const ResultFailure(this.failure);

  final IntentionFailure failure;
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

enum IntentionFailureCode {
  validation,
  notFound,
  conflict,
  unavailable,
  corruption,
}

sealed class IntentionFailure {
  const IntentionFailure();

  IntentionFailureCode get code;
}

final class IntentionValidationFailure extends IntentionFailure {
  const IntentionValidationFailure();

  @override
  IntentionFailureCode get code => IntentionFailureCode.validation;
}

final class IntentionNotFoundFailure extends IntentionFailure {
  const IntentionNotFoundFailure();

  @override
  IntentionFailureCode get code => IntentionFailureCode.notFound;
}

final class IntentionConflictFailure extends IntentionFailure {
  const IntentionConflictFailure();

  @override
  IntentionFailureCode get code => IntentionFailureCode.conflict;
}

final class IntentionUnavailableFailure extends IntentionFailure {
  const IntentionUnavailableFailure();

  @override
  IntentionFailureCode get code => IntentionFailureCode.unavailable;
}

final class IntentionCorruptionFailure extends IntentionFailure {
  const IntentionCorruptionFailure();

  @override
  IntentionFailureCode get code => IntentionFailureCode.corruption;
}

final class IntentionRepositoryException implements Exception {
  const IntentionRepositoryException(this.failure);

  final IntentionFailure failure;
}
