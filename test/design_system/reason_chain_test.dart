import 'dart:typed_data' show ByteData;
import 'dart:ui' show ImageByteFormat;

import 'package:doable/src/design_system/components/reason_chain.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Цепочка стоит в левом верхнем углу снимка, поэтому точки заданы в
// логических пикселях макета: ромб с центром в 5,75, первая линия от 9,5
// шириной 11, затем кольцо 7 и линия 10 на каждое промежуточное намерение.
void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме концы цепочки цвета приоритета, а линии и '
        'кольца — он же пополам с grip', (tester) async {
      for (final (priority, color) in [
        (DoablePriority.p1, colors.p1),
        (DoablePriority.p2, colors.p2),
        (DoablePriority.p3, colors.p3),
        (DoablePriority.p4, colors.p4),
      ]) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          _app(
            brightness,
            ReasonChain(reasons: 4, priority: priority),
            boundary,
          ),
        );

        final pixels = await _capture(tester, boundary);
        final mid = Color.lerp(color, colors.grip, .5)!;
        expect(pixels.at(5, 5), isSameColorAs(color), reason: 'ромб');
        expect(pixels.at(14, 5), isSameColorAs(mid), reason: 'первая линия');
        expect(pixels.at(21, 5), isSameColorAs(mid), reason: 'первое кольцо');
        expect(pixels.at(24, 5), isSameColorAs(colors.bg), reason: 'внутри');
        expect(pixels.at(32, 5), isSameColorAs(mid), reason: 'линия');
        expect(pixels.at(75, 5), isSameColorAs(color), reason: 'круг');
      }
    });

    testWidgets('в $themeName теме выполненная цепочка целиком grip', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _app(
          brightness,
          const ReasonChain(reasons: 4, priority: DoablePriority.p1, off: true),
          boundary,
        ),
      );

      final pixels = await _capture(tester, boundary);
      for (final (x, part) in [
        (5, 'ромб'),
        (14, 'линия'),
        (21, 'кольцо'),
        (75, 'круг'),
      ]) {
        expect(pixels.at(x, 5), isSameColorAs(colors.grip), reason: part);
      }
    });
  }

  testWidgets('до семи шагов цепочка рисуется целиком: кольцо на каждое '
      'промежуточное намерение', (tester) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      _app(
        Brightness.light,
        const ReasonChain(reasons: 7, priority: DoablePriority.p1),
        boundary,
      ),
    );

    final pixels = await _capture(tester, boundary);
    final mid = Color.lerp(DoableColors.light.p1, DoableColors.light.grip, .5)!;
    // Левый край k-го кольца: 20,5 + 17 · k; шесть колец, середина свободна.
    for (var ring = 0; ring < 6; ring++) {
      final left = 21 + 17 * ring;
      expect(pixels.at(left, 5), isSameColorAs(mid), reason: 'кольцо $ring');
      expect(
        pixels.at(left + 3, 5),
        isSameColorAs(DoableColors.light.bg),
        reason: 'середина кольца $ring',
      );
    }
  });

  testWidgets('от восьми шагов по три кольца остаются у концов, а середину '
      'занимает многоточие из трёх точек без линий', (tester) async {
    final colors = DoableColors.light;
    final mid = Color.lerp(colors.p1, colors.grip, .5)!;
    for (final reasons in [8, 12]) {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _app(
          Brightness.light,
          ReasonChain(reasons: reasons, priority: DoablePriority.p1),
          boundary,
        ),
      );

      final pixels = await _capture(tester, boundary);
      for (final left in [21, 38, 55, 85, 102, 119]) {
        expect(pixels.at(left, 5), isSameColorAs(mid), reason: 'кольцо $left');
      }
      // Три сплошные точки 3, между ними по 3 и по 4 до крайних колец.
      for (final center in [67, 73, 79]) {
        expect(pixels.at(center, 5), isSameColorAs(mid), reason: 'точка');
      }
      for (final gap in [63, 70, 76, 82]) {
        expect(pixels.at(gap, 5), isSameColorAs(colors.bg), reason: 'зазор');
      }
      expect(pixels.at(140, 5), isSameColorAs(colors.p1), reason: 'круг');
    }
  });

  testWidgets('высота цепочки 11, ширина растёт с шагами до семи и после '
      'восьмого постоянна', (tester) async {
    Future<Size> sizeOf(int reasons) async {
      await tester.pumpWidget(
        _app(
          Brightness.light,
          ReasonChain(reasons: reasons, priority: DoablePriority.p4),
          GlobalKey(),
        ),
      );
      return tester.getSize(find.byType(ReasonChain));
    }

    expect(await sizeOf(1), const Size(29.5, 11));
    expect(await sizeOf(4), const Size(80.5, 11));
    expect(await sizeOf(7), const Size(131.5, 11));
    expect(await sizeOf(8), const Size(144.5, 11));
    expect(await sizeOf(20), const Size(144.5, 11));
  });

  testWidgets('цепочка не создаёт узла экранного диктора', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        Brightness.light,
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Причин в цепочке: 4',
          child: const ReasonChain(reasons: 4, priority: DoablePriority.p2),
        ),
        GlobalKey(),
      ),
    );

    final node = tester.getSemantics(find.byType(ReasonChain));
    expect(node.label, 'Причин в цепочке: 4');
    expect(node.childrenCount, 0);
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
