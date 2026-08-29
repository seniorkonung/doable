final class IntentionId {
  IntentionId(String value) : value = _requireValue(value);

  final String value;

  static String _requireValue(String value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'не должен быть пустым');
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is IntentionId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
