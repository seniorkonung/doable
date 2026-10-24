import 'package:doable/src/design_system/components/tag_chip.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме малый чип — фон bg с углами radius-xs, '
        'точка 7 и название caption цвета muted, а у выделенного — ink', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TagChip.small(name: 'Дом', color: DoableTagColor.blue),
              TagChip.small(name: 'Работа', color: null, strong: true),
            ],
          ),
        ),
      );

      final ground = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(TagChip).first,
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        ground.decoration,
        BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
        ),
      );
      final dots = tester.widgetList<TagDot>(find.byType(TagDot)).toList();
      expect([for (final dot in dots) dot.color], [DoableTagColor.blue, null]);
      expect(
        [for (final dot in dots) dot.size],
        [TagDotSize.small, TagDotSize.small],
      );

      final plain = _style(tester, 'Дом');
      expect(plain.color, colors.muted);
      expect(plain.fontSize, DoableType.caption.fontSize);
      expect(plain.fontWeight, DoableType.caption.fontWeight);
      expect(plain.height, DoableType.caption.height);
      expect(_style(tester, 'Работа').color, colors.ink);
    });
  }

  testWidgets('точка стоит в 7 от начала и в 5 перед названием, после '
      'названия остаётся 8, а высота — строка caption и по 1 сверху и снизу', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        child: const TagChip.small(name: 'Дом', color: DoableTagColor.teal),
      ),
    );

    final chip = tester.getRect(find.byType(TagChip));
    final dot = tester.getRect(find.byType(TagDot));
    final name = tester.getRect(find.text('Дом'));
    expect(dot.left - chip.left, 7);
    expect(name.left - dot.right, 5);
    expect(chip.right - name.right, DoableMetrics.space2);
    expect(chip.height, 20);
    expect(dot.center.dy, chip.center.dy);
  });

  testWidgets('при тексте масштаба 2 чип растёт по высоте, а длинное '
      'название в узком месте обрезается краем в одну строку', (tester) async {
    const name = 'Очень длинное название тега, которое не помещается';
    await tester.pumpWidget(
      _app(
        textScale: 2,
        child: const SizedBox(
          width: 120,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TagChip.small(name: name, color: DoableTagColor.pink),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(TagChip)), const Size(120, 38));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
    expect(paragraph.overflow, TextOverflow.clip);
    expect(paragraph.size.height, 36);
    expect(
      paragraph.getMaxIntrinsicWidth(double.infinity),
      greaterThan(paragraph.size.width),
    );
  });
}

TextStyle _style(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

Widget _app({
  required Widget child,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(body: Center(child: child)),
  ),
);
