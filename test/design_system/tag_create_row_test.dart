import 'package:doable/src/design_system/components/tag_create_row.dart';
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
        'теме строка, плюс и текст следуют токенам', (tester) async {
      final colors = switch (brightness) {
        Brightness.light => DoableColors.light,
        Brightness.dark => DoableColors.dark,
      };

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          row: TagCreateRow(
            text: 'Создать тег «Спорт»',
            label: 'Создать тег «Спорт»',
            onPressed: () {},
          ),
        ),
      );

      final row = tester.getRect(find.byType(TagCreateRow));
      expect(row.height, 48);
      expect(
        tester.widget<InkWell>(find.byType(InkWell)).borderRadius,
        BorderRadius.circular(DoableMetrics.radiusSm),
      );

      final plus = tester.widget<DoableIcon>(_plus);
      expect(plus.size, 18);
      expect(plus.color, colors.accent);
      final plusRect = tester.getRect(_plus);
      expect(plusRect.left - row.left, DoableMetrics.space4);
      expect(plusRect.center.dy, row.center.dy);

      final text = tester.getRect(find.text('Создать тег «Спорт»'));
      expect(text.left - plusRect.right, 10);
      final style = tester
          .widget<Text>(find.text('Создать тег «Спорт»'))
          .style!;
      expect(style.fontSize, DoableType.action.fontSize);
      expect(style.fontWeight, DoableType.action.fontWeight);
      expect(style.letterSpacing, DoableType.action.letterSpacing);
      expect(style.color, colors.accent);
    });
  }

  testWidgets('длинный текст переносится целиком, а строка растёт', (
    tester,
  ) async {
    const text =
        'Создать тег «Подготовка к ежегодной встрече выпускников и поиск '
        'подарков для всех однокурсников»';
    await tester.pumpWidget(
      _app(
        width: 240,
        row: TagCreateRow(text: text, label: text, onPressed: () {}),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.getSize(find.text(text)).height, greaterThan(22 * 2));
    expect(tester.getSize(find.byType(TagCreateRow)).height, greaterThan(48));
  });

  testWidgets('строка — одна кнопка с названием потребителя, '
      'а нажатие передаётся ему', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;

    await tester.pumpWidget(
      _app(
        row: TagCreateRow(
          text: 'Создать тег «Спорт»',
          label: 'Создать тег Спорт',
          onPressed: () => taps++,
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(TagCreateRow));
    expect(
      node,
      matchesSemantics(
        label: 'Создать тег Спорт',
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    expect(tester.getSemantics(find.text('Создать тег «Спорт»')), same(node));

    await tester.tap(find.byType(TagCreateRow));
    expect(taps, 1);
    semantics.dispose();
  });
}

final _plus = find.byWidgetPredicate(
  (widget) => widget is DoableIcon && widget.icon == DoableIconData.plusSmall,
);

Widget _app({
  required TagCreateRow row,
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
