import 'package:doable/src/design_system/components/add_row.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _addKey = ValueKey('add');

void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме строка высотой tap-min: заголовок row '
        'цвета ink в space-1 от края, справа «Добавить» section цвета accent '
        'с плюсом 18, а его область нажатия выходит на 6 за край', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          child: _row(onAdd: () {}),
        ),
      );

      final row = tester.getRect(find.byType(AddRow));
      final title = tester.getRect(find.text('Теги'));
      final word = tester.getRect(find.text('Добавить'));
      final plus = tester.getRect(find.byType(DoableIcon));
      final add = tester.getRect(find.byKey(_addKey));
      expect(row.height, DoableMetrics.tapMin);
      expect(title.left - row.left, DoableMetrics.space1);
      expect(title.center.dy, row.center.dy);
      expect(add, Rect.fromLTRB(add.left, row.top, row.right + 6, row.bottom));
      expect(row.right - word.right, DoableMetrics.space1);
      expect(word.left - plus.right, DoableMetrics.space1);
      expect(plus.left - add.left, 6);
      expect(plus.center.dy, row.center.dy);

      final titleStyle = _style(tester, 'Теги');
      expect(titleStyle.color, colors.ink);
      expect(titleStyle.fontSize, DoableType.row.fontSize);
      expect(titleStyle.fontWeight, DoableType.row.fontWeight);
      expect(titleStyle.height, DoableType.row.height);
      final wordStyle = _style(tester, 'Добавить');
      expect(wordStyle.color, colors.accent);
      expect(wordStyle.fontSize, DoableType.section.fontSize);
      expect(wordStyle.fontWeight, DoableType.section.fontWeight);
      expect(wordStyle.height, DoableType.section.height);
      final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(
        (icon.icon, icon.size, icon.color),
        (DoableIconData.plusSmall, 18.0, colors.accent),
      );
    });

    testWidgets('в $themeName теме выключенное «Добавить» окрашено grip, '
        'стоит на прежнем месте и объявляет недоступность', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          child: _row(onAdd: () {}),
        ),
      );
      final enabledAdd = tester.getRect(find.byKey(_addKey));
      final enabledWord = tester.getRect(find.text('Добавить'));

      await tester.pumpWidget(
        _app(brightness: brightness, child: _row(onAdd: null)),
      );
      // Кнопка плавно меняет цвет подписи при выключении.
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byKey(_addKey)), enabledAdd);
      expect(tester.getRect(find.text('Добавить')), enabledWord);
      expect(_style(tester, 'Добавить').color, colors.grip);
      expect(
        tester.widget<DoableIcon>(find.byType(DoableIcon)).color,
        colors.grip,
      );
      expect(
        tester.getSemantics(find.byKey(_addKey)),
        matchesSemantics(
          label: 'Добавить теги',
          isButton: true,
          hasEnabledState: true,
        ),
      );
      await tester.tap(find.byKey(_addKey), warnIfMissed: false);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('«Добавить» объявляет переданное доступное название, а нажатие '
      'по его ключу и по полосе за краем вызывает обработчик', (tester) async {
    final semantics = tester.ensureSemantics();
    var adds = 0;
    await tester.pumpWidget(_app(child: _row(onAdd: () => adds++)));

    expect(
      tester.getSemantics(find.byKey(_addKey)),
      matchesSemantics(
        label: 'Добавить теги',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(find.byKey(_addKey));
    expect(adds, 1);
    final row = tester.getRect(find.byType(AddRow));
    await tester.tapAt(Offset(row.right + 3, row.center.dy));
    expect(adds, 2);
    await tester.tap(find.text('Теги'));
    expect(adds, 2);
    semantics.dispose();
  });

  testWidgets('выключенное «Добавить» не вызывает обработчик, переданный '
      'строке после выключения', (tester) async {
    var adds = 0;
    await tester.pumpWidget(_app(child: _row(onAdd: () => adds++)));
    await tester.pumpWidget(_app(child: _row(onAdd: null)));

    await tester.tap(find.byKey(_addKey), warnIfMissed: false);
    expect(adds, 0);
  });

  testWidgets('при тексте масштаба 2 длинный заголовок переносится, строка '
      'растёт без переполнения, а «Добавить» остаётся у края', (tester) async {
    const title = 'Очень длинный заголовок строки, который не помещается';
    await tester.pumpWidget(
      _app(
        textScale: 2,
        child: _row(title: title, onAdd: () {}),
      ),
    );

    expect(tester.takeException(), isNull);
    final row = tester.getRect(find.byType(AddRow));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.height, greaterThan(40));
    expect(row.height, paragraph.size.height);
    expect(tester.getRect(find.byKey(_addKey)).right, row.right + 6);
  });
}

AddRow _row({required VoidCallback? onAdd, String title = 'Теги'}) => AddRow(
  title: title,
  addText: 'Добавить',
  addLabel: 'Добавить теги',
  onAdd: onAdd,
  addKey: _addKey,
);

TextStyle _style(WidgetTester tester, String text) => tester
    .renderObject<RenderParagraph>(
      find.descendant(
        of: find.text(text),
        matching: find.byType(RichText),
        matchRoot: true,
      ),
    )
    .text
    .style!;

/// Строка стоит прямо в поле содержимого с отступами 16, поэтому полоса
/// «Добавить» за краем лежит в границах родителя.
Widget _app({
  required Widget child,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: child,
        ),
      ),
    ),
  ),
);
