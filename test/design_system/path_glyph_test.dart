import 'package:doable/src/design_system/components/path_glyph.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой теме', Brightness.light, DoableColors.light),
    ('тёмной теме', Brightness.dark, DoableColors.dark),
  ]) {
    for (final size in [12.0, 14.0]) {
      // Глиф рисуется на сетке 14 макета.
      final scale = size / 14;

      group('в $themeName на размере ${size.toInt()}', () {
        testWidgets('пунктирный ромб — обводка 1,5 штрихами 2,4 через 2 '
            'со скруглёнными углами по контуру ромба', (tester) async {
          await tester.pumpWidget(
            _app(
              brightness,
              PathGlyph(
                shape: PathGlyphShape.diamond,
                outline: PathGlyphOutline.dashed,
                size: size,
                color: colors.accent,
              ),
            ),
          );

          final glyph = find.byType(PathGlyph);
          expect(tester.getSize(glyph), Size.square(size));
          final (path, paint) = _drawnPath(tester, glyph);
          expect(paint.color, isSameColorAs(colors.accent));
          expect(paint.style, PaintingStyle.stroke);
          expect(paint.strokeWidth, closeTo(1.5 * scale, 1e-6));
          expect(paint.strokeJoin, StrokeJoin.round);
          final dashes = path.computeMetrics().toList();
          // Периметр 4 · 5,75√2 ≈ 32,5 вмещает восемь штрихов.
          expect(dashes, hasLength(8));
          for (final dash in dashes.take(7)) {
            expect(dash.length, closeTo(2.4 * scale, 1e-3));
          }
          expect(
            dashes.first.getTangentForOffset(0)!.position,
            _near(const Offset(7, 1.25) * scale),
          );
          for (final dash in dashes) {
            final point = dash.getTangentForOffset(dash.length / 2)!.position;
            final grid = point / scale;
            // Точки ромба: |x − 7| + |y − 7| = 5,75.
            expect(
              (grid.dx - 7).abs() + (grid.dy - 7).abs(),
              closeTo(5.75, 1e-3),
            );
          }
        });

        testWidgets('пунктирное кольцо — радиус 5,25, обводка 1,5 штрихами '
            '2,2 через 2,2', (tester) async {
          await tester.pumpWidget(
            _app(
              brightness,
              PathGlyph(
                shape: PathGlyphShape.ring,
                outline: PathGlyphOutline.dashed,
                size: size,
                color: colors.grip,
              ),
            ),
          );

          final glyph = find.byType(PathGlyph);
          expect(tester.getSize(glyph), Size.square(size));
          final (path, paint) = _drawnPath(tester, glyph);
          expect(paint.color, isSameColorAs(colors.grip));
          expect(paint.style, PaintingStyle.stroke);
          expect(paint.strokeWidth, closeTo(1.5 * scale, 1e-6));
          final dashes = path.computeMetrics().toList();
          // Окружность 2π · 5,25 ≈ 33 вмещает восемь штрихов.
          expect(dashes, hasLength(8));
          for (final dash in dashes.take(7)) {
            expect(dash.length, closeTo(2.2 * scale, 1e-3));
          }
          for (final dash in dashes) {
            final point = dash.getTangentForOffset(dash.length / 2)!.position;
            expect(
              (point - const Offset(7, 7) * scale).distance,
              closeTo(5.25 * scale, 1e-2),
            );
          }
        });

        testWidgets('сплошной ромб — заполненный квадрат 9,5 со скруглением '
            '1,5, повёрнутый на 45°', (tester) async {
          await tester.pumpWidget(
            _app(
              brightness,
              PathGlyph(
                shape: PathGlyphShape.diamond,
                outline: PathGlyphOutline.solid,
                size: size,
                color: colors.grip,
              ),
            ),
          );

          final glyph = find.byType(PathGlyph);
          expect(tester.getSize(glyph), Size.square(size));
          // Вершина ромба со скруглением 1,5 отстоит от центра на
          // 9,5/√2 − 1,5(√2 − 1) ≈ 6,1, сторона — на 4,75.
          expect(
            tester.renderObject(glyph),
            paints..path(
              color: colors.grip,
              style: PaintingStyle.fill,
              includes: [
                for (final point in const [
                  Offset(7, 7),
                  Offset(7, 1.1),
                  Offset(12.9, 7),
                  Offset(7, 12.9),
                  Offset(1.1, 7),
                ])
                  point * scale,
              ],
              excludes: [
                for (final point in const [
                  Offset(7, 0.7),
                  Offset(13.3, 7),
                  Offset(7, 13.3),
                  Offset(0.7, 7),
                  Offset(3.4, 3.4),
                  Offset(10.6, 10.6),
                ])
                  point * scale,
              ],
            ),
          );
        });

        testWidgets('сплошное кольцо — диаметр 10 с обводкой 1,5 внутрь', (
          tester,
        ) async {
          await tester.pumpWidget(
            _app(
              brightness,
              PathGlyph(
                shape: PathGlyphShape.ring,
                outline: PathGlyphOutline.solid,
                size: size,
                color: colors.accent,
              ),
            ),
          );

          final glyph = find.byType(PathGlyph);
          expect(tester.getSize(glyph), Size.square(size));
          late Offset center;
          late double radius;
          late Paint paint;
          expect(
            tester.renderObject(glyph),
            paints..something((method, arguments) {
              if (method != #drawCircle) return false;
              center = arguments[0] as Offset;
              radius = arguments[1] as double;
              paint = arguments[2] as Paint;
              return true;
            }),
          );
          expect(center, _near(const Offset(7, 7) * scale));
          expect(radius, closeTo(4.25 * scale, 1e-6));
          expect(paint.color, isSameColorAs(colors.accent));
          expect(paint.style, PaintingStyle.stroke);
          expect(paint.strokeWidth, closeTo(1.5 * scale, 1e-6));
        });
      });
    }
  }

  testWidgets('глиф не создаёт узла экранного диктора', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final shape in PathGlyphShape.values) {
      for (final outline in PathGlyphOutline.values) {
        await tester.pumpWidget(
          _app(
            Brightness.light,
            Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Исходное намерение',
              child: PathGlyph(
                shape: shape,
                outline: outline,
                size: 14,
                color: DoableColors.light.grip,
              ),
            ),
          ),
        );

        final node = tester.getSemantics(find.byType(PathGlyph));
        expect(node.label, 'Исходное намерение');
        expect(node.childrenCount, 0);
      }
    }
    semantics.dispose();
  });
}

Matcher _near(Offset expected) => isA<Offset>()
    .having((offset) => offset.dx, 'dx', closeTo(expected.dx, 1e-3))
    .having((offset) => offset.dy, 'dy', closeTo(expected.dy, 1e-3));

(Path, Paint) _drawnPath(WidgetTester tester, Finder finder) {
  late Path path;
  late Paint paint;
  expect(
    tester.renderObject(finder),
    paints..something((method, arguments) {
      if (method != #drawPath) return false;
      path = arguments[0] as Path;
      paint = arguments[1] as Paint;
      return true;
    }),
  );
  return (path, paint);
}

Widget _app(Brightness brightness, Widget child) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(body: Center(child: child)),
);
