import '../domain/intention_text.dart';

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

enum IntentionFailureCode {
  validation,
  notFound,
  conflict,
  unavailable,
  corruption,
  unexpected,
}

sealed class IntentionFailure {
  const IntentionFailure();

  IntentionFailureCode get code;
}

sealed class IntentionValidationFailure extends IntentionFailure {
  const IntentionValidationFailure();

  @override
  IntentionFailureCode get code => IntentionFailureCode.validation;
}

final class IntentionGenericValidationFailure
    extends IntentionValidationFailure {
  const IntentionGenericValidationFailure();
}

final class IntentionTextInputValidationFailure
    extends IntentionValidationFailure {
  const IntentionTextInputValidationFailure(this.textFailure);

  final IntentionTextValidationFailure textFailure;
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

final class IntentionUnexpectedFailure extends IntentionFailure {
  const IntentionUnexpectedFailure();

  @override
  IntentionFailureCode get code => IntentionFailureCode.unexpected;
}
