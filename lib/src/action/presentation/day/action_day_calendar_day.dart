import 'package:flutter/material.dart';

import '../../../design_system/components/month_grid_day.dart';
import '../../../design_system/components/week_strip_day.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../application/action_day_statuses.dart';
import 'action_day_calendar_labels.dart';
import 'action_day_calendar_viewport.dart';

/// Ячейка допустимого дня встроенного календаря экрана дня.
///
/// Часть реализации `ActionDayCalendar`: признаки ячейки вычисляет календарь
/// из своих входов, а нажатие ячейка передаёт в [onSelected]. Выбранность и
/// «сегодня» отмечаются независимо, поэтому при совпадении дней сохраняются оба
/// признака. В неделе тексты и состояние переводятся в контракт [WeekStripDay],
/// в месяце — [MonthGridDay]. Высоту строки задаёт [rowHeight].
///
/// Для вспомогательных технологий ячейка — одна кнопка выбора с полной датой
/// и днём недели, состоянием выбранности, отдельной отметкой «сегодня» и
/// состоянием дня [status], если есть отметка. Доступная активация выполняет
/// то же нажатие, что и касание; число и отметка отдельно не читаются.
final class ActionDayCalendarDay extends StatelessWidget {
  const ActionDayCalendarDay({
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
  final ActionDayStatus? status;
  final bool isSelected;
  final bool isToday;
  final ActionDayCalendarMode mode;

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
    required ActionDayCalendarMode mode,
  }) {
    if (mode == ActionDayCalendarMode.week) {
      return WeekStripDay.rowHeight(
        context,
        dayTexts: [for (var day = 1; day <= 31; day++) '$day'],
        weekdayTexts: [
          for (var day = 1; day <= DateTime.daysPerWeek; day++)
            actionDayCalendarWeekdayLabel(context, DateTime.utc(2024, 1, day)),
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
    if (mode == ActionDayCalendarMode.week) {
      return WeekStripDay(
        dayText: '${date.day}',
        weekdayText: actionDayCalendarWeekdayLabel(
          context,
          DateTime.utc(date.year, date.month, date.day),
        ),
        isSelected: isSelected,
        isToday: isToday,
        mark: actionDayCalendarDayMark(status),
        semanticLabel: actionDayCalendarDayLabel(
          context,
          date: date,
          isToday: isToday,
          status: status,
        ),
        onTap: onSelected,
      );
    }
    return MonthGridDay(
      dayText: '${date.day}',
      isSelected: isSelected,
      isToday: isToday,
      isOutsideMonth: isOutsideMonth,
      mark: actionDayCalendarDayMark(status),
      semanticLabel: actionDayCalendarDayLabel(
        context,
        date: date,
        isToday: isToday,
        status: status,
      ),
      onTap: onSelected,
    );
  }
}
