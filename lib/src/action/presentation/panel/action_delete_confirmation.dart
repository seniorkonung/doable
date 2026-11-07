import 'package:flutter/material.dart' hide Action;
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/confirm_dialog.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../domain/action.dart';

/// Подтверждение называет действие и его дату: сегодняшнюю словом, остальные
/// числом и месяцем.
Future<bool> confirmActionDeletion(
  BuildContext context,
  Action action, {
  required CalendarDate today,
}) {
  final localizations = AppLocalizations.of(context);
  final date = action.date;
  return showConfirmDialog(
    context: context,
    title: localizations.actionDeleteDialogTitle,
    text: ConfirmDialogText(
      before: localizations.actionDeleteDialogBefore,
      name: action.title.value,
      after: localizations.actionDeleteDialogAfter(
        date == today
            ? localizations.actionDeleteDialogToday
            // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
            : DateFormat.MMMMd(Localizations.localeOf(context).toLanguageTag())
                  .format(DateTime.utc(date.year, date.month, date.day)),
      ),
    ),
    cancelLabel: localizations.detailsCancelEditAction,
    actionLabel: localizations.actionDeleteDialogAction,
  );
}
