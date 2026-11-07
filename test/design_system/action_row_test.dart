import 'dart:ui' show ImageByteFormat;

import 'package:doable/src/design_system/components/action_check.dart';
import 'package:doable/src/design_system/components/action_row.dart';
import 'package:doable/src/design_system/components/reason_chain.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
    testWidgets('в $themeName теме строка — плоскость fill, корневое намерение '
        'и описание muted, а действие ink', (tester) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _app(
          brightness,
          _row(goal: 'Цель', action: 'Действие', description: 'Описание'),
          boundary: boundary,
        ),
      );

      final rect = tester.getRect(find.byType(ActionRow));
      // Левое поле строки свободно от содержимого: цвет в нём — цвет плоскости.
      expect(
        await _pixel(tester, boundary, Offset(rect.left + 4, rect.center.dy)),
        isSameColorAs(colors.fill),
      );
      _expectStyle(
        _style(tester, 'Цель'),
        DoableType.caption.copyWith(color: colors.muted),
      );
      _expectStyle(
        _style(tester, 'Действие'),
        DoableType.action.copyWith(color: colors.ink),
      );
      expect(
        _style(tester, 'Действие').decoration,
        isNot(TextDecoration.lineThrough),
      );
      _expectStyle(
        _style(tester, 'Описание'),
        DoableType.note.copyWith(color: colors.muted),
      );
    });

    testWidgets('в $themeName теме у выполненного действия название muted и '
        'зачёркнуто, а кольцо и цепочка серые', (tester) async {
      await tester.pumpWidget(
        _app(brightness, _row(action: 'Действие', done: true)),
      );

      expect(_style(tester, 'Действие').color, colors.muted);
      expect(_style(tester, 'Действие').decoration, TextDecoration.lineThrough);
      expect(tester.widget<ActionCheck>(find.byType(ActionCheck)).done, isTrue);
      expect(tester.widget<ReasonChain>(find.byType(ReasonChain)).off, isTrue);
    });
  }

  testWidgets('приоритет и число шагов пути уходят в кольцо и цепочку, а у '
      'невыполненного действия они цветные', (tester) async {
    await tester.pumpWidget(
      _app(Brightness.light, _row(priority: DoablePriority.p2, reasons: 4)),
    );

    final check = tester.widget<ActionCheck>(find.byType(ActionCheck));
    expect(check.priority, DoablePriority.p2);
    expect(check.done, isFalse);
    final chain = tester.widget<ReasonChain>(find.byType(ReasonChain));
    expect(chain.priority, DoablePriority.p2);
    expect(chain.reasons, 4);
    expect(chain.off, isFalse);
  });

  testWidgets('корневое намерение занимает одну строку с многоточием, действие '
      'переносится целиком, а описание — не больше двух строк', (tester) async {
    const goal =
        'Поддерживать форму тела сильной и выносливой на долгие годы вперёд '
        'без травм и перерывов';
    const action =
        'Подготовить рюкзак, палатку и запас еды для долгого похода через '
        'горы на целую неделю вперёд';
    const description =
        'Первая строка описания достаточно длинная, чтобы занять место. '
        'Вторая строка описания тоже длинная, чтобы заполнить второе место. '
        'Третьей строки не будет, она обрезается многоточием.';
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _row(goal: goal, action: action, description: description),
        width: 300,
      ),
    );

    final goalParagraph = tester.renderObject<RenderParagraph>(find.text(goal));
    expect(goalParagraph.didExceedMaxLines, isTrue);
    expect(goalParagraph.size.height, goalParagraph.preferredLineHeight);

    final actionParagraph = tester.renderObject<RenderParagraph>(
      find.text(action),
    );
    expect(actionParagraph.didExceedMaxLines, isFalse);
    expect(
      actionParagraph.size.height,
      greaterThan(actionParagraph.preferredLineHeight * 2),
    );

    final descriptionParagraph = tester.renderObject<RenderParagraph>(
      find.text(description),
    );
    expect(descriptionParagraph.didExceedMaxLines, isTrue);
    expect(
      descriptionParagraph.size.height,
      descriptionParagraph.preferredLineHeight * 2,
    );
  });

  testWidgets('текст стоит правее флажка шириной 52 с полями 9 сверху, 10 '
      'снизу и 16 справа, а цепочка отстоит на 2 от корневого намерения и на 5 '
      'от действия', (tester) async {
    await tester.pumpWidget(
      _app(Brightness.light, _row(goal: 'Цель', action: 'Действие')),
    );

    final row = tester.getRect(find.byType(ActionRow));
    final goal = tester.getRect(find.text('Цель'));
    final chain = tester.getRect(find.byType(ReasonChain));
    final action = tester.getRect(find.text('Действие'));
    expect(row.width, 390);
    expect(row.height, 77);
    expect(goal.left - row.left, 52);
    expect(row.right - goal.right, 16);
    expect(goal.top - row.top, 9);
    expect(chain.left, goal.left);
    expect(chain.top - goal.bottom, 2);
    expect(action.top - chain.bottom, 5);
    expect(row.bottom - action.bottom, 10);
  });

  testWidgets('кольцо флажка стоит по центру высоты строки с описанием в две '
      'строки, а описание отстоит от действия на 2', (tester) async {
    const description =
        'Первая строка описания достаточно длинная, чтобы занять место. '
        'Вторая строка описания тоже длинная, чтобы заполнить второе место.';
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _row(goal: 'Цель', action: 'Действие', description: description),
        width: 300,
      ),
    );

    final row = tester.getRect(find.byType(ActionRow));
    final mark = tester.getRect(find.byType(ActionCheck));
    final action = tester.getRect(find.text('Действие'));
    final descriptionRect = tester.getRect(find.text(description));
    expect(mark.size, const Size.square(22));
    expect(mark.center.dy, row.center.dy);
    // Область флажка 52 с полем 4 слева: кольцо по центру остальных 48.
    expect(mark.left - row.left, 17);
    expect(descriptionRect.top - action.bottom, 2);
    expect(row.bottom - descriptionRect.bottom, 10);
  });

  testWidgets('флажок и текст вызывают каждый свой обработчик по ключам '
      'потребителя, а область флажка занимает всю высоту строки', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _row(
          action: 'Действие',
          checkKey: const ValueKey('check'),
          openKey: const ValueKey('open'),
          onToggle: () => calls.add('toggle'),
          onOpen: () => calls.add('open'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('check')));
    await tester.pumpAndSettle();
    expect(calls, ['toggle']);

    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    expect(calls, ['toggle', 'open']);

    await tester.tap(find.text('Действие'));
    await tester.pumpAndSettle();
    expect(calls, ['toggle', 'open', 'open']);

    // Угол области флажка далеко от кольца, но это тоже флажок.
    final row = tester.getRect(find.byType(ActionRow));
    await tester.tapAt(row.topLeft + const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(calls, ['toggle', 'open', 'open', 'toggle']);
  });

  testWidgets('без обработчика флажок выключен: нажатие его не открывает '
      'действие, а раскладка не меняется', (tester) async {
    final calls = <String>[];
    ActionRow row({VoidCallback? onToggle}) => _row(
      goal: 'Цель',
      action: 'Действие',
      onToggle: onToggle,
      onOpen: () => calls.add('open'),
    );

    await tester.pumpWidget(
      _app(Brightness.light, row(onToggle: () => calls.add('toggle'))),
    );
    final enabled = [
      tester.getRect(find.byType(ActionRow)),
      tester.getRect(find.byType(ActionCheck)),
      tester.getRect(find.text('Действие')),
    ];

    await tester.pumpWidget(_app(Brightness.light, row()));
    final disabled = [
      tester.getRect(find.byType(ActionRow)),
      tester.getRect(find.byType(ActionCheck)),
      tester.getRect(find.text('Действие')),
    ];
    expect(disabled, enabled);

    await tester.tap(find.byType(ActionCheck));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets('диктор слышит две кнопки с названиями потребителя: флажок с '
      'состоянием выполнения и текст', (tester) async {
    final semantics = tester.ensureSemantics();
    Future<void> pump({required bool done, VoidCallback? onToggle}) async {
      await tester.pumpWidget(
        _app(
          Brightness.light,
          _row(
            done: done,
            checkLabel: 'Выполнить: Действие, приоритет P1',
            label: 'Действие. Цель. Шагов в пути: 4',
            onToggle: onToggle,
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
    SemanticsNode node(String label) =>
        tester.getSemantics(find.bySemanticsLabel(label));

    await pump(done: false, onToggle: () {});
    expect(
      node('Выполнить: Действие, приоритет P1'),
      check(checked: false, enabled: true),
    );
    expect(
      node('Действие. Цель. Шагов в пути: 4'),
      matchesSemantics(
        label: 'Действие. Цель. Шагов в пути: 4',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

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
    semantics.dispose();
  });

  testWidgets('клавиатура обводит кольцом фокуса метку флажка, затем область '
      'текста, а Enter нажимает сфокусированную кнопку', (tester) async {
    final boundary = GlobalKey();
    final calls = <String>[];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        Padding(
          padding: const EdgeInsets.all(16),
          child: _row(
            onToggle: () => calls.add('toggle'),
            onOpen: () => calls.add('open'),
          ),
        ),
        boundary: boundary,
      ),
    );
    final row = tester.getRect(find.byType(ActionRow));
    final mark = tester.getRect(find.byType(ActionCheck));
    // Полоса `accent` лежит в 2–4 от метки; точка в её середине не зависит от
    // сглаживания края круга.
    final aroundMark = Offset(mark.left - 3, mark.center.dy);
    final aroundText = Offset(row.right + 3.5, row.center.dy);
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
      await _pixel(tester, boundary, aroundText),
      isNot(isSameColorAs(colors.accent)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, ['toggle']);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      await _pixel(tester, boundary, aroundText),
      isSameColorAs(colors.accent),
    );
    expect(
      await _pixel(tester, boundary, aroundMark),
      isNot(isSameColorAs(colors.accent)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, ['toggle', 'open']);
  });
  testWidgets('первая линия «when» стоит над корнем и цепочкой, а без неё '
      'строка прежняя', (tester) async {
    await tester.pumpWidget(
      _app(Brightness.light, _row(goal: 'Цель', when: 'Сегодня · 18:00')),
    );

    final when = tester.getRect(find.text('Сегодня · 18:00'));
    final goal = tester.getRect(find.text('Цель'));
    final chain = tester.getRect(find.byType(ReasonChain));
    expect(when.bottom, lessThanOrEqualTo(goal.top));
    expect(goal.bottom, lessThanOrEqualTo(chain.top));
    _expectStyle(
      _style(tester, 'Сегодня · 18:00'),
      DoableType.label.copyWith(color: DoableColors.light.muted),
    );

    await tester.pumpWidget(_app(Brightness.light, _row(goal: 'Цель')));
    expect(find.text('Сегодня · 18:00'), findsNothing);
    expect(find.text('Цель'), findsOneWidget);
  });

  testWidgets('без корневого намерения строки корня нет, а цепочка остаётся', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(Brightness.light, _row(goal: null, when: 'Завтра')),
    );

    expect(find.text('Цель'), findsNothing);
    expect(find.text('Завтра'), findsOneWidget);
    expect(find.byType(ReasonChain), findsOneWidget);
    expect(find.text('Действие'), findsOneWidget);
  });
}

ActionRow _row({
  String? goal = 'Цель',
  String? when,
  String action = 'Действие',
  String? description,
  DoablePriority priority = DoablePriority.p1,
  int reasons = 3,
  bool done = false,
  String checkLabel = 'Выполнить',
  String label = 'Открыть',
  Key? checkKey,
  Key? openKey,
  VoidCallback? onToggle,
  VoidCallback? onOpen,
}) => ActionRow(
  goal: goal,
  when: when,
  action: action,
  description: description,
  priority: priority,
  reasons: reasons,
  done: done,
  checkLabel: checkLabel,
  label: label,
  checkKey: checkKey,
  openKey: openKey,
  onToggle: onToggle,
  onOpen: onOpen ?? () {},
);

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
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);
