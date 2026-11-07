import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar_day.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar_viewport.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarDate date(int year, int month, int day) =>
    CalendarDate.fromParts(year, month, day);

ActionDayCalendarViewport week(CalendarDate focusedDate) =>
    ActionDayCalendarViewport(
      focusedDate: focusedDate,
      mode: ActionDayCalendarMode.week,
    );

ActionDayCalendarViewport month(CalendarDate focusedDate) =>
    ActionDayCalendarViewport(
      focusedDate: focusedDate,
      mode: ActionDayCalendarMode.month,
    );

/// Ячейка дня календаря по её календарной дате; при [skipOffstage] `false` —
/// и за краем видимой части прокрутки.
Finder calendarDay(CalendarDate value, {bool skipOffstage = true}) =>
    find.byKey(
      ValueKey('action-day-calendar-day-${value.toCanonicalString()}'),
      skipOffstage: skipOffstage,
    );

ActionDayCalendarDay dayCell(WidgetTester tester, CalendarDate value) =>
    tester.widget<ActionDayCalendarDay>(calendarDay(value));

/// Позиции крайней недели за пределами диапазона [CalendarDate].
final Finder unavailableCalendarDays = find.byKey(
  const ValueKey('action-day-calendar-unavailable-day'),
);

/// Видимые позиции дней по строкам сверху вниз, внутри строки — слева
/// направо: дата доступного дня или `null` для позиции за пределами диапазона.
///
/// При [skipOffstage] `false` учитываются и строки показанного периода за
/// краем видимой части общей прокрутки.
List<List<CalendarDate?>> visibleWeeks(
  WidgetTester tester, {
  bool skipOffstage = true,
}) {
  final rows = <double, List<(double, CalendarDate?)>>{};
  void addPosition(Element element, CalendarDate? value) {
    final position = (element.renderObject! as RenderBox).localToGlobal(
      Offset.zero,
    );
    rows.putIfAbsent(position.dy, () => []).add((position.dx, value));
  }

  final days = find.byType(ActionDayCalendarDay, skipOffstage: skipOffstage);
  for (final element in days.evaluate()) {
    addPosition(element, (element.widget as ActionDayCalendarDay).date);
  }
  final unavailable = find.byKey(
    const ValueKey('action-day-calendar-unavailable-day'),
    skipOffstage: skipOffstage,
  );
  for (final element in unavailable.evaluate()) {
    addPosition(element, null);
  }
  final tops = rows.keys.toList()..sort();
  return [
    for (final top in tops)
      [
        for (final (_, value)
            in rows[top]!..sort((a, b) => a.$1.compareTo(b.$1)))
          value,
      ],
  ];
}

/// Начало жеста перелистывания: пользователь проводит по дням периода, а не
/// по шапке календаря.
Finder get calendarPeriodArea => find.byType(ActionDayCalendarDay).first;

/// Перелистывает календарь горизонтальным свайпом к следующему периоду.
Future<void> swipeToNextPeriod(WidgetTester tester) async {
  await tester.drag(
    calendarPeriodArea,
    Offset(-tester.getSize(find.byType(ActionDayCalendar)).width * 0.8, 0),
  );
  await tester.pumpAndSettle();
}

/// Перелистывает календарь горизонтальным свайпом к предыдущему периоду.
Future<void> swipeToPreviousPeriod(WidgetTester tester) async {
  await tester.drag(
    calendarPeriodArea,
    Offset(tester.getSize(find.byType(ActionDayCalendar)).width * 0.8, 0),
  );
  await tester.pumpAndSettle();
}

/// [count] последовательных недель по семь дней, начиная с [firstDay].
List<List<CalendarDate>> weeksFrom(CalendarDate firstDay, int count) => [
  for (var row = 0; row < count; row++)
    [
      for (var column = 0; column < 7; column++)
        _shift(firstDay, row * 7 + column),
    ],
];

CalendarDate _shift(CalendarDate value, int days) {
  final shifted = DateTime.utc(value.year, value.month, value.day + days);
  return CalendarDate.fromParts(shifted.year, shifted.month, shifted.day);
}

/// Событие, полученное потребителем от календаря.
sealed class CalendarEvent {
  const CalendarEvent();
}

final class DateSelected extends CalendarEvent {
  const DateSelected(this.date);

  final CalendarDate date;

  @override
  bool operator ==(Object other) => other is DateSelected && other.date == date;

  @override
  int get hashCode => date.hashCode;

  @override
  String toString() => 'DateSelected($date)';
}

final class ViewportChanged extends CalendarEvent {
  const ViewportChanged(this.viewport);

  final ActionDayCalendarViewport viewport;

  @override
  bool operator ==(Object other) =>
      other is ViewportChanged && other.viewport == viewport;

  @override
  int get hashCode => viewport.hashCode;

  @override
  String toString() => 'ViewportChanged($viewport)';
}

final class MonthSelectionCompleted extends CalendarEvent {
  const MonthSelectionCompleted(this.viewport);

  final ActionDayCalendarViewport viewport;

  @override
  bool operator ==(Object other) =>
      other is MonthSelectionCompleted && other.viewport == viewport;

  @override
  int get hashCode => viewport.hashCode;

  @override
  String toString() => 'MonthSelectionCompleted($viewport)';
}

/// Потребитель календаря в тестах.
///
/// Как экран дня, он владеет выбранной датой и просмотром: выбор дня
/// синхронно переносит в нажатый день и выбор, и дату просмотра, сохраняя
/// представление, а изменение просмотра принимается как есть. Каждое
/// полученное событие записывается в [events].
final class CalendarConsumer {
  CalendarConsumer._();

  final _host = GlobalKey<_CalendarConsumerHostState>();
  final List<CalendarEvent> events = [];

  CalendarDate get selectedDate => _host.currentState!._selectedDate;
  ActionDayCalendarViewport get viewport => _host.currentState!._viewport;

  /// Заменяет входы календаря от имени потребителя, не создавая событий.
  void replaceInputs({
    CalendarDate? selectedDate,
    ActionDayCalendarViewport? viewport,
    CalendarDate? today,
    Map<CalendarDate, ActionDayStatus>? dayStatuses,
    bool? hasDayMarksReadFailure,
  }) => _host.currentState!._replace(
    selectedDate: selectedDate,
    viewport: viewport,
    today: today,
    dayStatuses: dayStatuses,
    hasDayMarksReadFailure: hasDayMarksReadFailure,
  );

  /// Перестраивает потребителя с прежними входами: календарь получает новый
  /// экземпляр виджета с теми же значениями, как при обновлении страницы по
  /// причинам, не связанным с календарём.
  void rebuild() => _host.currentState!._rebuild();

  /// Убирает календарь из дерева, сохраняя потребителя, его входы и журнал.
  void removeCalendar() => _host.currentState!._setCalendarShown(false);

  /// Создаёт календарь заново с текущими входами потребителя.
  void restoreCalendar() => _host.currentState!._setCalendarShown(true);

  /// Убирает общую прокрутку вместе с календарём, сохраняя потребителя, его
  /// входы и журнал.
  void removeScrollView() => _host.currentState!._setScrollViewShown(false);

  /// Создаёт общую прокрутку и календарь заново с текущими входами
  /// потребителя. Прокрутка с ключом хранения восстанавливает сохранённое
  /// смещение.
  void restoreScrollView() => _host.currentState!._setScrollViewShown(true);
}

/// Показывает календарь у нового потребителя.
///
/// [locale] — системная локаль устройства. Локаль календаря выбирают правила и
/// делегаты приложения, поэтому смена `tester.platformDispatcher.localesTestValue`
/// меняет язык у того же потребителя, а неподдерживаемый язык даёт английский.
///
/// Календарь — первый элемент общей вертикальной прокрутки потребителя, как
/// на экране дня; [contentBelow] — следующие за ним элементы той же прокрутки.
/// [scrollStorageKey] — ключ, под которым общая прокрутка сохраняет смещение в
/// хранилище страниц маршрута, как прокрутки страниц приложения.
Future<CalendarConsumer> pumpCalendarConsumer(
  WidgetTester tester, {
  required CalendarDate selectedDate,
  required ActionDayCalendarViewport viewport,
  required CalendarDate today,
  Locale locale = const Locale('ru'),
  List<Widget> contentBelow = const [],
  PageStorageKey<String>? scrollStorageKey,
  Map<CalendarDate, ActionDayStatus> dayStatuses = const {},
  bool hasDayMarksReadFailure = false,
}) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final consumer = CalendarConsumer._();
  await tester.pumpWidget(
    MaterialApp(
      theme: doableTheme(Brightness.light),
      darkTheme: doableTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      home: Scaffold(
        body: _CalendarConsumerHost(
          key: consumer._host,
          consumer: consumer,
          selectedDate: selectedDate,
          viewport: viewport,
          today: today,
          contentBelow: contentBelow,
          scrollStorageKey: scrollStorageKey,
          dayStatuses: dayStatuses,
          hasDayMarksReadFailure: hasDayMarksReadFailure,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return consumer;
}

final class _CalendarConsumerHost extends StatefulWidget {
  const _CalendarConsumerHost({
    super.key,
    required this.consumer,
    required this.selectedDate,
    required this.viewport,
    required this.today,
    required this.contentBelow,
    required this.scrollStorageKey,
    required this.dayStatuses,
    required this.hasDayMarksReadFailure,
  });

  final CalendarConsumer consumer;
  final CalendarDate selectedDate;
  final ActionDayCalendarViewport viewport;
  final CalendarDate today;
  final List<Widget> contentBelow;
  final PageStorageKey<String>? scrollStorageKey;
  final Map<CalendarDate, ActionDayStatus> dayStatuses;
  final bool hasDayMarksReadFailure;

  @override
  State<_CalendarConsumerHost> createState() => _CalendarConsumerHostState();
}

final class _CalendarConsumerHostState extends State<_CalendarConsumerHost> {
  late CalendarDate _selectedDate = widget.selectedDate;
  late ActionDayCalendarViewport _viewport = widget.viewport;
  late CalendarDate _today = widget.today;
  late Map<CalendarDate, ActionDayStatus> _dayStatuses = widget.dayStatuses;
  late bool _hasDayMarksReadFailure = widget.hasDayMarksReadFailure;
  bool _scrollViewShown = true;
  bool _calendarShown = true;

  void _rebuild() {
    setState(() {});
  }

  void _setCalendarShown(bool value) {
    setState(() => _calendarShown = value);
  }

  void _setScrollViewShown(bool value) {
    setState(() => _scrollViewShown = value);
  }

  void _replace({
    CalendarDate? selectedDate,
    ActionDayCalendarViewport? viewport,
    CalendarDate? today,
    Map<CalendarDate, ActionDayStatus>? dayStatuses,
    bool? hasDayMarksReadFailure,
  }) {
    setState(() {
      _selectedDate = selectedDate ?? _selectedDate;
      _viewport = viewport ?? _viewport;
      _today = today ?? _today;
      _dayStatuses = dayStatuses ?? _dayStatuses;
      _hasDayMarksReadFailure =
          hasDayMarksReadFailure ?? _hasDayMarksReadFailure;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_scrollViewShown) {
      return const SizedBox.shrink();
    }
    return CustomScrollView(
      key: widget.scrollStorageKey,
      slivers: [
        SliverToBoxAdapter(
          child: _calendarShown ? _buildCalendar() : const SizedBox.shrink(),
        ),
        ...widget.contentBelow,
      ],
    );
  }

  Widget _buildCalendar() => ActionDayCalendar(
    selectedDate: _selectedDate,
    viewport: _viewport,
    today: _today,
    dayStatusForDate: (value) => _dayStatuses[value],
    hasDayMarksReadFailure: _hasDayMarksReadFailure,
    onDateSelected: (value) {
      widget.consumer.events.add(DateSelected(value));
      setState(() {
        _selectedDate = value;
        _viewport = _viewport.withFocusedDate(value);
      });
    },
    onViewportChanged: (value) {
      widget.consumer.events.add(ViewportChanged(value));
      setState(() => _viewport = value);
    },
    onMonthSelectionCompleted: (value) {
      widget.consumer.events.add(MonthSelectionCompleted(value));
      setState(() => _viewport = value);
    },
  );
}
