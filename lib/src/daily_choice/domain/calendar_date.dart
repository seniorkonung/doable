enum CalendarDateField { date }

enum CalendarDateValidationReason { invalidFormat, invalidDate }

final class CalendarDateValidationFailure {
  const CalendarDateValidationFailure({
    required this.field,
    required this.reason,
  });

  final CalendarDateField field;
  final CalendarDateValidationReason reason;
}

final class CalendarDateValidationException implements Exception {
  const CalendarDateValidationException(this.failure);

  final CalendarDateValidationFailure failure;
}

final class CalendarDate {
  const CalendarDate._(this.year, this.month, this.day);

  static final RegExp _canonicalPattern = RegExp(
    r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$',
  );

  final int year;
  final int month;
  final int day;

  static CalendarDate fromParts(int year, int month, int day) {
    if (year < 1 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > _daysInMonth(year, month)) {
      throw const CalendarDateValidationException(
        CalendarDateValidationFailure(
          field: CalendarDateField.date,
          reason: CalendarDateValidationReason.invalidDate,
        ),
      );
    }
    return CalendarDate._(year, month, day);
  }

  static CalendarDate parseCanonical(String value) {
    if (value.length != 10 || !_canonicalPattern.hasMatch(value)) {
      throw const CalendarDateValidationException(
        CalendarDateValidationFailure(
          field: CalendarDateField.date,
          reason: CalendarDateValidationReason.invalidFormat,
        ),
      );
    }
    return fromParts(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(5, 7)),
      int.parse(value.substring(8, 10)),
    );
  }

  String toCanonicalString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  static int _daysInMonth(int year, int month) => switch (month) {
    4 || 6 || 9 || 11 => 30,
    2 => _isLeapYear(year) ? 29 : 28,
    _ => 31,
  };

  static bool _isLeapYear(int year) =>
      year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

  @override
  bool operator ==(Object other) =>
      other is CalendarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toCanonicalString();
}
