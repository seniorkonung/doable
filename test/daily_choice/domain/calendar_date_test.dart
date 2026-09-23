import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('дата дневного выбора', () {
    test('сохраняет календарные части и каноническую запись', () {
      final earliest = CalendarDate.fromParts(1, 1, 1);
      final latest = CalendarDate.fromParts(9999, 12, 31);

      expect(earliest.toCanonicalString(), '0001-01-01');
      expect(latest.toCanonicalString(), '9999-12-31');
      expect(
        CalendarDate.parseCanonical('2026-09-23'),
        CalendarDate.fromParts(2026, 9, 23),
      );
      expect(CalendarDate.parseCanonical('1900-03-01').year, 1900);
      expect(CalendarDate.parseCanonical('2000-02-29').day, 29);
    });

    test('отклоняет годы вне диапазона и невозможные дни', () {
      for (final parts in [
        [0, 1, 1],
        [10000, 1, 1],
        [2026, 0, 1],
        [2026, 13, 1],
        [2026, 4, 31],
        [2026, 1, 0],
        [2026, 1, 32],
        [1900, 2, 29],
        [2001, 2, 29],
      ]) {
        expect(
          () => CalendarDate.fromParts(parts[0], parts[1], parts[2]),
          _throwsDateFailure(CalendarDateValidationReason.invalidDate),
        );
      }
      expect(CalendarDate.fromParts(2000, 2, 29).day, 29);
      expect(CalendarDate.fromParts(2004, 2, 29).day, 29);
      expect(CalendarDate.fromParts(1900, 2, 28).day, 28);
    });

    test('при чтении отвергает неканонический формат без исправления', () {
      for (final value in [
        '2026-9-23',
        '026-09-23',
        '2026-09-23Z',
        ' 2026-09-23',
        '2026-09-23T00:00:00',
        '٢٠٢٦-٠٩-٢٣',
      ]) {
        expect(
          () => CalendarDate.parseCanonical(value),
          _throwsDateFailure(CalendarDateValidationReason.invalidFormat),
        );
      }
      expect(
        () => CalendarDate.parseCanonical('1900-02-29'),
        _throwsDateFailure(CalendarDateValidationReason.invalidDate),
      );
      expect(
        () => CalendarDate.parseCanonical('0000-01-01'),
        _throwsDateFailure(CalendarDateValidationReason.invalidDate),
      );
    });
  });
}

Matcher _throwsDateFailure(CalendarDateValidationReason reason) => throwsA(
  isA<CalendarDateValidationException>()
      .having(
        (exception) => exception.failure.field,
        'поле',
        CalendarDateField.date,
      )
      .having((exception) => exception.failure.reason, 'причина', reason),
);
