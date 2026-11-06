import '../../intention/domain/intention_id.dart';
import '../../shared/domain/calendar_date.dart';
import '../domain/action_id.dart';
import '../domain/action_priority.dart';
import '../domain/action_schedule.dart';
import '../domain/action_text.dart';

/// Строка списка действий: поля действия, корневое намерение пути с названием
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
    required IntentionId rootIntentionId,
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
      rootIntentionId: rootIntentionId,
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
    required this.rootIntentionId,
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

  /// Корневое намерение пути: текущее или удалённое. По нему потребитель
  /// узнаёт, что изменение намерения затрагивает строку.
  final IntentionId rootIntentionId;

  /// Название корневого намерения: текущее, а у удалённого — из надгробия.
  final String rootTitle;

  /// Число намерений сохранённого пути, включая корневое.
  final int pathIntentionCount;
}
