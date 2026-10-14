import '../../daily_choice/domain/calendar_date.dart';

/// Календарный период с включительными границами без часового пояса.
sealed class StatisticsPeriod {
  const StatisticsPeriod();

  int get year;
  CalendarDate get firstDate;
  CalendarDate get lastDate;
  StatisticsPeriod? get previous;
  StatisticsPeriod? get next;
  bool contains(CalendarDate localDate);
}

final class StatisticsMonth extends StatisticsPeriod {
  StatisticsMonth(int year, int month)
    : firstDate = CalendarDate.fromParts(year, month, 1);

  @override
  final CalendarDate firstDate;

  @override
  int get year => firstDate.year;
  int get month => firstDate.month;

  @override
  CalendarDate get lastDate =>
      CalendarDate.fromParts(year, month, DateTime.utc(year, month + 1, 0).day);

  @override
  StatisticsMonth? get previous {
    if (firstDate == CalendarDate.earliest) return null;
    return month == 1
        ? StatisticsMonth(year - 1, 12)
        : StatisticsMonth(year, month - 1);
  }

  @override
  StatisticsMonth? get next {
    if (year == CalendarDate.latest.year && month == 12) return null;
    return month == 12
        ? StatisticsMonth(year + 1, 1)
        : StatisticsMonth(year, month + 1);
  }

  @override
  bool contains(CalendarDate localDate) =>
      localDate.year == year && localDate.month == month;

  @override
  bool operator ==(Object other) =>
      other is StatisticsMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

final class StatisticsYear extends StatisticsPeriod {
  StatisticsYear(int year) : firstDate = CalendarDate.fromParts(year, 1, 1);

  @override
  final CalendarDate firstDate;

  @override
  int get year => firstDate.year;

  @override
  CalendarDate get lastDate => CalendarDate.fromParts(year, 12, 31);

  @override
  StatisticsYear? get previous =>
      year == CalendarDate.earliest.year ? null : StatisticsYear(year - 1);

  @override
  StatisticsYear? get next =>
      year == CalendarDate.latest.year ? null : StatisticsYear(year + 1);

  @override
  bool contains(CalendarDate localDate) => localDate.year == year;

  @override
  bool operator ==(Object other) =>
      other is StatisticsYear && other.year == year;

  @override
  int get hashCode => year.hashCode;
}
