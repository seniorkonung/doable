import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/calendar_date.dart';

part 'daily_choice_local_date_provider.g.dart';

/// Источник текущей локальной календарной даты устройства для каталога
/// дневных выборов.
///
/// Каждый вызов заново читает часы, поэтому один и тот же источник отдаёт
/// новый день после местной полуночи. Момент чтения выбирает потребитель:
/// получение источника из Riverpod дату не читает и не фиксирует день запуска
/// приложения.
///
/// Дата служит только интерфейсу каталога: начальному выбору дня и обозначению
/// сегодняшнего дня. Порядок подтверждённых изменений по-прежнему определяет
/// ревизия графа (ADR-0006). Календарный компонент часы не получает: потребитель
/// передаёт ему уже прочитанную дату (ADR-0017).
typedef DailyChoiceLocalDateSource = CalendarDate Function();

/// Производственный источник: местные год, месяц и день устройства в момент
/// вызова.
CalendarDate readDeviceLocalDate() {
  final now = DateTime.now();
  return CalendarDate.fromParts(now.year, now.month, now.day);
}

/// Источник локального сегодня каталога; по умолчанию — часы устройства.
///
/// Зависимостью владеет композиция приложения: `AppRuntime` предоставляет
/// контейнеру переданный при создании источник или [readDeviceLocalDate].
/// Проверки подставляют управляемую дату через `AppRuntime` или переопределение
/// провайдера до первого открытия каталога.
@Riverpod(keepAlive: true)
DailyChoiceLocalDateSource dailyChoiceLocalDateSource(Ref ref) =>
    readDeviceLocalDate;
