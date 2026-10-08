import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_store.dart';

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
