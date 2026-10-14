import 'dart:ui' show Tristate;

import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/design_system/components/month_grid_day.dart';
import 'package:doable/src/design_system/components/month_grid_weekday.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('день месяца доступен одной кнопкой по всей области нажатия', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selected = false;
    var presses = 0;
    const label = 'Среда, 30 сентября 2026, сегодня, всё выполнено';

    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => MonthGridDay(
                dayText: '30',
                isSelected: selected,
                isToday: true,
                isOutsideMonth: true,
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
      tester.getTopLeft(find.byType(MonthGridDay)) + const Offset(22, 1),
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

  testWidgets(
    'высоты строк месяца вмещают крупное число и подпись с переносом',
    (tester) async {
      var dayHeight = 0.0;
      var weekdayHeight = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: doableTheme(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
            child: Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) {
                    dayHeight = MonthGridDay.rowHeight(
                      context,
                      dayTexts: const ['8', '30'],
                      columnWidth: 44,
                    );
                    weekdayHeight = MonthGridWeekday.rowHeight(
                      context,
                      texts: const ['Пн', 'Ср'],
                      columnWidth: 44,
                    );
                    return SizedBox(
                      width: 44,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: weekdayHeight,
                            child: const MonthGridWeekday(text: 'Ср'),
                          ),
                          SizedBox(
                            height: dayHeight,
                            child: MonthGridDay(
                              dayText: '30',
                              isSelected: true,
                              isToday: true,
                              isOutsideMonth: true,
                              mark: DayMark.todo,
                              semanticLabel: 'Среда, 30 сентября 2026',
                              onTap: () {},
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(dayHeight, greaterThan(44));
      expect(weekdayHeight, greaterThan(28));
      expect(tester.takeException(), isNull);
      for (final (type, text) in [
        (MonthGridDay, '30'),
        (MonthGridWeekday, 'Ср'),
      ]) {
        final cell = tester.getRect(find.byType(type));
        final bounds = tester.getRect(find.text(text));
        expect(bounds.intersect(cell), bounds);
      }
    },
  );
}
