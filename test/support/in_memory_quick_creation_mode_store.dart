import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_controller.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_store.dart';

/// Явная композиция настройки для страниц с панелью без AppRuntime.
/// Фабрика создаёт отдельные контроллер и хранилище для каждого контейнера.
final inMemoryQuickCreationModeOverride = quickCreationModeControllerProvider
    .overrideWith(
      () => QuickCreationModeController(
        initialMode: QuickCreationMode.intention,
        store: InMemoryQuickCreationModeStore(),
      ),
    );

/// Явная настройка установки для сценариев, не проверяющих файловое хранение.
final class InMemoryQuickCreationModeStore implements QuickCreationModeStore {
  QuickCreationMode mode = QuickCreationMode.intention;

  @override
  Future<QuickCreationMode> read() async => mode;

  @override
  Future<QuickCreationModeSaveResult> save(QuickCreationMode mode) async {
    this.mode = mode;
    return const QuickCreationModeSaved();
  }
}
