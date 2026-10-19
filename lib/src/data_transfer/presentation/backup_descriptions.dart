import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../graph_backups/graph_change_summary.dart';

/// Когда сделана резервная копия: её день по местному времени устройства
/// относительно текущего дня и время по правилам локали.
sealed class BackupMoment {
  const BackupMoment._(this.time);

  factory BackupMoment.of(
    BuildContext context,
    DateTime madeAt, {
    required DateTime now,
  }) {
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
      return BackupMadeToday._(time);
    }
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return BackupMadeYesterday._(time);
    }
    // Перерыв в использовании копии не удаляет, поэтому копия может быть
    // сделана и в прошлом году; тогда дата называет и год.
    return BackupMadeEarlier._(
      time,
      date: DateFormat(
        made.year == today.year ? 'd MMMM' : 'd MMMM y',
        locale,
      ).format(made),
    );
  }

  /// Время копии по правилам локали.
  final String time;
}

final class BackupMadeToday extends BackupMoment {
  const BackupMadeToday._(super.time) : super._();
}

final class BackupMadeYesterday extends BackupMoment {
  const BackupMadeYesterday._(super.time) : super._();
}

/// Копия сделана раньше вчерашнего дня.
final class BackupMadeEarlier extends BackupMoment {
  const BackupMadeEarlier._(super.time, {required this.date}) : super._();

  /// Дата копии: «6 октября», а копии прошлых лет — «6 октября 2025».
  final String date;
}

/// Изменения [counts] без нулевых частей: «3 добавлено, 2 изменено, 1
/// удалено»; без изменений — `null`.
String? changeCountsText(
  AppLocalizations localizations,
  GraphChangeCounts counts,
) {
  final parts = [
    if (counts.added > 0) localizations.dataBackupAdded(counts.added),
    if (counts.changed > 0) localizations.dataBackupChanged(counts.changed),
    if (counts.deleted > 0) localizations.dataBackupDeleted(counts.deleted),
  ];
  return parts.isEmpty ? null : parts.join(', ');
}
