import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/shared/presentation/timestamp_dates_line.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(initializeDateFormatting);

  final ru = lookupAppLocalizations(const Locale('ru'));
  final en = lookupAppLocalizations(const Locale('en'));
  const currentYear = 2026;

  test('изменение в день создания оставляет одну дату создания', () {
    final line = timestampDatesLine(
      localizations: ru,
      locale: 'ru',
      createdAt: DateTime(2026, 10, 6, 0, 5),
      updatedAt: DateTime(2026, 10, 6, 23, 55),
      currentYear: currentYear,
    );

    expect(line.created, (label: 'Создано', date: '6 окт.'));
    expect(line.changed, isNull);
  });

  test('изменение в другой день добавляет дату изменения', () {
    final line = timestampDatesLine(
      localizations: en,
      locale: 'en',
      createdAt: DateTime(2026, 3, 27, 23, 55),
      updatedAt: DateTime(2026, 3, 28, 0, 5),
      currentYear: currentYear,
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
      final line = timestampDatesLine(
        localizations: localizations,
        locale: locale,
        createdAt: DateTime(2025, 3, 14, 12),
        updatedAt: DateTime(2026, 10, 3, 12),
        currentYear: currentYear,
      );

      expect(line.created, created);
      expect(line.changed, changed);
    });
  }
}
