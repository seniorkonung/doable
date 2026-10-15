import 'dart:ui' show Tristate;

import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/design_system/components/week_strip_day.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('день — одна кнопка с названием, выбранностью и нажатием', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selected = false;
    var presses = 0;
    const label = 'Четверг, 8 октября 2026, сегодня, всё выполнено';

    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => WeekStripDay(
                dayText: '8',
                weekdayText: 'Чт',
                isSelected: selected,
                isToday: true,
                mark: DayMark.done,
                semanticLabel: label,
                onTap: () => setState(() {
                  selected = !selected;
                  presses++;
                }),
              ),
            ),
          ),
        ),
      ),
    );

    final button = find.bySemanticsLabel(label);
    expect(button, findsOneWidget);
    expect(
      tester.getSemantics(button),
      matchesSemantics(
        label: label,
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    await tester.tapAt(
      tester.getTopLeft(find.byType(WeekStripDay)) + const Offset(24, 1),
    );
    await tester.pump();
    expect(presses, 1);
    final node = tester.getSemantics(button);
    expect(node.flagsCollection.isSelected, Tristate.isTrue);
    expect(node.childrenCount, 0);

    tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
    await tester.pump();
    expect(presses, 2);
    expect(
      tester.getSemantics(button).flagsCollection.isSelected,
      Tristate.isFalse,
    );
    semantics.dispose();
  });

  testWidgets('высота строки сохраняет крупные тексты целиком в узкой ячейке', (
    tester,
  ) async {
    var height = 0.0;
    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
          child: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) {
                  height = WeekStripDay.rowHeight(
                    context,
                    dayTexts: const ['28'],
                    weekdayTexts: const ['Чт'],
                    columnWidth: 48,
                  );
                  return SizedBox(
                    width: 48,
                    height: height,
                    child: WeekStripDay(
                      dayText: '28',
                      weekdayText: 'Чт',
                      isSelected: true,
                      isToday: true,
                      mark: DayMark.todo,
                      semanticLabel: 'Четверг, 28 мая 2026',
                      onTap: () {},
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(height, greaterThan(54));
    expect(tester.takeException(), isNull);
    final cell = tester.getRect(find.byType(WeekStripDay));
    for (final text in ['28', 'Чт']) {
      final bounds = tester.getRect(find.text(text));
      expect(cell.contains(bounds.topLeft), isTrue);
      expect(cell.contains(bounds.bottomRight), isTrue);
    }
  });
}
