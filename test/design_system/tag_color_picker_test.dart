import 'package:doable/src/design_system/components/tag_color_picker.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('десять именованных кнопок образуют группу, '
      'выбор передаётся потребителю и повторное нажатие его не снимает', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    DoableTagColor? value;
    final changes = <DoableTagColor?>[];

    await tester.pumpWidget(
      _app(
        child: StatefulBuilder(
          builder: (context, setState) => TagColorPicker(
            value: value,
            label: 'Цвет',
            colorLabel: _colorLabel,
            groupLabel: 'Цвет тега',
            onChanged: (color) {
              changes.add(color);
              setState(() => value = color);
            },
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Цвет тега'), findsOneWidget);
    expect(_buttons, findsNWidgets(10));
    for (final color in [null, ...DoableTagColor.values]) {
      final node = tester.getSemantics(_button(_colorLabel(color)));
      expect(node.label, _colorLabel(color));
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(node.hasFlag(SemanticsFlag.hasSelectedState), isTrue);
      expect(node.hasFlag(SemanticsFlag.isSelected), color == null);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    }

    final blue = _button('Синий');
    // Нажатие у края ячейки, за пределами самого образца.
    await tester.tapAt(tester.getTopLeft(blue) + const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(changes, [DoableTagColor.blue]);
    expect(find.text('Синий'), findsOneWidget);
    expect(_selectedLabels(tester), ['Синий']);

    await tester.tap(blue);
    await tester.pumpAndSettle();
    expect(changes, [DoableTagColor.blue, DoableTagColor.blue]);
    expect(_selectedLabels(tester), ['Синий']);

    final none = tester.getSemantics(_button('Без цвета'));
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      none.id,
      SemanticsAction.tap,
    );
    await tester.pumpAndSettle();
    expect(changes.last, isNull);
    expect(find.text('Без цвета'), findsOneWidget);
    expect(_selectedLabels(tester), ['Без цвета']);
    semantics.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме образцы используют палитру, кольцо и галочку выбора', (
      tester,
    ) async {
      final colors = brightness == Brightness.light
          ? DoableColors.light
          : DoableColors.dark;

      for (final value in [null, DoableTagColor.blue]) {
        await tester.pumpWidget(
          _app(
            brightness: brightness,
            child: _picker(value: value),
          ),
        );
        await tester.pumpAndSettle();

        for (final color in [null, ...DoableTagColor.values]) {
          final pattern = paints;
          if (color == value) {
            pattern
              ..circle(color: colors.raised)
              ..circle(
                color: colors.ink,
                radius: 17,
                style: PaintingStyle.stroke,
                strokeWidth: 2,
              );
          }
          if (color == null) {
            pattern.circle(
              color: colors.grip,
              radius: 13,
              style: PaintingStyle.stroke,
              strokeWidth: 2,
            );
          } else {
            pattern.circle(color: colors[color.token], radius: 14);
          }
          final swatch = tester.renderObject(_button(_colorLabel(color)));
          expect(swatch, pattern);
          expect(
            swatch,
            paintsExactlyCountTimes(#drawCircle, color == value ? 3 : 1),
          );
        }
        final check = find.byType(DoableIcon);
        expect(check, findsOneWidget);
        final icon = tester.widget<DoableIcon>(check);
        expect(icon.icon, DoableIconData.check);
        expect(icon.color, value == null ? colors.ink : colors.bg);
        expect(tester.getSize(check), const Size.square(14));
      }
    });
  }

  testWidgets('образцы идут в порядке палитры в двух рядах по пять, '
      'вся ячейка имеет высоту не меньше tap-min', (tester) async {
    await tester.pumpWidget(_app(child: _picker()));

    final cells = [
      for (final color in [null, ...DoableTagColor.values])
        tester.getRect(_button(_colorLabel(color))),
    ];
    for (var i = 0; i < cells.length; i++) {
      expect(cells[i].height, greaterThanOrEqualTo(DoableMetrics.tapMin));
      expect(cells[i].width, greaterThanOrEqualTo(DoableMetrics.tapMin));
      expect(cells[i].top, cells[i < 5 ? 0 : 5].top);
      if (i % 5 > 0) {
        expect(cells[i].left, cells[i - 1].right);
      }
    }
    expect(cells[5].top, cells[0].bottom);
    expect(cells[5].left, cells[0].left);
  });

  testWidgets('при масштабе текста 2,5 обе подписи шапки переносятся '
      'без обрезания, а шапка растёт', (tester) async {
    await tester.pumpWidget(
      _app(
        textScale: 2.5,
        child: _picker(value: DoableTagColor.orange, label: 'Цвет тега'),
      ),
    );

    expect(tester.takeException(), isNull);
    final gridTop = tester.getTopLeft(_button('Без цвета')).dy;
    final pickerTop = tester.getTopLeft(find.byType(TagColorPicker)).dy;
    expect(gridTop - pickerTop, greaterThan(DoableMetrics.tapMin));
    for (final label in ['Цвет тега', 'Оранжевый']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        tester.getRect(find.text(label)).bottom,
        lessThanOrEqualTo(gridTop),
      );
    }
  });
}

Finder get _buttons => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.button == true,
);

Finder _button(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.button == true &&
      widget.properties.label == label,
);

List<String> _selectedLabels(WidgetTester tester) => [
  for (final color in [null, ...DoableTagColor.values])
    if (tester
        .getSemantics(_button(_colorLabel(color)))
        .hasFlag(SemanticsFlag.isSelected))
      _colorLabel(color),
];

TagColorPicker _picker({DoableTagColor? value, String label = 'Цвет'}) =>
    TagColorPicker(
      value: value,
      label: label,
      colorLabel: _colorLabel,
      groupLabel: 'Цвет тега',
      onChanged: (_) {},
    );

Widget _app({
  required Widget child,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Center(child: SizedBox(width: 300, child: child)),
    ),
  ),
);

String _colorLabel(DoableTagColor? color) => switch (color) {
  null => 'Без цвета',
  DoableTagColor.brown => 'Коричневый',
  DoableTagColor.orange => 'Оранжевый',
  DoableTagColor.olive => 'Оливковый',
  DoableTagColor.green => 'Зелёный',
  DoableTagColor.teal => 'Бирюзовый',
  DoableTagColor.blue => 'Синий',
  DoableTagColor.violet => 'Сиреневый',
  DoableTagColor.purple => 'Фиолетовый',
  DoableTagColor.pink => 'Розовый',
};
