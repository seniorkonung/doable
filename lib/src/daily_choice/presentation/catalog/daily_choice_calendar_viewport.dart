import '../../domain/calendar_date.dart';

/// Представление встроенного календаря каталога.
enum DailyChoiceCalendarMode {
  /// Свёрнутое: одна неделя с понедельника по воскресенье.
  week,

  /// Раскрытое: сетка месяца.
  month,
}

/// Просматриваемый период календаря каталога: неделя или месяц, содержащие
/// [focusedDate], в зависимости от [mode].
///
/// Дата просмотра не является выбранной датой фильтра и не меняет её.
final class DailyChoiceCalendarViewport {
  const DailyChoiceCalendarViewport({
    required this.focusedDate,
    required this.mode,
  });

  final CalendarDate focusedDate;
  final DailyChoiceCalendarMode mode;

  DailyChoiceCalendarViewport withFocusedDate(CalendarDate value) =>
      DailyChoiceCalendarViewport(focusedDate: value, mode: mode);

  @override
  bool operator ==(Object other) =>
      other is DailyChoiceCalendarViewport &&
      other.focusedDate == focusedDate &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(focusedDate, mode);

  @override
  String toString() =>
      'DailyChoiceCalendarViewport($focusedDate, ${mode.name})';
}
