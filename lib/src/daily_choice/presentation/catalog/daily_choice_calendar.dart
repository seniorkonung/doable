import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../domain/calendar_date.dart';
import 'daily_choice_calendar_day.dart';
import 'daily_choice_calendar_viewport.dart';

/// Встроенный недельный и месячный календарь каталога дневных выборов.
///
/// Календарь управляется потребителем и не хранит собственных выбора или
/// просмотра:
///
/// - [selectedDate] — выбранная дата фильтра, которую календарь только
///   отмечает;
/// - [viewport] — дата просмотра и представление, определяющие видимую
///   неделю или месяц;
/// - [today] — текущий локальный день; календарь не читает часы сам.
///
/// Нажатие на доступный день сообщает [onDateSelected] с календарной датой
/// ячейки, в том числе при повторном нажатии выбранного дня. Потребитель
/// синхронно делает этот день и выбранной датой, и датой просмотра, сохраняя
/// представление. Перелистывание периода сообщает только [onViewportChanged]
/// и не выбирает день. Изменения входов потребителем отражаются без обратных
/// событий.
///
/// `table_calendar`, его форматы, контроллер страниц и технические `DateTime`
/// остаются деталями реализации и не входят в контракт (ADR-0017).
final class DailyChoiceCalendar extends StatelessWidget {
  const DailyChoiceCalendar({
    super.key,
    required this.selectedDate,
    required this.viewport,
    required this.today,
    required this.onDateSelected,
    required this.onViewportChanged,
  });

  final CalendarDate selectedDate;
  final DailyChoiceCalendarViewport viewport;
  final CalendarDate today;
  final ValueChanged<CalendarDate> onDateSelected;
  final ValueChanged<DailyChoiceCalendarViewport> onViewportChanged;

  @override
  Widget build(BuildContext context) {
    return TableCalendar<Never>(
      locale: Localizations.localeOf(context).toLanguageTag(),
      firstDay: _firstDay,
      lastDay: _lastDay,
      focusedDay: _technicalDate(viewport.focusedDate),
      currentDay: _technicalDate(today),
      calendarFormat: switch (viewport.mode) {
        DailyChoiceCalendarMode.week => CalendarFormat.week,
        DailyChoiceCalendarMode.month => CalendarFormat.month,
      },
      availableCalendarFormats: _calendarFormats,
      startingDayOfWeek: StartingDayOfWeek.monday,
      rangeSelectionMode: RangeSelectionMode.disabled,
      // Представление переключает только потребитель, поэтому вертикальные
      // жесты остаются общей прокрутке страницы.
      availableGestures: AvailableGestures.horizontalSwipe,
      headerVisible: false,
      calendarBuilders: CalendarBuilders(prioritizedBuilder: _buildDay),
      onDaySelected: _selectDay,
      onPageChanged: _reportFocusedDay,
    );
  }

  Widget _buildDay(BuildContext context, DateTime day, DateTime focusedDay) {
    final date = _availableDate(day);
    // Позиция крайней недели за пределами CalendarDate сохраняет место в
    // строке, но не показывает несуществующую дату.
    if (date == null) {
      return _unavailableDay;
    }
    return DailyChoiceCalendarDay(
      key: ValueKey('daily-choice-calendar-day-${date.toCanonicalString()}'),
      date: date,
      isSelected: date == selectedDate,
      isToday: date == today,
      isOutsideMonth:
          viewport.mode == DailyChoiceCalendarMode.month &&
          (day.year != focusedDay.year || day.month != focusedDay.month),
    );
  }

  // Аргумент фокуса библиотеки не используется: дату просмотра в нажатый
  // день переносит потребитель.
  void _selectDay(DateTime day, DateTime _) {
    // Библиотека не сообщает о нажатии дней за пределами диапазона; проверка
    // сохраняет это свойство адаптера независимо от версии пакета.
    final date = _availableDate(day);
    if (date != null) {
      onDateSelected(date);
    }
  }

  void _reportFocusedDay(DateTime focusedDay) {
    // Технический фокус крайней недели может выйти за предел диапазона;
    // ближайший допустимый день принадлежит той же неделе.
    final focusedDate = _calendarDate(_clampToRange(focusedDay));
    // Библиотека сообщает о смене страницы и после синхронизации с входами
    // потребителя; повтор текущего просмотра не является его изменением.
    if (focusedDate != viewport.focusedDate) {
      onViewportChanged(viewport.withFocusedDate(focusedDate));
    }
  }
}

/// Пределы календаря совпадают с допустимым диапазоном [CalendarDate].
final _firstDay = _technicalDate(CalendarDate.earliest);
final _lastDay = _technicalDate(CalendarDate.latest);

const _unavailableDay = SizedBox.expand(
  key: ValueKey('daily-choice-calendar-unavailable-day'),
);

/// Названия форматов нужны только скрытой кнопке формата библиотеки.
const _calendarFormats = {CalendarFormat.month: '', CalendarFormat.week: ''};

/// Библиотека вычисляет периоды над `DateTime` в UTC. Это нейтральное
/// представление календарных частей, а не часовой пояс даты дневного выбора.
DateTime _technicalDate(CalendarDate date) =>
    DateTime.utc(date.year, date.month, date.day);

CalendarDate _calendarDate(DateTime day) =>
    CalendarDate.fromParts(day.year, day.month, day.day);

/// Календарная дата технического дня или `null` для позиции за пределами
/// диапазона [CalendarDate].
CalendarDate? _availableDate(DateTime day) =>
    day.isBefore(_firstDay) || day.isAfter(_lastDay)
    ? null
    : _calendarDate(day);

DateTime _clampToRange(DateTime day) => day.isBefore(_firstDay)
    ? _firstDay
    : day.isAfter(_lastDay)
    ? _lastDay
    : day;
