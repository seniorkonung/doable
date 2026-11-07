import '../../graph/application/graph_command_result.dart';
import '../../shared/domain/calendar_date.dart';
import '../domain/action_id.dart';
import '../domain/action_path.dart';
import '../domain/action_priority.dart';
import '../domain/action_schedule.dart';
import '../domain/action_text.dart';
import 'action_result.dart';

/// Исполняется через общий последовательный исполнитель графа: каждая команда
/// — одна транзакция записи с одной ревизией. Команды действий не меняют
/// намерения и связи.
sealed class ActionCommand
    implements GraphCommand<ActionCommandSuccess, ActionCommandFailure> {
  const ActionCommand();
}

/// Создаёт невыполненное действие с указанным путём.
final class CreateAction extends ActionCommand {
  const CreateAction({
    required this.title,
    required this.description,
    required this.path,
    required this.date,
    required this.schedule,
    required this.priority,
  });

  final ActionTitle title;
  final ActionDescription? description;
  final ActionPath path;
  final CalendarDate date;
  final ActionSchedule schedule;
  final ActionPriority priority;
}

/// Правка одного поля действия: оставить или заменить.
sealed class ActionFieldPatch<T> {
  const ActionFieldPatch();

  /// Значение поля после правки при текущем значении [current].
  T resolve(T current);
}

final class ActionFieldUnchanged<T> extends ActionFieldPatch<T> {
  const ActionFieldUnchanged();

  @override
  T resolve(T current) => current;
}

/// Заменяет значение, в том числе отсутствие описания: `null` очищает его.
final class ActionFieldSet<T> extends ActionFieldPatch<T> {
  const ActionFieldSet(this.value);

  final T value;

  @override
  T resolve(T current) => value;
}

/// Правка любого сочетания изменяемых полей действия. Пустая правка и
/// прежние значения допустимы: они ничего не меняют.
final class ActionFieldsPatch {
  const ActionFieldsPatch({
    this.title = const ActionFieldUnchanged<ActionTitle>(),
    this.description = const ActionFieldUnchanged<ActionDescription?>(),
    this.date = const ActionFieldUnchanged<CalendarDate>(),
    this.schedule = const ActionFieldUnchanged<ActionSchedule>(),
    this.priority = const ActionFieldUnchanged<ActionPriority>(),
    this.isCompleted = const ActionFieldUnchanged<bool>(),
  });

  final ActionFieldPatch<ActionTitle> title;
  final ActionFieldPatch<ActionDescription?> description;
  final ActionFieldPatch<CalendarDate> date;
  final ActionFieldPatch<ActionSchedule> schedule;
  final ActionFieldPatch<ActionPriority> priority;
  final ActionFieldPatch<bool> isCompleted;
}

/// Заменяет поля действия и обновляет время изменения только при фактической
/// перемене состояния. Путь, идентичность и порядок создания не меняются.
final class UpdateActionFields extends ActionCommand {
  const UpdateActionFields({required this.actionId, required this.patch});

  final ActionId actionId;
  final ActionFieldsPatch patch;
}

/// Заменяет путь существующего действия после проверки актуальности графа.
final class SetActionPath extends ActionCommand {
  const SetActionPath({required this.actionId, required this.path});

  final ActionId actionId;
  final ActionPath path;
}

/// Удаляет действие вместе с его путём; намерения и связи остаются.
final class DeleteAction extends ActionCommand {
  const DeleteAction(this.actionId);

  final ActionId actionId;
}
