import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/calendar_date.dart';

part 'local_date_provider.g.dart';

/// Показание местных часов устройства: текущая местная календарная дата и
/// время до начала следующей.
final class LocalDay {
  LocalDay({required this.date, required this.untilNextDate}) {
    if (untilNextDate <= Duration.zero) {
      throw ArgumentError.value(
        untilNextDate,
        'untilNextDate',
        'Время до следующей местной даты должно быть положительным.',
      );
    }
  }

  /// Текущая местная календарная дата.
  final CalendarDate date;

  /// Действительное время от момента показания до начала следующей местной
  /// даты; всегда положительно.
  final Duration untilNextDate;
}

/// Источник показаний местных часов устройства.
///
/// Каждый вызов заново читает часы, поэтому один и тот же источник отдаёт
/// новый день после местной полуночи. Дата и время до следующей даты берутся
/// из одного чтения и согласованы между собой. Момент чтения выбирает
/// потребитель: получение источника из Riverpod часы не читает и не фиксирует
/// день запуска приложения.
///
/// Показание служит только интерфейсу: начальному выбору дня и обозначению
/// сегодняшнего дня. Порядок подтверждённых изменений по-прежнему
/// определяет ревизия графа (ADR-0006). Календарный компонент часы не
/// получает: потребитель передаёт ему уже прочитанную дату (ADR-0017).
typedef LocalDateSource = LocalDay Function();

/// Повторное чтение часов, когда начало следующей местной даты не удалось
/// определить по её полуночи.
const localDateRecheckDelay = Duration(minutes: 1);

/// Производственный источник: местные дата и время устройства в момент вызова.
LocalDay readDeviceLocalDay() {
  final now = DateTime.now();
  return LocalDay(
    date: CalendarDate.fromParts(now.year, now.month, now.day),
    // Полночь следующей даты строится по правилам местного часового пояса:
    // сутки с переводом часов длятся 23 или 25 часов, а не фиксированные 24.
    untilNextDate: untilLocalDateStart(
      now,
      DateTime(now.year, now.month, now.day + 1),
    ),
  );
}

/// Время от момента [now] до [nextDateStart] — местной полуночи следующей
/// даты.
///
/// При переводе часов назад ровно в полночь эта полночь может прийтись на
/// момент, когда часы снова показывают текущую дату, то есть не позже [now].
/// Тогда начало следующей даты неизвестно, и часы перечитываются через
/// [localDateRecheckDelay] вместо немедленных повторов.
@visibleForTesting
Duration untilLocalDateStart(DateTime now, DateTime nextDateStart) {
  final remaining = nextDateStart.difference(now);
  return remaining > Duration.zero ? remaining : localDateRecheckDelay;
}

/// Источник местного сегодня; по умолчанию — часы устройства.
///
/// Зависимостью владеет композиция приложения: `AppRuntime` предоставляет
/// контейнеру переданный при создании источник или [readDeviceLocalDay].
/// Проверки подставляют управляемые часы через `AppRuntime` или
/// переопределение провайдера до первого чтения часов.
@Riverpod(keepAlive: true)
LocalDateSource localDateSource(Ref ref) => readDeviceLocalDay;
