import 'action_day.dart';
import 'action_day_statuses.dart';

/// Чтения действий. Подмешивается в `PersonalGraphRepository`: отдельного
/// репозитория действий нет (ADR-0009).
abstract interface class ActionReadContract {
  /// Читает ограниченную порцию одной секции выбранного дня. Первая порция
  /// несёт точные числа обеих секций и признак времени во всём дне на одной
  /// ревизии; продолжение привязано к ревизии первой порции, а смена ревизии —
  /// конфликт.
  Future<ActionDayPageResult> getActionDayPage(ActionDayQuery query);

  /// Читает состояния дней окна календаря агрегатом по выполнению всех
  /// действий каждой даты на одном снимке (ADR-0024, ADR-0025).
  Future<ActionDayStatusesReadResult> getActionDayStatuses(
    ActionDayStatusQuery query,
  );
}
