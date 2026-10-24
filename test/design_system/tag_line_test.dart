import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/tag_chip.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/components/tag_line.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_test/flutter_test.dart';

// Шрифт тестов рисует каждый знак квадратом в кегль: знак `caption` — 13,
// поэтому чип с названием из трёх букв шириной 7 + 7 + 5 + 39 + 8 = 66,
// а число «+2» — 26.
void main() {
  testWidgets('все теги помещаются через 6 без числа, а последнему тегу '
      'место под число не нужно', (tester) async {
    await tester.pumpWidget(_app(width: 210, tags: _threeTags));

    expect(_line(tester).hiddenTagCount, 0);
    expect(
      [for (final name in _threeNames) _inLine(tester, find.text(name)).left],
      [19, 91, 163],
    );
    expect(tester.getSize(find.byType(TagLine)), const Size(210, 20));
  });

  testWidgets('тег показывается, только если после него остаётся место под '
      'число, а не поместившиеся теги заменяет «+N» через 6 после последнего', (
    tester,
  ) async {
    // Второй тег кончился бы на 138, но число «+1» после него требует ещё 32.
    await tester.pumpWidget(_app(width: 160, tags: _threeTags));

    final line = _line(tester);
    expect(line.hiddenTagCount, 2);
    expect(line, paints..something(_paragraphAt(const Offset(72, 1))));
    expect(tester.getSize(find.byType(TagLine)), const Size(98, 20));
  });

  testWidgets('единственный видимый тег, который не помещается перед числом, '
      'обрезается краем своей области', (tester) async {
    await tester.pumpWidget(
      _app(
        width: 120,
        tags: const [
          TagChip.small(name: 'Длинное название', color: DoableTagColor.blue),
          TagChip.small(name: 'Дом', color: DoableTagColor.teal),
        ],
      ),
    );

    final line = _line(tester);
    expect(line.hiddenTagCount, 1);
    expect(
      line,
      paints
        ..something(_clipTo(const Rect.fromLTRB(0, 0, 88, 20)))
        ..something(_paragraphAt(const Offset(94, 1))),
    );
    expect(tester.getSize(find.byType(TagLine)), const Size(120, 20));
  });

  testWidgets('метки стоят первыми и места не уступают, а тег на узкой линии '
      'виден и обрезается краем линии', (tester) async {
    await tester.pumpWidget(
      _app(
        width: 60,
        marks: const [
          Badge.mark(icon: DoableIconData.bolt, tone: BadgeTone.ink),
        ],
        tags: const [TagChip.small(name: 'Дом', color: DoableTagColor.teal)],
      ),
    );

    expect(
      _inLine(tester, find.byType(Badge)),
      const Rect.fromLTWH(0, 0, 22, 20),
    );
    expect(_inLine(tester, find.byType(TagChip)).left, 28);
    expect(_line(tester).hiddenTagCount, 0);
    expect(
      _line(tester),
      paints..something(_clipTo(const Rect.fromLTRB(28, 0, 60, 20))),
    );
  });

  testWidgets('линия заново раскладывает теги при смене ширины', (
    tester,
  ) async {
    await tester.pumpWidget(_app(width: 160, tags: _threeTags));
    expect(_line(tester).hiddenTagCount, 2);

    await tester.pumpWidget(_app(width: 210, tags: _threeTags));

    expect(_line(tester).hiddenTagCount, 0);
  });

  testWidgets('метки, теги и число не создают узлов экранного диктора', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        width: 160,
        semanticsLabel: 'Прогулка',
        marks: const [
          Badge.mark(icon: DoableIconData.bolt, tone: BadgeTone.ink),
        ],
        tags: _threeTags,
      ),
    );

    final node = tester.getSemantics(find.byType(TagLine));
    expect(node.label, 'Прогулка');
    expect(node.childrenCount, 0);
    semantics.dispose();
  });

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме число — caption цвета muted '
        'с табличными цифрами', (tester) async {
      await tester.pumpWidget(
        _app(brightness: brightness, width: 160, tags: _threeTags),
      );

      final style = _line(tester).countStyle;
      expect(style.color, colors.muted);
      expect(style.fontSize, DoableType.caption.fontSize);
      expect(style.fontWeight, DoableType.caption.fontWeight);
      expect(style.height, DoableType.caption.height);
      expect(style.fontFeatures, const [FontFeature.tabularFigures()]);
    });
  }

  testWidgets('при тексте масштаба 2 линия растёт с тегами, метка стоит по '
      'центру, а место под число растёт вместе с ним', (tester) async {
    // Чип — 7 + 7 + 5 + 78 + 8 = 105 в высоту 38, число «+1» — 52.
    // Теги начинаются с 28. Второй тег кончился бы на 244, а с числом
    // после него — на 302, поэтому на линии шириной 290 он не виден.
    await tester.pumpWidget(
      _app(
        width: 290,
        textScale: 2,
        marks: const [
          Badge.mark(icon: DoableIconData.bolt, tone: BadgeTone.ink),
        ],
        tags: _threeTags,
      ),
    );

    expect(tester.takeException(), isNull);
    final line = _line(tester);
    expect(line.size.height, 38);
    expect(
      _inLine(tester, find.byType(Badge)),
      const Rect.fromLTWH(0, 9, 22, 20),
    );
    expect(line.hiddenTagCount, 2);
    expect(line, paints..something(_paragraphAt(const Offset(139, 1))));
  });
}

const _threeNames = ['Дом', 'Сад', 'Чай'];

const _threeTags = [
  TagChip.small(name: 'Дом', color: DoableTagColor.teal),
  TagChip.small(name: 'Сад', color: DoableTagColor.green),
  TagChip.small(name: 'Чай', color: DoableTagColor.brown),
];

RenderTagLine _line(WidgetTester tester) =>
    tester.renderObject<RenderTagLine>(find.byType(TagLine));

/// Место элемента относительно начала линии.
Rect _inLine(WidgetTester tester, Finder finder) =>
    tester.getRect(finder).shift(-tester.getTopLeft(find.byType(TagLine)));

bool Function(Symbol, List<Object?>) _clipTo(Rect rect) =>
    (method, arguments) => method == #clipRect && arguments[0] == rect;

bool Function(Symbol, List<Object?>) _paragraphAt(Offset offset) =>
    (method, arguments) => method == #drawParagraph && arguments[1] == offset;

Widget _app({
  required double width,
  required List<TagChip> tags,
  List<Badge> marks = const [],
  Brightness brightness = Brightness.light,
  double textScale = 1,
  String? semanticsLabel,
}) {
  Widget line = TagLine(marks: marks, tags: tags);
  if (semanticsLabel != null) {
    line = Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticsLabel,
      child: line,
    );
  }
  return MaterialApp(
    theme: doableTheme(brightness),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: line,
            ),
          ),
        ),
      ),
    ),
  );
}
