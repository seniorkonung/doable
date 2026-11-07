import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/day_mark.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../application/action_day_statuses.dart';

// Подписи календаря, общие для календаря экрана дня и листа даты: обе сетки
// называют месяц, дни недели и дни одинаково.

/// Короткое название дня недели над колонкой: «Пн».
String actionDayCalendarWeekdayLabel(BuildContext context, DateTime day) {
  final label = DateFormat.E(Localizations.localeOf(context).toLanguageTag())
      .format(day);
  return label[0].toUpperCase() + label.substring(1);
}

/// Заголовок месяца: «Октябрь 2026».
String actionDayCalendarMonthTitle(BuildContext context, CalendarDate date) {
  // L — самостоятельная форма названия месяца, без суффикса года:
  // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
  final title = DateFormat(
    'LLLL y',
    Localizations.localeOf(context).toLanguageTag(),
  ).format(DateTime.utc(date.year, date.month, date.day));
  return title[0].toUpperCase() + title.substring(1);
}

/// Отметка под числом дня по состоянию дня; без состояния отметки нет.
DayMark actionDayCalendarDayMark(ActionDayStatus? status) => switch (status) {
  null => DayMark.none,
  ActionDayStatus.hasIncomplete => DayMark.todo,
  ActionDayStatus.allCompleted => DayMark.done,
};

/// Полная дата с днём недели по текущей локали и, у сегодняшнего дня,
/// отметка «сегодня», затем состояние дня, если оно известно.
String actionDayCalendarDayLabel(
  BuildContext context, {
  required CalendarDate date,
  required bool isToday,
  required ActionDayStatus? status,
}) {
  // Технический `DateTime` в UTC нужен только для форматирования
  // календарных частей и не задаёт часовой пояс даты.
  final fullDate = MaterialLocalizations.of(context)
      .formatFullDate(DateTime.utc(date.year, date.month, date.day));
  final localizations = AppLocalizations.of(context);
  return [
    fullDate,
    if (isToday) localizations.actionDateToday,
    ?switch (status) {
      null => null,
      ActionDayStatus.allCompleted =>
        localizations.actionCalendarDayAllCompleted,
      ActionDayStatus.hasIncomplete =>
        localizations.actionCalendarDayHasIncomplete,
    },
  ].join(', ');
}
