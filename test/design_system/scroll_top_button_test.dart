import 'dart:typed_data' show ByteData;
import 'dart:ui' show ImageByteFormat;

import 'package:doable/src/design_system/components/scroll_top_button.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_shadows.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    final themeName = brightness == Brightness.light ? 'светлой' : 'тёмной';
    final colors = switch (brightness) {
      Brightness.light => DoableColors.light,
      Brightness.dark => DoableColors.dark,
    };
    final shadows = switch (brightness) {
      Brightness.light => DoableShadows.light,
      Brightness.dark => DoableShadows.dark,
    };

    testWidgets('в $themeName теме кнопка — круг 44 цвета raised с обводкой '
        'hairline, тенью shadow-float и стрелкой 20 цвета ink по центру', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(_app(brightness: brightness, boundary: boundary));

      final button = tester.getRect(find.byType(ScrollTopButton));
      expect(button.size, const Size.square(44));
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byType(ScrollTopButton),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as ShapeDecoration;
      expect(decoration.color, colors.raised);
      expect(
        decoration.shape,
        CircleBorder(side: BorderSide(color: colors.hairline)),
      );
      expect(decoration.shadows, shadows.shadowFloat);
      final arrow = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(arrow.icon, DoableIconData.toTop);
      expect(arrow.color, colors.ink);
      expect(tester.getSize(find.byType(DoableIcon)), const Size.square(20));
      expect(tester.getCenter(find.byType(DoableIcon)), button.center);

      // Точка круга между обводкой и стрелкой: поле сплошь `raised`.
      final pixels = await _capture(tester, boundary);
      final origin = tester.getTopLeft(find.byKey(boundary));
      expect(
        pixels.at(
          (button.center.dx - origin.dx).round(),
          (button.top - origin.dy).round() + 8,
        ),
        isSameColorAs(colors.raised),
      );
    });
  }

  testWidgets('кнопка не показывает текста, а название и команда нажатия '
      'принадлежат одному узлу диктора', (tester) async {
    final semantics = tester.ensureSemantics();
    var presses = 0;
    await tester.pumpWidget(_app(onPressed: () => presses++));

    expect(find.byType(Text), findsNothing);
    final node = tester.getSemantics(find.bySemanticsLabel(_label));
    expect(
      node,
      matchesSemantics(
        label: _label,
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(node.childrenCount, 0);

    node.owner!.performAction(node.id, SemanticsAction.tap);
    expect(presses, 1);
    semantics.dispose();
  });

  testWidgets('касание по кругу вызывает команду потребителя', (tester) async {
    var presses = 0;
    await tester.pumpWidget(_app(onPressed: () => presses++));

    await tester.tap(find.byType(ScrollTopButton));

    expect(presses, 1);
  });

  testWidgets('название потребителя заменяет прежнее', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    expect(find.bySemanticsLabel(_label), findsOneWidget);

    await tester.pumpWidget(_app(label: 'Наверх'));

    expect(find.bySemanticsLabel(_label), findsNothing);
    expect(find.bySemanticsLabel('Наверх'), findsOneWidget);
    semantics.dispose();
  });
}

const _label = 'К началу списка';

Widget _app({
  Brightness brightness = Brightness.light,
  String label = _label,
  VoidCallback? onPressed,
  GlobalKey? boundary,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: Center(
      child: RepaintBoundary(
        key: boundary,
        child: ColoredBox(
          color: switch (brightness) {
            Brightness.light => DoableColors.light.bg,
            Brightness.dark => DoableColors.dark.bg,
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ScrollTopButton(label: label, onPressed: onPressed ?? () {}),
          ),
        ),
      ),
    ),
  ),
);

final class _Pixels {
  _Pixels(this._bytes, this._width);

  final ByteData _bytes;
  final int _width;

  Color at(int x, int y) {
    final index = (y * _width + x) * 4;
    return Color.fromARGB(
      _bytes.getUint8(index + 3),
      _bytes.getUint8(index),
      _bytes.getUint8(index + 1),
      _bytes.getUint8(index + 2),
    );
  }
}

/// Снимок границы перерисовки в логических пикселях: тест идёт при
/// коэффициенте пикселей 1.
Future<_Pixels> _capture(WidgetTester tester, GlobalKey boundary) async {
  final render = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundary),
  );
  return (await tester.runAsync(() async {
    final image = await render.toImage();
    try {
      final bytes = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
      return _Pixels(bytes, image.width);
    } finally {
      image.dispose();
    }
  }))!;
}
