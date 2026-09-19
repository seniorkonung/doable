import '../../graph/application/graph_command_result.dart';
import '../domain/intention_id.dart';
import '../domain/intention_text.dart';

enum IntentionFailureCode {
  validation,
  notFound,
  conflict,
  unavailable,
  corruption,
  unexpected,
}

sealed class IntentionFailure implements GraphCommandFailure {
  const IntentionFailure();

  IntentionFailureCode get code;

  @override
  GraphFailureCategory get category => switch (code) {
    IntentionFailureCode.validation => GraphFailureCategory.validation,
    IntentionFailureCode.notFound => GraphFailureCategory.notFound,
    IntentionFailureCode.conflict => GraphFailureCategory.conflict,
    IntentionFailureCode.unavailable => GraphFailureCategory.unavailable,
    IntentionFailureCode.corruption => GraphFailureCategory.corruption,
    IntentionFailureCode.unexpected => GraphFailureCategory.unexpected,
  };
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

final class IntentionHasBlockingRelationsFailure extends IntentionFailure {
  const IntentionHasBlockingRelationsFailure(this.intentionId);

  final IntentionId intentionId;

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

typedef Result<T> = GraphResult<T, IntentionFailure>;
typedef ResultSuccess<T> = GraphResultSuccess<T, IntentionFailure>;
typedef ResultFailure<T> = GraphResultFailure<T, IntentionFailure>;
