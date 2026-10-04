import 'package:flutter_test/flutter_test.dart';

import '../../domain/calendar_date_test.dart' as calendar_date_test;
import 'daily_choice_calendar_boundaries_test.dart' as boundaries_test;

/// Дочерний прогон `daily_choice_calendar_time_zone_test.dart`.
///
/// Выполняет проверки календарных дат в отдельном процессе `flutter test`,
/// которому родительская проверка задаёт TZ=America/New_York. Имя без
/// суффикса `_test` исключает файл из обычного прогона, а сам он не запускает
/// родительскую проверку.
void main() {
  // Без перехода времени проверки ниже прошли бы, ничего не доказав, поэтому
  // прогон начинается с подтверждения перехода.
  setUpAll(_expectDaylightSavingTransitions);

  group('дата дневного выбора', calendar_date_test.main);
  group('календарь дневного выбора', boundaries_test.main);
}

/// Подтверждает, что локальное смещение процесса меняется при переходах
/// America/New_York на летнее (2026-03-08) и зимнее (2026-11-01) время.
///
/// Без базы часовых поясов или при игнорировании TZ процесс работает в UTC, и
/// смещение до и после перехода совпадает.
void _expectDaylightSavingTransitions() {
  for (final (transition, before, after) in [
    ('летнее', DateTime(2026, 3, 7, 12), DateTime(2026, 3, 9, 12)),
    ('зимнее', DateTime(2026, 10, 31, 12), DateTime(2026, 11, 2, 12)),
  ]) {
    expect(
      after.timeZoneOffset,
      isNot(before.timeZoneOffset),
      reason:
          'Смещение процесса не меняется при переходе на $transition время '
          '(${before.timeZoneName}); вероятно, TZ не применён или нет базы '
          'часовых поясов.',
    );
  }
}
