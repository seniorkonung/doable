import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/doable_priority.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../domain/action_priority.dart';
import '../../domain/action_schedule.dart';

/// Дата поля: слово для дней рядом с [today], иначе число и короткий месяц, а
/// год — только если он не совпадает с годом [today].
String actionDateValue(
  BuildContext context,
  CalendarDate date, {
  required CalendarDate today,
}) {
  final localizations = AppLocalizations.of(context);
  final value = _dateTime(date);
  // Полночь UTC не знает перевода часов, поэтому дни делятся без остатка.
  return switch (value.difference(_dateTime(today)).inDays) {
    0 => localizations.actionDateToday,
    1 => localizations.actionDateTomorrow,
    -1 => localizations.actionDateYesterday,
    // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
    _ => DateFormat(
      date.year == today.year ? 'd MMM' : 'd MMM y',
      _locale(context),
    ).format(value),
  };
}

/// Полная дата для диктора: короткий вид поля зависит от сегодняшнего дня.
String actionFullDate(BuildContext context, CalendarDate date) =>
    DateFormat.yMMMMEEEEd(_locale(context)).format(_dateTime(date));

/// Время поля в формате часов из [actionUsesTwelveHourClock].
///
/// Формат не выбирается здесь: время строится под тот же формат, что и
/// циферблат, поэтому подписи не расходятся с ним.
String actionTimeValue(BuildContext context, ActionSchedule schedule) =>
    switch (schedule) {
      ActionAllDay() => AppLocalizations.of(context).actionAllDay,
      ActionAtHour(:final hour) =>
        MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay(hour: hour, minute: 0),
          alwaysUse24HourFormat: !actionUsesTwelveHourClock(context),
        ),
    };

/// Показывает ли формат часов действий половину суток.
///
/// Единственное место выбора формата для циферблата и всех подписей времени:
/// итоговый формат складывается из настройки 24-часового времени устройства и
/// шаблона локали. Остальные места берут формат отсюда и не решают его сами.
bool actionUsesTwelveHourClock(BuildContext context) =>
    hourFormat(
      of: MaterialLocalizations.of(context).timeOfDayFormat(
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      ),
    ) ==
    HourFormat.h;

DoablePriority actionDesignPriority(ActionPriority priority) =>
    switch (priority) {
      ActionPriority.p1 => DoablePriority.p1,
      ActionPriority.p2 => DoablePriority.p2,
      ActionPriority.p3 => DoablePriority.p3,
      ActionPriority.p4 => DoablePriority.p4,
    };

ActionPriority actionPriority(DoablePriority priority) => switch (priority) {
  DoablePriority.p1 => ActionPriority.p1,
  DoablePriority.p2 => ActionPriority.p2,
  DoablePriority.p3 => ActionPriority.p3,
  DoablePriority.p4 => ActionPriority.p4,
};

String actionPriorityName(DoablePriority priority) => switch (priority) {
  DoablePriority.p1 => 'P1',
  DoablePriority.p2 => 'P2',
  DoablePriority.p3 => 'P3',
  DoablePriority.p4 => 'P4',
};

/// Диктор слышит порядок приоритетов: выбранную пилюлю объявляет её состояние.
String actionPriorityItemLabel(
  AppLocalizations localizations,
  DoablePriority priority,
) {
  final name = actionPriorityName(priority);
  return switch (priority) {
    DoablePriority.p1 => localizations.relationSheetPriorityHighest(name),
    DoablePriority.p2 ||
    DoablePriority.p3 => localizations.actionPriorityOption(name),
    DoablePriority.p4 => localizations.relationSheetPriorityLowest(name),
  };
}

DateTime _dateTime(CalendarDate date) =>
    DateTime.utc(date.year, date.month, date.day);

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toLanguageTag();
