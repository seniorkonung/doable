import 'dart:ui' show ImageByteFormat;

import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/relation_row.dart';
import 'package:doable/src/design_system/components/relation_stroke.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart' hide Badge;
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
    testWidgets('в $themeName теме p1–p3 подкрашены своим цветом в 10% поверх '
        'fill, а p4 и архивированная связь — чистая fill', (tester) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _app(
          brightness,
          Column(
            spacing: 8,
            children: [
              _row(name: 'P1', priority: RelationRowPriority.p1),
              _row(name: 'P2', priority: RelationRowPriority.p2),
              _row(name: 'P3', priority: RelationRowPriority.p3),
              _row(name: 'P4', priority: RelationRowPriority.p4),
              _row(
                name: 'Архивная',
                priority: RelationRowPriority.p1,
                archived: true,
              ),
            ],
          ),
          boundary: boundary,
        ),
      );

      // Левое поле строки свободно от содержимого, поэтому цвет в нём — цвет
      // плоскости.
      Future<Color> plane(String name) {
        final rect = tester.getRect(_rowOf(name));
        return _pixel(tester, boundary, Offset(rect.left + 4, rect.center.dy));
      }

      expect(
        await plane('P1'),
        isSameColorAs(Color.lerp(colors.fill, colors.p1, .1)!),
      );
      expect(
        await plane('P2'),
        isSameColorAs(Color.lerp(colors.fill, colors.p2, .1)!),
      );
      expect(
        await plane('P3'),
        isSameColorAs(Color.lerp(colors.fill, colors.p3, .1)!),
      );
      expect(await plane('P4'), isSameColorAs(colors.fill));
      expect(await plane('Архивная'), isSameColorAs(colors.fill));
    });

    testWidgets('в $themeName теме у p1–p3 метка цвета приоритета, а подпись — '
        'он же, смешанный с ink; у p4 и архивированной связи метка grip, '
        'подпись muted', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          Column(
            spacing: 8,
            children: [
              _row(
                name: 'P1',
                label: 'Нужно · P1',
                priority: RelationRowPriority.p1,
              ),
              _row(
                name: 'P3',
                label: 'Можно · P3',
                kind: RelationRowKind.can,
                priority: RelationRowPriority.p3,
              ),
              _row(
                name: 'P4',
                label: 'Нужно · P4',
                priority: RelationRowPriority.p4,
              ),
              _row(
                name: 'Архивная',
                label: 'Нужно · P2',
                priority: RelationRowPriority.p2,
                archived: true,
              ),
            ],
          ),
        ),
      );

      final p1 = _kindOf(tester, 'P1');
      expect(p1, isA<RelationStrokeNeed>());
      expect((p1 as RelationStrokeNeed).color, colors.p1);
      _expectStyle(
        _style(tester, 'Нужно · P1'),
        DoableType.label.copyWith(color: Color.lerp(colors.ink, colors.p1, .7)),
      );

      final p3 = _kindOf(tester, 'P3');
      expect(p3, isA<RelationStrokeCan>());
      expect((p3 as RelationStrokeCan).color, colors.p3);
      expect(
        _style(tester, 'Можно · P3').color,
        Color.lerp(colors.ink, colors.p3, .7),
      );

      expect((_kindOf(tester, 'P4') as RelationStrokeNeed).color, colors.grip);
      expect(_style(tester, 'Нужно · P4').color, colors.muted);

      expect(
        (_kindOf(tester, 'Архивная') as RelationStrokeNeed).color,
        colors.grip,
      );
      expect(_style(tester, 'Нужно · P2').color, colors.muted);
    });

    testWidgets('в $themeName теме название — ink, у архивированной связи и у '
        'связи с архивированным соседом — muted, а подкраска и метка связи с '
        'архивированным соседом остаются', (tester) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _app(
          brightness,
          Column(
            spacing: 8,
            children: [
              _row(name: 'Обычная', label: 'Обычная подпись'),
              _row(name: 'Архивная связь', archived: true),
              _row(
                name: 'Архивный сосед',
                label: 'Подпись соседа',
                intentionArchived: true,
              ),
            ],
          ),
          boundary: boundary,
        ),
      );

      _expectStyle(
        _style(tester, 'Обычная'),
        DoableType.action.copyWith(color: colors.ink),
      );
      expect(_style(tester, 'Архивная связь').color, colors.muted);
      expect(_style(tester, 'Архивный сосед').color, colors.muted);
      expect(
        (_kindOf(tester, 'Архивный сосед') as RelationStrokeNeed).color,
        colors.p1,
      );
      expect(
        _style(tester, 'Подпись соседа').color,
        Color.lerp(colors.ink, colors.p1, .7),
      );
      final rect = tester.getRect(_rowOf('Архивный сосед'));
      expect(
        await _pixel(tester, boundary, Offset(rect.left + 4, rect.center.dy)),
        isSameColorAs(Color.lerp(colors.fill, colors.p1, .1)!),
      );
    });

    testWidgets('в $themeName теме после подписи стоят отметки соседа в 6 друг '
        'от друга: коробка архива muted, затем молния ink, а в приглушённой '
        'строке молния muted', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          Column(
            spacing: 8,
            children: [
              _row(name: 'Без отметок'),
              _row(name: 'Действие', action: true),
              _row(
                name: 'Архивный сосед-действие',
                action: true,
                intentionArchived: true,
              ),
              _row(
                name: 'Архивная связь-действие',
                action: true,
                archived: true,
              ),
            ],
          ),
        ),
      );

      expect(_badges('Без отметок'), findsNothing);

      final action = _badges('Действие');
      expect(action, findsOneWidget);
      expect(tester.widget<BadgeMark>(action).icon, DoableIconData.bolt);
      expect(tester.widget<BadgeMark>(action).tone, BadgeTone.ink);

      final marks = _badges('Архивный сосед-действие');
      expect(marks, findsNWidgets(2));
      final archive = tester.widget<BadgeMark>(marks.at(0));
      final bolt = tester.widget<BadgeMark>(marks.at(1));
      expect(archive.icon, DoableIconData.archive);
      expect(archive.tone, BadgeTone.muted);
      expect(bolt.icon, DoableIconData.bolt);
      expect(bolt.tone, BadgeTone.muted);
      expect(
        tester.getRect(marks.at(1)).left - tester.getRect(marks.at(0)).right,
        6,
      );

      final dimmed = _badges('Архивная связь-действие');
      expect(dimmed, findsOneWidget);
      expect(tester.widget<BadgeMark>(dimmed).tone, BadgeTone.muted);
    });

    testWidgets(
      'в $themeName теме строка имеет поле 16 слева, метку вида 15 × 2 '
      'над названием и стрелку по центру правых 48 на всю высоту',
      (tester) async {
        await tester.pumpWidget(
          _app(
            brightness,
            _row(name: 'Название', label: 'Нужно · P1', action: true),
          ),
        );

        final row = tester.getRect(find.byType(RelationRow));
        final mark = tester.getRect(find.byType(RelationKindMark));
        final label = tester.getRect(find.text('Нужно · P1'));
        final bolt = tester.getRect(_badges('Название'));
        final name = tester.getRect(find.text('Название'));
        expect(row.width, 390);
        expect(row.height, 64);
        expect(mark.size, const Size(15, 2));
        expect(mark.left - row.left, 16);
        expect(label.left - mark.right, 6);
        expect(mark.center.dy, label.center.dy);
        expect(bolt.left - label.right, 8);
        expect(name.left - row.left, 16);
        // Поле сверху 9, строка метки 20 и 2 до названия.
        expect(name.top - row.top, 31);

        final arrow = tester.getRect(_arrow);
        expect(arrow.size, const Size(20, 20));
        expect(arrow.center.dy, row.center.dy);
        // Область шириной 48 с полем справа 4: значок по центру левых 44.
        expect(row.right - arrow.center.dx, 26);
        final icon = tester.widget<DoableIcon>(_arrow);
        expect(icon.color, colors.muted);
      },
    );

    testWidgets('в $themeName теме длинное название переносится целиком, а '
        'заметка занимает не больше двух строк и без заметки её строки '
        'нет', (tester) async {
      const long =
          'Подготовиться к долгому походу через горы с палаткой и '
          'запасом еды на неделю вперёд';
      const note =
          'Первая строка заметки достаточно длинная, чтобы занять место. '
          'Вторая строка заметки тоже длинная, чтобы заполнить второе место. '
          'Третьей строки не будет, она обрезается многоточием.';
      await tester.pumpWidget(
        _app(
          brightness,
          Column(
            spacing: 8,
            children: [
              _row(name: long, note: note),
              _row(name: 'Короткое'),
            ],
          ),
          width: 300,
        ),
      );

      final name = tester.renderObject<RenderParagraph>(find.text(long));
      expect(name.didExceedMaxLines, isFalse);
      expect(name.size.height, greaterThan(name.preferredLineHeight * 2));

      final noteParagraph = tester.renderObject<RenderParagraph>(
        find.text(note),
      );
      expect(noteParagraph.didExceedMaxLines, isTrue);
      expect(noteParagraph.size.height, noteParagraph.preferredLineHeight * 2);
      _expectStyle(
        _style(tester, note),
        DoableType.note.copyWith(color: colors.muted),
      );

      // Строка с короткой заметкой не имеет ни пустого места под названием.
      expect(
        tester.getRect(_rowOf('Короткое')).bottom -
            tester.getRect(find.text('Короткое')).bottom,
        11,
      );
    });

    testWidgets('в $themeName теме строка и стрелка вызывают каждая свой '
        'обработчик', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        _app(
          brightness,
          _row(
            name: 'Название',
            onOpen: () => calls.add('open'),
            onWalk: () => calls.add('walk'),
          ),
        ),
      );

      final row = tester.getRect(find.byType(RelationRow));
      await tester.tap(find.text('Название'));
      await tester.pumpAndSettle();
      expect(calls, ['open']);

      await tester.tapAt(row.topLeft + const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(calls, ['open', 'open']);

      await tester.tap(_arrow);
      await tester.pumpAndSettle();
      expect(calls, ['open', 'open', 'walk']);

      // Область стрелки занимает всю высоту строки, а не только значок.
      await tester.tapAt(row.topRight - const Offset(10, -4));
      await tester.pumpAndSettle();
      expect(calls, ['open', 'open', 'walk', 'walk']);
    });

    testWidgets('в $themeName теме диктор слышит строку и стрелку двумя '
        'кнопками со своими названиями', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          brightness,
          _row(
            name: 'Название',
            semanticLabel: 'Открыть связь: нужно, Название',
            walkLabel: 'Открыть намерение: Название',
          ),
        ),
      );

      Matcher button(String label) => matchesSemantics(
        label: label,
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Открыть связь: нужно, Название'),
        ),
        button('Открыть связь: нужно, Название'),
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Открыть намерение: Название'),
        ),
        button('Открыть намерение: Название'),
      );
      semantics.dispose();
    });

    testWidgets('в $themeName теме при крупном тексте длинные подпись и '
        'название переносятся без переполнения, а стрелка остаётся на всю '
        'высоту', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          _row(
            name: 'Handlungsbereitschaftsvoraussetzung',
            label: 'Можно использовать · P2',
            kind: RelationRowKind.can,
            priority: RelationRowPriority.p2,
            note:
                'Заметка связи длиннее, чем помещается в две строки узкой '
                'строки при двукратном тексте',
            action: true,
            intentionArchived: true,
          ),
          width: 320,
          textScale: 2,
        ),
      );

      expect(tester.takeException(), isNull);
      final name = tester.renderObject<RenderParagraph>(
        find.text('Handlungsbereitschaftsvoraussetzung'),
      );
      expect(name.didExceedMaxLines, isFalse);
      expect(name.size.height, greaterThan(name.preferredLineHeight));
      final label = tester.renderObject<RenderParagraph>(
        find.text('Можно использовать · P2'),
      );
      expect(label.size.height, greaterThan(label.preferredLineHeight));
      expect(
        tester.getRect(find.text('Можно использовать · P2')).right,
        lessThanOrEqualTo(tester.getRect(_badges('Handlungs').first).left),
      );

      final row = tester.getRect(find.byType(RelationRow));
      await tester.tapAt(row.bottomRight - const Offset(10, 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('в $themeName теме клавиатура обводит кольцом фокуса '
        'сфокусированную область, а Enter её нажимает', (tester) async {
      final boundary = GlobalKey();
      final calls = <String>[];
      await tester.pumpWidget(
        _app(
          brightness,
          Padding(
            padding: const EdgeInsets.all(16),
            child: _row(
              name: 'Название',
              onOpen: () => calls.add('open'),
              onWalk: () => calls.add('walk'),
            ),
          ),
          boundary: boundary,
        ),
      );
      final row = tester.getRect(find.byType(RelationRow));
      final left = Offset(row.left - 3.5, row.center.dy);
      final right = Offset(row.right + 3.5, row.center.dy);
      expect(
        await _pixel(tester, boundary, left),
        isNot(isSameColorAs(colors.accent)),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        await _pixel(tester, boundary, left),
        isSameColorAs(colors.accent),
      );
      expect(
        await _pixel(tester, boundary, right),
        isNot(isSameColorAs(colors.accent)),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, ['open']);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        await _pixel(tester, boundary, right),
        isSameColorAs(colors.accent),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, ['open', 'walk']);
    });
  }
}

RelationRow _row({
  required String name,
  String label = 'Нужно · P1',
  RelationRowKind kind = RelationRowKind.need,
  RelationRowPriority priority = RelationRowPriority.p1,
  String? note,
  bool action = false,
  bool archived = false,
  bool intentionArchived = false,
  String? semanticLabel,
  String? walkLabel,
  VoidCallback? onOpen,
  VoidCallback? onWalk,
}) => RelationRow(
  kind: kind,
  priority: priority,
  label: label,
  name: name,
  note: note,
  action: action,
  archived: archived,
  intentionArchived: intentionArchived,
  semanticLabel: semanticLabel ?? 'Связь: $name',
  walkLabel: walkLabel ?? 'Намерение: $name',
  onOpen: onOpen ?? () {},
  onWalk: onWalk ?? () {},
);

Finder _rowOf(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(RelationRow));

/// Отметки соседа строки с названием, начинающимся с [name].
Finder _badges(String name) => find.descendant(
  of: find.ancestor(
    of: find.textContaining(name),
    matching: find.byType(RelationRow),
  ),
  matching: find.bySubtype<Badge>(),
);

final Finder _arrow = find.byWidgetPredicate(
  (widget) =>
      widget is DoableIcon && widget.icon == DoableIconData.arrowUpRight,
);

RelationStrokeKind _kindOf(WidgetTester tester, String name) => tester
    .widget<RelationKindMark>(
      find.descendant(
        of: _rowOf(name),
        matching: find.byType(RelationKindMark),
      ),
    )
    .kind;

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
  double textScale = 1,
  GlobalKey? boundary,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: RepaintBoundary(
    key: boundary,
    child: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  ),
);
