import '../../graph/application/graph_revision.dart';
import '../domain/intention_id.dart';

/// Удержание намерения на ревизии графа (ADR-0056): главное намерение
/// удерживает себя, пока активно, а активное вспомогательное удерживается,
/// пока до него можно дойти вниз от активного главного по активным связям
/// через активные вспомогательные. Архивное намерение не удерживается.
enum IntentionHolding { held, notHeld }

/// Чтение удержания. Подмешивается в `PersonalGraphRepository`: отдельного
/// репозитория удержания нет (ADR-0009).
abstract interface class IntentionHoldingReadContract {
  /// Читает удержание каждого из [ids] по индексу текущей ревизии графа,
  /// строя индекс вне очереди записи, если его нет. Ответ относится только к
  /// ревизии успеха. Если граф изменил удержание, пока индекс строился,
  /// построенный результат отбрасывается: удержание новой ревизии читается
  /// заново после пакета с `IntentionHoldingChanged`.
  Future<IntentionHoldingResult> getIntentionHolding(Set<IntentionId> ids);
}

sealed class IntentionHoldingResult {
  const IntentionHoldingResult();
}

final class IntentionHoldingRead extends IntentionHoldingResult {
  IntentionHoldingRead({
    required this.revision,
    required Map<IntentionId, IntentionHolding> holdings,
  }) : holdings = Map.unmodifiable(holdings);

  final GraphRevision revision;

  /// Удержание каждого запрошенного намерения на [revision].
  final Map<IntentionId, IntentionHolding> holdings;
}

/// Подтверждённая команда изменила удержание, пока индекс строился.
final class IntentionHoldingExpired extends IntentionHoldingResult {
  const IntentionHoldingExpired();
}

/// Индекс не построен: хранилище недоступно, данные повреждены или подсчёт
/// отказал. Причина записана в диагностику.
final class IntentionHoldingFailed extends IntentionHoldingResult {
  const IntentionHoldingFailed();
}
