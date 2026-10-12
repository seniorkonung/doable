import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('диапазон из одного дня допустим на обеих границах календаря', () {
    for (final date in [CalendarDate.earliest, CalendarDate.latest]) {
      final query = DailyChoiceDayStatusQuery(firstDate: date, lastDate: date);

      expect(query.firstDate, date);
      expect(query.lastDate, date);
    }
  });

  test(
    '98 дней включительно допустимы через границу года и високосный день',
    () {
      for (final (first, last) in [
        ('2026-12-01', '2027-03-08'),
        ('2024-02-01', '2024-05-08'),
      ]) {
        final firstDate = CalendarDate.parseCanonical(first);
        final lastDate = CalendarDate.parseCanonical(last);
        final query = DailyChoiceDayStatusQuery(
          firstDate: firstDate,
          lastDate: lastDate,
        );

        expect(query.firstDate, firstDate);
        expect(query.lastDate, lastDate);
      }
    },
  );

  test('обратный диапазон отклоняется до чтения', () {
    expect(
      () => DailyChoiceDayStatusQuery(
        firstDate: CalendarDate.fromParts(2026, 10, 6),
        lastDate: CalendarDate.fromParts(2026, 10, 5),
      ),
      throwsA(
        isA<DailyChoiceDayStatusQueryValidationException>().having(
          (error) => error.failure,
          'failure',
          DailyChoiceDayStatusQueryValidationFailure.reversedRange,
        ),
      ),
    );
  });

  test('99 дней включительно превышают предел чтения', () {
    expect(
      () => DailyChoiceDayStatusQuery(
        firstDate: CalendarDate.fromParts(2024, 2, 1),
        lastDate: CalendarDate.fromParts(2024, 5, 9),
      ),
      throwsA(
        isA<DailyChoiceDayStatusQueryValidationException>().having(
          (error) => error.failure,
          'failure',
          DailyChoiceDayStatusQueryValidationFailure.rangeTooLong,
        ),
      ),
    );
  });

  test('результат сохраняет состояния при изменении исходной карты', () {
    final firstDate = CalendarDate.fromParts(2026, 10, 5);
    final lastDate = CalendarDate.fromParts(2026, 10, 7);
    final incompleteDate = CalendarDate.fromParts(2026, 10, 6);
    final statuses = {
      firstDate: DailyChoiceDayStatus.allCompleted,
      incompleteDate: DailyChoiceDayStatus.hasIncomplete,
    };
    final result = DailyChoiceDayStatuses(
      query: DailyChoiceDayStatusQuery(
        firstDate: firstDate,
        lastDate: lastDate,
      ),
      statuses: statuses,
    );

    statuses.clear();

    expect(result.statuses, {
      firstDate: DailyChoiceDayStatus.allCompleted,
      incompleteDate: DailyChoiceDayStatus.hasIncomplete,
    });
    expect(result.statuses[lastDate], isNull);
    expect(
      () => result.statuses[firstDate] = DailyChoiceDayStatus.hasIncomplete,
      throwsUnsupportedError,
    );
  });
}
