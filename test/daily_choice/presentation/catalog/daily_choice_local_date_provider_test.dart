import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/daily_choice_local_date.dart';

void main() {
  group('источник локальной даты каталога', () {
    test('по умолчанию предоставляет показание часов устройства', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(dailyChoiceLocalDateSourceProvider),
        same(readDeviceLocalDay),
      );
    });

    test(
      'дата устройства читается из местных года, месяца и дня при вызове',
      () {
        final before = DateTime.now();
        final date = readDeviceLocalDay().date;
        final after = DateTime.now();

        // Чтение может совпасть с местной полуночью, поэтому допустим день
        // любого из окружающих моментов.
        expect(date, anyOf(_localDateOf(before), _localDateOf(after)));
      },
    );

    test('показание устройства отсчитывает время до местной полуночи '
        'следующей даты', () {
      final before = DateTime.now();
      final day = readDeviceLocalDay();
      final after = DateTime.now();

      final date = day.date;
      final nextDateStart = DateTime(date.year, date.month, date.day + 1);
      expect(day.untilNextDate, greaterThan(Duration.zero));
      // Момент чтения лежит между окружающими моментами, поэтому и начало
      // следующей даты, отсчитанное от них, окружает местную полночь.
      expect(before.add(day.untilNextDate).isAfter(nextDateStart), isFalse);
      expect(after.add(day.untilNextDate).isBefore(nextDateStart), isFalse);
    });

    group('время до начала следующей местной даты', () {
      test('равно действительному промежутку до неё, а не 24 часам', () {
        // Полночи Нью-Йорка вокруг перехода на летнее и на зимнее время
        // 2026 года: сутки 8 марта короче, 1 ноября — длиннее.
        expect(
          untilLocalDateStart(
            DateTime.utc(2026, 3, 8, 5),
            DateTime.utc(2026, 3, 9, 4),
          ),
          const Duration(hours: 23),
        );
        expect(
          untilLocalDateStart(
            DateTime.utc(2026, 11, 1, 4),
            DateTime.utc(2026, 11, 2, 5),
          ),
          const Duration(hours: 25),
        );
        expect(
          untilLocalDateStart(
            DateTime.utc(2026, 10, 5, 3, 59, 59, 999),
            DateTime.utc(2026, 10, 5, 4),
          ),
          const Duration(milliseconds: 1),
        );
      });

      test('при уже прошедшей полуночи часы перечитываются позже, '
          'а не немедленно', () {
        // Перевод часов назад ровно в полночь: местная полночь следующей даты
        // приходится на момент, когда часы снова показывают текущую дату.
        final now = DateTime.utc(2026, 10, 24, 21);

        expect(untilLocalDateStart(now, now), localDateRecheckDelay);
        expect(
          untilLocalDateStart(now, now.subtract(const Duration(hours: 1))),
          localDateRecheckDelay,
        );
        expect(localDateRecheckDelay, greaterThan(Duration.zero));
      });
    });

    test('показание не допускает неположительного времени до следующей '
        'даты', () {
      expect(
        () => DailyChoiceLocalDay(
          date: _date(2026, 10, 5),
          untilNextDate: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => DailyChoiceLocalDay(
          date: _date(2026, 10, 5),
          untilNextDate: const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('управляемый источник возвращает новый день при следующем вызове', () {
      final localDate = ControlledDailyChoiceLocalDate(_date(2026, 10, 5));

      expect(localDate.read().date, _date(2026, 10, 5));

      localDate.today = _date(2026, 10, 6);
      localDate.untilNextDate = const Duration(minutes: 30);
      final next = localDate.read();
      expect(next.date, _date(2026, 10, 6));
      expect(next.untilNextDate, const Duration(minutes: 30));

      localDate.today = _date(2027, 1, 1);
      expect(localDate.read().date, _date(2027, 1, 1));
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

        expect(source().date, _date(2026, 10, 5));
        localDate.today = _date(2026, 10, 6);
        expect(source().date, _date(2026, 10, 6));
        expect(localDate.readCount, 2);
      },
    );
  });
}

CalendarDate _date(int year, int month, int day) =>
    CalendarDate.fromParts(year, month, day);

CalendarDate _localDateOf(DateTime moment) =>
    _date(moment.year, moment.month, moment.day);
