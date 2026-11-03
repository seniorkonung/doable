import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../design_system/components/dates_line.dart';

/// Строка дат подробностей сущности: день создания и, если он другой, день
/// последнего изменения — оба по местной дате устройства.
///
/// Дата называет день и сокращённый месяц, а год — только если он не
/// совпадает с [currentYear].
DatesLine timestampDatesLine({
  required AppLocalizations localizations,
  required String locale,
  required DateTime createdAt,
  required DateTime updatedAt,
  required int currentYear,
}) {
  final created = createdAt.toLocal();
  final changed = updatedAt.toLocal();
  // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
  String format(DateTime date) => DateFormat(
    date.year == currentYear ? 'd MMM' : 'd MMM y',
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
