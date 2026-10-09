/// Право конкретного запуска продолжить создание после начального поиска.
///
/// Владелец запуска передаёт один экземпляр поиску и проверяет [isActive]
/// после получения ID. Право зависит от жизни этого запуска и его исходной
/// страницы, а не от наличия других потоков в истории.
abstract interface class DailyChoicePickerLaunch {
  bool get isActive;

  /// Синхронно и необратимо прекращает запуск до закрытия поиска.
  /// Повторная отмена безопасна; операция не изменяет граф или историю.
  void cancel();
}

/// Назначение поиска независимо от сессии его фильтров и выдачи.
sealed class DailyChoicePickerContext {
  const DailyChoicePickerContext();

  bool get canContinue => switch (this) {
    InitialDailyChoicePickerContext(:final launch) => launch.isActive,
    AuxiliaryDailyChoicePickerContext() => true,
  };

  void cancelLaunch() {
    switch (this) {
      case InitialDailyChoicePickerContext(:final launch):
        launch.cancel();
      case AuxiliaryDailyChoicePickerContext():
        break;
    }
  }
}

/// Начальный поиск основания или действия для самостоятельного создания.
final class InitialDailyChoicePickerContext extends DailyChoicePickerContext {
  const InitialDailyChoicePickerContext({required this.launch});

  final DailyChoicePickerLaunch launch;
}

/// Вспомогательный выбор возвращает ID или null вызвавшей странице.
final class AuxiliaryDailyChoicePickerContext extends DailyChoicePickerContext {
  const AuxiliaryDailyChoicePickerContext();
}
