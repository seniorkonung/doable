import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../graph/application/graph_command_coordinator.dart';
import '../../graph_format/graph_format_records.dart';
import 'graph_composition.dart';
import 'graph_import.dart';
import 'graph_replacement.dart';

/// Импорт файла экспорта на протяжении жизни контейнера приложения: чтение
/// выбранного файла, ожидание подтверждения, ход и отмена замены не зависят
/// от открытых страниц.
///
/// Композиция переопределяет фабрику, передавая операцию импорта и состав
/// графа. Провайдер без автоматического освобождения сохраняет состояние
/// между страницами:
/// https://riverpod.dev/docs/concepts2/auto_dispose#enablingdisabling-automatic-disposal
final graphImportControllerProvider =
    NotifierProvider<GraphImportController, GraphImportState>(
      () => throw StateError(
        'Операция импорта графа должна быть предоставлена композицией '
        'приложения.',
      ),
      isAutoDispose: false,
    );

sealed class GraphImportState {
  const GraphImportState();
}

/// Импорта нет, в том числе пока открыт системный диалог выбора файла.
final class GraphImportIdle extends GraphImportState {
  const GraphImportIdle();
}

/// Выбранный документ копируется во временный файл и проверяется по
/// заголовку. Доли хода у чтения нет.
final class GraphImportReadingFile extends GraphImportState {
  const GraphImportReadingFile();
}

/// Файл прочитан, и импорт ждёт подтверждения замены: граф не пуст или его
/// состав не прочитан.
final class GraphImportAwaitingConfirmation extends GraphImportState {
  const GraphImportAwaitingConfirmation(this.header);

  /// Дата сохранения файла и количества его записей каждого вида.
  final GraphFormatHeader header;
}

/// Граф заменяется записями файла.
final class GraphImportReplacing extends GraphImportState {
  const GraphImportReplacing(this.progress);

  final GraphReplacementProgress progress;
}

/// Замена прошла точку невозврата и подтверждается: отмена больше не
/// принимается, и импорт завершается так же, как без неё. Ход замены к этому
/// моменту полный.
final class GraphImportCommitting extends GraphImportState {
  const GraphImportCommitting();
}

/// Отмена принята: чтение файла прекращается, а начатая замена
/// откатывается. Состояние держится, пока не прекращено копирование
/// документа или не закончен откат.
final class GraphImportCancelling extends GraphImportState {
  const GraphImportCancelling();
}

final class GraphImportController extends Notifier<GraphImportState> {
  GraphImportController(this._import, this._composition);

  final GraphImport _import;

  /// Состав графа, по которому импорт решает, нужно ли подтверждение замены.
  final GraphCompositionSource _composition;

  /// Импорт начат и не завершён: ожидается ответ диалога, файл читается,
  /// ожидается подтверждение или идёт импорт, принятый координатором.
  var _isImporting = false;

  /// Отмена чтения выбранного файла, пока её можно запросить: `null` вне
  /// чтения и после принятой отмены.
  GraphImportReadingCancellation? _readingCancellation;

  /// Ответ на подтверждение замены, пока импорт его ждёт.
  Completer<bool>? _confirmation;

  /// Отмена идущей замены, пока её можно запросить: `null` без замены и
  /// после принятой отмены.
  GraphReplacementCancellation? _replacementCancellation;

  @override
  GraphImportState build() => const GraphImportIdle();

  /// Открывает системный диалог выбора файла и ведёт импорт выбранного
  /// документа до его принятия [GraphCommandCoordinator]. Завершается
  /// принятым импортом, по токену которого вызывающий предъявляет его отказ
  /// по праву инициатора, или `null`, если импорт не принят. Успех и отказ
  /// предъявляет координатор, а отмена сообщения не даёт.
  ///
  /// Как только документ выбран, состояние сообщает чтение файла — его
  /// копирование и проверку заголовка, — которое прекращает [cancel]. Если
  /// граф не пуст или его состав не прочитан, импорт затем ждёт [confirm] или
  /// [decline]. Диалог, который не открылся, и отказ чтения координатор
  /// принимает импортом, который сразу ими завершается, а импорт прочитанного
  /// файла — после подтверждения или сразу при пустом графе. Отмена диалога и
  /// чтения и отказ от подтверждения ничего не меняют, а временного файла не
  /// оставляют.
  ///
  /// Пока ожидается ответ диалога или импорт не завершён, вызов ничего не
  /// делает.
  Future<GraphImportAccepted?> start() async {
    if (_isImporting) return null;
    _isImporting = true;
    final readingCancellation = GraphImportReadingCancellation();
    final reading = await _import.readChosenFile(
      onDocumentChosen: () {
        _readingCancellation = readingCancellation;
        _publish(const GraphImportReadingFile());
      },
      cancellation: readingCancellation,
    );
    switch (reading) {
      case GraphImportFileReadingCancelled():
        _readingCancellation = null;
        _finish();
        return null;
      case GraphImportFileReadingFailed(:final failure):
        _readingCancellation = null;
        return _accept((_) async => GraphImportFailed(failure));
      case GraphImportFileRead(:final file):
        final requiresConfirmation = await _requiresConfirmation();
        _readingCancellation = null;
        // Отмена, принятая, пока читался состав графа, прекращает импорт так
        // же, как отмена чтения файла.
        if (readingCancellation.finish() ||
            (requiresConfirmation && !await _confirm(file.header))) {
          await file.discard();
          _finish();
          return null;
        }
        return _accept(
          (exclusive) => _replace(file, exclusive),
          onRejected: file.discard,
        );
    }
  }

  /// Подтверждает замену графа, которой ждёт импорт. Без ожидания
  /// подтверждения ничего не меняет.
  void confirm() => _answerConfirmation(confirmed: true);

  /// Отказывается от замены графа, которой ждёт импорт: граф не меняется, а
  /// временный файл удаляется. Без ожидания подтверждения ничего не меняет.
  void decline() => _answerConfirmation(confirmed: false);

  /// Отменяет чтение выбранного файла или идущую замену, если она ещё не
  /// прошла точку невозврата. Принятие отмены и проверка в точке невозврата —
  /// одно синхронное решение, поэтому после точки невозврата, как и без
  /// чтения и замены, ничего не меняется.
  void cancel() {
    if (_readingCancellation case final reading?) {
      if (!reading.request()) return;
      _readingCancellation = null;
      _publish(const GraphImportCancelling());
      return;
    }
    final replacement = _replacementCancellation;
    if (replacement == null || !replacement.request()) return;
    _replacementCancellation = null;
    _publish(const GraphImportCancelling());
  }

  /// Нужно ли подтверждение замены: граф не пуст, или его состав не прочитан,
  /// а отказ чтения не означает пустого графа.
  Future<bool> _requiresConfirmation() async => switch (await _composition
      .watchComposition()
      .first) {
    GraphCompositionReadSucceeded(:final composition) => !composition.isEmpty,
    GraphCompositionReadFailed() => true,
  };

  Future<bool> _confirm(GraphFormatHeader header) {
    final confirmation = _confirmation = Completer<bool>();
    _publish(GraphImportAwaitingConfirmation(header));
    return confirmation.future;
  }

  void _answerConfirmation({required bool confirmed}) {
    final confirmation = _confirmation;
    _confirmation = null;
    confirmation?.complete(confirmed);
  }

  /// Передаёт импорт [import] координатору. Импорт, который координатор не
  /// принял, ничего не меняет, а [onRejected] отбрасывает прочитанный файл.
  Future<GraphImportAccepted?> _accept(
    Future<GraphImportOutcome> Function(
      GraphExclusiveReplacement<GraphImported> exclusive,
    )
    import, {
    Future<void> Function()? onRejected,
  }) async {
    switch (ref.read(graphCommandCoordinatorProvider.notifier).acceptImport((
      exclusive,
    ) async {
      try {
        return await import(exclusive);
      } finally {
        _finish();
      }
    })) {
      case final GraphImportAccepted accepted:
        return accepted;
      // Импорт не принят: идёт восстановление копии или приложение завершает
      // работу.
      case GraphReplacementAlreadyRunning() ||
          GraphCommandCoordinatorDraining():
        await onRejected?.call();
        _finish();
        return null;
    }
  }

  Future<GraphImportOutcome> _replace(
    GraphImportFile file,
    GraphExclusiveReplacement<GraphImported> exclusive,
  ) async {
    final cancellation = _replacementCancellation =
        GraphReplacementCancellation(
          onPointOfNoReturn: () => _publish(const GraphImportCommitting()),
        );
    _publish(
      const GraphImportReplacing(
        GraphReplacementProgress(GraphReplacementPhase.snapshotWrite, 0),
      ),
    );
    try {
      return await _import.importFile(
        file,
        exclusive,
        onProgress: (progress) {
          // После принятой отмены ход не публикуется: до конца отката
          // состояние сообщает отмену.
          if (_replacementCancellation != null) {
            _publish(GraphImportReplacing(progress));
          }
        },
        cancellation: cancellation,
      );
    } finally {
      _replacementCancellation = null;
    }
  }

  void _finish() {
    _isImporting = false;
    _publish(const GraphImportIdle());
  }

  /// Выключение приложения освобождает контейнер, не дожидаясь импорта, а
  /// импорт, принятый координатором, продолжается до исхода, которого
  /// выключение дожидается. Состояние освобождённого контейнера никто не
  /// наблюдает.
  void _publish(GraphImportState next) {
    if (ref.mounted) state = next;
  }
}
