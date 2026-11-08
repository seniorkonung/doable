import '../../shared/domain/calendar_date.dart';
import 'action_id.dart';
import 'action_path.dart';
import 'action_priority.dart';
import 'action_schedule.dart';
import 'action_text.dart';

/// Неизменяемый порядок создания действия внутри локального хранилища
/// (ADR-0010). Не заменяет идентичность, время и ревизию графа.
final class ActionCreationSequence
    implements Comparable<ActionCreationSequence> {
  factory ActionCreationSequence(int value) {
    if (value <= 0) {
      throw ArgumentError.value(value, 'value', 'Должен быть положительным');
    }
    return ActionCreationSequence._(value);
  }

  const ActionCreationSequence._(this.value);

  final int value;

  @override
  int compareTo(ActionCreationSequence other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      other is ActionCreationSequence && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ActionCreationSequence';
}

/// Показание часов устройства о создании или последнем изменении действия.
/// Служит только для показа (ADR-0006).
final class ActionTimestamp {
  ActionTimestamp(DateTime value) : value = value.toUtc();

  final DateTime value;

  @override
  bool operator ==(Object other) =>
      other is ActionTimestamp && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Действие — разовое дело на дату с обязательным путём. Поля уже проверены
/// своими типами, поэтому собрать недопустимое действие нельзя.
final class Action {
  const Action({
    required this.id,
    required this.title,
    required this.description,
    required this.path,
    required this.date,
    required this.schedule,
    required this.priority,
    required this.isCompleted,
    required this.creationSequence,
    required this.createdAt,
    required this.updatedAt,
  });

  final ActionId id;
  final ActionTitle title;
  final ActionDescription? description;
  final ActionPath path;
  final CalendarDate date;
  final ActionSchedule schedule;
  final ActionPriority priority;
  final bool isCompleted;
  final ActionCreationSequence creationSequence;
  final ActionTimestamp createdAt;
  final ActionTimestamp updatedAt;
}
