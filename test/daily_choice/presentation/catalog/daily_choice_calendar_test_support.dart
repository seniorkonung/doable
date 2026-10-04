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

/// Даты видимых ячеек по строкам сверху вниз, внутри строки — слева направо.
List<List<CalendarDate>> visibleWeeks(WidgetTester tester) {
  final rows = <double, List<(double, CalendarDate)>>{};
  for (final element in find.byType(DailyChoiceCalendarDay).evaluate()) {
    final position = (element.renderObject! as RenderBox).localToGlobal(
      Offset.zero,
    );
    final cell = element.widget as DailyChoiceCalendarDay;
    rows.putIfAbsent(position.dy, () => []).add((position.dx, cell.date));
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
