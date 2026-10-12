import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('месяц задаёт включительные границы с учётом високосного года', () {
    for (final (year, month, lastDay) in [
      (2026, 10, 31),
      (2026, 4, 30),
      (2026, 2, 28),
      (2024, 2, 29),
      (1900, 2, 28),
      (2000, 2, 29),
    ]) {
      final period = StatisticsMonth(year, month);

      expect(period.firstDate, CalendarDate.fromParts(year, month, 1));
      expect(period.lastDate, CalendarDate.fromParts(year, month, lastDay));
    }
  });

  test('год включает все даты от первого января до последнего декабря', () {
    final period = StatisticsYear(2024);

    expect(period.firstDate, CalendarDate.fromParts(2024, 1, 1));
    expect(period.lastDate, CalendarDate.fromParts(2024, 12, 31));
    expect(period.contains(CalendarDate.fromParts(2024, 2, 29)), isTrue);
    expect(period.contains(period.firstDate), isTrue);
    expect(period.contains(period.lastDate), isTrue);
    expect(period.contains(CalendarDate.fromParts(2023, 12, 31)), isFalse);
    expect(period.contains(CalendarDate.fromParts(2025, 1, 1)), isFalse);
  });

  test('принадлежность месяцу включает границы и исключает соседние даты', () {
    final period = StatisticsMonth(2026, 10);

    expect(period.contains(period.firstDate), isTrue);
    expect(period.contains(period.lastDate), isTrue);
    expect(period.contains(CalendarDate.fromParts(2026, 10, 12)), isTrue);
    expect(period.contains(CalendarDate.fromParts(2026, 9, 30)), isFalse);
    expect(period.contains(CalendarDate.fromParts(2026, 11, 1)), isFalse);
    expect(period.contains(CalendarDate.fromParts(2025, 10, 12)), isFalse);
  });

  test('соседние месяцы переходят через границу года в обе стороны', () {
    expect(StatisticsMonth(2026, 1).previous, StatisticsMonth(2025, 12));
    expect(StatisticsMonth(2026, 12).next, StatisticsMonth(2027, 1));
    expect(StatisticsMonth(2026, 10).previous, StatisticsMonth(2026, 9));
    expect(StatisticsMonth(2026, 10).next, StatisticsMonth(2026, 11));
  });

  test('соседние годы сохраняют годовой период', () {
    expect(StatisticsYear(2026).previous, StatisticsYear(2025));
    expect(StatisticsYear(2026).next, StatisticsYear(2027));
  });

  test('за границами календарных дат соседних периодов нет', () {
    final firstMonth = StatisticsMonth(CalendarDate.earliest.year, 1);
    final lastMonth = StatisticsMonth(CalendarDate.latest.year, 12);
    final firstYear = StatisticsYear(CalendarDate.earliest.year);
    final lastYear = StatisticsYear(CalendarDate.latest.year);

    expect(firstMonth.firstDate, CalendarDate.earliest);
    expect(lastMonth.lastDate, CalendarDate.latest);
    expect(firstYear.firstDate, CalendarDate.earliest);
    expect(lastYear.lastDate, CalendarDate.latest);
    expect(firstMonth.previous, isNull);
    expect(firstYear.previous, isNull);
    expect(lastMonth.next, isNull);
    expect(lastYear.next, isNull);
    expect(firstMonth.next, StatisticsMonth(1, 2));
    expect(lastMonth.previous, StatisticsMonth(9999, 11));
    expect(firstYear.next, StatisticsYear(2));
    expect(lastYear.previous, StatisticsYear(9998));
  });

  test('период отклоняет год и месяц вне допустимого календаря', () {
    for (final create in <StatisticsPeriod Function()>[
      () => StatisticsMonth(0, 1),
      () => StatisticsYear(10000),
      () => StatisticsMonth(2026, 13),
    ]) {
      expect(create, throwsA(isA<CalendarDateValidationException>()));
    }
  });
}
