import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../graph/application/graph_command_coordinator.dart';
import 'document_access.dart';
import 'graph_export.dart';

/// Экспорт графа на протяжении жизни контейнера приложения: принятый
/// экспорт и его ход не зависят от открытых страниц.
///
/// Композиция переопределяет фабрику, передавая операцию экспорта.
/// Провайдер без автоматического освобождения сохраняет состояние между
/// страницами:
/// https://riverpod.dev/docs/concepts2/auto_dispose#enablingdisabling-automatic-disposal
final graphExportControllerProvider =
    NotifierProvider<GraphExportController, GraphExportState>(
      () => throw StateError(
        'Операция экспорта графа должна быть предоставлена композицией '
        'приложения.',
      ),
      isAutoDispose: false,
    );

sealed class GraphExportState {
  const GraphExportState();
}

/// Экспорта нет.
final class GraphExportIdle extends GraphExportState {
  const GraphExportIdle();
}

/// Экспорт идёт.
final class GraphExportRunning extends GraphExportState {
  const GraphExportRunning(this.progress);

  /// Доля записанных записей от количеств заголовка файла, от 0 до 1.
  final double progress;
}

final class GraphExportController extends Notifier<GraphExportState> {
  GraphExportController(this._export);

  final GraphExport _export;

  /// Ожидается ответ системного диалога сохранения.
  var _isChoosingDocument = false;

  @override
  GraphExportState build() => const GraphExportIdle();

  /// Открывает системный диалог сохранения; выбранный документ запускает
  /// экспорт, принятый [GraphCommandCoordinator]. Успех и отказ экспорта
  /// предъявляет общая поверхность результатов, а повтор из сообщения об
  /// отказе снова вызывает [start].
  ///
  /// Отмена диалога ничего не меняет. Диалог, который не открылся, даёт
  /// отказ экспорта, чтобы человек мог повторить. Файл с данными, выбранный в
  /// диалоге, экспорт не перезаписывает: исход предлагает повторить и
  /// сохранить копию под новым именем. Пока ожидается ответ
  /// диалога или идёт экспорт, вызов ничего не делает. Завершается, когда
  /// ответ диалога обработан.
  Future<void> start() async {
    if (_isChoosingDocument || state is GraphExportRunning) return;
    _isChoosingDocument = true;
    try {
      final Future<GraphExportOutcome> Function()? export =
          switch (await _export.chooseDocument()) {
            DocumentCreated(:final document) => () => _write(document),
            DocumentCreationFailed() => () async => GraphExportOutcome.failed,
            ExistingFileChosen() => () async => GraphExportOutcome.existingFile,
            DocumentCreationCancelled() => null,
          };
      if (export == null) return;
      // Второй экспорт этот контроллер не запускает, поэтому экспорт не
      // принимается только во время выключения приложения.
      ref
          .read(graphCommandCoordinatorProvider.notifier)
          .acceptExport(export: export, retry: () => unawaited(start()));
    } finally {
      _isChoosingDocument = false;
    }
  }

  Future<GraphExportOutcome> _write(CreatedDocument document) async {
    _publish(const GraphExportRunning(0));
    try {
      return await _export.write(
        document,
        onProgress: (share) => _publish(GraphExportRunning(share)),
      );
    } finally {
      _publish(const GraphExportIdle());
    }
  }

  /// Выключение приложения освобождает контейнер, не дожидаясь экспорта, а
  /// экспорт продолжается до результата, которого выключение дожидается.
  /// Состояние освобождённого контейнера никто не наблюдает.
  void _publish(GraphExportState next) {
    if (ref.mounted) state = next;
  }
}
