import 'dart:typed_data' show ByteData;
import 'dart:ui' show ImageByteFormat;

import 'package:doable/src/design_system/components/choice_check.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме p1–p3 рисуют кольцо цвета приоритета с его '
        'тоном 12% внутри, а p4 — кольцо без тона', (tester) async {
      for (final (priority, color) in [
        (DoablePriority.p1, colors.p1),
        (DoablePriority.p2, colors.p2),
        (DoablePriority.p3, colors.p3),
        (DoablePriority.p4, colors.p4),
      ]) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          _app(brightness, ChoiceCheck(priority: priority), boundary),
        );

        final pixels = await _capture(tester, boundary);
        // Точка на кольце шириной 2 по диагонали левого верхнего угла.
        expect(pixels.at(3, 4), isSameColorAs(color));
        expect(
          pixels.at(11, 11),
          isSameColorAs(
            priority == DoablePriority.p4
                ? colors.bg
                : Color.alphaBlend(color.withValues(alpha: .12), colors.bg),
          ),
        );
      }
    });

    testWidgets('в $themeName теме выполненный выбор — кольцо и заливка grip '
        'с галочкой 12 цвета fill, приоритет не виден', (tester) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _app(
          brightness,
          const ChoiceCheck(priority: DoablePriority.p1, done: true),
          boundary,
        ),
      );

      final pixels = await _capture(tester, boundary);
      expect(pixels.at(3, 4), isSameColorAs(colors.grip));
      // Точка внутри кольца левее галочки.
      expect(pixels.at(4, 11), isSameColorAs(colors.grip));
      final check = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(check.icon, DoableIconData.check);
      expect(check.size, 12);
      expect(check.color, colors.fill);
    });
  }

  testWidgets('кольцо занимает 22 на 22 в обоих состояниях', (tester) async {
    for (final done in [false, true]) {
      await tester.pumpWidget(
        _app(
          Brightness.light,
          ChoiceCheck(priority: DoablePriority.p2, done: done),
          GlobalKey(),
        ),
      );

      expect(tester.getSize(find.byType(ChoiceCheck)), const Size.square(22));
    }
  });

  testWidgets('метка не создаёт узла экранного диктора и не нажимается', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Brightness.light,
        GestureDetector(
          onTap: () => taps++,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Выполнить',
            child: const ChoiceCheck(priority: DoablePriority.p1, done: true),
          ),
        ),
        GlobalKey(),
      ),
    );

    final node = tester.getSemantics(find.byType(ChoiceCheck));
    expect(node.label, 'Выполнить');
    expect(node.childrenCount, 0);

    // Нажатие по метке достаётся охватывающей области, а не самой метке.
    await tester.tap(find.byType(ChoiceCheck));
    expect(taps, 1);
    semantics.dispose();
  });
}

Widget _app(Brightness brightness, Widget child, GlobalKey boundary) =>
    MaterialApp(
      theme: doableTheme(brightness),
      home: Scaffold(
        body: RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: switch (brightness) {
              Brightness.light => DoableColors.light.bg,
              Brightness.dark => DoableColors.dark.bg,
            },
            child: Align(alignment: Alignment.topLeft, child: child),
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
