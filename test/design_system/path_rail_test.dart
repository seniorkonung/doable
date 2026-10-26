import 'package:doable/src/design_system/components/path_glyph.dart';
import 'package:doable/src/design_system/components/path_rail.dart';
import 'package:doable/src/design_system/components/relation_stroke.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final colors = DoableColors.light;
  final need = RelationStrokeKind.need(colors.grip);
  final glyph = PathGlyph(
    shape: PathGlyphShape.diamond,
    outline: PathGlyphOutline.solid,
    size: 14,
    color: colors.grip,
  );

  testWidgets('колонка 22 слева, глиф против первой строки: сверху сегмент 17, '
      'глиф 14, снизу остаток высоты содержимого', (tester) async {
    await tester.pumpWidget(
      _app(
        PathRail(
          mark: PathRailMark.glyph(
            glyph,
            above: const RelationStrokeKind.undetermined(),
            below: need,
          ),
          child: const SizedBox(key: _content, height: 80),
        ),
      ),
    );

    final rail = tester.getRect(find.byType(PathRail));
    expect(rail.height, 80);
    expect(
      tester.getRect(find.byKey(_content)),
      Rect.fromLTRB(rail.left + 22, rail.top, rail.right, rail.bottom),
    );
    expect(
      tester.getRect(find.byType(PathGlyph)),
      Rect.fromLTWH(rail.left + 4, rail.top + 17, 14, 14),
    );
    final strokes = find.byType(RelationStroke);
    expect(strokes, findsNWidgets(2));
    expect(
      tester.widget<RelationStroke>(strokes.first).kind,
      const RelationStrokeKind.undetermined(),
    );
    expect(
      tester.getRect(strokes.first),
      Rect.fromLTWH(rail.left + 10, rail.top, 2, 17),
    );
    expect(tester.widget<RelationStroke>(strokes.last).kind, need);
    expect(
      tester.getRect(strokes.last),
      Rect.fromLTWH(rail.left + 10, rail.top + 31, 2, 80 - 31),
    );
    for (final stroke in strokes.evaluate()) {
      expect(
        (stroke.widget as RelationStroke).axis,
        RelationStrokeAxis.vertical,
      );
    }
  });

  testWidgets('у первой строки нет линии сверху, у последней — снизу, а глиф '
      'остаётся на месте', (tester) async {
    await tester.pumpWidget(
      _app(
        PathRail(
          mark: PathRailMark.glyph(glyph, below: need),
          child: const SizedBox(height: 48),
        ),
      ),
    );
    var rail = tester.getRect(find.byType(PathRail));
    expect(
      tester.getRect(find.byType(PathGlyph)),
      Rect.fromLTWH(rail.left + 4, rail.top + 17, 14, 14),
    );
    expect(
      tester.getRect(find.byType(RelationStroke)),
      Rect.fromLTWH(rail.left + 10, rail.top + 31, 2, 48 - 31),
    );

    await tester.pumpWidget(
      _app(
        PathRail(
          mark: PathRailMark.glyph(glyph, above: need),
          child: const SizedBox(height: 48),
        ),
      ),
    );
    rail = tester.getRect(find.byType(PathRail));
    expect(
      tester.getRect(find.byType(PathGlyph)),
      Rect.fromLTWH(rail.left + 4, rail.top + 17, 14, 14),
    );
    expect(
      tester.getRect(find.byType(RelationStroke)),
      Rect.fromLTWH(rail.left + 10, rail.top, 2, 17),
    );
  });

  testWidgets('строка без глифа — одна линия по центру колонки на всю высоту '
      'содержимого', (tester) async {
    await tester.pumpWidget(
      _app(
        PathRail(
          mark: PathRailMark.stroke(need),
          child: const SizedBox(height: 52),
        ),
      ),
    );

    final rail = tester.getRect(find.byType(PathRail));
    expect(rail.height, 52);
    expect(find.byType(PathGlyph), findsNothing);
    expect(
      tester.widget<RelationStroke>(find.byType(RelationStroke)).kind,
      need,
    );
    expect(
      tester.getRect(find.byType(RelationStroke)),
      Rect.fromLTWH(rail.left + 10, rail.top, 2, 52),
    );
  });

  testWidgets('текст масштаба 2 переносится, строка растёт по содержимому '
      'без переполнения', (tester) async {
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: PathRail(
            mark: PathRailMark.glyph(glyph, below: need),
            child: const Padding(
              padding: EdgeInsets.only(left: 10),
              child: Text(
                'Каждое утро делать зарядку и много ходить пешком по парку',
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final rail = tester.getRect(find.byType(PathRail));
    final text = tester.getRect(find.byType(Text));
    expect(text.left, rail.left + 22 + 10);
    expect(rail.height, text.height);
    expect(text.height, greaterThan(48));
    expect(
      tester.getRect(find.byType(RelationStroke)),
      Rect.fromLTWH(rail.left + 10, rail.top + 31, 2, rail.height - 31),
    );
  });

  testWidgets('экранный диктор слышит только содержимое строки', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        Semantics(
          container: true,
          explicitChildNodes: true,
          child: PathRail(
            mark: PathRailMark.glyph(glyph, above: need, below: need),
            child: Semantics(
              container: true,
              label: 'Исходное намерение',
              child: const SizedBox(height: 48),
            ),
          ),
        ),
      ),
    );

    final row = tester.getSemantics(find.byType(PathGlyph));
    expect(row.childrenCount, 1);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Исходное намерение')),
      isNot(row),
    );
    for (final stroke in find.byType(RelationStroke).evaluate()) {
      expect(tester.getSemantics(find.byWidget(stroke.widget)), row);
    }
    semantics.dispose();
  });
}

const _content = Key('содержимое');

Widget _app(Widget child) => MaterialApp(
  theme: doableTheme(Brightness.light),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: 320, child: child),
    ),
  ),
);
