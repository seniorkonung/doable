import 'dart:async';

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../l10n/app_localizations.dart';
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
/// представление. Перелистывание периода горизонтальным свайпом или кнопками
/// шапки сообщает только [onViewportChanged] и не выбирает день; за первую и
/// последнюю неделю или месяц диапазона [CalendarDate] перелистать нельзя.
/// Изменения входов потребителем отражаются без обратных событий.
///
/// Шапка называет месяц и год даты просмотра, а отдельная подпись — полную
/// выбранную дату, даже если её нет в видимом периоде.
///
/// `table_calendar`, его форматы, контроллер страниц и технические `DateTime`
/// остаются деталями реализации и не входят в контракт (ADR-0017).
final class DailyChoiceCalendar extends StatefulWidget {
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
  State<DailyChoiceCalendar> createState() => _DailyChoiceCalendarState();
}

final class _DailyChoiceCalendarState extends State<DailyChoiceCalendar> {
  /// Контроллер страниц принадлежит библиотеке: она создаёт его вместе с
  /// сеткой и сама освобождает. Кнопки шапки перелистывают им страницы, чтобы
  /// переход шёл тем же путём, что и свайп.
  late PageController _pages;

  @override
  Widget build(BuildContext context) {
    final viewport = widget.viewport;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DailyChoiceCalendarHeader(
          selectedDate: widget.selectedDate,
          viewport: viewport,
          onPrevious: _hasPreviousPeriod(viewport) ? _showPreviousPeriod : null,
          onNext: _hasNextPeriod(viewport) ? _showNextPeriod : null,
        ),
        TableCalendar<Never>(
          locale: Localizations.localeOf(context).toLanguageTag(),
          firstDay: _firstDay,
          lastDay: _lastDay,
          focusedDay: _technicalDate(viewport.focusedDate),
          currentDay: _technicalDate(widget.today),
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
          pageAnimationDuration: _pageAnimationDuration,
          pageAnimationCurve: _pageAnimationCurve,
          calendarBuilders: CalendarBuilders(prioritizedBuilder: _buildDay),
          onCalendarCreated: (pages) => _pages = pages,
          onDaySelected: _selectDay,
          onPageChanged: _reportFocusedDay,
        ),
      ],
    );
  }

  // О смене страницы, как и после свайпа, сообщает _reportFocusedDay.
  void _showPreviousPeriod() => unawaited(
    _pages.previousPage(
      duration: _pageAnimationDuration,
      curve: _pageAnimationCurve,
    ),
  );

  void _showNextPeriod() => unawaited(
    _pages.nextPage(
      duration: _pageAnimationDuration,
      curve: _pageAnimationCurve,
    ),
  );

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
      isSelected: date == widget.selectedDate,
      isToday: date == widget.today,
      isOutsideMonth:
          widget.viewport.mode == DailyChoiceCalendarMode.month &&
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
      widget.onDateSelected(date);
    }
  }

  void _reportFocusedDay(DateTime focusedDay) {
    // Технический фокус крайней недели может выйти за предел диапазона;
    // ближайший допустимый день принадлежит той же неделе.
    final focusedDate = _calendarDate(_clampToRange(focusedDay));
    // Библиотека сообщает о смене страницы и после синхронизации с входами
    // потребителя; повтор текущего просмотра не является его изменением.
    if (focusedDate != widget.viewport.focusedDate) {
      widget.onViewportChanged(widget.viewport.withFocusedDate(focusedDate));
    }
  }
}

/// Пределы календаря совпадают с допустимым диапазоном [CalendarDate].
final _firstDay = _technicalDate(CalendarDate.earliest);
final _lastDay = _technicalDate(CalendarDate.latest);

const _unavailableDay = SizedBox.expand(
  key: ValueKey('daily-choice-calendar-unavailable-day'),
);

/// Переход к соседнему периоду: общий для свайпа и кнопок шапки.
const _pageAnimationDuration = Duration(milliseconds: 300);
const _pageAnimationCurve = Curves.easeOut;

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

/// Есть ли в диапазоне [CalendarDate] период перед видимым.
bool _hasPreviousPeriod(DailyChoiceCalendarViewport viewport) =>
    _firstDay.isBefore(_visiblePeriodStart(viewport));

/// Есть ли в диапазоне [CalendarDate] период после видимого.
bool _hasNextPeriod(DailyChoiceCalendarViewport viewport) =>
    _lastDay.isAfter(_visiblePeriodEnd(viewport));

/// Первый день видимой недели или месяца.
DateTime _visiblePeriodStart(DailyChoiceCalendarViewport viewport) {
  final focusedDay = _technicalDate(viewport.focusedDate);
  return switch (viewport.mode) {
    DailyChoiceCalendarMode.week => DateTime.utc(
      focusedDay.year,
      focusedDay.month,
      focusedDay.day - (focusedDay.weekday - DateTime.monday),
    ),
    DailyChoiceCalendarMode.month => DateTime.utc(
      focusedDay.year,
      focusedDay.month,
    ),
  };
}

/// Последний день видимой недели или месяца; крайняя неделя может
/// заканчиваться за пределом диапазона.
DateTime _visiblePeriodEnd(DailyChoiceCalendarViewport viewport) {
  final start = _visiblePeriodStart(viewport);
  return switch (viewport.mode) {
    DailyChoiceCalendarMode.week => DateTime.utc(
      start.year,
      start.month,
      start.day + DateTime.daysPerWeek - 1,
    ),
    DailyChoiceCalendarMode.month => DateTime.utc(
      start.year,
      start.month + 1,
      0,
    ),
  };
}

/// Шапка календаря: полная выбранная дата, месяц и год даты просмотра и
/// команды соседних периодов текущего представления.
final class _DailyChoiceCalendarHeader extends StatelessWidget {
  const _DailyChoiceCalendarHeader({
    required this.selectedDate,
    required this.viewport,
    required this.onPrevious,
    required this.onNext,
  });

  final CalendarDate selectedDate;
  final DailyChoiceCalendarViewport viewport;

  /// `null`, когда соседнего периода нет в диапазоне [CalendarDate].
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final (previousLabel, nextLabel) = switch (viewport.mode) {
      DailyChoiceCalendarMode.week => (
        localizations.dailyChoiceCalendarPreviousWeek,
        localizations.dailyChoiceCalendarNextWeek,
      ),
      DailyChoiceCalendarMode.month => (
        localizations.dailyChoiceCalendarPreviousMonth,
        localizations.dailyChoiceCalendarNextMonth,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            localizations.dailyChoiceCalendarSelectedDate(
              dates.formatFullDate(_technicalDate(selectedDate)),
            ),
            style: textTheme.titleSmall,
          ),
        ),
        Row(
          children: [
            IconButton(
              onPressed: onPrevious,
              tooltip: previousLabel,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                dates.formatMonthYear(_technicalDate(viewport.focusedDate)),
                textAlign: TextAlign.center,
                style: textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: onNext,
              tooltip: nextLabel,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}
