import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('105 дней включительно допустимы через границу года и високосный '
      'день', () {
    for (final (first, last) in [
      ('2026-12-01', '2027-03-15'),
      ('2024-02-01', '2024-05-15'),
    ]) {
      final firstDate = CalendarDate.parseCanonical(first);
      final lastDate = CalendarDate.parseCanonical(last);

      final query = ActionDayStatusQuery(
        firstDate: firstDate,
        lastDate: lastDate,
      );

      expect(query.firstDate, firstDate);
      expect(query.lastDate, lastDate);
    }
  });

  test('обратный диапазон отклоняется до чтения', () {
    expect(
      () => ActionDayStatusQuery(
        firstDate: CalendarDate.fromParts(2026, 10, 6),
        lastDate: CalendarDate.fromParts(2026, 10, 5),
      ),
      throwsA(
        isA<ActionDayStatusQueryValidationException>().having(
          (error) => error.failure,
          'failure',
          ActionDayStatusQueryValidationFailure.reversedRange,
        ),
      ),
    );
  });

  test('106 дней включительно превышают предел чтения', () {
    expect(
      () => ActionDayStatusQuery(
        firstDate: CalendarDate.fromParts(2024, 2, 1),
        lastDate: CalendarDate.fromParts(2024, 5, 16),
      ),
      throwsA(
        isA<ActionDayStatusQueryValidationException>().having(
          (error) => error.failure,
          'failure',
          ActionDayStatusQueryValidationFailure.rangeTooLong,
        ),
      ),
    );
  });
}
