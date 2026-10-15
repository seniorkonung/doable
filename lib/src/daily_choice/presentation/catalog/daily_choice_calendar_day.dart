import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/day_mark.dart';
import '../../../design_system/components/month_grid_day.dart';
import '../../../design_system/components/week_strip_day.dart';
import '../../application/daily_choice_day_statuses.dart';
import '../../domain/calendar_date.dart';
import 'daily_choice_calendar_viewport.dart';

/// Ячейка допустимого дня встроенного календаря каталога.
///
/// Часть реализации `DailyChoiceCalendar`: признаки ячейки вычисляет календарь
/// из своих входов, а нажатие ячейка передаёт в [onSelected]. Выбранность и
/// «сегодня» отмечаются независимо, поэтому при совпадении дней сохраняются оба
/// признака. В неделе тексты и состояние переводятся в контракт [WeekStripDay],
/// в месяце — [MonthGridDay]. Высоту строки задаёт [rowHeight].
///
/// Для вспомогательных технологий ячейка — одна кнопка выбора с полной датой
/// и днём недели, состоянием выбранности, отдельной отметкой «сегодня» и
/// состоянием дня [status], если есть отметка. Доступная активация выполняет
/// то же нажатие, что и касание; число и отметка отдельно не читаются.
final class DailyChoiceCalendarDay extends StatelessWidget {
  const DailyChoiceCalendarDay({
    super.key,
    required this.date,
    required this.isSelected,
    required this.isToday,
    required this.isOutsideMonth,
    required this.mode,
    required this.onSelected,
    this.status,
  });

  final CalendarDate date;
  final DailyChoiceDayStatus? status;
  final bool isSelected;
  final bool isToday;
  final DailyChoiceCalendarMode mode;

  /// День соседнего месяца в месячном представлении.
  final bool isOutsideMonth;

  final VoidCallback onSelected;

  /// Высота строки дней при ширине колонки [columnWidth].
  ///
  /// Число любого дня месяца, в том числе выделенное как сегодняшнее,
  /// помещается в ячейку целиком в текущем масштабе текста: если ширины не
  /// хватает, число переносится, а строка становится выше. Ячейка не ниже
  /// области нажатия. Место под отметку резервируется и при её отсутствии.
  static double rowHeight(
    BuildContext context, {
    required double columnWidth,
    required DailyChoiceCalendarMode mode,
  }) {
    if (mode == DailyChoiceCalendarMode.week) {
      return WeekStripDay.rowHeight(
        context,
        dayTexts: [for (var day = 1; day <= 31; day++) '$day'],
        weekdayTexts: [
          for (var day = 1; day <= DateTime.daysPerWeek; day++)
            _weekdayLabel(context, DateTime.utc(2024, 1, day)),
        ],
        columnWidth: columnWidth,
      );
    }
    return MonthGridDay.rowHeight(
      context,
      dayTexts: [for (var day = 1; day <= 31; day++) '$day'],
      columnWidth: columnWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mode == DailyChoiceCalendarMode.week) {
      return WeekStripDay(
        dayText: '${date.day}',
        weekdayText: _weekdayLabel(
          context,
          DateTime.utc(date.year, date.month, date.day),
        ),
        isSelected: isSelected,
        isToday: isToday,
        mark: _mark,
        semanticLabel: _label(context),
        onTap: onSelected,
      );
    }
    return MonthGridDay(
      dayText: '${date.day}',
      isSelected: isSelected,
      isToday: isToday,
      isOutsideMonth: isOutsideMonth,
      mark: _mark,
      semanticLabel: _label(context),
      onTap: onSelected,
    );
  }

  DayMark get _mark => switch (status) {
    null => DayMark.none,
    DailyChoiceDayStatus.hasIncomplete => DayMark.todo,
    DailyChoiceDayStatus.allCompleted => DayMark.done,
  };

  /// Полная дата с днём недели по текущей локали и, у сегодняшнего дня,
  /// отметка «сегодня», затем состояние дня, если оно известно.
  String _label(BuildContext context) {
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
}

String _weekdayLabel(BuildContext context, DateTime day) {
  final label = DateFormat.E(Localizations.localeOf(context).toLanguageTag())
      .format(day);
  return label[0].toUpperCase() + label.substring(1);
}
