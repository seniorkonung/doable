import 'dart:ui' show ImageByteFormat;

import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/choice_check.dart';
import 'package:doable/src/design_system/components/choice_head.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _chainKey = ValueKey('chain');
const _checkKey = ValueKey('check');
const _optionsKey = ValueKey('options');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Inter')..addFont(
          rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
        ))
        .load();
  });

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме исходное намерение — caption muted, '
        'действие — headline ink, а у выполненного выбора оба зачёркнуты, '
        'действие muted, а галочка цвета листа', (tester) async {
      await tester.pumpWidget(
        _app(brightness, _head(goal: 'Цель', action: 'Действие')),
      );

      _expectStyle(
        _style(tester, 'Цель'),
        DoableType.caption.copyWith(color: colors.muted),
      );
      _expectStyle(
        _style(tester, 'Действие'),
        DoableType.headline.copyWith(color: colors.ink),
      );
      expect(
        _style(tester, 'Цель').decoration,
        isNot(TextDecoration.lineThrough),
      );
      expect(
        _style(tester, 'Действие').decoration,
        isNot(TextDecoration.lineThrough),
      );

      await tester.pumpWidget(
        _app(brightness, _head(goal: 'Цель', action: 'Действие', done: true)),
      );

      _expectStyle(
        _style(tester, 'Цель'),
        DoableType.caption.copyWith(color: colors.muted),
      );
      _expectStyle(
        _style(tester, 'Действие'),
        DoableType.headline.copyWith(color: colors.muted),
      );
      expect(_style(tester, 'Цель').decoration, TextDecoration.lineThrough);
      expect(_style(tester, 'Действие').decoration, TextDecoration.lineThrough);
      final check = tester.widget<ChoiceCheck>(find.byType(ChoiceCheck));
      expect(check.done, isTrue);
      expect(check.markColor, colors.raised);
    });
  }

  testWidgets('кольцо стоит у левого края шапки по центру её высоты, текст в '
      '34 от края, а цепочка отстоит на 2 от исходного намерения и на 5 от '
      'действия', (tester) async {
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _head(goal: 'Цель', action: 'Действие', priority: DoablePriority.p2),
      ),
    );

    final head = tester.getRect(find.byType(ChoiceHead));
    final mark = tester.getRect(find.byType(ChoiceCheck));
    final goal = tester.getRect(find.text('Цель'));
    final chain = tester.getRect(find.byKey(_chainKey));
    final action = tester.getRect(find.text('Действие'));
    expect(
      tester.widget<ChoiceCheck>(find.byType(ChoiceCheck)).priority,
      DoablePriority.p2,
    );
    expect(mark.size, const Size.square(22));
    expect(mark.left, head.left);
    expect(mark.center.dy, head.center.dy);
    expect(goal.left - head.left, 34);
    expect(chain.left, goal.left);
    expect(goal.top - head.top, 8);
    expect(chain.top - goal.bottom, 2);
    expect(action.top - chain.bottom, 5);
    expect(action.left, goal.left);
    expect(head.bottom - action.bottom, 10);
  });

  testWidgets('области кнопок выходят за края шапки и принимают там касания, '
      'а текст их не перехватывает', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _head(
          onToggle: () => calls.add('toggle'),
          options: ChoiceHeadOptions.available(
            label: 'Параметры',
            onOpen: () => calls.add('options'),
            buttonKey: _optionsKey,
          ),
          checkKey: _checkKey,
        ),
      ),
    );

    final head = tester.getRect(find.byType(ChoiceHead));
    final check = tester.getRect(find.byKey(_checkKey));
    final options = tester.getRect(find.byKey(_optionsKey));
    expect(check.width, 44);
    expect(check.top, head.top);
    expect(check.bottom, head.bottom);
    expect(check.left - head.left, -11);
    expect(options.size, const Size.square(44));
    expect(options.top, head.top);
    expect(options.right - head.right, 14);

    await tester.tapAt(Offset(head.left - 5, head.center.dy));
    await tester.pump();
    expect(calls, ['toggle']);
    // Угол области флажка далеко от кольца, но это тоже флажок.
    await tester.tapAt(head.topLeft + const Offset(30, 2));
    await tester.pump();
    expect(calls, ['toggle', 'toggle']);

    await tester.tapAt(Offset(head.right + 10, head.top + 18));
    await tester.pump();
    expect(calls, ['toggle', 'toggle', 'options']);

    // Против текста ни флажок, ни параметры не срабатывают.
    await tester.tap(find.text('Действие'));
    await tester.tapAt(head.topLeft + const Offset(36, 4));
    await tester.pump();
    expect(calls, ['toggle', 'toggle', 'options']);
  });

  testWidgets('без onToggle флажок не принимает нажатие, а раскладка не '
      'меняется', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(
      _app(Brightness.light, _head(onToggle: () => toggles++)),
    );
    final enabled = _layout(tester);

    await tester.pumpWidget(_app(Brightness.light, _head()));
    expect(_layout(tester), enabled);

    await tester.tap(find.byType(ChoiceCheck));
    await tester.pump();
    expect(toggles, 0);
  });

  testWidgets('кнопки параметров нет, пока потребитель её не задал: текст '
      'доходит до правого края шапки', (tester) async {
    await tester.pumpWidget(_app(Brightness.light, _head()));

    final head = tester.getRect(find.byType(ChoiceHead));
    expect(find.byType(DoableIcon), findsNothing);
    expect(tester.getRect(find.byType(Wrap).first).right, head.right);
  });

  testWidgets('кнопка параметров — три точки muted в квадрате tap-min у '
      'верхнего правого угла, а текст кончается до её области', (tester) async {
    final colors = DoableColors.light;
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _head(
          options: const ChoiceHeadOptions.available(
            label: 'Параметры',
            onOpen: _noop,
            buttonKey: _optionsKey,
          ),
        ),
      ),
    );

    final head = tester.getRect(find.byType(ChoiceHead));
    final options = tester.getRect(find.byKey(_optionsKey));
    final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
    expect(icon.size, 24);
    expect(icon.color, colors.muted);
    expect(icon.icon, DoableIconData.more);
    expect(
      tester.getRect(find.byType(DoableIcon)).center.dx,
      options.center.dx,
    );
    // Центр точек в 18 от верха шапки, против первой строки исходного
    // намерения.
    expect(tester.getRect(find.byType(DoableIcon)).center.dy, head.top + 18);
    expect(tester.getRect(find.byType(Wrap).first).right, options.left);
  });

  testWidgets('временно недоступная кнопка параметров остаётся на месте и не '
      'принимает нажатие, а раскладка совпадает с доступной', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _head(
          options: ChoiceHeadOptions.available(
            label: 'Параметры',
            onOpen: () => opened++,
            buttonKey: _optionsKey,
          ),
        ),
      ),
    );
    final available = _layout(tester);
    final availableButton = tester.getRect(find.byKey(_optionsKey));

    await tester.pumpWidget(
      _app(
        Brightness.light,
        _head(
          options: const ChoiceHeadOptions.unavailable(
            label: 'Параметры',
            buttonKey: _optionsKey,
          ),
        ),
      ),
    );
    expect(_layout(tester), available);
    expect(tester.getRect(find.byKey(_optionsKey)), availableButton);
    expect(find.byType(DoableIcon), findsOneWidget);

    await tester.tap(find.byKey(_optionsKey));
    await tester.pump();
    expect(opened, 0);
  });

  testWidgets('названия по 255 символов переносятся и не обрезаются, а метка '
      'архива встаёт под текст, когда в строке нет места', (tester) async {
    final goal = List.filled(8, 'Поддерживать форму').join(' ');
    final action = List.filled(9, 'Подготовить рюкзак').join(' ');
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _head(
          goal: goal,
          action: action,
          goalBadge: const Badge.archived(word: 'Архив'),
          actionBadge: const Badge.archived(word: 'Архив'),
          options: const ChoiceHeadOptions.available(
            label: 'Параметры',
            onOpen: _noop,
          ),
        ),
        width: 300,
      ),
    );

    for (final text in [goal, action]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        paragraph.size.height,
        greaterThan(paragraph.preferredLineHeight * 2),
      );
    }
    final badges = tester.getRect(find.byType(BadgeArchived).first);
    final goalRect = tester.getRect(find.text(goal));
    expect(badges.top, greaterThanOrEqualTo(goalRect.bottom));
    final actionBadge = tester.getRect(find.byType(BadgeArchived).last);
    final actionRect = tester.getRect(find.text(action));
    expect(actionBadge.top, greaterThanOrEqualTo(actionRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('метка архива исходного намерения высотой 18 не увеличивает его '
      'строку, а метка действия остаётся своей высоты 20 в 8 от текста', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(Brightness.light, _head(goal: 'Цель', action: 'Действие')),
    );
    final plain = tester.getRect(find.byType(ChoiceHead));

    await tester.pumpWidget(
      _app(
        Brightness.light,
        _head(
          goal: 'Цель',
          action: 'Действие',
          goalBadge: const Badge.archived(word: 'Архив'),
          actionBadge: const Badge.archived(word: 'Архив'),
        ),
      ),
    );

    expect(tester.getRect(find.byType(ChoiceHead)).height, plain.height);
    final goal = tester.getRect(find.text('Цель'));
    final goalBadge = tester.getRect(find.byType(BadgeArchived).first);
    expect(goalBadge.height, 18);
    expect(goalBadge.left - goal.right, 8);
    expect(goalBadge.center.dy, goal.center.dy);
    final action = tester.getRect(find.text('Действие'));
    final actionBadge = tester.getRect(find.byType(BadgeArchived).last);
    expect(actionBadge.height, 20);
    expect(actionBadge.left - action.right, 8);
    expect(actionBadge.center.dy, action.center.dy);
  });

  testWidgets('диктор слышит две кнопки с названиями потребителя: флажок с '
      'состоянием выполнения и параметры, в том числе недоступные', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    Future<void> pump({
      required bool done,
      VoidCallback? onToggle,
      ChoiceHeadOptions? options,
    }) async {
      await tester.pumpWidget(
        _app(
          Brightness.light,
          _head(
            done: done,
            onToggle: onToggle,
            checkLabel: 'Выполнить: Действие, приоритет P1',
            options: options ?? const ChoiceHeadOptions.none(),
          ),
        ),
      );
      // Фокус кнопки узнаёт о выключении на следующем кадре.
      await tester.pump();
    }

    Matcher check({required bool checked, required bool enabled}) =>
        matchesSemantics(
          label: 'Выполнить: Действие, приоритет P1',
          isButton: true,
          hasCheckedState: true,
          isChecked: checked,
          hasEnabledState: true,
          isEnabled: enabled,
          isFocusable: enabled,
          hasTapAction: enabled,
          hasFocusAction: enabled,
        );
    Matcher options({required bool enabled}) => matchesSemantics(
      label: 'Параметры выбора',
      isButton: true,
      hasEnabledState: true,
      isEnabled: enabled,
      isFocusable: enabled,
      hasTapAction: enabled,
      hasFocusAction: enabled,
    );
    SemanticsNode node(String label) =>
        tester.getSemantics(find.bySemanticsLabel(label));

    await pump(done: false, onToggle: () {});
    expect(
      node('Выполнить: Действие, приоритет P1'),
      check(checked: false, enabled: true),
    );
    expect(find.bySemanticsLabel('Параметры выбора'), findsNothing);

    await pump(done: true, onToggle: () {});
    expect(
      node('Выполнить: Действие, приоритет P1'),
      check(checked: true, enabled: true),
    );

    await pump(done: false);
    expect(
      node('Выполнить: Действие, приоритет P1'),
      check(checked: false, enabled: false),
    );

    await pump(
      done: false,
      options: const ChoiceHeadOptions.available(
        label: 'Параметры выбора',
        onOpen: _noop,
      ),
    );
    expect(node('Параметры выбора'), options(enabled: true));

    await pump(
      done: false,
      options: const ChoiceHeadOptions.unavailable(label: 'Параметры выбора'),
    );
    expect(node('Параметры выбора'), options(enabled: false));
    semantics.dispose();
  });

  testWidgets('клавиатура обводит кольцом фокуса метку флажка, затем кнопку '
      'параметров, а Enter нажимает сфокусированную кнопку', (tester) async {
    final boundary = GlobalKey();
    final calls = <String>[];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _head(
          onToggle: () => calls.add('toggle'),
          options: ChoiceHeadOptions.available(
            label: 'Параметры',
            onOpen: () => calls.add('options'),
            buttonKey: _optionsKey,
          ),
        ),
        boundary: boundary,
      ),
    );
    final mark = tester.getRect(find.byType(ChoiceCheck));
    final options = tester.getRect(find.byKey(_optionsKey));
    // Полоса `accent` лежит в 2–4 от края; точка в её середине не зависит от
    // сглаживания края круга.
    final aroundMark = Offset(mark.left - 3, mark.center.dy);
    final aroundOptions = Offset(options.right + 2.5, options.center.dy);
    final colors = DoableColors.light;
    expect(
      await _pixel(tester, boundary, aroundMark),
      isNot(isSameColorAs(colors.accent)),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      await _pixel(tester, boundary, aroundMark),
      isSameColorAs(colors.accent),
    );
    expect(
      await _pixel(tester, boundary, aroundOptions),
      isNot(isSameColorAs(colors.accent)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, ['toggle']);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      await _pixel(tester, boundary, aroundOptions),
      isSameColorAs(colors.accent),
    );
    expect(
      await _pixel(tester, boundary, aroundMark),
      isNot(isSameColorAs(colors.accent)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, ['toggle', 'options']);
  });
}

void _noop() {}

ChoiceHead _head({
  String goal = 'Цель',
  String action = 'Действие',
  DoablePriority priority = DoablePriority.p1,
  bool done = false,
  String checkLabel = 'Выполнить',
  VoidCallback? onToggle,
  Widget? goalBadge,
  Widget? actionBadge,
  ChoiceHeadOptions options = const ChoiceHeadOptions.none(),
  Key? checkKey,
}) => ChoiceHead(
  goal: goal,
  action: action,
  priority: priority,
  chain: const SizedBox(key: _chainKey, width: 40, height: 11),
  done: done,
  checkLabel: checkLabel,
  onToggle: onToggle,
  goalBadge: goalBadge,
  actionBadge: actionBadge,
  options: options,
  checkKey: checkKey,
);

/// Прямоугольники, по которым видно любой сдвиг раскладки шапки.
List<Rect> _layout(WidgetTester tester) => [
  tester.getRect(find.byType(ChoiceHead)),
  tester.getRect(find.byType(ChoiceCheck)),
  tester.getRect(find.text('Цель')),
  tester.getRect(find.text('Действие')),
];

TextStyle _style(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

void _expectStyle(TextStyle actual, TextStyle expected) {
  expect(actual.color, expected.color);
  expect(actual.fontFamily, expected.fontFamily);
  expect(actual.fontSize, expected.fontSize);
  expect(actual.fontWeight, expected.fontWeight);
  expect(actual.height, expected.height);
  expect(actual.letterSpacing, expected.letterSpacing);
}

/// Цвет пикселя [point] в логических координатах границы [boundary].
Future<Color> _pixel(
  WidgetTester tester,
  GlobalKey boundary,
  Offset point,
) async {
  final render = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundary),
  );
  return (await tester.runAsync(() async {
    final image = await render.toImage();
    try {
      final bytes = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
      final index = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
      return Color.fromARGB(
        bytes.getUint8(index + 3),
        bytes.getUint8(index),
        bytes.getUint8(index + 1),
        bytes.getUint8(index + 2),
      );
    } finally {
      image.dispose();
    }
  }))!;
}

/// Шапка стоит в поле содержимого листа шириной 20: полосы кнопок за её краями
/// лежат в этом поле. Лист прокручивается, поэтому высокая шапка не упирается
/// в окно теста.
Widget _app(
  Brightness brightness,
  Widget child, {
  double width = 390,
  GlobalKey? boundary,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: RepaintBoundary(
    key: boundary,
    child: Scaffold(
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: child,
            ),
          ),
        ),
      ),
    ),
  ),
);
