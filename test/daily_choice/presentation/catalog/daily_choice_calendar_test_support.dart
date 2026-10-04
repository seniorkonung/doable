import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarDate date(int year, int month, int day) =>
    CalendarDate.fromParts(year, month, day);

DailyChoiceCalendarViewport week(CalendarDate focusedDate) =>
    DailyChoiceCalendarViewport(
      focusedDate: focusedDate,
      mode: DailyChoiceCalendarMode.week,
    );

DailyChoiceCalendarViewport month(CalendarDate focusedDate) =>
    DailyChoiceCalendarViewport(
      focusedDate: focusedDate,
      mode: DailyChoiceCalendarMode.month,
    );

/// Ячейка дня календаря по её календарной дате.
Finder calendarDay(CalendarDate value) => find.byKey(
  ValueKey('daily-choice-calendar-day-${value.toCanonicalString()}'),
);

DailyChoiceCalendarDay dayCell(WidgetTester tester, CalendarDate value) =>
    tester.widget<DailyChoiceCalendarDay>(calendarDay(value));

/// Позиции крайней недели за пределами диапазона [CalendarDate].
final Finder unavailableCalendarDays = find.byKey(
  const ValueKey('daily-choice-calendar-unavailable-day'),
);

/// Видимые позиции дней по строкам сверху вниз, внутри строки — слева
/// направо: дата доступного дня или `null` для позиции за пределами диапазона.
List<List<CalendarDate?>> visibleWeeks(WidgetTester tester) {
  final rows = <double, List<(double, CalendarDate?)>>{};
  void addPosition(Element element, CalendarDate? value) {
    final position = (element.renderObject! as RenderBox).localToGlobal(
      Offset.zero,
    );
    rows.putIfAbsent(position.dy, () => []).add((position.dx, value));
  }

  for (final element in find.byType(DailyChoiceCalendarDay).evaluate()) {
    addPosition(element, (element.widget as DailyChoiceCalendarDay).date);
  }
  for (final element in unavailableCalendarDays.evaluate()) {
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
Finder get calendarPeriodArea => find.byType(DailyChoiceCalendarDay).first;

/// Перелистывает календарь горизонтальным свайпом к следующему периоду.
Future<void> swipeToNextPeriod(WidgetTester tester) async {
  await tester.drag(calendarPeriodArea, const Offset(-600, 0));
  await tester.pumpAndSettle();
}

/// Перелистывает календарь горизонтальным свайпом к предыдущему периоду.
Future<void> swipeToPreviousPeriod(WidgetTester tester) async {
  await tester.drag(calendarPeriodArea, const Offset(600, 0));
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

  final DailyChoiceCalendarViewport viewport;

  @override
  bool operator ==(Object other) =>
      other is ViewportChanged && other.viewport == viewport;

  @override
  int get hashCode => viewport.hashCode;

  @override
  String toString() => 'ViewportChanged($viewport)';
}

/// Потребитель календаря в тестах.
///
/// Как страница каталога, он владеет выбранной датой и просмотром: выбор дня
/// синхронно переносит в нажатый день и выбор, и дату просмотра, сохраняя
/// представление, а изменение просмотра принимается как есть. Каждое
/// полученное событие записывается в [events].
final class CalendarConsumer {
  CalendarConsumer._();

  final _host = GlobalKey<_CalendarConsumerHostState>();
  final List<CalendarEvent> events = [];

  CalendarDate get selectedDate => _host.currentState!._selectedDate;
  DailyChoiceCalendarViewport get viewport => _host.currentState!._viewport;

  /// Заменяет входы календаря от имени потребителя, не создавая событий.
  void replaceInputs({
    CalendarDate? selectedDate,
    DailyChoiceCalendarViewport? viewport,
    CalendarDate? today,
  }) => _host.currentState!._replace(
    selectedDate: selectedDate,
    viewport: viewport,
    today: today,
  );

  /// Перестраивает потребителя с прежними входами: календарь получает новый
  /// экземпляр виджета с теми же значениями, как при обновлении страницы по
  /// причинам, не связанным с календарём.
  void rebuild() => _host.currentState!._rebuild();

  /// Убирает календарь из дерева, сохраняя потребителя, его входы и журнал.
  void removeCalendar() => _host.currentState!._setCalendarShown(false);

  /// Создаёт календарь заново с текущими входами потребителя.
  void restoreCalendar() => _host.currentState!._setCalendarShown(true);
}

Future<CalendarConsumer> pumpCalendarConsumer(
  WidgetTester tester, {
  required CalendarDate selectedDate,
  required DailyChoiceCalendarViewport viewport,
  required CalendarDate today,
  Locale locale = const Locale('ru'),
}) async {
  final consumer = CalendarConsumer._();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _CalendarConsumerHost(
                key: consumer._host,
                consumer: consumer,
                selectedDate: selectedDate,
                viewport: viewport,
                today: today,
              ),
            ),
          ],
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
  });

  final CalendarConsumer consumer;
  final CalendarDate selectedDate;
  final DailyChoiceCalendarViewport viewport;
  final CalendarDate today;

  @override
  State<_CalendarConsumerHost> createState() => _CalendarConsumerHostState();
}

final class _CalendarConsumerHostState extends State<_CalendarConsumerHost> {
  late CalendarDate _selectedDate = widget.selectedDate;
  late DailyChoiceCalendarViewport _viewport = widget.viewport;
  late CalendarDate _today = widget.today;
  bool _calendarShown = true;

  void _rebuild() {
    setState(() {});
  }

  void _setCalendarShown(bool value) {
    setState(() => _calendarShown = value);
  }

  void _replace({
    CalendarDate? selectedDate,
    DailyChoiceCalendarViewport? viewport,
    CalendarDate? today,
  }) {
    setState(() {
      _selectedDate = selectedDate ?? _selectedDate;
      _viewport = viewport ?? _viewport;
      _today = today ?? _today;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_calendarShown) {
      return const SizedBox.shrink();
    }
    return DailyChoiceCalendar(
      selectedDate: _selectedDate,
      viewport: _viewport,
      today: _today,
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
    );
  }
}
