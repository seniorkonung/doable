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

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light ? 'светлой' : 'тёмной';
    final colors = switch (brightness) {
      Brightness.light => DoableColors.light,
      Brightness.dark => DoableColors.dark,
    };

    for (final (kind, look, label, build, background, foreground) in [
      (
        'тихая',
        'плашка fill с текстом ink',
        'Отмена',
        (VoidCallback? onPressed) =>
            Button.quiet(label: 'Отмена', onPressed: onPressed),
        colors.fill,
        colors.ink,
      ),
      (
        'разрушительная',
        'плашка accent с текстом on-accent',
        'Удалить',
        (VoidCallback? onPressed) =>
            Button.danger(label: 'Удалить', onPressed: onPressed),
        colors.accent,
        colors.onAccent,
      ),
    ]) {
      testWidgets('в $theme теме $kind кнопка — $look шириной по подписи', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(brightness: brightness, button: build(() {}), block: false),
        );

        final plane = tester.getRect(_plane);
        final text = tester.getRect(find.text(label));
        expect(plane.height, DoableMetrics.controlHeight);
        expect(plane.width, text.width + 2 * DoableMetrics.space4);
        expect(_planeMaterial(tester).color, background);
        expect(_planeMaterial(tester).shape, const StadiumBorder());
        expect(
          tester.getSize(find.byType(Button)).height,
          greaterThanOrEqualTo(DoableMetrics.tapMin),
          reason: 'область нажатия выше плашки',
        );

        final style = _labelStyle(tester, label);
        expect(style.color, foreground);
        expect(style.fontSize, DoableType.section.fontSize);
        expect(style.fontWeight, DoableType.section.fontWeight);
        expect(tester.getCenter(find.text(label)), plane.center);
      });

      testWidgets('в $theme теме выключенная $kind кнопка остаётся на месте '
          'плашкой fill с текстом grip и объявляется недоступной', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(brightness: brightness, button: build(() {}), block: false),
        );
        final enabledPlane = tester.getRect(_plane);

        await tester.pumpWidget(
          _app(brightness: brightness, button: build(null), block: false),
        );
        // Material меняет цвета кнопки с анимацией.
        await tester.pumpAndSettle();

        expect(tester.getRect(_plane), enabledPlane);
        expect(_planeMaterial(tester).color, colors.fill);
        expect(_labelStyle(tester, label).color, colors.grip);
        expect(
          tester.getSemantics(find.text(label)),
          matchesSemantics(label: label, isButton: true, hasEnabledState: true),
        );
        semantics.dispose();
      });
    }
  }

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light ? 'светлой' : 'тёмной';
    final colors = switch (brightness) {
      Brightness.light => DoableColors.light,
      Brightness.dark => DoableColors.dark,
    };

    testWidgets('в $theme теме текстовая кнопка — текст accent без плашки '
        'размера sm с областью нажатия не меньше tap-min', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          button: Button.text(
            label: 'Сбросить',
            semanticLabel: 'Сбросить условия',
            onPressed: () {},
          ),
          block: false,
        ),
      );

      final pill = tester.getRect(_plane);
      final text = tester.getRect(find.text('Сбросить'));
      expect(pill.height, DoableMetrics.controlHeightSm);
      expect(pill.width, text.width + 2 * DoableMetrics.space2);
      expect(_planeMaterial(tester).color, Colors.transparent);
      expect(
        tester.getSize(find.byType(Button)).height,
        greaterThanOrEqualTo(DoableMetrics.tapMin),
        reason: 'область нажатия выше подписи',
      );

      final style = _labelStyle(tester, 'Сбросить');
      expect(style.color, colors.accent);
      expect(style.fontSize, DoableType.section.fontSize);
      expect(style.fontWeight, DoableType.section.fontWeight);
      expect(tester.getCenter(find.text('Сбросить')), pill.center);
      expect(
        tester.getSemantics(find.byType(Button)),
        matchesSemantics(
          label: 'Сбросить условия',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('в $theme теме выключенная текстовая кнопка остаётся на месте '
        'с текстом grip и объявляется недоступной', (tester) async {
      final semantics = tester.ensureSemantics();
      Button build(VoidCallback? onPressed) => Button.text(
        label: 'Сбросить',
        semanticLabel: 'Сбросить условия',
        onPressed: onPressed,
      );
      await tester.pumpWidget(
        _app(brightness: brightness, button: build(() {}), block: false),
      );
      final enabledPill = tester.getRect(_plane);

      await tester.pumpWidget(
        _app(brightness: brightness, button: build(null), block: false),
      );
      // Material меняет цвета кнопки с анимацией.
      await tester.pumpAndSettle();

      expect(tester.getRect(_plane), enabledPill);
      expect(_planeMaterial(tester).color, Colors.transparent);
      expect(_labelStyle(tester, 'Сбросить').color, colors.grip);
      expect(
        tester.getSemantics(find.byType(Button)),
        matchesSemantics(
          label: 'Сбросить условия',
          isButton: true,
          hasEnabledState: true,
        ),
      );
      semantics.dispose();
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

TextStyle _labelStyle(WidgetTester tester, String label) => tester
    .renderObject<RenderParagraph>(
      find.descendant(of: find.text(label), matching: find.byType(RichText)),
    )
    .text
    .style!;

/// С [block] кнопка стоит в контейнере шириной 360, без него — свободно.
Widget _app({
  required Button button,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool block = true,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: block ? SizedBox(width: 360, child: button) : button,
      ),
    ),
  ),
);
