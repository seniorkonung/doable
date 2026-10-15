/// Режим быстрого создания; порядок значений задаёт порядок меню.
enum QuickCreationMode {
  intention,
  relation,
  dailyChoice;

  /// Постоянный формат настройки установки, независимый от имени и индекса.
  String get storageKey => switch (this) {
    QuickCreationMode.intention => 'intention',
    QuickCreationMode.relation => 'relation',
    QuickCreationMode.dailyChoice => 'daily-choice',
  };

  /// Проверяет внешнее значение; неизвестный ключ не получает режим по умолчанию.
  /// Отсутствие доверенного режима обрабатывает граница чтения настройки.
  static QuickCreationMode? fromStorageKey(String key) {
    for (final mode in values) {
      if (mode.storageKey == key) return mode;
    }
    return null;
  }
}
