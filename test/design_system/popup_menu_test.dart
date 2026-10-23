import 'package:doable/src/design_system/components/popup_menu.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_shadows.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Перенос названий и высота пунктов зависят от метрик шрифта макета.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('Inter')..addFont(
          rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
        ))
        .load();
  });

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light ? 'светлой' : 'тёмной';

    testWidgets('в $theme теме меню стоит на 4 под строкой у её содержимого, '
        'а плоскость и пункты следуют токенам', (tester) async {
      final colors = _colorsOf(brightness);
      final shadows = _shadowsOf(brightness);
      final menu = _Menu();
      _useScreen(tester);
      await tester.pumpWidget(menu.app(brightness: brightness, rowTop: 100));

      await menu.open(tester);

      final row = tester.getRect(_row);
      final panel = tester.getRect(_panel);
      expect(panel.width, 228);
      expect(panel.top, row.bottom + 4);
      expect(panel.left, row.left + _contentInset);
      expect(panel.height, 6 + 3 * 48 + 6);
      expect(
        find
            .byType(ModalBarrier)
            .evaluate()
            .map((element) => (element.widget as ModalBarrier).color),
        everyElement(anyOf(isNull, Colors.transparent)),
        reason: 'экран под меню не затемняется',
      );

      final decoration =
          tester.widget<DecoratedBox>(_panel).decoration as BoxDecoration;
      expect(decoration.color, colors.raised);
      expect(decoration.borderRadius, BorderRadius.circular(20));
      expect(decoration.boxShadow, shadows.shadowFloat);
      final border = decoration.border! as Border;
      expect(border.top.color, colors.hairline);
      expect(border.top.width, 1);
      expect(border.top.strokeAlign, BorderSide.strokeAlignOutside);

      for (final (index, name) in ['Изменить', 'Дублировать'].indexed) {
        final item = tester.getRect(_itemOf(name));
        expect(item.height, 48);
        expect(item.left, panel.left + 6);
        expect(item.right, panel.right - 6);
        expect(item.top, panel.top + 6 + index * 48);

        final icon = tester.widget<DoableIcon>(_iconOf(name));
        expect(icon.size, 22);
        expect(icon.color, colors.ink);
        final iconRect = tester.getRect(_iconOf(name));
        expect(iconRect.left - item.left, DoableMetrics.space3);
        expect(iconRect.center.dy, item.center.dy);

        final text = tester.widget<Text>(find.text(name));
        expect(text.style!.fontSize, DoableType.action.fontSize);
        expect(text.style!.fontWeight, DoableType.action.fontWeight);
        expect(text.style!.color, colors.ink);
        expect(
          tester.getRect(find.text(name)).left - iconRect.right,
          DoableMetrics.space3,
        );
      }
    });

    testWidgets('в $theme теме разрушительный пункт стоит последним и '
        'окрашен danger', (tester) async {
      final colors = _colorsOf(brightness);
      final menu = _Menu();
      _useScreen(tester);
      await tester.pumpWidget(menu.app(brightness: brightness, rowTop: 100));

      await menu.open(tester);

      final last = tester.getRect(_itemOf('Удалить'));
      expect(last.bottom, tester.getRect(_panel).bottom - 6);
      expect(
        tester.widget<DoableIcon>(_iconOf('Удалить')).color,
        colors.danger,
      );
      expect(
        tester.widget<Text>(find.text('Удалить')).style!.color,
        colors.danger,
      );
    });

    testWidgets('в $theme теме без места снизу меню стоит на 4 над строкой', (
      tester,
    ) async {
      final menu = _Menu();
      _useScreen(tester);
      // Под строкой остаётся меньше высоты меню и поля Material в 8.
      await tester.pumpWidget(
        menu.app(brightness: brightness, rowTop: _screen.height - 48 - 160),
      );

      await menu.open(tester);

      final row = tester.getRect(_row);
      final panel = tester.getRect(_panel);
      expect(panel.bottom, row.top - 4);
      expect(panel.left, row.left + _contentInset);
    });
  }

  testWidgets('над строкой меню встаёт и при нижнем системном отступе, '
      'который не оставляет места под строкой', (tester) async {
    final menu = _Menu();
    _useScreen(tester, bottomPadding: 48);
    await tester.pumpWidget(menu.app(rowTop: _screen.height - 48 - 200));

    await menu.open(tester);

    expect(tester.getRect(_panel).bottom, tester.getRect(_row).top - 4);
  });

  testWidgets('крупный шрифт переносит название и растит пункт, а меню '
      'учитывает рост, выбирая место над строкой', (tester) async {
    final menu = _Menu();
    _useScreen(tester, textScale: 2);
    await tester.pumpWidget(menu.app(rowTop: _screen.height - 48 - 220));

    await menu.open(tester);

    final duplicate = tester.getRect(_itemOf('Дублировать'));
    expect(duplicate.height, greaterThan(48));
    final panel = tester.getRect(_panel);
    expect(panel.bottom, tester.getRect(_row).top - 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('системный жирный шрифт переносит название, которое без '
      'жирности помещается в строку, и меню встаёт над строкой', (
    tester,
  ) async {
    final menu = _Menu();
    // При кегле 1,5 «Дублировать» без жирности помещается в строку пункта,
    // а жирным переносится.
    _useScreen(tester, textScale: 1.5, boldText: true);
    // Под строкой помещается меню с названиями в одну строку, но не меню
    // с перенесённым названием.
    await tester.pumpWidget(menu.app(rowTop: _screen.height - 48 - 210));

    await menu.open(tester);

    expect(
      tester.getSize(find.text('Дублировать')).height,
      greaterThan(tester.getSize(find.text('Изменить')).height),
      reason: 'жирное название переносится',
    );
    expect(tester.getRect(_panel).bottom, tester.getRect(_row).top - 4);
  });

  testWidgets('меню следует за строкой, которую опускает скрытая после '
      'открытия меню клавиатура', (tester) async {
    final menu = _Menu();
    _useScreen(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pumpWidget(menu.appAboveKeyboard(rowBottom: 300));
    await menu.open(tester);
    final raised = tester.getRect(_row);
    expect(tester.getRect(_panel).top, raised.bottom + 4);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    final row = tester.getRect(_row);
    expect(row.top, greaterThan(raised.top), reason: 'строка опустилась');
    final panel = tester.getRect(_panel);
    expect(panel.top, row.bottom + 4);
    expect(panel.left, row.left + _contentInset);
  });

  testWidgets('выбор пункта закрывает меню и возвращает его значение', (
    tester,
  ) async {
    final menu = _Menu();
    _useScreen(tester);
    await tester.pumpWidget(menu.app(rowTop: 100));
    await menu.open(tester);

    await tester.tap(find.text('Дублировать'));
    await tester.pumpAndSettle();

    expect(_panel, findsNothing);
    expect(menu.result, completion(_Action.duplicate));
  });

  testWidgets('касание вне меню закрывает только меню без выбора', (
    tester,
  ) async {
    final menu = _Menu();
    _useScreen(tester);
    await tester.pumpWidget(menu.app(rowTop: 100));
    await menu.open(tester);

    await tester.tapAt(const Offset(350, 600));
    await tester.pumpAndSettle();

    expect(_panel, findsNothing);
    expect(_row, findsOneWidget);
    expect(menu.result, completion(isNull));
  });

  testWidgets('системное «назад» закрывает только меню без выбора', (
    tester,
  ) async {
    final menu = _Menu();
    _useScreen(tester);
    await tester.pumpWidget(menu.app(rowTop: 100));
    await menu.open(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(_panel, findsNothing);
    expect(_row, findsOneWidget);
    expect(menu.result, completion(isNull));
  });

  testWidgets('меню называет строку, а пункты — свои действия', (tester) async {
    final semantics = tester.ensureSemantics();
    final menu = _Menu();
    _useScreen(tester);
    await tester.pumpWidget(menu.app(rowTop: 100));
    await menu.open(tester);

    expect(
      find.bySemanticsLabel('Тег: спорт'),
      findsOneWidget,
      reason: 'меню объявляет себя названием строки',
    );
    for (final name in ['Изменить', 'Дублировать', 'Удалить']) {
      expect(
        tester.getSemantics(_itemOf(name)),
        isSemantics(
          label: name,
          role: SemanticsRole.menuItem,
          isButton: true,
          hasTapAction: true,
        ),
      );
    }
    semantics.dispose();
  });
}

enum _Action { edit, duplicate, delete }

const _contentInset = 40.0;
const _screen = Size(390, 844);

/// Строка, у которой открывается меню, и результат его показа.
final class _Menu {
  late BuildContext _rowContext;
  late Future<_Action?> result;

  /// Страница со строкой на [rowTop] от верха экрана.
  Widget app({
    required double rowTop,
    Brightness brightness = Brightness.light,
  }) => _page(
    brightness: brightness,
    row: (row) => Positioned(top: rowTop, left: 12, right: 12, child: row),
  );

  /// Страница со строкой на [rowBottom] над клавиатурой: тело страницы
  /// сжимается её отступом.
  Widget appAboveKeyboard({required double rowBottom}) => _page(
    brightness: Brightness.light,
    row: (row) =>
        Positioned(bottom: rowBottom, left: 12, right: 12, child: row),
  );

  Widget _page({
    required Brightness brightness,
    required Widget Function(Widget row) row,
  }) => MaterialApp(
    theme: doableTheme(brightness),
    home: Scaffold(
      body: Stack(
        children: [
          row(
            Builder(
              builder: (context) {
                _rowContext = context;
                return const SizedBox(key: _rowKey, height: 48);
              },
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    result = showPopupMenu(
      row: _rowContext,
      contentInset: _contentInset,
      label: 'Тег: спорт',
      actions: const [
        PopupMenuAction(
          value: _Action.edit,
          icon: DoableIconData.edit,
          name: 'Изменить',
        ),
        PopupMenuAction(
          value: _Action.duplicate,
          icon: DoableIconData.copy,
          name: 'Дублировать',
        ),
      ],
      destructive: const PopupMenuAction(
        value: _Action.delete,
        icon: DoableIconData.delete,
        name: 'Удалить',
      ),
    );
    await tester.pumpAndSettle();
  }
}

const _rowKey = ValueKey('строка');
final _row = find.byKey(_rowKey);

final _panel = find.byWidgetPredicate(
  (widget) =>
      widget is DecoratedBox &&
      widget.decoration is BoxDecoration &&
      (widget.decoration as BoxDecoration).boxShadow != null,
);

Finder _itemOf(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(InkWell));

Finder _iconOf(String name) =>
    find.descendant(of: _itemOf(name), matching: find.byType(DoableIcon));

/// Экран телефона из макета; [bottomPadding] — нижний системный отступ,
/// [textScale] и [boldText] — системные масштаб и жирность текста.
void _useScreen(
  WidgetTester tester, {
  double bottomPadding = 0,
  double textScale = 1,
  bool boldText = false,
}) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _screen
    ..padding = FakeViewPadding(bottom: bottomPadding);
  tester.platformDispatcher
    ..textScaleFactorTestValue = textScale
    ..accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      boldText: boldText,
    );
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

DoableColors _colorsOf(Brightness brightness) => switch (brightness) {
  Brightness.light => DoableColors.light,
  Brightness.dark => DoableColors.dark,
};

DoableShadows _shadowsOf(Brightness brightness) => switch (brightness) {
  Brightness.light => DoableShadows.light,
  Brightness.dark => DoableShadows.dark,
};
