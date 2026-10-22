import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/components/tag_row.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме строка, точка, название и галочка следуют токенам', (
      tester,
    ) async {
      final colors = switch (brightness) {
        Brightness.light => DoableColors.light,
        Brightness.dark => DoableColors.dark,
      };

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          row: TagRow(
            name: 'Работа',
            color: DoableTagColor.blue,
            mark: TagRowMark.checked,
            label: 'Работа',
            onPressed: () {},
          ),
        ),
      );

      final row = tester.getRect(find.byType(TagRow));
      expect(row.height, 48);
      expect(
        tester.widget<Material>(_material).color,
        Colors.transparent,
        reason: 'у строки нет своего фона',
      );
      expect(
        tester.widget<InkWell>(find.byType(InkWell)).borderRadius,
        BorderRadius.circular(DoableMetrics.radiusSm),
      );

      final dot = tester.widget<TagDot>(find.byType(TagDot));
      expect(dot.size, TagDotSize.large);
      expect(dot.color, DoableTagColor.blue);
      final dotRect = tester.getRect(find.byType(TagDot));
      expect(dotRect.left - row.left, DoableMetrics.space3);
      expect(dotRect.center.dy, row.center.dy);

      final name = tester.getRect(find.text('Работа'));
      expect(name.left - dotRect.right, DoableMetrics.space3);
      final style = tester.widget<Text>(find.text('Работа')).style!;
      expect(style.fontSize, DoableType.action.fontSize);
      expect(style.fontWeight, DoableType.action.fontWeight);
      expect(style.color, colors.ink);

      final tick = tester.widget<DoableIcon>(_tick);
      expect(tick.size, 20);
      expect(tick.color, colors.accent);
      final tickRect = tester.getRect(_tick);
      expect(row.right - tickRect.right, DoableMetrics.space3);
      expect(tickRect.left - name.right, DoableMetrics.space3);
    });
  }

  testWidgets('длинное название переносится целиком, а строка растёт', (
    tester,
  ) async {
    const name =
        'Подготовка к ежегодной встрече выпускников и поиск подарков '
        'для всех однокурсников';
    await tester.pumpWidget(
      _app(
        width: 240,
        row: TagRow(
          name: name,
          color: DoableTagColor.green,
          mark: TagRowMark.checked,
          label: name,
          onPressed: () {},
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.getSize(find.text(name)).height, greaterThan(22 * 2));
    expect(tester.getSize(find.byType(TagRow)).height, greaterThan(48));
  });

  testWidgets('тег без цвета показан кольцом точки', (tester) async {
    await tester.pumpWidget(
      _app(
        row: TagRow(
          name: 'Разное',
          color: null,
          mark: TagRowMark.none,
          label: 'Разное',
          onPressed: () {},
        ),
      ),
    );

    final dot = tester.widget<TagDot>(find.byType(TagDot));
    expect(dot.color, isNull);
    expect(dot.size, TagDotSize.large);
  });

  testWidgets('отметка видна галочкой и объявляется состоянием строки, '
      'а нажатие передаётся потребителю', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;

    await tester.pumpWidget(
      _app(
        row: TagRow(
          name: 'Работа',
          color: DoableTagColor.blue,
          mark: TagRowMark.none,
          label: 'Работа',
          onPressed: () => taps++,
        ),
      ),
    );
    expect(_tick, findsNothing);
    expect(
      tester.getSemantics(find.byType(TagRow)),
      matchesSemantics(
        label: 'Работа',
        hasCheckedState: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );

    await tester.tap(find.byType(TagRow));
    expect(taps, 1);

    await tester.pumpWidget(
      _app(
        row: TagRow(
          name: 'Работа',
          color: DoableTagColor.blue,
          mark: TagRowMark.checked,
          label: 'Работа',
          onPressed: () => taps++,
        ),
      ),
    );
    expect(_tick, findsOneWidget);
    expect(
      tester.getSemantics(find.byType(TagRow)),
      matchesSemantics(
        label: 'Работа',
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('недоступная строка не принимает нажатие и объявляет '
      'недоступность, сохраняя отметку', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        row: const TagRow(
          name: 'Работа',
          color: DoableTagColor.blue,
          mark: TagRowMark.checked,
          label: 'Работа',
          onPressed: null,
        ),
      ),
    );

    expect(_tick, findsOneWidget);
    expect(
      tester.getSemantics(find.byType(TagRow)),
      matchesSemantics(
        label: 'Работа',
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('строка — один узел экранного диктора без отдельных точки '
      'и названия', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        row: TagRow(
          name: 'Работа',
          color: DoableTagColor.blue,
          mark: TagRowMark.none,
          label: 'Работа',
          onPressed: () {},
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(TagRow));
    expect(node.mergeAllDescendantsIntoThisNode, isTrue);
    expect(tester.getSemantics(find.byType(TagDot)), same(node));
    expect(tester.getSemantics(find.text('Работа')), same(node));
    semantics.dispose();
  });
}

final _material = find.descendant(
  of: find.byType(TagRow),
  matching: find.byType(Material),
);

final _tick = find.byWidgetPredicate(
  (widget) => widget is DoableIcon && widget.icon == DoableIconData.check,
);

Widget _app({
  required TagRow row,
  Brightness brightness = Brightness.light,
  double width = 360,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: width, child: row),
    ),
  ),
);
