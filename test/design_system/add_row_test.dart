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

    testWidgets('в $themeName теме строка с подсказкой высотой tap-min: '
        'подсказка hint цвета muted в space-1 от края, справа «Добавить» '
        'как в строке с заголовком', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          child: _hintRow(onAdd: () {}),
        ),
      );

      final row = tester.getRect(find.byType(AddRow));
      final hint = tester.getRect(find.text(_hint));
      final word = tester.getRect(find.text('Добавить'));
      final plus = tester.getRect(find.byType(DoableIcon));
      final add = tester.getRect(find.byKey(_addKey));
      expect(row.height, DoableMetrics.tapMin);
      expect(hint.left - row.left, DoableMetrics.space1);
      expect(hint.center.dy, row.center.dy);
      expect(add, Rect.fromLTRB(add.left, row.top, row.right + 6, row.bottom));
      expect(row.right - word.right, DoableMetrics.space1);
      expect(plus.left - add.left, 6);

      final hintStyle = _style(tester, _hint);
      expect(hintStyle.color, colors.muted);
      expect(hintStyle.fontSize, DoableType.hint.fontSize);
      expect(hintStyle.fontWeight, DoableType.hint.fontWeight);
      expect(hintStyle.height, DoableType.hint.height);
      final wordStyle = _style(tester, 'Добавить');
      expect(wordStyle.color, colors.accent);
      expect(wordStyle.fontSize, DoableType.section.fontSize);
      expect(wordStyle.fontWeight, DoableType.section.fontWeight);
      expect(
        tester.widget<DoableIcon>(find.byType(DoableIcon)).color,
        colors.accent,
      );
    });

    testWidgets('в $themeName теме строка без «Добавить» не показывает и не '
        'объявляет его, а подсказка занимает строку', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          child: AddRow.hintOnly(hint: _hint),
        ),
      );

      final row = tester.getRect(find.byType(AddRow));
      final paragraph = tester.renderObject<RenderParagraph>(find.text(_hint));
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(DoableIcon), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Добав')), findsNothing);
      expect(row.height, DoableMetrics.tapMin);
      expect(row.width, 800 - 2 * 16);
      expect(
        tester.getRect(find.text(_hint)).left - row.left,
        DoableMetrics.space1,
      );
      expect(paragraph.constraints.maxWidth, row.width - DoableMetrics.space1);
      expect(_style(tester, _hint).color, colors.muted);
      semantics.dispose();
    });

    testWidgets('в $themeName теме строка без подсказки держит одно '
        '«Добавить» у правого края', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          child: AddRow.addOnly(
            addText: 'Добавить',
            addLabel: 'Создать дневной выбор',
            onAdd: () {},
            addKey: _addKey,
          ),
        ),
      );

      final row = tester.getRect(find.byType(AddRow));
      final word = tester.getRect(find.text('Добавить'));
      final add = tester.getRect(find.byKey(_addKey));
      expect(find.byType(Text), findsOneWidget);
      expect(row.height, DoableMetrics.tapMin);
      expect(add, Rect.fromLTRB(add.left, row.top, row.right + 6, row.bottom));
      expect(row.right - word.right, DoableMetrics.space1);
      expect(_style(tester, 'Добавить').color, colors.accent);
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

  testWidgets('«Добавить» строки с подсказкой объявляет переданное доступное '
      'название, а нажатие по нему вызывает обработчик', (tester) async {
    final semantics = tester.ensureSemantics();
    var adds = 0;
    await tester.pumpWidget(_app(child: _hintRow(onAdd: () => adds++)));

    expect(
      tester.getSemantics(find.byKey(_addKey)),
      matchesSemantics(
        label: 'Создать дневной выбор',
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
    await tester.tap(find.text(_hint));
    expect(adds, 1);
    semantics.dispose();
  });

  testWidgets('при тексте масштаба 2 длинная подсказка переносится, строка '
      'растёт без переполнения, а «Добавить» остаётся у края', (tester) async {
    const hint =
        'Дневные выборы, которые начинаются с этого намерения, и ещё немного';
    await tester.pumpWidget(
      _app(
        textScale: 2,
        child: _hintRow(hint: hint, onAdd: () {}),
      ),
    );

    expect(tester.takeException(), isNull);
    final row = tester.getRect(find.byType(AddRow));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(hint));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.height, greaterThan(DoableMetrics.tapMin));
    expect(row.height, paragraph.size.height);
    expect(tester.getRect(find.byKey(_addKey)).right, row.right + 6);
  });

  testWidgets('при тексте масштаба 2 длинная подсказка без «Добавить» '
      'переносится без переполнения', (tester) async {
    const hint =
        'Дневные выборы, которые начинаются с этого намерения, и ещё немного';
    await tester.pumpWidget(
      _app(textScale: 2, child: AddRow.hintOnly(hint: hint)),
    );

    expect(tester.takeException(), isNull);
    final row = tester.getRect(find.byType(AddRow));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(hint));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.height, greaterThan(DoableMetrics.tapMin));
    expect(row.height, paragraph.size.height);
  });
}

AddRow _row({required VoidCallback? onAdd, String title = 'Теги'}) => AddRow(
  title: title,
  addText: 'Добавить',
  addLabel: 'Добавить теги',
  onAdd: onAdd,
  addKey: _addKey,
);

const _hint = 'Дневные выборы, которые начинаются с этого намерения.';

AddRow _hintRow({required VoidCallback onAdd, String hint = _hint}) =>
    AddRow.hint(
      hint: hint,
      addText: 'Добавить',
      addLabel: 'Создать дневной выбор',
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
