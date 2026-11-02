import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/doable_priority.dart';
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice_priority.dart';
import '../../domain/daily_choice_schedule.dart';

/// Дата поля: слово для дней рядом с [today], иначе число и короткий месяц, а
/// год — только если он не совпадает с годом [today].
String dailyChoiceDateValue(
  BuildContext context,
  CalendarDate date, {
  required CalendarDate today,
}) {
  final localizations = AppLocalizations.of(context);
  final value = _dateTime(date);
  // Полночь UTC не знает перевода часов, поэтому дни делятся без остатка.
  return switch (value.difference(_dateTime(today)).inDays) {
    0 => localizations.dailyChoiceCalendarToday,
    1 => localizations.dailyChoiceDateTomorrow,
    -1 => localizations.dailyChoiceDateYesterday,
    // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
    _ => DateFormat(
      date.year == today.year ? 'd MMM' : 'd MMM y',
      _locale(context),
    ).format(value),
  };
}

/// Полная дата для диктора: короткий вид поля зависит от сегодняшнего дня.
String dailyChoiceFullDate(BuildContext context, CalendarDate date) =>
    DateFormat.yMMMMEEEEd(_locale(context)).format(_dateTime(date));

/// Время поля в формате часов устройства; минуты показываются как сохранены.
String dailyChoiceTimeValue(
  BuildContext context,
  DailyChoiceSchedule schedule,
) => switch (schedule) {
  DailyChoiceAllDay() => AppLocalizations.of(context).dailyChoiceAllDay,
  DailyChoiceTime(:final hour, :final minute) => TimeOfDay(
    hour: hour,
    minute: minute,
  ).format(context),
};

DoablePriority dailyChoiceDesignPriority(DailyChoicePriority priority) =>
    switch (priority) {
      DailyChoicePriority.p1 => DoablePriority.p1,
      DailyChoicePriority.p2 => DoablePriority.p2,
      DailyChoicePriority.p3 => DoablePriority.p3,
      DailyChoicePriority.p4 => DoablePriority.p4,
    };

String dailyChoicePriorityName(DoablePriority priority) => switch (priority) {
  DoablePriority.p1 => 'P1',
  DoablePriority.p2 => 'P2',
  DoablePriority.p3 => 'P3',
  DoablePriority.p4 => 'P4',
};

/// Диктор слышит порядок приоритетов: выбранную пилюлю объявляет её состояние.
String dailyChoicePriorityItemLabel(
  AppLocalizations localizations,
  DoablePriority priority,
) {
  final name = dailyChoicePriorityName(priority);
  return switch (priority) {
    DoablePriority.p1 => localizations.relationSheetPriorityHighest(name),
    DoablePriority.p2 ||
    DoablePriority.p3 => localizations.dailyChoicePriorityOption(name),
    DoablePriority.p4 => localizations.relationSheetPriorityLowest(name),
  };
}

DateTime _dateTime(CalendarDate date) =>
    DateTime.utc(date.year, date.month, date.day);

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toLanguageTag();
