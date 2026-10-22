import '../../../intention/domain/intention_id.dart';

/// Контекст панели тегов по ADR-0040: определяет отметку строки и смысл
/// нажатия на неё. Контекст собирает вызывающий сценарий из явных
/// зависимостей.
sealed class TagsPanelContext {
  const TagsPanelContext();
}

/// Выбор тегов существующего намерения: отметка показывает подтверждённое
/// назначение тега этому намерению.
final class TagsPanelAssignmentContext extends TagsPanelContext {
  const TagsPanelAssignmentContext(this.intentionId);

  final IntentionId intentionId;
}

/// Одно открытие панели тегов.
///
/// Идентичность задаёт сам экземпляр: модель панели привязана к нему,
/// поэтому каждое открытие начинает с пустого поиска и собственного
/// состояния, не разделяя их с прежними открытиями того же контекста.
final class TagsPanelOpening {
  TagsPanelOpening(this.context);

  final TagsPanelContext context;

  bool _isClosed = false;

  /// Открытие закрыто вместе с маршрутом панели, хотя её содержимое и модель
  /// ещё живут до конца закрывающей анимации.
  bool get isClosed => _isClosed;

  void close() => _isClosed = true;
}
