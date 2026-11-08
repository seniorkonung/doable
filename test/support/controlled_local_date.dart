import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/shared/presentation/local_day/local_date_provider.dart';
import 'package:flutter_riverpod/misc.dart';

/// Управляемое локальное сегодня для проверок интерфейса.
///
/// Проверка задаёт [today] до первого чтения часов и меняет его, когда
/// нужно наступление другого дня, без ожидания настоящих суток. Источник
/// [read] подставляется в `AppRuntime` или через [override] в Riverpod.
final class ControlledLocalDate {
  ControlledLocalDate(
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
  LocalDay read() {
    _readCount += 1;
    return LocalDay(date: today, untilNextDate: untilNextDate);
  }

  /// Подстановка [read] вместо часов устройства в `ProviderScope` или
  /// `ProviderContainer`.
  Override get override => localDateSourceProvider.overrideWithValue(read);
}
