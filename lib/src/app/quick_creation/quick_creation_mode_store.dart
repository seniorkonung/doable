import '../../shared/diagnostics/diagnostics_sink.dart';
import 'quick_creation_mode.dart';

/// Хранилище одной настройки установки, независимое от данных личного графа.
///
/// Композиция приложения владеет единственным экземпляром на весь процесс.
/// Реализация владеет файловыми операциями, очередью и безопасной диагностикой
/// отказов; вызывающая сторона получает типизированный исход без исключений.
abstract interface class QuickCreationModeStore {
  /// Читает сохранённый режим при запуске.
  ///
  /// Отсутствие настройки возвращает [QuickCreationMode.intention] без
  /// диагностики. Нечитаемое или неизвестное содержимое возвращает тот же режим
  /// с безопасной диагностикой категории отказа, без пользовательского текста.
  Future<QuickCreationMode> read();

  /// Синхронно принимает неизменяемый [mode] в очередь до асинхронной границы.
  ///
  /// Каждый вызов имеет отдельную полную попытку и собственный исход Future.
  /// Попытки выполняются строго в порядке принятия, по одной, включая подготовку
  /// временного файла и атомарную замену основного файла. Значения не объединяются,
  /// не вытесняются поздними выборами и не перечитываются из состояния контроллера.
  ///
  /// Успех означает завершённую замену файла; отказ оставляет последнее успешно
  /// записанное значение. После любого исхода начинается следующая попытка, даже
  /// при отказе диагностического получателя. Автоматических повторов и отмены нет.
  /// Незавершённая попытка не считается сохранённой. Исключения записи превращаются
  /// в [QuickCreationModeSaveFailed] и не выходят синхронно или через Future.
  Future<QuickCreationModeSaveResult> save(QuickCreationMode mode);
}

/// Исход только одной принятой записи, не состояние текущего режима.
sealed class QuickCreationModeSaveResult {
  const QuickCreationModeSaveResult();
}

final class QuickCreationModeSaved extends QuickCreationModeSaveResult {
  const QuickCreationModeSaved();
}

/// Безопасная категория отказа без исходного исключения, пути или содержимого.
final class QuickCreationModeSaveFailed extends QuickCreationModeSaveResult {
  const QuickCreationModeSaveFailed(this.code);

  final DiagnosticsFailureCode code;
}
