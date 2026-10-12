import '../../application/daily_choice_day_statuses.dart';
import '../../domain/calendar_date.dart';

/// Окно отметок вокруг месяца [focusedDate], общее для недели и месяца.
/// Покрывает сетки предыдущего, текущего и следующего месяцев с полными
/// неделями по краям, обрезанными по допустимому диапазону [CalendarDate].
DailyChoiceDayStatusQuery dailyChoiceCalendarDayMarksWindow(
  CalendarDate focusedDate,
) {
  final previousMonth = DateTime.utc(focusedDate.year, focusedDate.month - 1);
  final nextMonthEnd = DateTime.utc(focusedDate.year, focusedDate.month + 2, 0);
  final firstDay = DateTime.utc(
    previousMonth.year,
    previousMonth.month,
    previousMonth.day - (previousMonth.weekday - DateTime.monday),
  );
  final lastDay = DateTime.utc(
    nextMonthEnd.year,
    nextMonthEnd.month,
    nextMonthEnd.day + (DateTime.sunday - nextMonthEnd.weekday),
  );

  return DailyChoiceDayStatusQuery(
    firstDate: _clampToCalendarDate(firstDay),
    lastDate: _clampToCalendarDate(lastDay),
  );
}

final _firstDay = DateTime.utc(
  CalendarDate.earliest.year,
  CalendarDate.earliest.month,
  CalendarDate.earliest.day,
);
final _lastDay = DateTime.utc(
  CalendarDate.latest.year,
  CalendarDate.latest.month,
  CalendarDate.latest.day,
);

CalendarDate _clampToCalendarDate(DateTime day) => day.isBefore(_firstDay)
    ? CalendarDate.earliest
    : day.isAfter(_lastDay)
    ? CalendarDate.latest
    : CalendarDate.fromParts(day.year, day.month, day.day);
