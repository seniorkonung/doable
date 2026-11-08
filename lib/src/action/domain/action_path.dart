import '../../intention/domain/intention_id.dart';

/// Путь действия — его причина: непустая последовательность различных
/// намерений от корневого до конечного. Путь из одного намерения допустим.
///
/// Тип проверяет только форму. Что намерения существуют, активны и соседние
/// соединены активной связью, проверяет транзакция записи графа.
final class ActionPath {
  factory ActionPath(Iterable<IntentionId> intentions) {
    final ordered = List<IntentionId>.unmodifiable(intentions);
    if (ordered.isEmpty || ordered.toSet().length != ordered.length) {
      throw ArgumentError.value(intentions, 'intentions');
    }
    return ActionPath._(ordered);
  }

  const ActionPath._(this.intentions);

  final List<IntentionId> intentions;
}
