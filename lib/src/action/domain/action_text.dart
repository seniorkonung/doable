import '../../intention/domain/intention_text.dart';

/// Название действия. Правила допустимого текста — те же, что у названия
/// намерения: [IntentionText.normalizeTitle].
final class ActionTitle {
  factory ActionTitle(String input) =>
      ActionTitle._(IntentionText.normalizeTitle(input));

  const ActionTitle._(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is ActionTitle && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ActionTitle';
}

/// Описание действия. Правила допустимого текста — те же, что у описания
/// намерения: [IntentionText.normalizeDescription].
final class ActionDescription {
  const ActionDescription._(this.value);

  final String value;

  /// Возвращает `null`, если описание пусто или состоит из одних пробелов.
  static ActionDescription? fromInput(String input) {
    final normalized = IntentionText.normalizeDescription(input);
    return normalized == null ? null : ActionDescription._(normalized);
  }

  @override
  bool operator ==(Object other) =>
      other is ActionDescription && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ActionDescription';
}
