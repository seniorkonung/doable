import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../daily_choice/domain/calendar_date.dart';
import '../../../design_system/components/dates_line.dart';
import '../../domain/intention.dart';

/// Строка дат в конце «Обзора»: день создания намерения и, если он другой,
/// день последнего изменения — оба по местной дате устройства.
///
/// Дата называет день и сокращённый месяц, а год — только если он не
/// совпадает с годом [today].
DatesLine intentionDatesLine({
  required AppLocalizations localizations,
  required String locale,
  required IntentionTimestamp createdAt,
  required IntentionTimestamp updatedAt,
  required CalendarDate today,
}) {
  final created = createdAt.value.toLocal();
  final changed = updatedAt.value.toLocal();
  // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
  String format(DateTime date) => DateFormat(
    date.year == today.year ? 'd MMM' : 'd MMM y',
    locale,
  ).format(date);
  final sameDay =
      created.year == changed.year &&
      created.month == changed.month &&
      created.day == changed.day;
  return DatesLine(
    created: (label: localizations.detailsCreatedLabel, date: format(created)),
    changed: sameDay
        ? null
        : (label: localizations.detailsChangedLabel, date: format(changed)),
  );
}
