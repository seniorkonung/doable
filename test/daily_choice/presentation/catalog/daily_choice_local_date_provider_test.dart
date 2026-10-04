import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/daily_choice_local_date.dart';

void main() {
  group('источник локальной даты каталога', () {
    test('по умолчанию предоставляет чтение даты устройства', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(dailyChoiceLocalDateSourceProvider),
        same(readDeviceLocalDate),
      );
    });

    test(
      'дата устройства читается из местных года, месяца и дня при вызове',
      () {
        final before = DateTime.now();
        final date = readDeviceLocalDate();
        final after = DateTime.now();

        // Чтение может совпасть с местной полуночью, поэтому допустим день
        // любого из окружающих моментов.
        expect(date, anyOf(_localDateOf(before), _localDateOf(after)));
      },
    );

    test('управляемый источник возвращает новый день при следующем вызове', () {
      final localDate = ControlledDailyChoiceLocalDate(_date(2026, 10, 5));

      expect(localDate.read(), _date(2026, 10, 5));

      localDate.today = _date(2026, 10, 6);
      expect(localDate.read(), _date(2026, 10, 6));

      localDate.today = _date(2027, 1, 1);
      expect(localDate.read(), _date(2027, 1, 1));
      expect(localDate.readCount, 3);
    });

    test(
      'подстановка через Riverpod не читает дату при получении источника',
      () {
        final localDate = ControlledDailyChoiceLocalDate(_date(2026, 10, 5));
        final container = ProviderContainer(overrides: [localDate.override]);
        addTearDown(container.dispose);

        final source = container.read(dailyChoiceLocalDateSourceProvider);
        expect(localDate.readCount, 0);

        expect(source(), _date(2026, 10, 5));
        localDate.today = _date(2026, 10, 6);
        expect(source(), _date(2026, 10, 6));
        expect(localDate.readCount, 2);
      },
    );
  });
}

CalendarDate _date(int year, int month, int day) =>
    CalendarDate.fromParts(year, month, day);

CalendarDate _localDateOf(DateTime moment) =>
    _date(moment.year, moment.month, moment.day);
