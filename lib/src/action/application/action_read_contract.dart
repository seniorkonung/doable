import '../domain/action_id.dart';
import 'action_day.dart';
import 'action_day_statuses.dart';
import 'action_details.dart';
import 'intention_actions.dart';

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

  /// Наблюдает действие с сохранённым путём на текущих данных намерений и
  /// связей. Перечитывает его при подтверждённом изменении самого действия и
  /// намерений и связей последнего прочитанного пути. Успех со значением
  /// `null` — действия нет.
  Stream<ActionReadResult> watchAction(ActionId id);

  /// Читает ограниченную порцию действий, в сохранённых путях которых
  /// намерение играет выбранную роль; архивное намерение читается как
  /// активное. Первая порция несёт числа всех ролей и число действий с
  /// намерением в пути на одной ревизии; продолжение привязано к ревизии
  /// первой порции, а смена ревизии — конфликт.
  Future<IntentionActionsPageResult> getIntentionActionsPage(
    IntentionActionsQuery query,
  );
}
