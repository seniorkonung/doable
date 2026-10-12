import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (description, focusedDate, firstDate, lastDate) in [
    (
      'октябрь покрывает соседние месячные сетки и крайние недели',
      '2026-10-15',
      '2026-08-31',
      '2026-12-06',
    ),
    (
      'январь включает предыдущий год',
      '2027-01-01',
      '2026-11-30',
      '2027-02-28',
    ),
    (
      'декабрь включает следующий год',
      '2026-12-31',
      '2026-10-26',
      '2027-01-31',
    ),
    (
      'март включает високосный февраль и полные граничные недели',
      '2024-03-31',
      '2024-01-29',
      '2024-05-05',
    ),
    (
      'февраль с понедельника по воскресенье не сокращает соседние сетки',
      '2027-02-14',
      '2026-12-28',
      '2027-04-04',
    ),
    (
      'январь первого года обрезается по первой допустимой дате',
      '0001-01-01',
      '0001-01-01',
      '0001-03-04',
    ),
    (
      'февраль первого года сохраняет первую допустимую неделю',
      '0001-02-28',
      '0001-01-01',
      '0001-04-01',
    ),
    (
      'ноябрь последнего года обрезает конец соседней сетки',
      '9999-11-01',
      '9999-09-27',
      '9999-12-31',
    ),
    (
      'декабрь последнего года обрезает следующий месяц',
      '9999-12-31',
      '9999-11-01',
      '9999-12-31',
    ),
  ]) {
    test(description, () {
      final window = dailyChoiceCalendarDayMarksWindow(
        CalendarDate.parseCanonical(focusedDate),
      );

      expect(window.firstDate, CalendarDate.parseCanonical(firstDate));
      expect(window.lastDate, CalendarDate.parseCanonical(lastDate));
    });
  }

  test('окно зависит только от месяца даты просмотра', () {
    final firstDay = dailyChoiceCalendarDayMarksWindow(
      CalendarDate.fromParts(2026, 10, 1),
    );
    final lastDay = dailyChoiceCalendarDayMarksWindow(
      CalendarDate.fromParts(2026, 10, 31),
    );

    expect(lastDay.firstDate, firstDay.firstDate);
    expect(lastDay.lastDate, firstDay.lastDate);
  });
}
