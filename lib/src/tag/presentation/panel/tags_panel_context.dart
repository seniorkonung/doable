import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/editor/intention_draft_tag_set.dart';

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

/// Выбор тегов черновика создания намерения: отметка показывает, входит ли
/// тег в набор черновика его сессии. Нажатие меняет только этот набор и не
/// отправляет команд графа.
final class TagsPanelDraftContext extends TagsPanelContext {
  const TagsPanelDraftContext(this.tagSet);

  final IntentionDraftTagSet tagSet;
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
