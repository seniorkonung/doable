import 'package:doable/src/design_system/components/value_chip.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('значение и действие доступны одной кнопкой со значком', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _app(
        ValueChip.icon(
          value: 'Сегодня',
          icon: ValueChipIcon.calendar,
          label: 'Дата: 8 октября 2026. Изменить дату',
          onPressed: () => taps++,
        ),
      ),
    );
    expect(
      tester.widget<DoableIcon>(find.byType(DoableIcon)).icon,
      DoableIconData.calendar,
    );
    expect(
      tester.getSemantics(find.byType(ValueChip)),
      isSemantics(
        label: 'Дата: 8 октября 2026. Изменить дату',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.text('Сегодня'));
    expect(taps, 1);
    expect(tester.widget<Text>(find.text('Сегодня')).softWrap, isFalse);
    semantics.dispose();
  });
  testWidgets('время показывает часы, а приоритет — кольцо своего цвета', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Column(
          children: [
            ValueChip.icon(
              value: 'Весь день',
              icon: ValueChipIcon.clock,
              label: 'Время',
              onPressed: _noop,
            ),
            ValueChip.priority(
              value: 'P2',
              priority: DoablePriority.p2,
              label: 'Приоритет',
              onPressed: _noop,
            ),
          ],
        ),
      ),
    );
    expect(
      tester.widget<DoableIcon>(find.byType(DoableIcon)).icon,
      DoableIconData.clock,
    );
    final ring = tester.widget<DecoratedBox>(
      find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
    );
    final decoration = ring.decoration as BoxDecoration;
    expect(
      decoration.border!.top.color,
      DoablePriority.p2.color(doableTheme(Brightness.light).extension()!),
    );
    expect(decoration.color!.a, closeTo(.12, .01));
  });
}

void _noop() {}
Widget _app(Widget child) => MaterialApp(
  theme: doableTheme(Brightness.light),
  home: Scaffold(body: child),
);
