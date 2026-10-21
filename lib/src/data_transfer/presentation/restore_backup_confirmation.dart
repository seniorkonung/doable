import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import '../../daily_choice/presentation/catalog/daily_choice_local_day_observer.dart';
import '../../design_system/doable_colors.dart';
import '../../design_system/doable_metrics.dart';
import '../../design_system/doable_type.dart';
import '../../graph_backups/graph_backup_registry.dart';
import '../../graph_backups/graph_backups_provider.dart';
import '../../graph_backups/graph_change_summary.dart';
import '../application/graph_restore.dart';
import 'backup_descriptions.dart';

/// Открывает над страницей подтверждение «Восстановить эту копию?»: когда
/// сделана копия [backup], что восстановление отменит — изменения
/// [changesSince] с тех пор, — и что оно заменит весь граф.
///
/// Пока изменения считаются, восстановить копию нельзя, чтобы его не
/// подтвердили, не увидев, что будет отменено. Не посчитанные изменения
/// подтверждение не называет, а восстановление остаётся доступным.
/// Возвращает `true`, только если выбрано «Восстановить копию».
Future<bool> confirmBackupRestore(
  BuildContext context, {
  required GraphBackupEntry backup,
  required Future<GraphChangesSinceBackup> changesSince,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _RestoreBackupConfirmation(
        backup: backup,
        changesSince: changesSince,
      ),
    ) ??
    false;

final class _RestoreBackupConfirmation extends ConsumerStatefulWidget {
  const _RestoreBackupConfirmation({
    required this.backup,
    required this.changesSince,
  });

  final GraphBackupEntry backup;
  final Future<GraphChangesSinceBackup> changesSince;

  @override
  ConsumerState<_RestoreBackupConfirmation> createState() =>
      _RestoreBackupConfirmationState();
}

final class _RestoreBackupConfirmationState
    extends ConsumerState<_RestoreBackupConfirmation> {
  /// Перестраивает подтверждение с началом другой местной даты, чтобы день
  /// копии назывался относительно нового сегодня.
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
    final colors = Theme.of(context).extension<DoableColors>()!;
    final title = localizations.dataRestoreConfirmationTitle;
    final made = switch (BackupMoment.of(
      context,
      widget.backup.madeAt,
      now: ref.watch(graphBackupsClockProvider)(),
    )) {
      BackupMadeToday(:final time) => localizations.dataRestoreMadeToday(time),
      BackupMadeYesterday(:final time) =>
        localizations.dataRestoreMadeYesterday(time),
      BackupMadeEarlier(:final dateWithYear, :final time) =>
        localizations.dataRestoreMadeOn(dateWithYear, time),
    };
    return FutureBuilder(
      future: widget.changesSince,
      builder: (context, counting) => AlertDialog(
        semanticLabel: title,
        scrollable: true,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [made, ?_sinceText(localizations, counting.data)].join(' '),
              style: DoableType.body.copyWith(
                color: colors.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: DoableMetrics.space2),
            Text(
              localizations.dataReplacementReplacesEverything,
              style: DoableType.body.copyWith(color: colors.ink),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(localizations.dataReplacementConfirmationCancel),
          ),
          FilledButton(
            onPressed: counting.connectionState == ConnectionState.done
                ? () => Navigator.of(context).pop(true)
                : null,
            child: Text(localizations.dataRestoreConfirm),
          ),
        ],
      ),
    );
  }
}

/// Что восстановление отменит; пока изменения считаются или если их не
/// посчитали — `null`.
String? _sinceText(
  AppLocalizations localizations,
  GraphChangesSinceBackup? changesSince,
) => switch (changesSince) {
  GraphChangesSinceBackupCounted(summary: GraphDataReplaced()) =>
    localizations.dataRestoreReplacedSince,
  GraphChangesSinceBackupCounted(summary: final GraphChangeCounts counts) =>
    switch (changeCountsText(localizations, counts)) {
      final changes? => localizations.dataRestoreChangesSince(changes),
      null => localizations.dataRestoreNoChangesSince,
    },
  GraphChangesSinceBackupUncounted() || null => null,
};
