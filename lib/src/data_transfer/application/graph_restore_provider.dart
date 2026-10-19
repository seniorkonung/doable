import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../graph/application/graph_command_coordinator.dart';
import '../../graph_backups/graph_backup_registry.dart';
import 'graph_replacement.dart';
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

/// Замена прошла точку невозврата и подтверждается: отмена больше не
/// принимается, и восстановление завершается так же, как без неё. Ход замены
/// к этому моменту полный.
final class GraphRestoreCommitting extends GraphRestoreState {
  const GraphRestoreCommitting();
}

/// Отмена принята до точки невозврата замены: восстановление прекращается,
/// а начатая замена откатывается. Состояние держится до конца отката.
final class GraphRestoreCancelling extends GraphRestoreState {
  const GraphRestoreCancelling();
}

final class GraphRestoreController extends Notifier<GraphRestoreState> {
  GraphRestoreController(this._restore);

  final GraphRestore _restore;

  /// Отмена идущего восстановления, пока её можно запросить: `null` без
  /// восстановления и после принятой отмены.
  GraphReplacementCancellation? _cancellation;

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
  /// Пока восстановление идёт, состояние сообщает его ход, после принятой
  /// [cancel] — отмену до её окончания, а после точки невозврата замены —
  /// подтверждение замены, которое отменить уже нельзя. Восстановление, не
  /// принятое координатором, состояния не меняет.
  GraphBackupRestoreStart start(GraphBackupEntry backup) => ref
      .read(graphCommandCoordinatorProvider.notifier)
      .acceptBackupRestore((exclusive) async {
        final cancellation = _cancellation = GraphReplacementCancellation(
          onPointOfNoReturn: () => _publish(const GraphRestoreCommitting()),
        );
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
              // После принятой отмены ход не публикуется: до конца отката
              // состояние сообщает отмену.
              if (_cancellation != null) {
                _publish(GraphRestoreRunning(progress));
              }
            },
            cancellation: cancellation,
          );
        } finally {
          _cancellation = null;
          _publish(const GraphRestoreIdle());
        }
      });

  /// Отменяет идущее восстановление, если замена ещё не прошла точку
  /// невозврата. Принятие отмены и проверка в точке невозврата — одно
  /// синхронное решение, поэтому после точки невозврата, как и без
  /// восстановления, ничего не меняется.
  void cancel() {
    final cancellation = _cancellation;
    if (cancellation == null || !cancellation.request()) return;
    _cancellation = null;
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
