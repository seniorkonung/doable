import '../../graph/application/graph_command_result.dart';
import '../../tag/domain/tag_id.dart';
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

/// Создание отклонено целиком: выбранные теги [missingTagIds] отсутствуют на
/// момент атомарной проверки.
///
/// Это исправляемая ошибка выбора, а не отсутствие намерения или повреждение
/// данных: исправление набора тегов разрешает новую проверку всей команды.
final class IntentionCreationTagsMissingFailure
    extends IntentionValidationFailure {
  IntentionCreationTagsMissingFailure(Iterable<TagId> missingTagIds)
    : missingTagIds = _requireNonEmpty(Set.unmodifiable(missingTagIds));

  /// Непустой неизменяемый набор отсутствующих идентификаторов.
  final Set<TagId> missingTagIds;

  static Set<TagId> _requireNonEmpty(Set<TagId> missingTagIds) {
    if (missingTagIds.isEmpty) {
      throw ArgumentError.value(
        missingTagIds,
        'missingTagIds',
        'Отказ отсутствующих тегов называет хотя бы один тег.',
      );
    }
    return missingTagIds;
  }
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
