import 'package:doable/src/design_system/components/add_row.dart';
import 'package:doable/src/design_system/components/tag_chip.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/components/tags_section.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _addKey = ValueKey('add');

void main() {
  testWidgets('блок передаёт строке заголовок, подписи, ключ и выключенность '
      '«Добавить»', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(child: _section(onAdd: null)));

    final row = find.byType(AddRow);
    expect(find.descendant(of: row, matching: find.text('Теги')), findsOne);
    expect(find.descendant(of: row, matching: find.text('Добавить')), findsOne);
    expect(
      tester.getSemantics(find.byKey(_addKey)),
      matchesSemantics(
        label: 'Добавить теги',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets('нажатие по ключу «Добавить» и по полосе за краем вызывает '
      'обработчик блока', (tester) async {
    var adds = 0;
    await tester.pumpWidget(
      _app(
        child: _section(onAdd: () => adds++, chips: [_chip('Дом')]),
      ),
    );

    await tester.tap(find.byKey(_addKey));
    expect(adds, 1);
    final row = tester.getRect(find.byType(AddRow));
    await tester.tapAt(Offset(row.right + 3, row.center.dy));
    expect(adds, 2);
  });

  testWidgets('без чипов блок состоит из одной шапки', (tester) async {
    await tester.pumpWidget(_app(child: _section(onAdd: () {})));

    expect(find.byType(Wrap), findsNothing);
    expect(
      tester.getRect(find.byType(TagsSection)),
      tester.getRect(find.byType(AddRow)),
    );
  });

  testWidgets('чипы стоят под шапкой и переносятся рядами с промежутком '
      'space-2 по обеим осям, а под последним рядом остаётся 6', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        width: 240,
        child: _section(
          onAdd: () {},
          chips: [_chip('Дом'), _chip('Сад'), _chip('Работа')],
        ),
      ),
    );

    final section = tester.getRect(find.byType(TagsSection));
    final header = tester.getRect(find.byType(AddRow));
    final chips = [
      for (final name in ['Дом', 'Сад', 'Работа'])
        tester.getRect(find.byKey(ValueKey(name))),
    ];
    expect(chips[0].topLeft, header.bottomLeft);
    expect(chips[1].left - chips[0].right, DoableMetrics.space2);
    expect(chips[1].top, chips[0].top);
    expect(chips[2].left, section.left);
    expect(chips[2].top - chips[0].bottom, DoableMetrics.space2);
    expect(section.bottom - chips[2].bottom, 6);
  });

  testWidgets('при тексте масштаба 2 шапка и чипы переносятся без '
      'переполнения', (tester) async {
    await tester.pumpWidget(
      _app(
        width: 320,
        textScale: 2,
        child: _section(
          onAdd: () {},
          chips: [_chip('Очень длинное название тега'), _chip('Дом')],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final section = tester.getRect(find.byType(TagsSection));
    final chip = tester.getRect(
      find.byKey(const ValueKey('Очень длинное название тега')),
    );
    expect(chip.width, lessThanOrEqualTo(section.width));
    expect(
      section.bottom - tester.getRect(find.byKey(const ValueKey('Дом'))).bottom,
      6,
    );
  });
}

TagsSection _section({
  required VoidCallback? onAdd,
  List<TagChip> chips = const [],
}) => TagsSection(
  title: 'Теги',
  addText: 'Добавить',
  addLabel: 'Добавить теги',
  onAdd: onAdd,
  addKey: _addKey,
  chips: chips,
);

TagChip _chip(String name) => TagChip.medium(
  name: name,
  color: DoableTagColor.blue,
  removeLabel: 'Убрать тег: $name',
  onRemove: () {},
  key: ValueKey(name),
);

/// Блок стоит в поле содержимого с отступами 16, как на странице.
Widget _app({
  required Widget child,
  double width = 320,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width + 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
        ),
      ),
    ),
  ),
);
