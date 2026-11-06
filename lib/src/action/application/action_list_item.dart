import '../../shared/domain/calendar_date.dart';
import '../domain/action_id.dart';
import '../domain/action_priority.dart';
import '../domain/action_schedule.dart';
import '../domain/action_text.dart';

/// Строка списка действий: поля действия, название его корневого намерения
/// и число намерений пути. Сам путь остаётся в хранилище.
final class ActionListItem {
  factory ActionListItem({
    required ActionId id,
    required ActionTitle title,
    required ActionDescription? description,
    required CalendarDate date,
    required ActionSchedule schedule,
    required ActionPriority priority,
    required bool isCompleted,
    required String rootTitle,
    required int pathIntentionCount,
  }) {
    if (pathIntentionCount < 1) {
      throw ArgumentError.value(pathIntentionCount, 'pathIntentionCount');
    }
    return ActionListItem._(
      id: id,
      title: title,
      description: description,
      date: date,
      schedule: schedule,
      priority: priority,
      isCompleted: isCompleted,
      rootTitle: rootTitle,
      pathIntentionCount: pathIntentionCount,
    );
  }

  const ActionListItem._({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.schedule,
    required this.priority,
    required this.isCompleted,
    required this.rootTitle,
    required this.pathIntentionCount,
  });

  final ActionId id;
  final ActionTitle title;
  final ActionDescription? description;
  final CalendarDate date;
  final ActionSchedule schedule;
  final ActionPriority priority;
  final bool isCompleted;

  /// Название корневого намерения: текущее, а у удалённого — из надгробия.
  final String rootTitle;

  /// Число намерений сохранённого пути, включая корневое.
  final int pathIntentionCount;
}
