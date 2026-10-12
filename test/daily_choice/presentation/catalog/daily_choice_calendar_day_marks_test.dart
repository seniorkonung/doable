import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';

void main() {
  for (final mode in DailyChoiceCalendarMode.values) {
    testWidgets(
      'галочка, пустой кружок и день без отметки в представлении ${mode.name}, '
      'включая соседний месяц, выбранный и сегодняшний дни',
      (tester) async {
        final completed = date(2026, 9, 30);
        final incomplete = date(2026, 10, 1);
        final empty = date(2026, 10, 2);
        final viewport = DailyChoiceCalendarViewport(
          focusedDate: incomplete,
          mode: mode,
        );
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: incomplete,
          viewport: viewport,
          today: completed,
          dayStatuses: {
            completed: DailyChoiceDayStatus.allCompleted,
            incomplete: DailyChoiceDayStatus.hasIncomplete,
          },
        );
        final colors = Theme.of(
          tester.element(find.byType(DailyChoiceCalendar)),
        ).colorScheme;
        final check = find.descendant(
          of: calendarDay(completed),
          matching: find.byIcon(Icons.check),
        );
        final circle = find.descendant(
          of: calendarDay(incomplete),
          matching: find.byIcon(Icons.circle_outlined),
        );
        expect(check, findsOneWidget);
        expect(circle, findsOneWidget);
        expect(tester.widget<Icon>(circle).color, colors.onPrimary);
        expect(
          tester.widget<Icon>(check).color,
          mode == DailyChoiceCalendarMode.month
              ? colors.onSurfaceVariant
              : colors.onSurface,
        );
        expect(
          find.descendant(of: calendarDay(empty), matching: find.byType(Icon)),
          findsNothing,
        );
        for (final mark in [check, circle]) {
          final day = mark == check ? completed : incomplete;
          final number = find.descendant(
            of: calendarDay(day),
            matching: find.text('${day.day}'),
          );
          expect(
            tester.getRect(mark).top,
            greaterThan(tester.getRect(number).bottom),
          );
        }

        consumer.replaceInputs(selectedDate: completed);
        await tester.pumpAndSettle();
        expect(tester.widget<Icon>(check).color, colors.onPrimary);
        expect(tester.widget<Icon>(circle).color, colors.onSurface);
        expect(consumer.events, isEmpty);
        expect(consumer.viewport, viewport);
      },
    );
  }

  testWidgets('отказ сохраняет отметки, выбор и управление; успех убирает '
      'строку и заменяет состояния без событий', (tester) async {
    final selected = date(2026, 10, 6);
    final consumer = await pumpCalendarConsumer(
      tester,
      selectedDate: selected,
      viewport: week(selected),
      today: date(2026, 10, 4),
      dayStatuses: {selected: DailyChoiceDayStatus.hasIncomplete},
    );
    consumer.replaceInputs(hasDayMarksReadFailure: true);
    await tester.pumpAndSettle();

    expect(find.text('Отметки дней не загружены.'), findsOneWidget);
    expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(consumer.selectedDate, selected);
    expect(consumer.events, isEmpty);

    await tester.tap(calendarDay(date(2026, 10, 7)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Следующая неделя'));
    await tester.pumpAndSettle();
    expect(consumer.events, [
      DateSelected(date(2026, 10, 7)),
      ViewportChanged(week(date(2026, 10, 14))),
    ]);
    expect(consumer.selectedDate, date(2026, 10, 7));
    consumer.events.clear();

    consumer.replaceInputs(
      viewport: week(selected),
      dayStatuses: {date(2026, 10, 7): DailyChoiceDayStatus.allCompleted},
      hasDayMarksReadFailure: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Отметки дней не загружены.'), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.circle_outlined), findsNothing);
    expect(consumer.events, isEmpty);
  });
}
