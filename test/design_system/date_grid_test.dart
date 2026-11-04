import 'dart:ui' show Tristate;

import 'package:doable/src/design_system/components/date_grid.dart';
import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/design_system/components/month_grid_day.dart';
import 'package:doable/src/design_system/components/month_grid_weekday.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// Октябрь 2026 начинается с четверга: шесть недель идут с понедельника
/// 28 сентября по воскресенье 8 ноября.
String _text(int index) => switch (index) {
  < 3 => '${28 + index}',
  < 34 => '${index - 2}',
  _ => '${index - 33}',
};

String _label(int index) => 'день $index';

List<DateGridDay> _days({
  int? selected,
  int? today,
  Map<int, DayMark> marks = const {},
  void Function(int index)? onTap,
}) => [
  for (var index = 0; index < 42; index++)
    DateGridDay(
      text: _text(index),
      semanticLabel: _label(index),
      onTap: () => onTap?.call(index),
      isSelected: index == selected,
      isToday: index == today,
      isOutsideMonth: index < 3 || index >= 34,
      mark: marks[index] ?? DayMark.none,
    ),
];

Widget _grid({
  List<DateGridDay>? days,
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  double width = 336,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      // Лист прокручивает тело, поэтому крупный шрифт не переполняет сетку.
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: DateGrid(
              title: 'Октябрь 2026',
              previousLabel: 'Предыдущий месяц',
              nextLabel: 'Следующий месяц',
              onPrevious: onPrevious,
              onNext: onNext,
              weekdays: _weekdays,
              days: days ?? _days(),
            ),
          ),
        ),
      ),
    ),
  ),
);

Finder _day(int index) => find.byWidgetPredicate(
  (widget) => widget is MonthGridDay && widget.semanticLabel == _label(index),
);

void main() {
  testWidgets(
    'сетка занимает всю ширину: шапка и подписи выше стандартных, шесть недель '
    'по семь дней без боковых полей',
    (tester) async {
      await tester.pumpWidget(_grid());

      final grid = tester.getRect(find.byType(DateGrid));
      expect(grid.width, 336);
      final previous = find.bySemanticsLabel('Предыдущий месяц');
      final next = find.bySemanticsLabel('Следующий месяц');
      expect(tester.getRect(previous).left, grid.left);
      expect(tester.getRect(previous).height, DoableMetrics.tapMin);
      expect(tester.getRect(next).right, grid.right);

      final weekdays = find.byType(MonthGridWeekday);
      expect(weekdays, findsNWidgets(7));
      for (var index = 0; index < 7; index++) {
        final rect = tester.getRect(weekdays.at(index));
        expect(rect.top, DoableMetrics.tapMin);
        expect(rect.height, 28);
        expect(rect.left, grid.left + index * 48);
      }
      final firstDay = tester.getRect(_day(0));
      expect(firstDay.left, grid.left);
      expect(firstDay.top, DoableMetrics.tapMin + 28);
      for (var index = 0; index < 42; index++) {
        final rect = tester.getRect(_day(index));
        expect(rect.width, 48, reason: 'день $index');
        expect(rect.height, DoableMetrics.tapMin, reason: 'день $index');
        expect(rect.left, grid.left + (index % 7) * 48, reason: 'день $index');
        expect(
          rect.top,
          firstDay.top + (index ~/ 7) * DoableMetrics.tapMin,
          reason: 'день $index',
        );
      }
      expect(tester.getRect(_day(41)).right, grid.right);
      expect(
        tester.getRect(_day(41)).bottom,
        firstDay.top + 6 * DoableMetrics.tapMin,
      );
    },
  );

  testWidgets(
    'каждый день, в том числе соседнего месяца, вызывает свой обработчик '
    'нажатием и доступной командой',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final taps = <int>[];
      await tester.pumpWidget(_grid(days: _days(onTap: taps.add)));

      for (final index in [0, 2, 3, 20, 33, 34, 41]) {
        await tester.tap(_day(index));
        await tester.pump();
        expect(taps.last, index);
        final node = tester.getSemantics(find.bySemanticsLabel(_label(index)));
        expect(node.flagsCollection.isButton, isTrue);
        tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.tap,
        );
        await tester.pump();
      }
      expect(taps, [0, 0, 2, 2, 3, 3, 20, 20, 33, 33, 34, 34, 41, 41]);
      semantics.dispose();
    },
  );

  testWidgets(
    'выбранный, сегодняшний и соседние дни выглядят по дизайну, а отметка '
    'стоит под числом и на выбранном дне в цвете on-accent',
    (tester) async {
      await tester.pumpWidget(
        _grid(
          days: _days(
            selected: 10,
            today: 11,
            marks: {
              10: DayMark.todo,
              11: DayMark.done,
              0: DayMark.todo,
              12: DayMark.done,
            },
          ),
        ),
      );
      final colors = tester
          .element(find.byType(DateGrid))
          .findAncestorWidgetOfExactType<MaterialApp>()!
          .theme!
          .extension<DoableColors>()!;

      Text number(int index) => tester.widget<Text>(
        find.descendant(of: _day(index), matching: find.byType(Text)),
      );
      DayMarkIndicator mark(int index) => tester.widget<DayMarkIndicator>(
        find.descendant(
          of: _day(index),
          matching: find.byType(DayMarkIndicator),
        ),
      );

      expect(number(10).style!.color, colors.onAccent);
      expect(number(10).style!.fontWeight, const FontWeight(650));
      expect(mark(10).mark, DayMark.todo);
      expect(mark(10).onAccent, isTrue);
      final fill = tester.widget<Ink>(
        find.descendant(of: _day(10), matching: find.byType(Ink)),
      );
      expect((fill.decoration! as BoxDecoration).color, colors.accent);

      expect(number(11).style!.color, colors.accent);
      expect(number(11).style!.fontWeight, const FontWeight(650));
      expect(mark(11).mark, DayMark.done);
      expect(mark(11).onAccent, isFalse);

      expect(number(0).style!.color, colors.muted);
      expect(number(0).style!.fontWeight, FontWeight.w400);
      expect(mark(0).mark, DayMark.todo);

      expect(number(12).style!.color, colors.ink);
      expect(number(12).style!.fontWeight, FontWeight.w500);
      expect(mark(12).mark, DayMark.done);
      expect(
        tester.getTopLeft(find.byWidget(mark(12))).dy,
        greaterThan(tester.getBottomLeft(find.byWidget(number(12))).dy - 1),
      );
    },
  );

  testWidgets('заголовок месяца не кнопка, а стрелки сообщают о переходе и при '
      'отсутствии обработчика недоступны', (tester) async {
    final semantics = tester.ensureSemantics();
    var previous = 0;
    await tester.pumpWidget(_grid(onPrevious: () => previous++));

    await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
    await tester.pump();
    expect(previous, 1);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Следующий месяц'))
          .flagsCollection
          .isEnabled,
      Tristate.isFalse,
    );
    final title = tester.getSemantics(find.text('Октябрь 2026'));
    expect(title.flagsCollection.isButton, isFalse);
    expect(title.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  testWidgets('подписи дней недели не читаются отдельно от названий дней', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_grid());

    expect(find.bySemanticsLabel('Пн'), findsNothing);
    expect(find.bySemanticsLabel(_label(0)), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('при крупном шрифте все недели одной высоты, а числа и подписи '
      'помещаются в ячейки', (tester) async {
    await tester.pumpWidget(_grid(width: 336, textScale: 2.5));

    expect(tester.takeException(), isNull);
    final firstDay = tester.getRect(_day(0));
    expect(firstDay.height, greaterThan(DoableMetrics.tapMin));
    for (var index = 0; index < 42; index++) {
      final rect = tester.getRect(_day(index));
      expect(rect.height, firstDay.height, reason: 'день $index');
      expect(
        rect.top,
        firstDay.top + (index ~/ 7) * firstDay.height,
        reason: 'день $index',
      );
      final number = tester.getRect(
        find.descendant(of: _day(index), matching: find.byType(Text)),
      );
      expect(number.intersect(rect), number, reason: 'день $index');
    }
    for (var index = 0; index < 7; index++) {
      final cell = tester.getRect(find.byType(MonthGridWeekday).at(index));
      final bounds = tester.getRect(find.text(_weekdays[index]));
      expect(bounds.intersect(cell), bounds, reason: _weekdays[index]);
    }
  });
}
