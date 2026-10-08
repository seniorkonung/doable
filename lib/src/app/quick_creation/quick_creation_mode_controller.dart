import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'quick_creation_mode.dart';
import 'quick_creation_mode_store.dart';

/// Единый режим для всех панелей на протяжении жизни контейнера приложения.
///
/// Композиция переопределяет фабрику, явно передавая начальный режим и хранилище.
/// Провайдер без автоматического освобождения сохраняет выбор между страницами:
/// https://riverpod.dev/docs/concepts2/auto_dispose#enablingdisabling-automatic-disposal
final quickCreationModeControllerProvider =
    NotifierProvider<QuickCreationModeController, QuickCreationMode>(
      () => throw StateError(
        'Начальный режим и хранилище быстрого создания должны быть предоставлены '
        'композицией приложения.',
      ),
      isAutoDispose: false,
    );

/// Текущее состояние отделено от исходов сохранения настройки установки.
final class QuickCreationModeController extends Notifier<QuickCreationMode> {
  QuickCreationModeController({
    required this._initialMode,
    required this._store,
  });

  final QuickCreationMode _initialMode;
  final QuickCreationModeStore _store;

  @override
  QuickCreationMode build() => _initialMode;

  /// Применяет выбор синхронно и передаёт его хранилищу в том же обработчике.
  /// Future сообщает только исход этой записи: его ожидание не нужно для смены
  /// режима, а поздний исход не меняет состояние, в том числе после освобождения.
  Future<QuickCreationModeSaveResult> select(QuickCreationMode mode) {
    state = mode;
    return _store.save(mode);
  }
}
