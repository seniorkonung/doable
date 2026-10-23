import 'package:doable/src/design_system/components/filter_button.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Шрифт тестов рисует каждый знак квадратом в кегль: число `label` из одной
// цифры шириной 13.
void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме кнопка без условий — квадрат 44 fill с '
        'углами radius-sm и иконкой фильтра 20 цвета muted по центру', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(brightness: brightness, button: _button(count: 0)),
      );

      final tile = tester.widget<Material>(_tile);
      expect(tile.color, colors.fill);
      expect(tile.borderRadius, BorderRadius.circular(DoableMetrics.radiusSm));
      final rect = tester.getRect(find.byType(FilterButton));
      expect(rect.size, const Size(44, 44));

      final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(icon.icon, DoableIconData.filter);
      expect(icon.size, 20);
      expect(icon.color, colors.muted);
      expect(tester.getCenter(find.byType(DoableIcon)), rect.center);
      expect(
        find.descendant(
          of: find.byType(FilterButton),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
    });

    testWidgets('в $themeName теме при условиях иконка и число label с '
        'табличными цифрами цвета accent стоят на accent-soft через 5, с '
        'полями 10 слева и space-3 справа', (tester) async {
      await tester.pumpWidget(
        _app(brightness: brightness, button: _button(count: 2)),
      );

      final tile = tester.widget<Material>(_tile);
      expect(tile.color, colors.accentSoft);
      expect(tile.borderRadius, BorderRadius.circular(DoableMetrics.radiusSm));

      final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(icon.icon, DoableIconData.filter);
      expect(icon.size, 20);
      expect(icon.color, colors.accent);

      final count = _style(tester, '2');
      expect(count.color, colors.accent);
      expect(count.fontSize, DoableType.label.fontSize);
      expect(count.fontWeight, DoableType.label.fontWeight);
      expect(count.fontFeatures, const [FontFeature.tabularFigures()]);

      final rect = tester.getRect(find.byType(FilterButton));
      final iconRect = tester.getRect(find.byType(DoableIcon));
      final countRect = tester.getRect(find.text('2'));
      // 10 + 20 + 5 + 13 + 12.
      expect(rect.size, const Size(60, 44));
      expect(iconRect.left - rect.left, 10);
      expect(countRect.left - iconRect.right, 5);
      expect(rect.right - countRect.right, DoableMetrics.space3);
      expect(iconRect.center.dy, rect.center.dy);
      expect(countRect.center.dy, rect.center.dy);
    });
  }

  testWidgets('кнопка — один узел с названием от потребителя и вызывает его '
      'обработчик', (tester) async {
    final semantics = tester.ensureSemantics();
    var openings = 0;

    await tester.pumpWidget(
      _app(button: _button(count: 2, onPressed: () => openings++)),
    );

    final node = tester.getSemantics(find.bySemanticsLabel(_label));
    expect(
      node,
      isSemantics(label: _label, isButton: true, hasTapAction: true),
    );
    expect(node.childrenCount, 0);

    await tester.tap(find.byType(FilterButton));
    expect(openings, 1);
    semantics.dispose();
  });

  testWidgets('при тексте масштаба 2 кнопка с условиями вмещает иконку и '
      'число', (tester) async {
    await tester.pumpWidget(_app(textScale: 2, button: _button(count: 12)));

    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byType(FilterButton));
    final count = tester.getRect(find.text('12'));
    expect(rect.height, 44);
    expect(rect.right - count.right, DoableMetrics.space3);
    expect(count.top, greaterThanOrEqualTo(rect.top));
    expect(count.bottom, lessThanOrEqualTo(rect.bottom));
  });
}

const _label = 'Фильтр по тегам. Условия: 2';

FilterButton _button({required int count, VoidCallback? onPressed}) =>
    FilterButton(count: count, label: _label, onPressed: onPressed ?? () {});

final _tile = find.descendant(
  of: find.byType(FilterButton),
  matching: find.byType(Material),
);

TextStyle _style(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

Widget _app({
  required FilterButton button,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(body: Center(child: button)),
  ),
);
