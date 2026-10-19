import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/doable_colors.dart';
import '../../design_system/doable_metrics.dart';
import '../../design_system/doable_type.dart';
import '../application/graph_restore.dart';
import '../application/graph_restore_provider.dart';

/// Пока идёт восстановление копии, показывает над страницей [child], её
/// панелью навигации и остальным приложением модальный прогресс с ходом и
/// кнопкой «Отменить».
///
/// Прогресс открывается, когда восстановление начинается, и закрывается без
/// сообщения, когда оно завершается: успехом, отказом или отменой. Исход
/// предъявляет координатор. Системное «назад» прогресс не закрывает.
final class GraphRestoreProgressHost extends ConsumerStatefulWidget {
  const GraphRestoreProgressHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<GraphRestoreProgressHost> createState() =>
      _GraphRestoreProgressHostState();
}

final class _GraphRestoreProgressHostState
    extends ConsumerState<GraphRestoreProgressHost> {
  /// Прогресс идущего восстановления.
  Route<void>? _progress;

  @override
  void initState() {
    super.initState();
    // Восстановление может завершиться раньше первого кадра прогресса,
    // поэтому прогресс открывает и закрывает слушатель состояния, а не сам
    // прогресс.
    ref.listenManual(graphRestoreControllerProvider, (_, state) {
      switch (state) {
        case GraphRestoreRunning() || GraphRestoreCancelling():
          _open();
        case GraphRestoreIdle():
          _close();
      }
    });
  }

  void _open() {
    if (_progress != null) return;
    final route = _progress = DialogRoute<void>(
      context: context,
      barrierColor: Theme.of(context).extension<DoableColors>()!.scrim,
      barrierDismissible: false,
      builder: (_) => const _GraphRestoreProgress(),
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

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Доля записи снимка замены в общем ходе восстановления. На профиле замера
/// решения 15 дизайна она занимает около 30 % восстановления, поэтому ход
/// растёт примерно равномерно.
const _snapshotWriteShare = 0.3;

/// Модальный прогресс восстановления: экранный диктор читает, что идёт
/// восстановление, его ход и кнопку «Отменить», а после отмены — «Отмена…»
/// до конца отката.
final class _GraphRestoreProgress extends ConsumerWidget {
  const _GraphRestoreProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<DoableColors>()!;
    final title = localizations.dataRestoreRunning;
    // Откат после отмены не измеряется. Когда восстановление завершено,
    // маршрут удаляется раньше следующего кадра.
    final (share, isCancelling) = switch (ref.watch(
      graphRestoreControllerProvider,
    )) {
      GraphRestoreRunning(:final progress) => (_overallShare(progress), false),
      GraphRestoreCancelling() || GraphRestoreIdle() => (null, true),
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
              liveRegion: isCancelling,
              child: OutlinedButton(
                onPressed: isCancelling
                    ? null
                    : ref.read(graphRestoreControllerProvider.notifier).cancel,
                child: Text(
                  isCancelling
                      ? localizations.dataReplacementCancelling
                      : localizations.dataReplacementCancel,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ход обеих фаз восстановления одной долей от 0 до 1.
double _overallShare(GraphRestoreProgress progress) => switch (progress.phase) {
  GraphRestorePhase.snapshotWrite => progress.share * _snapshotWriteShare,
  GraphRestorePhase.replacement =>
    _snapshotWriteShare + progress.share * (1 - _snapshotWriteShare),
};
