import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:flutter_riverpod/misc.dart';

/// Управляемое локальное сегодня для проверок каталога дневных выборов.
///
/// Проверка задаёт [today] до первого открытия каталога и меняет его, когда
/// нужно наступление другого дня, без ожидания настоящих суток. Источник
/// [read] подставляется в `AppRuntime` или через [override] в Riverpod.
final class ControlledDailyChoiceLocalDate {
  ControlledDailyChoiceLocalDate(
    this.today, {
    this.untilNextDate = const Duration(hours: 12),
  });

  /// Дата, которую вернёт следующее чтение источника.
  CalendarDate today;

  /// Время до следующей местной даты в следующем показании; по умолчанию
  /// показания сделаны в местный полдень.
  Duration untilNextDate;

  var _readCount = 0;

  /// Число чтений источника потребителями.
  int get readCount => _readCount;

  /// Источник локального сегодня: при каждом вызове возвращает текущие
  /// значения [today] и [untilNextDate].
  DailyChoiceLocalDay read() {
    _readCount += 1;
    return DailyChoiceLocalDay(date: today, untilNextDate: untilNextDate);
  }

  /// Подстановка [read] вместо часов устройства в `ProviderScope` или
  /// `ProviderContainer`.
  Override get override =>
      dailyChoiceLocalDateSourceProvider.overrideWithValue(read);
}
