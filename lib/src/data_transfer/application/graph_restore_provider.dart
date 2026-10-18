import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../graph/application/graph_command_coordinator.dart';
import '../../graph_backups/graph_backup_registry.dart';
import 'graph_restore.dart';

/// Восстановление резервной копии на протяжении жизни контейнера приложения:
/// принятое восстановление, его ход и отмена не зависят от открытых
/// страниц.
///
/// Композиция переопределяет фабрику, передавая операцию восстановления.
/// Провайдер без автоматического освобождения сохраняет состояние между
/// страницами:
/// https://riverpod.dev/docs/concepts2/auto_dispose#enablingdisabling-automatic-disposal
final graphRestoreControllerProvider =
    NotifierProvider<GraphRestoreController, GraphRestoreState>(
      () => throw StateError(
        'Операция восстановления копии должна быть предоставлена композицией '
        'приложения.',
      ),
      isAutoDispose: false,
    );

sealed class GraphRestoreState {
  const GraphRestoreState();
}

/// Восстановления нет.
final class GraphRestoreIdle extends GraphRestoreState {
  const GraphRestoreIdle();
}

/// Восстановление идёт.
final class GraphRestoreRunning extends GraphRestoreState {
  const GraphRestoreRunning(this.progress);

  final GraphRestoreProgress progress;
}

/// Отмена запрошена: восстановление прекращается, а начатая замена
/// откатывается. Состояние держится до конца отката.
final class GraphRestoreCancelling extends GraphRestoreState {
  const GraphRestoreCancelling();
}

final class GraphRestoreController extends Notifier<GraphRestoreState> {
  GraphRestoreController(this._restore);

  final GraphRestore _restore;

  /// Отмена принятого восстановления, пока оно идёт.
  Completer<void>? _cancellation;

  @override
  GraphRestoreState build() => const GraphRestoreIdle();

  /// Изменения графа с копии [backup] до текущего состояния для
  /// подтверждения восстановления по правилу
  /// [GraphRestore.countChangesSince].
  Future<GraphChangesSinceBackup> countChangesSince(GraphBackupEntry backup) =>
      _restore.countChangesSince(backup);

  /// Восстанавливает копию [backup] операцией, принятой
  /// [GraphCommandCoordinator]. Успех и отказ предъявляет координатор, а
  /// отмена сообщения не даёт.
  ///
  /// Пока восстановление идёт, состояние сообщает его ход, а после [cancel] —
  /// отмену до её окончания. Восстановление, не принятое координатором,
  /// состояния не меняет.
  GraphBackupRestoreStart start(GraphBackupEntry backup) => ref
      .read(graphCommandCoordinatorProvider.notifier)
      .acceptBackupRestore((exclusive) async {
        final cancellation = _cancellation = Completer<void>();
        _publish(
          const GraphRestoreRunning(
            GraphRestoreProgress(GraphRestorePhase.snapshotWrite, 0),
          ),
        );
        try {
          return await _restore.restore(
            backup,
            exclusive,
            onProgress: (progress) {
              if (!cancellation.isCompleted) {
                _publish(GraphRestoreRunning(progress));
              }
            },
            cancelled: cancellation.future,
          );
        } finally {
          _cancellation = null;
          _publish(const GraphRestoreIdle());
        }
      });

  /// Отменяет идущее восстановление; без него ничего не делает.
  void cancel() {
    final cancellation = _cancellation;
    if (cancellation == null || cancellation.isCompleted) return;
    cancellation.complete();
    _publish(const GraphRestoreCancelling());
  }

  /// Выключение приложения освобождает контейнер, не дожидаясь
  /// восстановления, а восстановление продолжается до исхода, которого
  /// выключение дожидается. Состояние освобождённого контейнера никто не
  /// наблюдает.
  void _publish(GraphRestoreState next) {
    if (ref.mounted) state = next;
  }
}
