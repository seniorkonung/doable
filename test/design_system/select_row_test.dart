import 'dart:ui' show CheckedState, Tristate;

import 'package:doable/src/design_system/components/select_row.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_shadows.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Перенос подписей и высота строк и пунктов зависят от метрик шрифта макета.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('Inter')..addFont(
          rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
        ))
        .load();
  });

  testWidgets('меню открывается над листом на 4 выше строки, выровнено по '
      'правому краю строки вместе с соседней кнопкой и отмечает выбранный '
      'вариант', (tester) async {
    final rows = _Rows();
    await _openSheet(tester, rows);
    final barriers = find.byType(ModalBarrier).evaluate().length;

    await tester.tap(find.text('Сортировка'));
    await tester.pumpAndSettle();

    final row = tester.getRect(_sortRow);
    final trailing = tester.getRect(_trailing);
    final panel = tester.getRect(_panel);
    expect(panel.bottom, row.top - 4);
    expect(panel.right, trailing.right);
    expect(panel.width, 228, reason: 'короткие пункты дают наименьшую ширину');
    expect(
      panel.top,
      lessThan(tester.getRect(find.text('Показать и упорядочить')).top),
      reason: 'меню стоит над шапкой листа, а не внутри его тела',
    );
    expect(
      find.byType(ModalBarrier).evaluate().length,
      barriers,
      reason: 'меню не добавляет затемнения',
    );

    final colors = DoableColors.light;
    final decoration =
        tester.widget<DecoratedBox>(_panel).decoration as BoxDecoration;
    expect(decoration.color, colors.raised);
    expect(decoration.borderRadius, BorderRadius.circular(20));
    expect(decoration.boxShadow, DoableShadows.light.shadowFloat);

    for (final (index, name) in [
      'Дата создания',
      'Дата изменения',
      'Название',
    ].indexed) {
      final item = tester.getRect(_itemOf(name));
      expect(item.height, 48);
      expect(item.left, panel.left + 6);
      expect(item.right, panel.right - 6);
      expect(item.top, panel.top + 6 + index * 48);
    }
    expect(
      find.descendant(
        of: _itemOf('Дата изменения'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DoableIcon && widget.icon == DoableIconData.check,
        ),
      ),
      findsOneWidget,
      reason: 'галочка только у выбранного варианта',
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is DoableIcon && widget.icon == DoableIconData.check,
      ),
      findsOneWidget,
    );
  });

  testWidgets('длинные названия переносятся, а меню не шире строки вместе с '
      'соседней кнопкой', (tester) async {
    final rows = _Rows(
      kinds: const [
        SelectRowItem(value: _Kind.all, label: 'Всё', count: '15'),
        SelectRowItem(
          value: _Kind.intentions,
          label: 'Только намерения, включая отложенные на неопределённый срок',
          count: '12',
        ),
        SelectRowItem(
          value: _Kind.actions,
          label: 'Только действия',
          count: '3',
        ),
      ],
    );
    await _openSheet(tester, rows, screen: const Size(320, 700));

    await tester.tap(find.text('Тип'));
    await tester.pumpAndSettle();

    final row = tester.getRect(_kindRow);
    final panel = tester.getRect(_panel);
    expect(panel.width, row.width - 8, reason: 'строка без внешних отступов');
    expect(panel.right, row.right - 4);
    expect(panel.bottom, row.top - 4);
    final long = tester.getRect(
      _itemOf('Только намерения, включая отложенные на неопределённый срок'),
    );
    expect(long.height, greaterThan(48));
    _expectInside(
      tester,
      find.text('Только намерения, включая отложенные на неопределённый срок'),
      long,
    );
    _expectInside(tester, find.text('12'), long);
    expect(
      tester
          .getRect(
            find.text(
              'Только намерения, включая отложенные на неопределённый срок',
            ),
          )
          .right,
      lessThan(tester.getRect(find.text('12')).left),
    );
  });

  testWidgets('при двукратном жирном системном тексте строки и пункты растут, '
      'а текст виден целиком и меню стоит над строкой', (tester) async {
    final rows = _Rows(
      kinds: const [
        SelectRowItem(value: _Kind.all, label: 'Всё', count: '15'),
        SelectRowItem(
          value: _Kind.intentions,
          label: 'Только намерения',
          count: '12',
        ),
        SelectRowItem(
          value: _Kind.actions,
          label: 'Только действия',
          count: '3',
        ),
      ],
      kind: _Kind.intentions,
    );
    await _openSheet(
      tester,
      rows,
      screen: const Size(320, 700),
      textScale: 2,
      boldText: true,
    );

    final row = tester.getRect(_kindButton);
    expect(row.height, greaterThan(52));
    final label = tester.getRect(
      find.descendant(of: _kindButton, matching: find.text('Тип')),
    );
    final value = tester.getRect(
      find.descendant(of: _kindButton, matching: find.text('Только намерения')),
    );
    _expectInside(tester, find.text('Тип'), row);
    _expectInside(
      tester,
      find.descendant(of: _kindButton, matching: find.text('Только намерения')),
      row,
    );
    expect(label.right, lessThan(value.left));
    expect(
      value.height,
      greaterThan(label.height),
      reason: 'выбранное значение переносится',
    );

    await tester.tap(find.text('Тип'));
    await tester.pumpAndSettle();

    final panel = tester.getRect(_panel);
    expect(panel.bottom, tester.getRect(_kindRow).top - 4);
    for (final (name, count) in [
      ('Всё', '15'),
      ('Только намерения', '12'),
      ('Только действия', '3'),
    ]) {
      final item = tester.getRect(_itemOf(name));
      expect(item.height, greaterThan(48));
      final itemName = find.descendant(
        of: _itemOf(name),
        matching: find.text(name),
      );
      _expectInside(tester, itemName, item);
      _expectInside(tester, find.text(count), item);
      expect(
        tester.getRect(itemName).right,
        lessThan(tester.getRect(find.text(count)).left),
      );
    }
    expect(tester.getRect(_itemOf('Только действия')).bottom, panel.bottom - 6);
  });

  testWidgets('открытое меню следует новым свойствам строки', (tester) async {
    final rows = _Rows(
      kinds: const [
        SelectRowItem(value: _Kind.all, label: 'Всё'),
        SelectRowItem(value: _Kind.intentions, label: 'Только намерения'),
        SelectRowItem(value: _Kind.actions, label: 'Только действия'),
      ],
    );
    await _openSheet(tester, rows);
    await tester.tap(find.text('Тип'));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsNothing);

    rows.kinds.value = const [
      SelectRowItem(value: _Kind.all, label: 'Всё', count: '3'),
      SelectRowItem(
        value: _Kind.intentions,
        label: 'Только намерения без готовности к действию',
        count: '2',
      ),
      SelectRowItem(value: _Kind.actions, label: 'Только действия', count: '1'),
    ];
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    final panel = tester.getRect(_panel);
    expect(panel.width, greaterThan(228));
    expect(panel.bottom, tester.getRect(_kindRow).top - 4);
    expect(panel.right, tester.getRect(_kindRow).right - 4);
  });

  testWidgets('выбор другого варианта закрывает меню и передаёт значение, а '
      'выбор текущего только закрывает меню', (tester) async {
    final rows = _Rows();
    await _openSheet(tester, rows);

    await tester.tap(find.text('Сортировка'));
    await tester.pumpAndSettle();
    expect(rows.opened, 1);
    await tester.tap(_itemOf('Дата изменения'));
    await tester.pumpAndSettle();

    expect(_panel, findsNothing);
    expect(rows.picked, isEmpty);

    await tester.tap(find.text('Сортировка'));
    await tester.pumpAndSettle();
    await tester.tap(_itemOf('Название'));
    await tester.pumpAndSettle();

    expect(_panel, findsNothing);
    expect(rows.picked, [_Field.name]);
    expect(find.text('Показать и упорядочить'), findsOneWidget);
  });

  testWidgets('касание вне меню только закрывает его: соседняя кнопка и '
      'затемнение листа не срабатывают', (tester) async {
    final rows = _Rows();
    await _openSheet(tester, rows);

    await tester.tap(find.text('Сортировка'));
    await tester.pumpAndSettle();
    await tester.tap(_trailing);
    await tester.pumpAndSettle();

    expect(_panel, findsNothing);
    expect(rows.trailingPresses, 0);
    expect(rows.picked, isEmpty);

    await tester.tap(find.text('Тип'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();

    expect(_panel, findsNothing);
    expect(find.text('Показать и упорядочить'), findsOneWidget);

    await tester.tap(_trailing);
    await tester.pump();
    expect(rows.trailingPresses, 1, reason: 'без меню кнопка работает');
  });

  testWidgets('системное «назад» закрывает сначала меню, а затем лист', (
    tester,
  ) async {
    final rows = _Rows();
    await _openSheet(tester, rows);
    await tester.tap(find.text('Тип'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(_panel, findsNothing);
    expect(find.text('Показать и упорядочить'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Показать и упорядочить'), findsNothing);
  });

  testWidgets('строка объявляется кнопкой меню с названием и значением, а '
      'пункты — взаимоисключающими вариантами с количеством', (tester) async {
    final semantics = tester.ensureSemantics();
    final rows = _Rows();
    await _openSheet(tester, rows);

    expect(
      tester.getSemantics(_kindButton),
      isSemantics(
        label: 'Тип',
        value: 'Всё',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasExpandedState: true,
        isExpanded: false,
        hasTapAction: true,
        isFocusable: true,
      ),
    );

    await tester.tap(find.text('Тип'));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(_kindButton).flagsCollection.isExpanded,
      Tristate.isTrue,
    );
    expect(
      find.bySemanticsLabel('Тип'),
      findsNWidgets(2),
      reason: 'меню называется названием строки',
    );
    for (final (name, count, checked) in [
      ('Всё', '15', true),
      ('Только намерения', '12', false),
      ('Только действия', '3', false),
    ]) {
      final item = tester.getSemantics(_itemOf(name)).getSemanticsData();
      expect(item.role, SemanticsRole.menuItemRadio);
      expect(item.label, '$name\n$count');
      final flags = item.flagsCollection;
      expect(
        flags.isChecked,
        checked ? CheckedState.isTrue : CheckedState.isFalse,
      );
      expect(flags.isInMutuallyExclusiveGroup, isTrue);
    }
    semantics.dispose();
  });

  testWidgets('закреплённое значение показано без меню, а пояснение объявлено '
      'вместе с недоступной строкой', (tester) async {
    final semantics = tester.ensureSemantics();
    final colors = DoableColors.light;
    await _openSheet(tester, _Rows(fixed: true));

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DoableIcon && widget.icon == DoableIconData.selector,
      ),
      findsOneWidget,
      reason: 'селектор остаётся только у доступной строки',
    );
    expect(
      tester.widget<Text>(find.text('Только действия')).style!.color,
      colors.muted,
    );
    expect(
      tester.getSemantics(find.text('Только действия')),
      isSemantics(
        label: 'Тип',
        value: 'Только действия',
        hint: 'Выбор из действия начинается только с действий.',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );

    await tester.tap(find.text('Только действия'));
    await tester.pumpAndSettle();

    expect(_panel, findsNothing);
    final note = tester.getRect(
      find.text('Выбор из действия начинается только с действий.'),
    );
    expect(note.top, greaterThan(tester.getRect(find.text('Тип')).bottom));
    expect(note.bottom, tester.getRect(_sortRow).top - 12);
    semantics.dispose();
  });
}

enum _Kind { all, intentions, actions }

enum _Field { created, changed, name }

/// Свойства строк листа, которые тест меняет и наблюдает.
final class _Rows {
  _Rows({
    List<SelectRowItem<_Kind>> kinds = const [
      SelectRowItem(value: _Kind.all, label: 'Всё', count: '15'),
      SelectRowItem(
        value: _Kind.intentions,
        label: 'Только намерения',
        count: '12',
      ),
      SelectRowItem(value: _Kind.actions, label: 'Только действия', count: '3'),
    ],
    _Kind kind = _Kind.all,
    this.fixed = false,
  }) : kinds = ValueNotifier(kinds),
       kind = ValueNotifier(kind);

  final ValueNotifier<List<SelectRowItem<_Kind>>> kinds;
  final ValueNotifier<_Kind> kind;
  final bool fixed;
  final picked = <_Field>[];
  var opened = 0;
  var trailingPresses = 0;
  final kindMenu = MenuController();
  final sortMenu = MenuController();
}

Future<void> _openSheet(
  WidgetTester tester,
  _Rows rows, {
  Size screen = const Size(390, 844),
  double textScale = 1,
  bool boldText = false,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = screen;
  tester.platformDispatcher
    ..textScaleFactorTestValue = textScale
    ..accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      boldText: boldText,
    );
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  await tester.pumpWidget(
    MaterialApp(
      theme: doableTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDoableSheet<void>(
                context: context,
                builder: (context, sheet) => Sheet(
                  sheet,
                  title: 'Показать и упорядочить',
                  text: 'Список меняется по мере выбора',
                  child: ListenableBuilder(
                    listenable: Listenable.merge([rows.kinds, rows.kind]),
                    builder: (context, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (rows.fixed)
                          SelectRow<_Kind>.disabled(
                            key: _kindKey,
                            label: 'Тип',
                            value: 'Только действия',
                            note:
                                'Выбор из действия начинается только с '
                                'действий.',
                          )
                        else
                          SelectRow(
                            key: _kindKey,
                            label: 'Тип',
                            items: rows.kinds.value,
                            value: rows.kind.value,
                            onChanged: (kind) => rows.kind.value = kind,
                            controller: rows.kindMenu,
                          ),
                        SelectRow(
                          key: _sortKey,
                          label: 'Сортировка',
                          items: const [
                            SelectRowItem(
                              value: _Field.created,
                              label: 'Дата создания',
                            ),
                            SelectRowItem(
                              value: _Field.changed,
                              label: 'Дата изменения',
                            ),
                            SelectRowItem(
                              value: _Field.name,
                              label: 'Название',
                            ),
                          ],
                          value: _Field.changed,
                          onChanged: rows.picked.add,
                          controller: rows.sortMenu,
                          onOpen: () => rows.opened++,
                          trailing: SizedBox.square(
                            key: _trailingKey,
                            dimension: 44,
                            child: IconButton(
                              onPressed: () => rows.trailingPresses++,
                              tooltip: 'Порядок',
                              icon: DoableIcon(
                                DoableIconData.sortDesc,
                                size: 20,
                                color: DoableColors.light.ink,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
}

/// Проверяет, что прямоугольник [finder] целиком лежит в [bounds].
void _expectInside(WidgetTester tester, Finder finder, Rect bounds) {
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(bounds.left), reason: '$finder');
  expect(rect.top, greaterThanOrEqualTo(bounds.top), reason: '$finder');
  expect(rect.right, lessThanOrEqualTo(bounds.right), reason: '$finder');
  expect(rect.bottom, lessThanOrEqualTo(bounds.bottom), reason: '$finder');
}

const _kindKey = ValueKey('тип');
const _sortKey = ValueKey('сортировка');
const _trailingKey = ValueKey('порядок');
final _kindRow = find.byKey(_kindKey);
final _sortRow = find.byKey(_sortKey);
final _trailing = find.byKey(_trailingKey);

/// Кнопка строки типа: название и значение.
final _kindButton = find
    .ancestor(of: find.text('Тип'), matching: find.byType(InkWell))
    .first;

/// Плоскость меню: в отличие от листа, она скруглена со всех сторон.
final _panel = find.byWidgetPredicate(
  (widget) =>
      widget is DecoratedBox &&
      widget.decoration is BoxDecoration &&
      (widget.decoration as BoxDecoration).boxShadow != null &&
      (widget.decoration as BoxDecoration).borderRadius ==
          BorderRadius.circular(20),
);

Finder _itemOf(String name) => find.ancestor(
  of: find.descendant(
    of: find.byType(MenuItemButton),
    matching: find.text(name),
  ),
  matching: find.byType(MenuItemButton),
);
