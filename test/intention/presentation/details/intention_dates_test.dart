import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_dates.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(initializeDateFormatting);

  final ru = lookupAppLocalizations(const Locale('ru'));
  final en = lookupAppLocalizations(const Locale('en'));
  final today = CalendarDate.fromParts(2026, 10, 29);

  test('изменение в день создания оставляет одну дату создания', () {
    final line = intentionDatesLine(
      localizations: ru,
      locale: 'ru',
      createdAt: IntentionTimestamp(DateTime(2026, 10, 6, 0, 5)),
      updatedAt: IntentionTimestamp(DateTime(2026, 10, 6, 23, 55)),
      today: today,
    );

    expect(line.created, (label: 'Создано', date: '6 окт.'));
    expect(line.changed, isNull);
  });

  test('изменение в другой день добавляет дату изменения', () {
    final line = intentionDatesLine(
      localizations: en,
      locale: 'en',
      createdAt: IntentionTimestamp(DateTime(2026, 3, 27, 23, 55)),
      updatedAt: IntentionTimestamp(DateTime(2026, 3, 28, 0, 5)),
      today: today,
    );

    expect(line.created, (label: 'Created', date: '27 Mar'));
    expect(line.changed, (label: 'Changed', date: '28 Mar'));
  });

  for (final (locale, localizations, created, changed) in [
    (
      'ru',
      ru,
      (label: 'Создано', date: '14 мар. 2025'),
      (label: 'Изменено', date: '3 окт.'),
    ),
    (
      'en',
      en,
      (label: 'Created', date: '14 Mar 2025'),
      (label: 'Changed', date: '3 Oct'),
    ),
  ]) {
    test('год называет только дата не текущего года: $locale', () {
      final line = intentionDatesLine(
        localizations: localizations,
        locale: locale,
        createdAt: IntentionTimestamp(DateTime(2025, 3, 14, 12)),
        updatedAt: IntentionTimestamp(DateTime(2026, 10, 3, 12)),
        today: CalendarDate.fromParts(2026, 10, 29),
      );

      expect(line.created, created);
      expect(line.changed, changed);
    });
  }
}
