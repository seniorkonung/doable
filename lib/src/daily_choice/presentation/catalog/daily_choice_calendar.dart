import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/calendar_handle.dart';
import '../../../design_system/components/calendar_header.dart';
import '../../../design_system/components/month_grid_weekday.dart';
import '../../../design_system/components/notice.dart';
import '../../application/daily_choice_day_statuses.dart';
import '../../domain/calendar_date.dart';
import 'daily_choice_calendar_day.dart';
import 'daily_choice_calendar_expansion.dart';
import 'daily_choice_calendar_paging.dart';
import 'daily_choice_calendar_period_picker.dart';
import 'daily_choice_calendar_viewport.dart';

/// Встроенный недельный и месячный календарь каталога дневных выборов.
///
/// Выбранной датой и просмотром управляет потребитель:
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
/// Заголовок месяца открывает встроенный выбор года и месяца. Его страницы
/// календарь хранит сам, не сообщая промежуточные переходы потребителю.
/// Выбор месяца сообщает только [onMonthSelectionCompleted] с итоговым
/// просмотром, даже равным прежнему. Закрытие заголовком не создаёт событий;
/// сворачивание ручкой возвращает неделю прежней даты просмотра.
/// Ручка раскрытия или сворачивания также сообщает только
/// [onViewportChanged]: меняется представление, а дата просмотра сохраняется
/// точно, поэтому раскрывается месяц и сворачивается неделя этой даты.
/// Событие приходит после завершения анимации; повторное нажатие меняет её
/// цель из текущего положения. Возврат не создаёт события.
/// Вертикальные жесты представление не переключают. Изменения входов
/// потребителем отражаются без обратных событий.
///
/// Шапка только месячного представления называет месяц и год даты просмотра;
/// у недели шапки и команд соседней недели нет. Полную выбранную дату называет
/// потребитель за пределами календаря, даже если её нет в видимом периоде.
/// [dayStatusForDate] задаёт галочку для всех выполненных дневных выборов,
/// кружок для невыполненного или отсутствие отметки. В неделе отметка стоит
/// под подписью дня недели внутри ячейки. Место под отметку резервируется всегда.
/// [hasDayMarksReadFailure] добавляет под ручкой пассивный [Notice],
/// не меняя отметок, выбора или просмотра и не предлагая действий.
///
/// Календарь закрепляется потребителем над прокруткой выдачи:
/// он занимает доступную ширину, а высоту определяет сам по шапке,
/// шести неделям месяца и системному масштабу текста. Раскрытие
/// увеличивает эту высоту и сдвигает последующее содержимое; собственной
/// вертикальной прокрутки у календаря нет. Семь колонок дней всегда занимают
/// всю ширину: при крупном тексте шапка, числа и подписи дней недели
/// переносятся, а строки
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
/// порядке после шапки, перед ручкой и сообщением об отказе. Команды месяца
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
    required this.onMonthSelectionCompleted,
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

  /// Показывать под ручкой пассивное сообщение об отказе получения отметок.
  /// Переданные состояния дней при этом сохраняются.
  final bool hasDayMarksReadFailure;

  final ValueChanged<CalendarDate> onDateSelected;
  final ValueChanged<DailyChoiceCalendarViewport> onViewportChanged;

  /// Один завершённый выбор месяца; [onViewportChanged] его не дублирует.
  final ValueChanged<DailyChoiceCalendarViewport> onMonthSelectionCompleted;

  @override
  State<DailyChoiceCalendar> createState() => _DailyChoiceCalendarState();
}

final class _DailyChoiceCalendarState extends State<DailyChoiceCalendar>
    with SingleTickerProviderStateMixin {
  /// Изолированные хранилища недельной и раскрытой сеток живут вместе
  /// с календарём; выбор периода также не обращается к хранилищу предков.
  ///
  /// Сетка библиотеки сохраняет номер страницы в ближайшем [PageStorage] и при
  /// создании заменяет им начальную страницу. Запись в хранилище предков
  /// определяется их `PageStorageKey`, поэтому под прокруткой страницы с таким
  /// ключом календарь делил бы с ней одну запись: после пересоздания показал
  /// бы период по её смещению и испортил бы сохранённое смещение. Запись в
  /// собственном хранилище не переживает календарь.
  var _weekStorage = PageStorageBucket();
  var _monthStorage = PageStorageBucket();

  bool _isPeriodPickerOpen = false;
  bool _isTransitioning = false;
  late DailyChoiceCalendarMode _targetMode = widget.viewport.mode;
  late final _expansion = AnimationController(
    vsync: this,
    value: _progressFor(widget.viewport.mode),
  );

  /// Контроллер страниц принадлежит библиотеке: она создаёт его вместе с
  /// сеткой и сама освобождает. Кнопки шапки перелистывают им страницы, чтобы
  /// переход шёл тем же путём, что и свайп.
  PageController? _weekPages;
  PageController? _monthPages;

  @override
  void dispose() {
    _expansion.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DailyChoiceCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewport != oldWidget.viewport) {
      _expansion.stop();
      _isTransitioning = false;
      _targetMode = widget.viewport.mode;
      _expansion.value = _progressFor(_targetMode);
      _discardInactiveGrid();
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewport = widget.viewport;
    final localizations = AppLocalizations.of(context);
    final isExpanded = _targetMode == DailyChoiceCalendarMode.month;
    final showWeek = _isTransitioning || !isExpanded;
    final showExpanded = _isTransitioning || isExpanded;
    final week = showWeek
        ? _buildGrid(DailyChoiceCalendarMode.week)
        : const SizedBox.shrink();
    final Widget expanded;
    if (!showExpanded) {
      expanded = const SizedBox.shrink();
    } else if (_isPeriodPickerOpen) {
      expanded = PageStorage(
        bucket: _monthStorage,
        child: DailyChoiceCalendarPeriodPicker(
          focusedDate: viewport.focusedDate,
          today: widget.today,
          onMonthSelected: _completeMonthSelection,
          onClose: () => setState(_closePeriodPicker),
        ),
      );
    } else {
      expanded = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            titleAction: (
              semanticLabel:
                  localizations.dailyChoiceCalendarChooseYearAndMonth,
              isExpanded: false,
              onTap: _openPeriodPicker,
            ),
          ),
          _buildGrid(DailyChoiceCalendarMode.month),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Дети сохраняют экземпляры между кадрами: анимация перестраивает
        // только раскладку, а не сетки и не выдачу потребителя.
        AnimatedBuilder(
          animation: _expansion,
          builder: (context, _) => ExcludeFocus(
            excluding: _isTransitioning,
            child: ExcludeSemantics(
              excluding: _isTransitioning,
              child: IgnorePointer(
                ignoring: _isTransitioning,
                child: DailyChoiceCalendarExpansion(
                  progress: _expansion.value,
                  week: week,
                  expanded: expanded,
                ),
              ),
            ),
          ),
        ),
        CalendarHandle(
          isExpanded: isExpanded,
          semanticLabel: isExpanded
              ? localizations.dailyChoiceCalendarCollapse
              : localizations.dailyChoiceCalendarExpand,
          onTap: _toggleMode,
        ),
        if (widget.hasDayMarksReadFailure)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Notice(
              message: localizations.dailyChoiceCalendarDayMarksUnavailable,
            ),
          ),
      ],
    );
  }

  Widget _buildGrid(DailyChoiceCalendarMode mode) => PageStorage(
    key: ValueKey(mode),
    bucket: mode == DailyChoiceCalendarMode.week ? _weekStorage : _monthStorage,
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Библиотека задаёт строкам фиксированную высоту; календарь вычисляет
        // её по ширине колонки и масштабу текста и строит собственные ячейки.
        final columnWidth = _columnWidth(constraints.maxWidth);
        return TableCalendarBase(
          firstDay: _firstDay,
          lastDay: _lastDay,
          focusedDay: _technicalDate(widget.viewport.focusedDate),
          calendarFormat: switch (mode) {
            DailyChoiceCalendarMode.week => CalendarFormat.week,
            DailyChoiceCalendarMode.month => CalendarFormat.month,
          },
          startingDayOfWeek: StartingDayOfWeek.monday,
          // Постоянные шесть строк включают дни соседних месяцев:
          // https://pub.dev/documentation/table_calendar/latest/table_calendar/TableCalendarBase/sixWeekMonthsEnforced.html
          sixWeekMonthsEnforced: true,
          availableGestures: AvailableGestures.horizontalSwipe,
          rowHeight: DailyChoiceCalendarDay.rowHeight(
            context,
            columnWidth: columnWidth,
            mode: mode,
          ),
          // В неделе подпись дня входит в ячейку:
          // https://pub.dev/documentation/table_calendar/latest/table_calendar/TableCalendarBase-class.html
          dowVisible: mode == DailyChoiceCalendarMode.month,
          dowHeight: _weekdayHeight(context, columnWidth: columnWidth),
          dowBuilder: _buildWeekday,
          dayBuilder: (context, day, focusedDay) =>
              _buildDay(context, day, focusedDay, mode),
          formatAnimationDuration: Duration.zero,
          pageAnimationEnabled: _isActive(mode),
          pageAnimationDuration: calendarPageAnimationDuration,
          pageAnimationCurve: calendarPageAnimationCurve,
          onCalendarCreated: (pages) {
            switch (mode) {
              case DailyChoiceCalendarMode.week:
                _weekPages = pages;
              case DailyChoiceCalendarMode.month:
                _monthPages = pages;
            }
          },
          onPageChanged: (day) => _reportFocusedDay(day, mode),
        );
      },
    ),
  );

  bool _isActive(DailyChoiceCalendarMode mode) =>
      !_isTransitioning && widget.viewport.mode == mode;

  // О смене страницы, как и после свайпа, сообщает _reportFocusedDay.
  void _showPreviousPeriod() => unawaited(
    _monthPages!.previousPage(
      duration: calendarPageAnimationDuration,
      curve: calendarPageAnimationCurve,
    ),
  );

  void _showNextPeriod() => unawaited(
    _monthPages!.nextPage(
      duration: calendarPageAnimationDuration,
      curve: calendarPageAnimationCurve,
    ),
  );

  void _toggleMode() {
    if (!_isTransitioning && !_isPeriodPickerOpen) {
      _stopPaging();
    }
    setState(() {
      _targetMode = switch (_targetMode) {
        DailyChoiceCalendarMode.week => DailyChoiceCalendarMode.month,
        DailyChoiceCalendarMode.month => DailyChoiceCalendarMode.week,
      };
      _isTransitioning = true;
    });
    final target = _progressFor(_targetMode);
    // animateTo начинает из текущего значения и отменяет прежнее завершение:
    // https://api.flutter.dev/flutter/animation/AnimationController/animateTo.html
    unawaited(
      _expansion
          .animateTo(
            target,
            duration: Duration(
              microseconds: (200000 * (target - _expansion.value).abs())
                  .round(),
            ),
            curve: Curves.easeOut,
          )
          .then((_) {
            setState(() {
              _isTransitioning = false;
              _discardInactiveGrid();
            });
            if (_targetMode != widget.viewport.mode) {
              widget.onViewportChanged(widget.viewport.withMode(_targetMode));
            }
          }),
    );
  }

  void _discardInactiveGrid() {
    switch (_targetMode) {
      case DailyChoiceCalendarMode.week:
        _closePeriodPicker();
      case DailyChoiceCalendarMode.month:
        _weekStorage = PageStorageBucket();
        _weekPages = null;
    }
  }

  void _openPeriodPicker() {
    _stopPaging();
    setState(() => _isPeriodPickerOpen = true);
  }

  void _closePeriodPicker() {
    _isPeriodPickerOpen = false;
    // При возвращении сетка создаётся с итоговым просмотром, без сохранённого
    // номера прежней страницы или представления:
    // https://api.flutter.dev/flutter/widgets/PageController/keepPage.html
    _monthStorage = PageStorageBucket();
    _monthPages = null;
  }

  void _completeMonthSelection(CalendarDate firstDate) {
    setState(_closePeriodPicker);
    widget.onMonthSelectionCompleted(
      DailyChoiceCalendarViewport(
        focusedDate: _focusedDateForMonth(firstDate),
        mode: DailyChoiceCalendarMode.month,
      ),
    );
  }

  CalendarDate _focusedDateForMonth(CalendarDate date) {
    final selected = widget.selectedDate;
    return selected.year == date.year && selected.month == date.month
        ? selected
        : CalendarDate.fromParts(date.year, date.month, 1);
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
    final pages = switch (widget.viewport.mode) {
      DailyChoiceCalendarMode.week => _weekPages!,
      DailyChoiceCalendarMode.month => _monthPages!,
    };
    if (pages.page case final page?) {
      pages.jumpToPage(page.round());
    }
  }

  /// Короткое название дня недели над колонкой. Каждый день и так называет
  /// свой день недели, поэтому подпись колонки не читается отдельно.
  Widget _buildWeekday(BuildContext context, DateTime day) {
    return ExcludeSemantics(
      child: MonthGridWeekday(text: _weekdayLabel(context, day)),
    );
  }

  Widget _buildDay(
    BuildContext context,
    DateTime day,
    DateTime focusedDay,
    DailyChoiceCalendarMode mode,
  ) {
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
      mode: mode,
      isOutsideMonth:
          mode == DailyChoiceCalendarMode.month &&
          (day.year != focusedDay.year || day.month != focusedDay.month),
      // Дату просмотра в нажатый день переносит потребитель.
      onSelected: () {
        if (_isActive(mode)) widget.onDateSelected(date);
      },
    );
  }

  void _reportFocusedDay(DateTime focusedDay, DailyChoiceCalendarMode mode) {
    if (!_isActive(mode)) return;
    // Технический фокус крайней недели может выйти за предел диапазона;
    // ближайший допустимый день принадлежит той же неделе.
    var focusedDate = _calendarDate(_clampToRange(focusedDay));
    final viewport = widget.viewport;
    if (viewport.mode == DailyChoiceCalendarMode.month &&
        (focusedDate.year != viewport.focusedDate.year ||
            focusedDate.month != viewport.focusedDate.month)) {
      focusedDate = _focusedDateForMonth(focusedDate);
    }
    // Библиотека сообщает о смене страницы и после синхронизации с входами
    // потребителя; повтор текущего просмотра не является его изменением.
    if (focusedDate != viewport.focusedDate) {
      widget.onViewportChanged(viewport.withFocusedDate(focusedDate));
    }
  }
}

double _progressFor(DailyChoiceCalendarMode mode) => switch (mode) {
  DailyChoiceCalendarMode.week => 0,
  DailyChoiceCalendarMode.month => 1,
};

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
