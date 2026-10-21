import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('варианты цвета тега сопоставлены одноимённым токенам tag-* '
      'в порядке палитры', () {
    expect(
      [for (final color in DoableTagColor.values) color.token],
      DoableColorToken.values.where(
        (token) => token.tokenName.startsWith('tag-'),
      ),
    );
    for (final color in DoableTagColor.values) {
      expect(color.token.tokenName, 'tag-${color.name}');
    }
  });

  for (final (themeName, theme, colors) in [
    ('светлой теме', doableTheme(Brightness.light), DoableColors.light),
    ('тёмной теме', doableTheme(Brightness.dark), DoableColors.dark),
    (
      'тёмной теме без палитры Doable',
      ThemeData(brightness: Brightness.dark),
      DoableColors.dark,
    ),
  ]) {
    testWidgets('в $themeName цветная точка залита своим токеном, '
        'а «Без цвета» — кольцо grip без заливки', (tester) async {
      await tester.pumpWidget(
        _app(
          theme: theme,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TagDot(color: DoableTagColor.blue, size: TagDotSize.large),
              TagDot(color: null, size: TagDotSize.large),
            ],
          ),
        ),
      );

      final dots = find.byType(TagDot);
      final colored = tester.renderObject(dots.first);
      expect(
        colored,
        paints..circle(color: colors.tagBlue, style: PaintingStyle.fill),
      );
      expect(colored, paintsExactlyCountTimes(#drawCircle, 1));
      final ring = tester.renderObject(dots.last);
      expect(
        ring,
        paints..circle(
          color: colors.grip,
          style: PaintingStyle.stroke,
          strokeWidth: 1.5,
        ),
      );
      expect(ring, paintsExactlyCountTimes(#drawCircle, 1));
    });
  }

  testWidgets('точка занимает заданный размер 7, 8 или 10', (tester) async {
    for (final (size, diameter) in [
      (TagDotSize.small, 7.0),
      (TagDotSize.medium, 8.0),
      (TagDotSize.large, 10.0),
    ]) {
      await tester.pumpWidget(
        _app(
          theme: doableTheme(Brightness.light),
          child: TagDot(color: DoableTagColor.green, size: size),
        ),
      );

      expect(tester.getSize(find.byType(TagDot)), Size.square(diameter));
    }
  });

  testWidgets('точка не создаёт узла экранного диктора', (tester) async {
    final semantics = tester.ensureSemantics();

    for (final color in [DoableTagColor.pink, null]) {
      await tester.pumpWidget(
        _app(
          theme: doableTheme(Brightness.light),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Дом',
            child: TagDot(color: color, size: TagDotSize.small),
          ),
        ),
      );

      final node = tester.getSemantics(find.byType(TagDot));
      expect(node.label, 'Дом');
      expect(node.childrenCount, 0);
    }
    semantics.dispose();
  });
}

Widget _app({required ThemeData theme, required Widget child}) => MaterialApp(
  theme: theme,
  home: Scaffold(body: Center(child: child)),
);
