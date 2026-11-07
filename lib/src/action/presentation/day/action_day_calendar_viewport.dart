import '../../../shared/domain/calendar_date.dart';

/// Представление встроенного календаря экрана дня.
enum ActionDayCalendarMode {
  /// Свёрнутое: одна неделя с понедельника по воскресенье.
  week,

  /// Раскрытое: сетка месяца.
  month,
}

/// Просматриваемый период календаря экрана дня: неделя или месяц, содержащие
/// [focusedDate], в зависимости от [mode].
///
/// Дата просмотра не является выбранной датой фильтра и не меняет её.
final class ActionDayCalendarViewport {
  const ActionDayCalendarViewport({
    required this.focusedDate,
    required this.mode,
  });

  final CalendarDate focusedDate;
  final ActionDayCalendarMode mode;

  ActionDayCalendarViewport withFocusedDate(CalendarDate value) =>
      ActionDayCalendarViewport(focusedDate: value, mode: mode);

  ActionDayCalendarViewport withMode(ActionDayCalendarMode value) =>
      ActionDayCalendarViewport(focusedDate: focusedDate, mode: value);

  @override
  bool operator ==(Object other) =>
      other is ActionDayCalendarViewport &&
      other.focusedDate == focusedDate &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(focusedDate, mode);

  @override
  String toString() => 'ActionDayCalendarViewport($focusedDate, ${mode.name})';
}
