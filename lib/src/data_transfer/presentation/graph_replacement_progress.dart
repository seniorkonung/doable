import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/doable_colors.dart';
import '../../design_system/doable_metrics.dart';
import '../../design_system/doable_type.dart';
import '../../graph_format/graph_format_records.dart';
import '../application/graph_import_provider.dart';
import '../application/graph_replacement.dart';
import '../application/graph_restore_provider.dart';
import 'import_data_confirmation.dart';

/// Пока идёт замена графа восстановлением копии или импортом, показывает над
/// страницей [child], её панелью навигации и остальным приложением модальный
/// прогресс с ходом и кнопкой «Отменить».
///
/// Прогресс восстановления открывается, когда оно начинается, а прогресс
/// импорта — как только выбран файл: пока файл читается, прогресс показывает
/// импорт без доли хода. Пока импорт ждёт подтверждения, вместо прогресса
/// открыто подтверждение импорта. Прогресс закрывается без сообщения, когда
/// операция завершается: успехом, отказом или отменой. Исход предъявляет
/// координатор. Системное «назад» прогресс не закрывает.
final class GraphReplacementProgressHost extends ConsumerStatefulWidget {
  const GraphReplacementProgressHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<GraphReplacementProgressHost> createState() =>
      _GraphReplacementProgressHostState();
}

final class _GraphReplacementProgressHostState
    extends ConsumerState<GraphReplacementProgressHost> {
  /// Прогресс идущей операции.
  Route<void>? _progress;

  @override
  void initState() {
    super.initState();
    // Операция может завершиться раньше первого кадра прогресса, поэтому
    // прогресс открывает и закрывает слушатель состояния, а не сам прогресс.
    ref.listenManual(graphRestoreControllerProvider, (_, state) {
      switch (state) {
        case GraphRestoreRunning() ||
            GraphRestoreCommitting() ||
            GraphRestoreCancelling():
          _open(_GraphReplacementOperation.restore);
        case GraphRestoreIdle():
          _close();
      }
    });
    ref.listenManual(graphImportControllerProvider, (_, state) {
      switch (state) {
        case GraphImportReadingFile() ||
            GraphImportReplacing() ||
            GraphImportCommitting() ||
            GraphImportCancelling():
          _open(_GraphReplacementOperation.import);
        case GraphImportAwaitingConfirmation(:final header):
          _close();
          unawaited(_confirmImport(header));
        case GraphImportIdle():
          _close();
      }
    });
  }

  void _open(_GraphReplacementOperation operation) {
    if (_progress != null) return;
    final route = _progress = DialogRoute<void>(
      context: context,
      barrierColor: Theme.of(context).extension<DoableColors>()!.scrim,
      barrierDismissible: false,
      builder: (_) => _GraphReplacementProgress(operation),
    );
    // Маршрут открывается напрямую, а не через showDialog, чтобы закрыть
    // именно его, а не верхний маршрут навигатора.
    unawaited(Navigator.of(context, rootNavigator: true).push(route));
  }

  void _close() {
    final route = _progress;
    if (route == null) return;
    _progress = null;
    // Маршрут удаляется, даже если он ещё не построен.
    route.navigator!.removeRoute(route);
  }

  /// Открывает подтверждение импорта файла с заголовком [header] и передаёт
  /// ответ импорту, который его ждёт.
  Future<void> _confirmImport(GraphFormatHeader header) async {
    final import = ref.read(graphImportControllerProvider.notifier);
    if (await confirmGraphImport(context, header: header)) {
      import.confirm();
    } else {
      import.decline();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Замена графа, ход которой показывает прогресс.
enum _GraphReplacementOperation {
  /// На профиле замера решения 15 дизайна запись снимка замены занимает
  /// около 30 % восстановления копии.
  restore(snapshotWriteShare: 0.3),

  /// На профиле замера решения 15 дизайна запись снимка замены занимает
  /// около 20 % импорта.
  import(snapshotWriteShare: 0.2);

  const _GraphReplacementOperation({required this.snapshotWriteShare});

  /// Доля записи снимка замены в общем ходе операции, с которой ход растёт
  /// примерно равномерно.
  final double snapshotWriteShare;
}

/// Модальный прогресс замены графа: экранный диктор читает, что идёт
/// операция [operation], её ход и кнопку «Отменить», после точки невозврата
/// замены — её недоступность, а после отмены — «Отмена…», пока не прекращено
/// чтение файла импорта или не закончен откат.
final class _GraphReplacementProgress extends ConsumerWidget {
  const _GraphReplacementProgress(this.operation);

  final _GraphReplacementOperation operation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<DoableColors>()!;
    final (title, (:share, :cancellation), cancel) = switch (operation) {
      _GraphReplacementOperation.restore => (
        localizations.dataRestoreRunning,
        _restoreProgress(ref.watch(graphRestoreControllerProvider)),
        ref.read(graphRestoreControllerProvider.notifier).cancel,
      ),
      _GraphReplacementOperation.import => (
        localizations.dataImportRunning,
        _importProgress(ref.watch(graphImportControllerProvider)),
        ref.read(graphImportControllerProvider.notifier).cancel,
      ),
    };
    return PopScope<void>(
      canPop: false,
      child: AlertDialog(
        semanticLabel: title,
        content: MergeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: DoableType.title.copyWith(color: colors.ink)),
              const SizedBox(height: DoableMetrics.space4),
              LinearProgressIndicator(
                value: share,
                semanticsValue: switch (share) {
                  null => null,
                  final share => localizations.dataReplacementProgress(share),
                },
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                color: colors.ink,
                backgroundColor: colors.hairline,
              ),
            ],
          ),
        ),
        actions: [
          // Экранный диктор сообщает «Отмена…», как только кнопка её
          // показывает.
          MergeSemantics(
            child: Semantics(
              liveRegion: cancellation == _Cancellation.accepted,
              child: OutlinedButton(
                onPressed: switch (cancellation) {
                  _Cancellation.available => cancel,
                  _Cancellation.unavailable || _Cancellation.accepted => null,
                },
                child: Text(switch (cancellation) {
                  _Cancellation.available || _Cancellation.unavailable =>
                    localizations.dataReplacementCancel,
                  _Cancellation.accepted =>
                    localizations.dataReplacementCancelling,
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Откат после отмены не измеряется. Когда восстановление завершено,
  /// маршрут удаляется раньше следующего кадра.
  _ProgressView _restoreProgress(GraphRestoreState state) => switch (state) {
    GraphRestoreRunning(:final progress) => (
      share: _overallShare(progress),
      cancellation: _Cancellation.available,
    ),
    GraphRestoreCommitting() => (
      share: 1.0,
      cancellation: _Cancellation.unavailable,
    ),
    GraphRestoreCancelling() ||
    GraphRestoreIdle() => (share: null, cancellation: _Cancellation.accepted),
  };

  /// Чтение файла и откат после отмены не измеряются. Когда импорт ждёт
  /// подтверждения или завершён, маршрут удаляется раньше следующего кадра.
  _ProgressView _importProgress(GraphImportState state) => switch (state) {
    GraphImportReadingFile() => (
      share: null,
      cancellation: _Cancellation.available,
    ),
    GraphImportReplacing(:final progress) => (
      share: _overallShare(progress),
      cancellation: _Cancellation.available,
    ),
    GraphImportCommitting() => (
      share: 1.0,
      cancellation: _Cancellation.unavailable,
    ),
    GraphImportCancelling() ||
    GraphImportAwaitingConfirmation() ||
    GraphImportIdle() => (share: null, cancellation: _Cancellation.accepted),
  };

  /// Ход обеих фаз замены одной долей от 0 до 1.
  double _overallShare(GraphReplacementProgress progress) {
    final snapshotWriteShare = operation.snapshotWriteShare;
    return switch (progress.phase) {
      GraphReplacementPhase.snapshotWrite =>
        progress.share * snapshotWriteShare,
      GraphReplacementPhase.replacement =>
        snapshotWriteShare + progress.share * (1 - snapshotWriteShare),
    };
  }
}

/// Что показывает прогресс: долю хода — `null`, пока её нет, — и отмену на
/// кнопке.
typedef _ProgressView = ({double? share, _Cancellation cancellation});

/// Отмена замены на кнопке прогресса.
enum _Cancellation {
  /// Отмену можно запросить кнопкой «Отменить».
  available,

  /// Замена прошла точку невозврата: «Отменить» недоступна до исхода.
  unavailable,

  /// Отмена принята: кнопка показывает «Отмена…», пока отмена не завершена.
  accepted,
}
