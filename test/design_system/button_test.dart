import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме основная кнопка — плашка ink с текстом bg на всю ширину', (
      tester,
    ) async {
      final colors = switch (brightness) {
        Brightness.light => DoableColors.light,
        Brightness.dark => DoableColors.dark,
      };

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          button: Button.primary(label: 'Готово', onPressed: () {}),
        ),
      );

      final plane = tester.getRect(_plane);
      expect(plane.height, DoableMetrics.controlHeight);
      expect(plane.width, 360);
      expect(_planeMaterial(tester).color, colors.ink);
      expect(_planeMaterial(tester).shape, const StadiumBorder());
      expect(
        tester.getSize(find.byType(Button)).height,
        greaterThanOrEqualTo(DoableMetrics.tapMin),
        reason: 'область нажатия выше плашки',
      );

      final style = _labelStyle(tester, 'Готово');
      expect(style.color, colors.bg);
      expect(style.fontSize, DoableType.section.fontSize);
      expect(style.fontWeight, DoableType.section.fontWeight);
      expect(tester.getCenter(find.text('Готово')), plane.center);
    });
  }

  testWidgets('нажатие по области выше плашки передаётся потребителю', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _app(
        button: Button.primary(label: 'Готово', onPressed: () => presses++),
      ),
    );

    final area = tester.getRect(find.byType(Button));
    final plane = tester.getRect(_plane);
    expect(area.top, lessThan(plane.top));
    await tester.tapAt(Offset(area.center.dx, area.top + 1));
    expect(presses, 1);
  });

  testWidgets('выключенная кнопка остаётся на месте плашкой fill с текстом '
      'grip и объявляется недоступной', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        button: Button.primary(label: 'Создать тег', onPressed: () {}),
      ),
    );
    final enabledPlane = tester.getRect(_plane);

    await tester.pumpWidget(
      _app(button: const Button.primary(label: 'Создать тег', onPressed: null)),
    );
    // Material меняет цвета кнопки с анимацией.
    await tester.pumpAndSettle();

    expect(tester.getRect(_plane), enabledPlane);
    expect(_planeMaterial(tester).color, DoableColors.light.fill);
    expect(_labelStyle(tester, 'Создать тег').color, DoableColors.light.grip);
    expect(
      tester.getSemantics(find.text('Создать тег')),
      matchesSemantics(
        label: 'Создать тег',
        isButton: true,
        hasEnabledState: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('с крупным шрифтом плашка растёт вместе с текстом', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        textScale: 2,
        button: Button.primary(label: 'Готово', onPressed: () {}),
      ),
    );

    final plane = tester.getRect(_plane);
    final label = tester.getRect(find.text('Готово'));
    expect(plane.height, greaterThan(DoableMetrics.controlHeight));
    expect(plane.top, lessThan(label.top));
    expect(plane.bottom, greaterThan(label.bottom));
  });
}

final _plane = find.descendant(
  of: find.byType(Button),
  matching: find.byType(Material),
);

Material _planeMaterial(WidgetTester tester) => tester.widget<Material>(_plane);

TextStyle _labelStyle(WidgetTester tester, String label) =>
    tester.renderObject<RenderParagraph>(find.text(label)).text.style!;

Widget _app({
  required Button button,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 360, child: button),
      ),
    ),
  ),
);
