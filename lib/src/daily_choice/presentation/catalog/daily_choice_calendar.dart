import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/calendar_handle.dart';
import '../../../design_system/components/calendar_header.dart';
import '../../../design_system/components/month_grid_weekday.dart';
import '../../application/daily_choice_day_statuses.dart';
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
/// шапки месяца сообщает только [onViewportChanged] и не выбирает день;
/// за первую и последнюю неделю или месяц диапазона [CalendarDate]
/// перелистать нельзя.
/// При перелистывании месяца датой просмотра становится [selectedDate], если она
/// входит в этот месяц, иначе его первое число.
/// Ручка раскрытия или сворачивания также сообщает только
/// [onViewportChanged]: меняется представление, а дата просмотра сохраняется
/// точно, поэтому раскрывается месяц и сворачивается неделя этой даты.
/// Вертикальные жесты представление не переключают. Изменения входов
/// потребителем отражаются без обратных событий.
///
/// Шапка только месячного представления называет месяц и год даты просмотра;
/// у недели шапки и команд соседней недели нет. Полную выбранную дату называет
/// потребитель за пределами календаря, даже если её нет в видимом периоде.
/// [dayStatusForDate] задаёт галочку для всех выполненных дневных выборов,
/// кружок для невыполненного или отсутствие отметки. В неделе отметка стоит
/// под подписью дня недели внутри ячейки. Место под отметку резервируется всегда.
/// [hasDayMarksReadFailure] добавляет под шапкой пассивную строку отказа,
/// не меняя отметок, выбора или просмотра и не предлагая действий.
///
/// Календарь рассчитан на размещение элементом общей вертикальной прокрутки
/// страницы: он занимает доступную ширину, а высоту определяет сам по шапке,
/// шести неделям месяца и системному масштабу текста. Раскрытие
/// увеличивает эту высоту и сдвигает последующее содержимое; собственной
/// вертикальной прокрутки у календаря нет, и вертикальные жесты по нему
/// прокручивают страницу. Семь колонок дней всегда занимают всю ширину: при
/// крупном тексте шапка, числа и подписи дней недели переносятся, а строки
/// становятся выше, без уменьшения текста.
///
/// Созданный или пересозданный календарь показывает период [viewport] при
/// любых `PageStorageKey` страницы. Он ничего не читает из хранилища страниц
/// ([PageStorage]) предков и ничего туда не записывает, поэтому сохранённое
/// положение общей прокрутки страницы не меняется.
///
/// Для вспомогательных технологий каждый допустимый день — одна кнопка выбора
/// с полной датой, днём недели, состоянием выбранности и отдельной отметкой
/// «сегодня», а у дня с отметкой — состоянием дня; дни читаются в календарном
/// порядке после шапки и строки отказа, перед ручкой. Команды месяца
/// сообщают свою доступность; раскрытие, сворачивание, смена месяца и выбор дня
/// выполнимы доступной активацией без жестов. Недели листаются только свайпом.
/// Подписи следуют локали приложения и меняются вместе с ней без событий.
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
    this.dayStatusForDate,
    this.hasDayMarksReadFailure = false,
  });

  final CalendarDate selectedDate;
  final DailyChoiceCalendarViewport viewport;
  final CalendarDate today;

  /// Готовое состояние дня или `null`, если отметки нет. Календарь вызывает
  /// функцию для всех строящихся дней, включая соседние периоды; чтения,
  /// окна и ревизии остаются у потребителя.
  final DailyChoiceDayStatus? Function(CalendarDate date)? dayStatusForDate;

  /// Показывать под шапкой пассивную строку отказа получения отметок.
  /// Переданные состояния дней при этом сохраняются.
  final bool hasDayMarksReadFailure;

  final ValueChanged<CalendarDate> onDateSelected;
  final ValueChanged<DailyChoiceCalendarViewport> onViewportChanged;

  @override
  State<DailyChoiceCalendar> createState() => _DailyChoiceCalendarState();
}

final class _DailyChoiceCalendarState extends State<DailyChoiceCalendar> {
  /// Собственное хранилище страниц, которое живёт столько же, сколько
  /// календарь.
  ///
  /// Сетка библиотеки сохраняет номер страницы в ближайшем [PageStorage] и при
  /// создании заменяет им начальную страницу. Запись в хранилище предков
  /// определяется их `PageStorageKey`, поэтому под прокруткой страницы с таким
  /// ключом календарь делил бы с ней одну запись: после пересоздания показал
  /// бы период по её смещению и испортил бы сохранённое смещение. Запись в
  /// собственном хранилище не переживает календарь.
  final _pageStorage = PageStorageBucket();

  /// Контроллер страниц принадлежит библиотеке: она создаёт его вместе с
  /// сеткой и сама освобождает. Кнопки шапки перелистывают им страницы, чтобы
  /// переход шёл тем же путём, что и свайп.
  late PageController _pages;

  @override
  Widget build(BuildContext context) {
    final viewport = widget.viewport;
    final localizations = AppLocalizations.of(context);
    final isExpanded = viewport.mode == DailyChoiceCalendarMode.month;
    final calendar = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isExpanded)
          CalendarHeader(
            title: _monthTitle(context, viewport.focusedDate),
            previousLabel: localizations.dailyChoiceCalendarPreviousMonth,
            nextLabel: localizations.dailyChoiceCalendarNextMonth,
            onPrevious: _hasPreviousMonth(viewport.focusedDate)
                ? _showPreviousPeriod
                : null,
            onNext: _hasNextMonth(viewport.focusedDate)
                ? _showNextPeriod
                : null,
          ),
        if (widget.hasDayMarksReadFailure)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              AppLocalizations.of(context)
                  .dailyChoiceCalendarDayMarksUnavailable,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        // Библиотека задаёт строкам фиксированную высоту, поэтому её
        // рассчитывает календарь: по ширине колонки и масштабу текста.
        LayoutBuilder(
          builder: (context, constraints) {
            final columnWidth = _columnWidth(constraints.maxWidth);
            // Основа библиотеки без готовых ячеек: ячейка `TableCalendar`
            // задаёт собственную подпись даты, скрывает содержимое от
            // вспомогательных технологий и объявляет пустое долгое нажатие.
            // Дни и подписи дней недели строит календарь, а страницы, жесты и
            // сетка остаются за библиотекой.
            return TableCalendarBase(
              firstDay: _firstDay,
              lastDay: _lastDay,
              focusedDay: _technicalDate(viewport.focusedDate),
              calendarFormat: switch (viewport.mode) {
                DailyChoiceCalendarMode.week => CalendarFormat.week,
                DailyChoiceCalendarMode.month => CalendarFormat.month,
              },
              startingDayOfWeek: StartingDayOfWeek.monday,
              // Постоянные шесть строк включают дни соседних месяцев:
              // https://pub.dev/documentation/table_calendar/latest/table_calendar/TableCalendarBase/sixWeekMonthsEnforced.html
              sixWeekMonthsEnforced: true,
              // Представление переключает только потребитель, поэтому
              // вертикальные жесты остаются общей прокрутке страницы.
              availableGestures: AvailableGestures.horizontalSwipe,
              rowHeight: DailyChoiceCalendarDay.rowHeight(
                context,
                columnWidth: columnWidth,
                mode: viewport.mode,
              ),
              // В неделе подпись дня входит в ячейку:
              // https://pub.dev/documentation/table_calendar/latest/table_calendar/TableCalendarBase-class.html
              dowVisible: viewport.mode == DailyChoiceCalendarMode.month,
              dowHeight: _weekdayHeight(context, columnWidth: columnWidth),
              dowBuilder: _buildWeekday,
              dayBuilder: _buildDay,
              pageAnimationDuration: _pageAnimationDuration,
              pageAnimationCurve: _pageAnimationCurve,
              onCalendarCreated: (pages) => _pages = pages,
              onPageChanged: _reportFocusedDay,
            );
          },
        ),
        CalendarHandle(
          isExpanded: isExpanded,
          semanticLabel: isExpanded
              ? localizations.dailyChoiceCalendarCollapse
              : localizations.dailyChoiceCalendarExpand,
          onTap: _toggleMode,
        ),
      ],
    );
    return PageStorage(bucket: _pageStorage, child: calendar);
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

  // Дата просмотра сохраняется, а к периоду нового представления библиотека
  // переходит без сообщения о смене страницы.
  void _toggleMode() {
    _stopPaging();
    final viewport = widget.viewport;
    widget.onViewportChanged(
      viewport.withMode(switch (viewport.mode) {
        DailyChoiceCalendarMode.week => DailyChoiceCalendarMode.month,
        DailyChoiceCalendarMode.month => DailyChoiceCalendarMode.week,
      }),
    );
  }

  /// Останавливает незаконченное перелистывание на странице, о которой
  /// потребитель уже знает.
  ///
  /// Анимация страницы продвигается в следующем кадре раньше, чем календарь
  /// получит новые входы. Без остановки библиотека сообщила бы о переходе,
  /// рассчитанном для прежнего представления, и он заменил бы просмотр,
  /// выбранный последней командой.
  void _stopPaging() {
    // PageView сообщает о странице, ближайшей к текущему положению, поэтому
    // переход к ней не создаёт нового сообщения.
    if (_pages.page case final page?) {
      _pages.jumpToPage(page.round());
    }
  }

  /// Короткое название дня недели над колонкой. Каждый день и так называет
  /// свой день недели, поэтому подпись колонки не читается отдельно.
  Widget _buildWeekday(BuildContext context, DateTime day) {
    return ExcludeSemantics(
      child: MonthGridWeekday(text: _weekdayLabel(context, day)),
    );
  }

  Widget _buildDay(BuildContext context, DateTime day, DateTime focusedDay) {
    final date = _availableDate(day);
    // Позиция крайней недели за пределами CalendarDate сохраняет место в
    // строке, но не показывает несуществующую дату, не объявляется и не
    // выбирается.
    if (date == null) {
      return _unavailableDay;
    }
    return DailyChoiceCalendarDay(
      key: ValueKey('daily-choice-calendar-day-${date.toCanonicalString()}'),
      date: date,
      status: widget.dayStatusForDate?.call(date),
      isSelected: date == widget.selectedDate,
      isToday: date == widget.today,
      mode: widget.viewport.mode,
      isOutsideMonth:
          widget.viewport.mode == DailyChoiceCalendarMode.month &&
          (day.year != focusedDay.year || day.month != focusedDay.month),
      // Дату просмотра в нажатый день переносит потребитель.
      onSelected: () => widget.onDateSelected(date),
    );
  }

  void _reportFocusedDay(DateTime focusedDay) {
    // Технический фокус крайней недели может выйти за предел диапазона;
    // ближайший допустимый день принадлежит той же неделе.
    var focusedDate = _calendarDate(_clampToRange(focusedDay));
    final viewport = widget.viewport;
    if (viewport.mode == DailyChoiceCalendarMode.month &&
        (focusedDate.year != viewport.focusedDate.year ||
            focusedDate.month != viewport.focusedDate.month)) {
      final selected = widget.selectedDate;
      focusedDate =
          selected.year == focusedDate.year &&
              selected.month == focusedDate.month
          ? selected
          : CalendarDate.fromParts(focusedDate.year, focusedDate.month, 1);
    }
    // Библиотека сообщает о смене страницы и после синхронизации с входами
    // потребителя; повтор текущего просмотра не является его изменением.
    if (focusedDate != viewport.focusedDate) {
      widget.onViewportChanged(viewport.withFocusedDate(focusedDate));
    }
  }
}

/// Пределы календаря совпадают с допустимым диапазоном [CalendarDate].
final _firstDay = _technicalDate(CalendarDate.earliest);
final _lastDay = _technicalDate(CalendarDate.latest);

const _unavailableDay = SizedBox.expand(
  key: ValueKey('daily-choice-calendar-unavailable-day'),
);

/// Ширина колонки дня, не больше фактической: высоты строк, рассчитанные по
/// ней, вмещают текст колонки.
double _columnWidth(double width) =>
    (width / DateTime.daysPerWeek).floorToDouble();

String _weekdayLabel(BuildContext context, DateTime day) {
  final label = DateFormat.E(Localizations.localeOf(context).toLanguageTag())
      .format(day);
  return label[0].toUpperCase() + label.substring(1);
}

/// Высота строки названий дней недели, в которую каждое название при ширине
/// колонки [columnWidth] помещается целиком, при необходимости с переносом.
double _weekdayHeight(BuildContext context, {required double columnWidth}) {
  // Названия не зависят от недели: подойдёт любая неделя с понедельника.
  final monday = DateTime.utc(2024);
  return MonthGridWeekday.rowHeight(
    context,
    texts: [
      for (var offset = 0; offset < DateTime.daysPerWeek; offset++)
        _weekdayLabel(
          context,
          DateTime.utc(monday.year, monday.month, monday.day + offset),
        ),
    ],
    columnWidth: columnWidth,
  );
}

/// Переход к соседнему периоду: общий для свайпа и кнопок шапки.
const _pageAnimationDuration = Duration(milliseconds: 300);
const _pageAnimationCurve = Curves.easeOut;

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

/// Есть ли допустимый месяц перед показанным или после него.
bool _hasPreviousMonth(CalendarDate focusedDate) =>
    _firstDay.isBefore(DateTime.utc(focusedDate.year, focusedDate.month));

bool _hasNextMonth(CalendarDate focusedDate) =>
    _lastDay.isAfter(DateTime.utc(focusedDate.year, focusedDate.month + 1, 0));

String _monthTitle(BuildContext context, CalendarDate date) {
  // L — самостоятельная форма названия месяца, без суффикса года:
  // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
  final title = DateFormat(
    'LLLL y',
    Localizations.localeOf(context).toLanguageTag(),
  ).format(_technicalDate(date));
  return title[0].toUpperCase() + title.substring(1);
}
