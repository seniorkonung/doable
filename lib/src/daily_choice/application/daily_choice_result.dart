import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../domain/daily_choice.dart';

sealed class DailyChoiceCommandFailure implements GraphCommandFailure {
  const DailyChoiceCommandFailure();
}

enum DailyChoiceValidationField {
  sourceIntention,
  selectedIntention,
  date,
  description,
  path,
}

final class DailyChoiceValidationFailure extends DailyChoiceCommandFailure {
  const DailyChoiceValidationFailure(this.field);

  final DailyChoiceValidationField field;

  @override
  GraphFailureCategory get category => GraphFailureCategory.validation;
}

final class DailyChoiceNotFoundFailure extends DailyChoiceCommandFailure {
  const DailyChoiceNotFoundFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

enum DailyChoiceConflictReason {
  participantArchived,
  relationArchived,
  selectedIntentionNotReady,
  confirmedPathChanged,
  dependencyChanged,
}

final class DailyChoiceConflictFailure extends DailyChoiceCommandFailure {
  const DailyChoiceConflictFailure(this.reason);

  final DailyChoiceConflictReason reason;

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class DailyChoiceUnavailableFailure extends DailyChoiceCommandFailure {
  const DailyChoiceUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class DailyChoiceCorruptionFailure extends DailyChoiceCommandFailure {
  const DailyChoiceCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class DailyChoiceUnexpectedFailure extends DailyChoiceCommandFailure {
  const DailyChoiceUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

/// Репозиторий возвращает успех только после commit целой операции. Весь пакет
/// изменений относится к одной подтверждённой ревизии. Отказ и операция без
/// фактических изменений не публикуют новый пакет и не продвигают ревизию.
sealed class DailyChoiceCommandSuccess implements GraphCommandOutcome {
  DailyChoiceCommandSuccess({required Iterable<GraphChange> changes})
    : changes = List<GraphChange>.unmodifiable(changes);

  @override
  final List<GraphChange> changes;
}

final class DailyChoiceCreated extends DailyChoiceCommandSuccess {
  DailyChoiceCreated({
    required this.choice,
    required this.path,
    required super.changes,
  });

  final DailyChoice choice;
  final StoredChoicePath path;
}

final class DailyChoiceFieldsUpdated extends DailyChoiceCommandSuccess {
  DailyChoiceFieldsUpdated({
    required this.before,
    required this.choice,
    required this.path,
    required super.changes,
  });

  final DailyChoice before;
  final DailyChoice choice;
  final StoredChoicePath path;
}

final class DailyChoicePathReplaced extends DailyChoiceCommandSuccess {
  DailyChoicePathReplaced({
    required this.before,
    required this.choice,
    required this.path,
    required super.changes,
  });

  final DailyChoice before;
  final DailyChoice choice;
  final StoredChoicePath path;
}

final class DailyChoiceDeleted extends DailyChoiceCommandSuccess {
  DailyChoiceDeleted({required this.choice, required super.changes});

  final DailyChoice choice;
}

typedef DailyChoiceCommandResult =
    GraphCommandResult<DailyChoiceCommandSuccess, DailyChoiceCommandFailure>;
