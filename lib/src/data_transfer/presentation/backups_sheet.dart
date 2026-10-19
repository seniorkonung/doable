import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import '../../daily_choice/presentation/catalog/daily_choice_local_day_observer.dart';
import '../../design_system/components/notice.dart';
import '../../design_system/components/sheet.dart';
import '../../design_system/doable_colors.dart';
import '../../design_system/doable_metrics.dart';
import '../../design_system/doable_type.dart';
import '../../graph/application/graph_command_coordinator.dart';
import '../../graph_backups/graph_backup_registry.dart';
import '../../graph_backups/graph_backups_provider.dart';
import '../../graph_backups/graph_change_summary.dart';
import '../application/graph_restore_provider.dart';
import 'backup_descriptions.dart';
import 'restore_backup_confirmation.dart';

/// Открывает над страницей и её панелью навигации панель «Резервные копии»
/// с копиями от новых к старым по созданию и кнопкой ручной копии.
///
/// Выбор копии открывает подтверждение её восстановления, а подтверждение
/// закрывает панель. Возвращает копию, восстановление которой подтверждено;
/// если панель закрыта без подтверждения — `null`. Восстановление начинает
/// вызывающий, когда панель уже закрыта: иначе её закрытие закрыло бы
/// модальный прогресс восстановления.
///
/// Ручная копия идёт без прогресса, а её успех сообщения не даёт: новая
/// копия появляется в списке. Отказ ручной копии показывает общая
/// поверхность результатов, когда панель уже закрыта.
Future<GraphBackupEntry?> showBackupsSheet(BuildContext context) =>
    showDoableSheet<GraphBackupEntry>(
      context: context,
      builder: (_) => const _BackupsSheet(),
    );

final class _BackupsSheet extends ConsumerStatefulWidget {
  const _BackupsSheet();

  @override
  ConsumerState<_BackupsSheet> createState() => _BackupsSheetState();
}

final class _BackupsSheetState extends ConsumerState<_BackupsSheet> {
  /// Перестраивает панель с началом другой местной даты, чтобы дни копий
  /// назывались относительно нового сегодня.
  late final DailyChoiceLocalDayObserver _localDay;

  @override
  void initState() {
    super.initState();
    _localDay = DailyChoiceLocalDayObserver(
      readLocalDay: ref.read(dailyChoiceLocalDateSourceProvider),
      onTodayChanged: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _localDay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final now = ref.watch(graphBackupsClockProvider)();
    return Sheet(
      title: localizations.dataBackupsTitle,
      text: localizations.dataBackupsExplanation,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...switch (ref.watch(graphBackupListProvider).value) {
            // Пока список не прочитан, панель показывает только кнопку.
            null => const <Widget>[],
            GraphBackupsReadSucceeded(:final backups) => [
              for (final backup in backups)
                _BackupRow(
                  backup,
                  now: now,
                  onPressed: () => _confirmRestore(context, ref, backup),
                ),
            ],
            // Отказ чтения не означает, что копий нет.
            GraphBackupsReadFailed() => [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DoableMetrics.space2,
                ),
                child: Notice(message: localizations.dataBackupsReadFailed),
              ),
            ],
          },
          const SizedBox(height: DoableMetrics.space3),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DoableMetrics.space2,
            ),
            child: FilledButton(
              // Вторую копию, пока делается первая, координатор не принимает,
              // а исход копии предъявляет сам.
              onPressed: () => ref
                  .read(graphCommandCoordinatorProvider.notifier)
                  .acceptManualBackup(
                    ref.read(graphBackupsProvider).makeManualBackup,
                  ),
              child: Text(localizations.dataBackupsMakeNow),
            ),
          ),
        ],
      ),
    );
  }
}

/// Подтверждает восстановление копии [backup] с изменениями с тех пор и
/// закрывает панель с подтверждённой копией.
Future<void> _confirmRestore(
  BuildContext context,
  WidgetRef ref,
  GraphBackupEntry backup,
) async {
  final confirmed = await confirmBackupRestore(
    context,
    backup: backup,
    changesSince: ref
        .read(graphRestoreControllerProvider.notifier)
        .countChangesSince(backup),
  );
  if (confirmed && context.mounted) Navigator.of(context).pop(backup);
}

/// Копия: когда она сделана и что изменилось с предыдущей копии. Экранный
/// диктор читает её как кнопку восстановления копии от этого момента со
/// сводкой.
final class _BackupRow extends StatelessWidget {
  const _BackupRow(this.backup, {required this.now, required this.onPressed});

  final GraphBackupEntry backup;
  final DateTime now;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<DoableColors>()!;
    final moment = _momentTexts(
      localizations,
      BackupMoment.of(context, backup.madeAt, now: now),
    );
    const figures = [FontFeature.tabularFigures()];
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: moment.restoreLabel,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(DoableMetrics.radiusLg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DoableMetrics.space4,
                vertical: 6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      moment.label,
                      style: DoableType.action.copyWith(
                        color: colors.ink,
                        fontFeatures: figures,
                      ),
                    ),
                  ),
                  Text(
                    _summaryText(localizations, backup.summary),
                    style: DoableType.hint.copyWith(
                      color: colors.muted,
                      fontFeatures: figures,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Подпись копии в списке и её доступное название.
({String label, String restoreLabel}) _momentTexts(
  AppLocalizations localizations,
  BackupMoment moment,
) => switch (moment) {
  BackupMadeToday(:final time) => (
    label: localizations.dataBackupMadeToday(time),
    restoreLabel: localizations.dataBackupRestoreMadeToday(time),
  ),
  BackupMadeYesterday(:final time) => (
    label: localizations.dataBackupMadeYesterday(time),
    restoreLabel: localizations.dataBackupRestoreMadeYesterday(time),
  ),
  BackupMadeEarlier(:final date, :final time) => (
    label: localizations.dataBackupMadeOn(date, time),
    restoreLabel: localizations.dataBackupRestoreMadeOn(date, time),
  ),
};

/// Что изменилось с предыдущей копии: части без нулевых чисел, «Нет
/// изменений» или признак замены графа.
String _summaryText(
  AppLocalizations localizations,
  GraphChangeSummary summary,
) => switch (summary) {
  GraphDataReplaced() => localizations.dataBackupDataReplaced,
  final GraphChangeCounts counts =>
    changeCountsText(localizations, counts) ??
        localizations.dataBackupNoChanges,
};
