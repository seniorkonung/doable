import 'dart:ui' show ImageByteFormat;

import 'package:doable/src/design_system/components/count_tiles.dart';
import 'package:doable/src/design_system/components/relation_stroke.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Group { needs, canUse, needed, canBeUsed }

const _needs = CountTile(
  id: _Group.needs,
  count: 3,
  name: 'Нужно',
  semanticLabel: 'Нужно: 3 связи',
  glyph: CountTileGlyph(
    kind: CountTileGlyphKind.need,
    direction: CountTileGlyphDirection.fromIntention,
  ),
);
const _canUse = CountTile(
  id: _Group.canUse,
  count: 1,
  name: 'Можно использовать',
  semanticLabel: 'Можно использовать: 1 связь, есть архивные',
  archived: true,
  glyph: CountTileGlyph(
    kind: CountTileGlyphKind.can,
    direction: CountTileGlyphDirection.fromIntention,
  ),
);
const _needed = CountTile(
  id: _Group.needed,
  count: 7,
  name: 'Нужно для',
  semanticLabel: 'Нужно для: 7 связей',
  glyph: CountTileGlyph(
    kind: CountTileGlyphKind.need,
    direction: CountTileGlyphDirection.toIntention,
  ),
);
const _canBeUsed = CountTile(
  id: _Group.canBeUsed,
  count: 0,
  name: 'Можно использовать для',
  semanticLabel: 'Можно использовать для: нет связей',
  glyph: CountTileGlyph(
    kind: CountTileGlyphKind.can,
    direction: CountTileGlyphDirection.toIntention,
  ),
);
const _groups = [_needs, _canUse, _needed, _canBeUsed];

const _started = CountTile(
  id: _Group.needs,
  count: 81,
  name: 'Начаты здесь',
  semanticLabel: 'Начаты здесь: 81',
);
const _onPath = CountTile(
  id: _Group.canUse,
  count: 5,
  name: 'На пути',
  semanticLabel: 'На пути: 5',
);
const _ended = CountTile(
  id: _Group.needed,
  count: 0,
  name: 'Закончены здесь',
  semanticLabel: 'Закончены здесь: 0',
);

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
    testWidgets('в $themeName теме в две колонки плитки стоят равными '
        'колонками и рядами с отступом 8', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          CountTiles(
            tiles: _groups,
            columns: CountTileColumns.two,
            value: _Group.needs,
            onPick: (_) {},
            label: 'Группы связей',
          ),
        ),
      );

      final needs = tester.getRect(_tile('Нужно'));
      final canUse = tester.getRect(_tile('Можно использовать'));
      final needed = tester.getRect(_tile('Нужно для'));
      final canBeUsed = tester.getRect(_tile('Можно использовать для'));
      expect(needs.left, 0);
      expect(needs.width, 191);
      expect(canUse.left - needs.right, 8);
      expect(canUse.right, 390);
      expect(canUse.width, 191);
      expect(needed.left, 0);
      expect(canBeUsed.right, 390);
      expect(needed.top - needs.bottom, 8);
      expect(canBeUsed.top, needed.top);
      expect(needs.height, canUse.height);
      expect(needed.height, canBeUsed.height);
    });

    testWidgets('в $themeName теме в три колонки плитки стоят равными '
        'колонками одной высоты с отступом 8', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          CountTiles(
            tiles: const [_started, _onPath, _ended],
            columns: CountTileColumns.three,
            value: _Group.needs,
            onPick: (_) {},
            label: 'Выборы намерения',
          ),
        ),
      );

      final started = tester.getRect(_tile('Начаты здесь'));
      final onPath = tester.getRect(_tile('На пути'));
      final ended = tester.getRect(_tile('Закончены здесь'));
      expect(started.left, 0);
      expect(started.width, closeTo(374 / 3, 0.001));
      expect(onPath.width, closeTo(374 / 3, 0.001));
      expect(ended.width, closeTo(374 / 3, 0.001));
      expect(onPath.left - started.right, closeTo(8, 0.001));
      expect(ended.left - onPath.right, closeTo(8, 0.001));
      expect(ended.right, closeTo(390, 0.001));
      expect(started.top, onPath.top);
      expect(started.height, onPath.height);
      expect(started.height, ended.height);
    });

    testWidgets('в $themeName теме плитка имеет поля 11 и 12, число стилем '
        'headline с табличными цифрами и подпись стилем caption muted '
        'под ним в 2', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          CountTiles(
            tiles: _groups,
            columns: CountTileColumns.two,
            value: _Group.needs,
            onPick: (_) {},
            label: 'Группы связей',
          ),
        ),
      );

      final tile = tester.getRect(_tile('Нужно'));
      final number = tester.getRect(find.text('3'));
      final caption = tester.getRect(find.text('Нужно'));
      expect(number.left - tile.left, 12);
      expect(number.top - tile.top, 11);
      expect(caption.left - tile.left, 12);
      expect(caption.top - number.bottom, 2);
      expect(tile.bottom - caption.bottom, 12);
      _expectStyle(
        _style(tester, '3'),
        DoableType.headline.copyWith(color: colors.ink),
      );
      expect(
        _style(tester, '3').fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      _expectStyle(
        _style(tester, 'Нужно'),
        DoableType.caption.copyWith(color: colors.muted),
      );
    });

    testWidgets('в $themeName теме открытая плитка — плоскость fill, закрытая '
        '— внутреннее кольцо hairline 1 без плоскости, а нулевое число '
        'цвета grip при подписи muted', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          CountTiles(
            tiles: _groups,
            columns: CountTileColumns.two,
            value: _Group.needs,
            onPick: (_) {},
            label: 'Группы связей',
          ),
        ),
      );

      final open = _plane(tester, 'Нужно');
      expect(open.color, colors.fill);
      expect(open.borderRadius, BorderRadius.circular(16));
      expect(_ring(tester, 'Нужно').border, isNull);

      final closed = _plane(tester, 'Нужно для');
      expect(closed.color, isNull);
      expect(closed.borderRadius, BorderRadius.circular(16));
      expect(
        _ring(tester, 'Нужно для').border,
        Border.all(color: colors.hairline),
      );
      expect(
        _ring(tester, 'Нужно для').borderRadius,
        BorderRadius.circular(16),
      );
      // Кольцо лежит внутри плитки и не сдвигает содержимое: закрытая плитка
      // с тем же полем стоит так же, как открытая.
      expect(
        tester.getRect(find.text('7')).left -
            tester.getRect(_tile('Нужно для')).left,
        12,
      );

      expect(_style(tester, '7').color, colors.ink);
      expect(_style(tester, '0').color, colors.grip);
      expect(_style(tester, 'Можно использовать для').color, colors.muted);
    });

    testWidgets('в $themeName теме отметка архива — малый значок muted после '
        'числа в 6, а у плитки без архива её нет', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          CountTiles(
            tiles: _groups,
            columns: CountTileColumns.two,
            value: _Group.needs,
            onPick: (_) {},
            label: 'Группы связей',
          ),
        ),
      );

      final archive = tester.widget<DoableIcon>(
        _archiveIcon(_tile('Можно использовать')),
      );
      expect(archive.size, 14);
      expect(archive.color, colors.muted);
      final archiveRect = tester.getRect(
        _archiveIcon(_tile('Можно использовать')),
      );
      expect(archiveRect.left - tester.getRect(find.text('1')).right, 6);
      expect(archiveRect.center.dy, tester.getRect(find.text('1')).center.dy);
      for (final name in ['Нужно', 'Нужно для', 'Можно использовать для']) {
        expect(_archiveIcon(_tile(name)), findsNothing);
      }
    });

    testWidgets('в $themeName теме плитка без глифа не рисует отметку '
        'направления', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          CountTiles(
            tiles: const [_started, _onPath, _ended],
            columns: CountTileColumns.three,
            value: _Group.needs,
            onPick: (_) {},
            label: 'Выборы намерения',
          ),
        ),
      );

      expect(find.byType(RelationStroke), findsNothing);
    });

    testWidgets('в $themeName теме глиф «нужно» от намерения — сплошная линия, '
        'закрашенная точка в начале, кольцо в конце и стрелка цвета числа', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _app(
          brightness,
          CountTiles(
            tiles: _groups,
            columns: CountTileColumns.two,
            value: _Group.needs,
            onPick: (_) {},
            label: 'Группы связей',
          ),
          boundary: boundary,
        ),
      );

      final glyph = _glyphRect(tester, 'Нужно');
      expect(glyph.size, const Size(38, 12));
      expect(
        tester.getRect(_tile('Нужно')).right - glyph.right,
        12,
        reason: 'глиф стоит в конце строки числа',
      );
      expect(glyph.center.dy, tester.getRect(find.text('3')).center.dy);
      final stroke = tester.widget<RelationStroke>(_stroke('Нужно'));
      expect(stroke.axis, RelationStrokeAxis.horizontal);
      expect(stroke.kind, isA<RelationStrokeNeed>());
      expect((stroke.kind as RelationStrokeNeed).color, colors.ink);

      Future<Color> at(double x, double y) =>
          _pixel(tester, boundary, glyph.topLeft + Offset(x, y));
      expect(await at(5.5, 6.5), isSameColorAs(colors.ink));
      expect(await at(32.5, 6.5), isSameColorAs(colors.fill));
      expect(await at(36.5, 6.5), isNot(isSameColorAs(colors.fill)));
      expect(await at(13.5, 6.5), isSameColorAs(colors.ink));
      expect(await at(16.5, 6.5), isSameColorAs(colors.ink));
      expect(await at(20.5, 6.5), isSameColorAs(colors.ink));
      expect(await at(26.5, 6.5), isNot(isSameColorAs(colors.fill)));
      expect(await at(27.5, 6.5), isSameColorAs(colors.fill));
    });

    testWidgets('в $themeName теме глиф «можно» к намерению — пунктир 3 через '
        '3, кольцо в начале и закрашенная точка в конце', (tester) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _app(
          brightness,
          CountTiles(
            tiles: _groups,
            columns: CountTileColumns.two,
            value: _Group.canBeUsed,
            onPick: (_) {},
            label: 'Группы связей',
          ),
          boundary: boundary,
        ),
      );

      final glyph = _glyphRect(tester, 'Можно использовать для');
      final stroke = tester.widget<RelationStroke>(
        _stroke('Можно использовать для'),
      );
      expect(stroke.axis, RelationStrokeAxis.horizontal);
      expect(stroke.kind, isA<RelationStrokeCan>());
      // Число равно нулю, поэтому глиф цвета grip.
      expect((stroke.kind as RelationStrokeCan).color, colors.grip);

      Future<Color> at(double x, double y) =>
          _pixel(tester, boundary, glyph.topLeft + Offset(x, y));
      expect(await at(5.5, 6.5), isSameColorAs(colors.fill));
      expect(await at(1.5, 6.5), isNot(isSameColorAs(colors.fill)));
      expect(await at(33.5, 6.5), isSameColorAs(colors.grip));
      expect(await at(13.5, 6.5), isNot(isSameColorAs(colors.fill)));
      expect(await at(16.5, 6.5), isSameColorAs(colors.fill));
      expect(await at(19.5, 6.5), isNot(isSameColorAs(colors.fill)));
      expect(await at(22.5, 6.5), isSameColorAs(colors.fill));
    });

    testWidgets('в $themeName теме глиф «нужно» к намерению — кольцо в начале '
        'и закрашенная точка в конце', (tester) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _app(
          brightness,
          CountTiles(
            tiles: _groups,
            columns: CountTileColumns.two,
            value: _Group.needed,
            onPick: (_) {},
            label: 'Группы связей',
          ),
          boundary: boundary,
        ),
      );

      final glyph = _glyphRect(tester, 'Нужно для');
      Future<Color> at(double x, double y) =>
          _pixel(tester, boundary, glyph.topLeft + Offset(x, y));
      expect(await at(5.5, 6.5), isSameColorAs(colors.fill));
      expect(await at(1.5, 6.5), isNot(isSameColorAs(colors.fill)));
      expect(await at(33.5, 6.5), isSameColorAs(colors.ink));
    });

    testWidgets('в $themeName теме нажатие на закрытую плитку выбирает её, а '
        'на открытую ничего не делает', (tester) async {
      final picked = <_Group>[];
      await tester.pumpWidget(
        _app(
          brightness,
          CountTiles(
            tiles: _groups,
            columns: CountTileColumns.two,
            value: _Group.needs,
            onPick: picked.add,
            label: 'Группы связей',
          ),
        ),
      );

      await tester.tap(find.text('Нужно'));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
      await tester.tap(find.text('Нужно для'));
      await tester.pumpAndSettle();
      expect(picked, [_Group.needed]);
    });

    testWidgets('в $themeName теме диктор слышит радиогруппу с доступным '
        'названием, а каждая плитка называет себя и сообщает выбор', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          brightness,
          CountTiles(
            tiles: _groups,
            columns: CountTileColumns.two,
            value: _Group.canUse,
            onPick: (_) {},
            label: 'Группы связей',
          ),
        ),
      );

      final group = tester.getSemantics(find.bySemanticsLabel('Группы связей'));
      expect(group.getSemanticsData().role, SemanticsRole.radioGroup);
      expect(
        group,
        matchesSemantics(
          label: 'Группы связей',
          children: [
            _tileSemantics('Нужно: 3 связи', selected: false),
            _tileSemantics(
              'Можно использовать: 1 связь, есть архивные',
              selected: true,
            ),
            _tileSemantics('Нужно для: 7 связей', selected: false),
            _tileSemantics(
              'Можно использовать для: нет связей',
              selected: false,
            ),
          ],
        ),
      );
      semantics.dispose();
    });

    testWidgets('в $themeName теме длинные подписи с крупным текстом '
        'переносятся без переполнения, и плитки ряда остаются одной '
        'высоты', (tester) async {
      const long = CountTile(
        id: _Group.canUse,
        count: 12,
        name: 'Handlungsbereitschaftsvoraussetzung',
        semanticLabel: 'Handlungsbereitschaftsvoraussetzung: 12',
        archived: true,
        glyph: CountTileGlyph(
          kind: CountTileGlyphKind.can,
          direction: CountTileGlyphDirection.fromIntention,
        ),
      );
      await tester.pumpWidget(
        _app(
          brightness,
          CountTiles(
            tiles: const [_needs, long, _needed, _canBeUsed],
            columns: CountTileColumns.two,
            value: _Group.needs,
            onPick: (_) {},
            label: 'Группы связей',
          ),
          width: 320,
          textScale: 2,
        ),
      );

      expect(tester.takeException(), isNull);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(long.name),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.textScaler.scale(10), 20);
      // Слово шире колонки и переносится на следующие строки.
      expect(paragraph.size.height, greaterThan(paragraph.preferredLineHeight));
      expect(
        tester.getRect(find.text(long.name)).right,
        lessThanOrEqualTo(tester.getRect(_tile(long.name)).right),
      );
      expect(
        tester.getSize(_tile('Нужно')).height,
        tester.getSize(_tile(long.name)).height,
      );
    });

    testWidgets('в $themeName теме клавиатура рисует focus-ring вокруг плитки '
        'и Enter выбирает её', (tester) async {
      final picked = <_Group>[];
      await tester.pumpWidget(
        _app(
          brightness,
          CountTiles(
            tiles: _groups,
            columns: CountTileColumns.two,
            value: _Group.needs,
            onPick: picked.add,
            label: 'Группы связей',
          ),
        ),
      );
      expect(_plane(tester, 'Нужно').boxShadow, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_plane(tester, 'Нужно').boxShadow, isNull);
      expect(_plane(tester, 'Можно использовать').boxShadow, [
        BoxShadow(color: colors.accent, spreadRadius: 4),
        BoxShadow(color: colors.bg, spreadRadius: 2),
      ]);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picked, [_Group.canUse]);
    });
  }
}

Matcher _tileSemantics(String label, {required bool selected}) =>
    matchesSemantics(
      label: label,
      hasCheckedState: true,
      isChecked: selected,
      isInMutuallyExclusiveGroup: true,
      hasEnabledState: true,
      isEnabled: true,
      isFocusable: true,
      hasTapAction: true,
      hasFocusAction: true,
    );

Finder _tile(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(InkWell));

Finder _archiveIcon(Finder tile) => find.descendant(
  of: tile,
  matching: find.byWidgetPredicate(
    (widget) => widget is DoableIcon && widget.icon == DoableIconData.archive,
  ),
);

Finder _stroke(String name) =>
    find.descendant(of: _tile(name), matching: find.byType(RelationStroke));

/// Прямоугольник глифа 38 × 12 плитки: линия занимает его 12 из 38 слева
/// с отступом 12.
Rect _glyphRect(WidgetTester tester, String name) {
  final line = tester.getRect(_stroke(name));
  return Rect.fromLTWH(line.left - 12, line.top, 38, 12);
}

BoxDecoration _plane(WidgetTester tester, String name) =>
    _decoration(tester, name, DecorationPosition.background);

BoxDecoration _ring(WidgetTester tester, String name) =>
    _decoration(tester, name, DecorationPosition.foreground);

BoxDecoration _decoration(
  WidgetTester tester,
  String name,
  DecorationPosition position,
) =>
    tester
            .widget<DecoratedBox>(
              find
                  .ancestor(
                    of: _tile(name),
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is DecoratedBox && widget.position == position,
                    ),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

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
