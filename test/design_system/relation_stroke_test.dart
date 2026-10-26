import 'package:doable/src/design_system/components/relation_stroke.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('токены линий: нужно 2, можно 1,5, пунктир 5 через 5', () {
    expect(DoableMetrics.strokeNeed, 2);
    expect(DoableMetrics.strokeCan, 1.5);
    expect(DoableMetrics.strokeDash, 5);
    expect(DoableMetrics.strokeGap, 5);
  });

  test('помощник пунктира начинает каждый контур со штриха заданной длины '
      'и укорачивает последний', () {
    final line = dashPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(23, 0),
      dash: 5,
      gap: 5,
    );
    expect(_dashes(line).map((dash) => dash.length), _lengths([5, 5, 3]));
    expect(
      _dashes(line).map((dash) => dash.start),
      _points([Offset.zero, const Offset(10, 0), const Offset(20, 0)]),
    );

    final twoContours = dashPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(9, 0)
        ..moveTo(0, 10)
        ..lineTo(4, 10),
      dash: 3,
      gap: 1,
    );
    expect(
      _dashes(twoContours).map((dash) => dash.length),
      _lengths([3, 3, 1, 3]),
    );
    expect([_dashes(twoContours)[3].start], _points([const Offset(0, 10)]));
  });

  for (final (themeName, brightness, colors) in [
    ('светлой теме', Brightness.light, DoableColors.light),
    ('тёмной теме', Brightness.dark, DoableColors.dark),
  ]) {
    group('в $themeName', () {
      testWidgets('вертикальная линия «нужно» сплошная stroke-need цвета '
          'потребителя на всю высоту', (tester) async {
        await tester.pumpWidget(
          _rail(brightness, RelationStrokeKind.need(colors.grip)),
        );

        final stroke = find.byType(RelationStroke);
        expect(
          tester.getSize(stroke),
          const Size(DoableMetrics.strokeNeed, 40),
        );
        expect(
          tester.renderObject(stroke),
          paints..line(
            p1: const Offset(1, 0),
            p2: const Offset(1, 40),
            color: colors.grip,
            strokeWidth: DoableMetrics.strokeNeed,
          ),
        );
      });

      testWidgets('вертикальная линия «можно» — пунктир stroke-can 5 через 5 '
          'цвета потребителя', (tester) async {
        await tester.pumpWidget(
          _rail(brightness, RelationStrokeKind.can(colors.accent)),
        );

        final stroke = find.byType(RelationStroke);
        expect(tester.getSize(stroke), const Size(DoableMetrics.strokeCan, 40));
        final (path, paint) = _drawnPath(tester, stroke);
        expect(paint.color, isSameColorAs(colors.accent));
        expect(paint.style, PaintingStyle.stroke);
        expect(paint.strokeWidth, DoableMetrics.strokeCan);
        final dashes = _dashes(path);
        expect(dashes.map((dash) => dash.length), _lengths([5, 5, 5, 5]));
        expect(
          dashes.map((dash) => dash.start),
          _points([
            const Offset(0.75, 0),
            const Offset(0.75, 10),
            const Offset(0.75, 20),
            const Offset(0.75, 30),
          ]),
        );
        expect([dashes.last.end], _points([const Offset(0.75, 35)]));
      });

      testWidgets('вертикальная линия без вида — сплошная 2 цвета hairline '
          'темы', (tester) async {
        await tester.pumpWidget(
          _rail(brightness, const RelationStrokeKind.undetermined()),
        );

        final stroke = find.byType(RelationStroke);
        expect(tester.getSize(stroke), const Size(2, 40));
        expect(
          tester.renderObject(stroke),
          paints..line(
            p1: const Offset(1, 0),
            p2: const Offset(1, 40),
            color: colors.hairline,
            strokeWidth: 2,
          ),
        );
      });

      testWidgets('отметка вида 15 × 2: «нужно» сплошная stroke-need, '
          '«можно» пунктир stroke-can 3 через 3, без вида hairline', (
        tester,
      ) async {
        await tester.pumpWidget(
          _mark(brightness, RelationStrokeKind.need(colors.grip)),
        );
        final need = find.byType(RelationStroke);
        expect(
          tester.getSize(find.byType(RelationKindMark)),
          const Size(15, 2),
        );
        expect(
          tester.renderObject(need),
          paints..line(
            p1: const Offset(0, 1),
            p2: const Offset(15, 1),
            color: colors.grip,
            strokeWidth: DoableMetrics.strokeNeed,
          ),
        );

        await tester.pumpWidget(
          _mark(brightness, RelationStrokeKind.can(colors.grip)),
        );
        final (path, paint) = _drawnPath(tester, find.byType(RelationStroke));
        expect(paint.color, isSameColorAs(colors.grip));
        expect(paint.strokeWidth, DoableMetrics.strokeCan);
        final dashes = _dashes(path);
        expect(dashes.map((dash) => dash.length), _lengths([3, 3, 3]));
        expect(
          dashes.map((dash) => dash.start),
          _points([
            const Offset(0, 1),
            const Offset(6, 1),
            const Offset(12, 1),
          ]),
        );

        await tester.pumpWidget(
          _mark(brightness, const RelationStrokeKind.undetermined()),
        );
        expect(
          tester.renderObject(find.byType(RelationStroke)),
          paints..line(
            p1: const Offset(0, 1),
            p2: const Offset(15, 1),
            color: colors.hairline,
            strokeWidth: 2,
          ),
        );
      });
    });
  }

  testWidgets('линии и отметка вида не создают узлов экранного диктора', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final kind in [
      RelationStrokeKind.need(DoableColors.light.grip),
      RelationStrokeKind.can(DoableColors.light.grip),
      const RelationStrokeKind.undetermined(),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: doableTheme(Brightness.light),
          home: Scaffold(
            body: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Нужно',
              child: SizedBox(
                width: 22,
                height: 40,
                child: Row(
                  children: [
                    RelationKindMark(kind: kind),
                    Column(
                      children: [
                        Expanded(
                          child: RelationStroke(
                            kind: kind,
                            axis: RelationStrokeAxis.vertical,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(RelationKindMark));
      expect(node.label, 'Нужно');
      expect(node.childrenCount, 0);
      expect(
        tester.getSemantics(
          find.byWidgetPredicate(
            (widget) =>
                widget is RelationStroke &&
                widget.axis == RelationStrokeAxis.vertical,
          ),
        ),
        node,
      );
    }
    semantics.dispose();
  });
}

Matcher _lengths(List<double> expected) => pairwiseCompare(
  expected,
  (double expected, double actual) => (actual - expected).abs() < 1e-3,
  'длина около',
);

Matcher _points(List<Offset> expected) => pairwiseCompare(
  expected,
  (Offset expected, Offset actual) => (actual - expected).distance < 1e-3,
  'точка около',
);

typedef _Dash = ({double length, Offset start, Offset end});

List<_Dash> _dashes(Path path) => [
  for (final contour in path.computeMetrics())
    (
      length: contour.length,
      start: contour.getTangentForOffset(0)!.position,
      end: contour.getTangentForOffset(contour.length)!.position,
    ),
];

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

Widget _rail(Brightness brightness, RelationStrokeKind kind) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 22,
        height: 40,
        child: Column(
          children: [
            Expanded(
              child: RelationStroke(
                kind: kind,
                axis: RelationStrokeAxis.vertical,
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Widget _mark(Brightness brightness, RelationStrokeKind kind) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: Center(child: RelationKindMark(kind: kind)),
  ),
);
