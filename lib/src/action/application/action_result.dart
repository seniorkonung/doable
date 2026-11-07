import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../domain/action.dart';

sealed class ActionCommandFailure implements GraphCommandFailure {
  const ActionCommandFailure();
}

final class ActionNotFoundFailure extends ActionCommandFailure {
  const ActionNotFoundFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

/// Актуальное состояние графа не допускает команду; перед новым
/// подтверждением нужна актуализация.
final class ActionConflictFailure extends ActionCommandFailure {
  const ActionConflictFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class ActionUnavailableFailure extends ActionCommandFailure {
  const ActionUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class ActionCorruptionFailure extends ActionCommandFailure {
  const ActionCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class ActionUnexpectedFailure extends ActionCommandFailure {
  const ActionUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

/// Репозиторий возвращает успех только после commit целой операции. Весь
/// пакет изменений относится к одной подтверждённой ревизии. Операция без
/// фактических изменений не продвигает ревизию.
sealed class ActionCommandSuccess implements GraphCommandOutcome {
  ActionCommandSuccess({required Iterable<GraphChange> changes})
    : changes = List<GraphChange>.unmodifiable(changes);

  @override
  final List<GraphChange> changes;
}

final class ActionFieldsUpdated extends ActionCommandSuccess {
  ActionFieldsUpdated({required this.action, required super.changes});

  /// Подтверждённое состояние действия после изменения.
  final Action action;
}

final class ActionDeleted extends ActionCommandSuccess {
  ActionDeleted({required this.action, required super.changes});

  /// Состояние действия перед удалением.
  final Action action;
}

typedef ActionCommandResult =
    GraphCommandResult<ActionCommandSuccess, ActionCommandFailure>;
