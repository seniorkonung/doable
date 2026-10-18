import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../design_system/components/notice.dart';
import '../../design_system/components/sheet.dart';
import '../../design_system/doable_colors.dart';
import '../../design_system/doable_metrics.dart';
import '../../design_system/doable_type.dart';
import '../../graph/application/graph_command_coordinator.dart';
import '../../graph_backups/graph_backup_registry.dart';
import '../../graph_backups/graph_backups_provider.dart';
import '../../graph_backups/graph_change_summary.dart';

/// Открывает над страницей и её панелью навигации панель «Резервные копии»
/// с копиями от новых к старым по созданию и кнопкой ручной копии.
///
/// Ручная копия идёт без прогресса, а её успех сообщения не даёт: новая
/// копия появляется в списке. Отказ ручной копии показывает общая
/// поверхность результатов, когда панель уже закрыта.
Future<void> showBackupsSheet(BuildContext context) => showDoableSheet<void>(
  context: context,
  builder: (_) => const _BackupsSheet(),
);

final class _BackupsSheet extends ConsumerWidget {
  const _BackupsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              for (final backup in backups) _BackupRow(backup, now: now),
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

/// Копия: когда она сделана и что изменилось с предыдущей копии. Экранный
/// диктор читает её как восстановление копии от этого момента со сводкой.
final class _BackupRow extends StatelessWidget {
  const _BackupRow(this.backup, {required this.now});

  final GraphBackupEntry backup;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final moment = _BackupMoment.of(context, backup.madeAt, now: now);
    const figures = [FontFeature.tabularFigures()];
    return MergeSemantics(
      child: Semantics(
        label: moment.restoreLabel,
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
                  _summaryText(AppLocalizations.of(context), backup.summary),
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
    );
  }
}

/// Момент копии относительно текущего дня по правилам локали: подпись в
/// списке и доступное название копии.
final class _BackupMoment {
  const _BackupMoment._({required this.label, required this.restoreLabel});

  factory _BackupMoment.of(
    BuildContext context,
    DateTime madeAt, {
    required DateTime now,
  }) {
    final localizations = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final made = madeAt.toLocal();
    final today = now.toLocal();
    // Время по шаблону локали: «08:15» по-русски, «8:15 AM» по-английски, —
    // а при 24-часовом формате устройства — «08:15» в любой локали.
    // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
    final time = switch (MediaQuery.alwaysUse24HourFormatOf(context)) {
      true => DateFormat.Hm(locale),
      false => DateFormat.jm(locale),
    }.format(made);
    final day = DateTime(made.year, made.month, made.day);
    if (day == DateTime(today.year, today.month, today.day)) {
      return _BackupMoment._(
        label: localizations.dataBackupMadeToday(time),
        restoreLabel: localizations.dataBackupRestoreMadeToday(time),
      );
    }
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return _BackupMoment._(
        label: localizations.dataBackupMadeYesterday(time),
        restoreLabel: localizations.dataBackupRestoreMadeYesterday(time),
      );
    }
    // Перерыв в использовании копии не удаляет, поэтому копия может быть
    // сделана и в прошлом году; тогда дата называет и год.
    final date = DateFormat(
      made.year == today.year ? 'd MMMM' : 'd MMMM y',
      locale,
    ).format(made);
    return _BackupMoment._(
      label: localizations.dataBackupMadeOn(date, time),
      restoreLabel: localizations.dataBackupRestoreMadeOn(date, time),
    );
  }

  final String label;
  final String restoreLabel;
}

/// Что изменилось с предыдущей копии: части без нулевых чисел, «Нет
/// изменений» или признак замены графа.
String _summaryText(
  AppLocalizations localizations,
  GraphChangeSummary summary,
) {
  switch (summary) {
    case GraphDataReplaced():
      return localizations.dataBackupDataReplaced;
    case GraphChangeCounts(:final added, :final changed, :final deleted):
      final parts = [
        if (added > 0) localizations.dataBackupAdded(added),
        if (changed > 0) localizations.dataBackupChanged(changed),
        if (deleted > 0) localizations.dataBackupDeleted(deleted),
      ];
      return parts.isEmpty
          ? localizations.dataBackupNoChanges
          : parts.join(', ');
  }
}
