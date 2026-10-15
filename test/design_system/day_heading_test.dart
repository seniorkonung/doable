import 'package:doable/src/design_system/components/day_heading.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('дата доступна как заголовок с отметкой и без неё', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: const Scaffold(
          body: DayHeading(
            weekday: 'Четверг',
            date: '8 октября 2026',
            todayLabel: 'Сегодня',
          ),
        ),
      ),
    );

    expect(find.semantics.byLabel(RegExp('Четверг')), findsOne);
    expect(find.semantics.byLabel(RegExp('Сегодня')), findsOne);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('8 октября 2026'))
          .flagsCollection
          .isHeader,
      isTrue,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: const Scaffold(
          body: DayHeading(weekday: 'Среда', date: '7 октября 2026'),
        ),
      ),
    );

    expect(find.semantics.byLabel(RegExp('Среда')), findsOne);
    expect(find.semantics.byLabel(RegExp('Сегодня')), findsNothing);
    expect(find.bySemanticsLabel('8 октября 2026'), findsNothing);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('7 октября 2026'))
          .flagsCollection
          .isHeader,
      isTrue,
    );
    semantics.dispose();
  });
}
