import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/day_mark.dart';
import '../../application/daily_choice_day_statuses.dart';
import '../../domain/calendar_date.dart';

// Подписи календаря, общие для календаря каталога и листа даты: обе сетки
// называют месяц, дни недели и дни одинаково.

/// Короткое название дня недели над колонкой: «Пн».
String dailyChoiceCalendarWeekdayLabel(BuildContext context, DateTime day) {
  final label = DateFormat.E(Localizations.localeOf(context).toLanguageTag())
      .format(day);
  return label[0].toUpperCase() + label.substring(1);
}

/// Заголовок месяца: «Октябрь 2026».
String dailyChoiceCalendarMonthTitle(BuildContext context, CalendarDate date) {
  // L — самостоятельная форма названия месяца, без суффикса года:
  // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
  final title = DateFormat(
    'LLLL y',
    Localizations.localeOf(context).toLanguageTag(),
  ).format(DateTime.utc(date.year, date.month, date.day));
  return title[0].toUpperCase() + title.substring(1);
}

/// Отметка под числом дня по состоянию дня; без состояния отметки нет.
DayMark dailyChoiceCalendarDayMark(DailyChoiceDayStatus? status) =>
    switch (status) {
      null => DayMark.none,
      DailyChoiceDayStatus.hasIncomplete => DayMark.todo,
      DailyChoiceDayStatus.allCompleted => DayMark.done,
    };

/// Полная дата с днём недели по текущей локали и, у сегодняшнего дня,
/// отметка «сегодня», затем состояние дня, если оно известно.
String dailyChoiceCalendarDayLabel(
  BuildContext context, {
  required CalendarDate date,
  required bool isToday,
  required DailyChoiceDayStatus? status,
}) {
  // Технический `DateTime` в UTC нужен только для форматирования
  // календарных частей и не задаёт часовой пояс даты.
  final fullDate = MaterialLocalizations.of(context)
      .formatFullDate(DateTime.utc(date.year, date.month, date.day));
  final localizations = AppLocalizations.of(context);
  return [
    fullDate,
    if (isToday) localizations.dailyChoiceCalendarToday,
    ?switch (status) {
      null => null,
      DailyChoiceDayStatus.allCompleted =>
        localizations.dailyChoiceCalendarDayAllCompleted,
      DailyChoiceDayStatus.hasIncomplete =>
        localizations.dailyChoiceCalendarDayHasIncomplete,
    },
  ].join(', ');
}
