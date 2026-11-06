import 'action_day.dart';

/// Чтения действий. Подмешивается в `PersonalGraphRepository`: отдельного
/// репозитория действий нет (ADR-0009).
abstract interface class ActionReadContract {
  /// Читает ограниченную порцию одной секции выбранного дня. Первая порция
  /// несёт точные числа обеих секций и признак времени во всём дне на одной
  /// ревизии; продолжение привязано к ревизии первой порции, а смена ревизии —
  /// конфликт.
  Future<ActionDayPageResult> getActionDayPage(ActionDayQuery query);
}
