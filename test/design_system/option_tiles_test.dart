import 'dart:ui' show ImageByteFormat;

import 'package:doable/src/design_system/components/option_tiles.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Kind { intention, action }

const _intention = OptionTile(
  id: _Kind.intention,
  icon: DoableIconData.intention,
  title: 'Намерение',
  hint: 'Любого размера. Может занять больше дня.',
);
const _action = OptionTile(
  id: _Kind.action,
  icon: DoableIconData.bolt,
  title: 'Действие',
  hint: 'Выполнимо за один день, и понятно, что делать.',
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
    testWidgets('в $themeName теме плитки стоят в равных колонках одной '
        'высоты и отличают выбранную плитку цветом и отметкой', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          OptionTiles(
            first: _intention,
            second: const OptionTile(
              id: _Kind.action,
              icon: DoableIconData.bolt,
              title: 'Действие',
              hint:
                  'Выполнимо за один день, и понятно, что делать, даже '
                  'если пояснение занимает несколько строк.',
            ),
            value: _Kind.intention,
            label: 'Намерение или действие',
            onChange: (_) {},
          ),
        ),
      );

      final first = tester.getRect(_tile('Намерение'));
      final second = tester.getRect(_tile('Действие'));
      expect(first.width, second.width);
      expect(first.height, second.height);
      expect(second.left - first.right, 8);
      expect(first.left, 0);
      expect(second.right, 390);

      final iconTile = tester.getRect(_iconTile('Намерение'));
      expect(iconTile.size, const Size.square(32));
      expect(iconTile.topLeft - first.topLeft, const Offset(12, 12));
      expect(tester.getRect(find.text('Намерение')).left - iconTile.right, 8);
      expect(
        tester.getRect(find.text('Намерение')).center.dy,
        iconTile.center.dy,
      );
      expect(
        tester.getRect(find.text(_intention.hint)).top - iconTile.bottom,
        6,
      );
      _expectStyle(
        _style(tester, 'Намерение'),
        DoableType.section.copyWith(color: colors.ink),
      );
      _expectStyle(
        _style(tester, _intention.hint),
        DoableType.hint.copyWith(color: colors.muted),
      );

      final chosen = _plane(tester, 'Намерение');
      expect(chosen.color, colors.fill);
      expect(chosen.border, isNull);
      expect(chosen.borderRadius, BorderRadius.circular(16));
      expect(_iconTileColor(tester, 'Намерение'), colors.accent);
      final chosenIcon = _icon(tester, 'Намерение', DoableIconData.intention);
      expect(chosenIcon.size, 20);
      expect(chosenIcon.color, colors.onAccent);
      final check = _icon(tester, 'Намерение', DoableIconData.check);
      expect(check.size, 18);
      expect(check.color, colors.accent);
      expect(tester.getRect(find.byWidget(check)).right, first.right - 12);

      final other = _plane(tester, 'Действие');
      expect(other.color, isNull);
      expect(other.border, Border.all(color: colors.hairline));
      expect(other.borderRadius, BorderRadius.circular(16));
      expect(_iconTileColor(tester, 'Действие'), colors.fill);
      expect(_icon(tester, 'Действие', DoableIconData.bolt).color, colors.ink);
      expect(
        find.descendant(
          of: _tile('Действие'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DoableIcon && widget.icon == DoableIconData.check,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('в $themeName теме обработчик получает только нажатие на '
        'невыбранную доступную плитку, а диктор слышит выбор в паре', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final changes = <_Kind>[];
      var enabled = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        _app(
          brightness,
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return OptionTiles(
                first: _intention,
                second: _action,
                value: _Kind.intention,
                label: 'Намерение или действие',
                onChange: enabled ? changes.add : null,
              );
            },
          ),
        ),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('Намерение или действие')),
        matchesSemantics(
          label: 'Намерение или действие',
          children: [
            _tileSemantics('Намерение\n${_intention.hint}', selected: true),
            _tileSemantics('Действие\n${_action.hint}', selected: false),
          ],
        ),
      );
      await tester.tap(find.text('Намерение'));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      await tester.tap(find.text('Действие'));
      await tester.pumpAndSettle();
      expect(changes, [_Kind.action]);

      rebuild(() => enabled = false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Действие'));
      await tester.pumpAndSettle();
      expect(changes, [_Kind.action]);
      expect(
        tester.getSemantics(find.text('Действие')),
        matchesSemantics(
          label: 'Действие\n${_action.hint}',
          isButton: true,
          hasEnabledState: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('в $themeName теме длинные слова с крупным текстом '
        'переносятся без переполнения, и плитки остаются равной высоты', (
      tester,
    ) async {
      const long = OptionTile(
        id: _Kind.action,
        icon: DoableIconData.bolt,
        title: 'Handlungsbereitschaft',
        hint: 'Durchführbarkeitsvoraussetzung',
      );
      await tester.pumpWidget(
        _app(
          brightness,
          OptionTiles(
            first: _intention,
            second: long,
            value: _Kind.action,
            label: 'Намерение или действие',
            onChange: (_) {},
          ),
          width: 320,
          textScale: 2,
        ),
      );

      expect(tester.takeException(), isNull);
      for (final text in [long.title, long.hint]) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.textScaler.scale(10), 20);
        // Слово шире колонки и переносится на следующие строки.
        expect(
          paragraph.size.height,
          greaterThan(paragraph.preferredLineHeight),
        );
        expect(
          tester.getRect(find.text(text)).right,
          lessThanOrEqualTo(tester.getRect(_tile(long.title)).right),
        );
      }
      expect(
        tester.getSize(_tile('Намерение')).height,
        tester.getSize(_tile(long.title)).height,
      );
    });

    testWidgets('в $themeName теме клавиатура рисует focus-ring вокруг '
        'плитки и Enter выбирает её', (tester) async {
      final changes = <_Kind>[];
      await tester.pumpWidget(
        _app(
          brightness,
          OptionTiles(
            first: _intention,
            second: _action,
            value: _Kind.intention,
            label: 'Намерение или действие',
            onChange: changes.add,
          ),
        ),
      );
      expect(_plane(tester, 'Намерение').boxShadow, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_plane(tester, 'Намерение').boxShadow, isNull);
      expect(_plane(tester, 'Действие').boxShadow, [
        BoxShadow(color: colors.accent, spreadRadius: 4),
        BoxShadow(color: colors.bg, spreadRadius: 2),
      ]);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(changes, [_Kind.action]);
    });
  }

  testWidgets(
    'плитки, частично прокрученные за верх области прокрутки, не закрашивают '
    'прозрачную панель над ней',
    (tester) async {
      final boundary = GlobalKey();
      final controller = ScrollController(initialScrollOffset: 30);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: doableTheme(Brightness.light),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: Column(
                children: [
                  const SizedBox(height: 44),
                  Expanded(
                    child: CustomScrollView(
                      controller: controller,
                      slivers: [
                        SliverToBoxAdapter(
                          child: OptionTiles(
                            first: _intention,
                            second: _action,
                            value: _Kind.intention,
                            label: 'Намерение или действие',
                            onChange: (_) {},
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 1000)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.getRect(_tile('Намерение')).top, 14);
      expect(
        await _pixel(tester, boundary, const Offset(50, 30)),
        isSameColorAs(DoableColors.light.bg),
      );
    },
  );
}

Matcher _tileSemantics(String label, {required bool selected}) =>
    matchesSemantics(
      label: label,
      isButton: true,
      hasEnabledState: true,
      isEnabled: true,
      hasSelectedState: true,
      isSelected: selected,
      isInMutuallyExclusiveGroup: true,
      isFocusable: true,
      hasTapAction: true,
      hasFocusAction: true,
    );

Finder _tile(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(InkWell));
Finder _iconTile(String title) => find.descendant(
  of: _tile(title),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
  ),
);
Color? _iconTileColor(WidgetTester tester, String title) =>
    (tester.widget<Container>(_iconTile(title)).decoration! as BoxDecoration)
        .color;
DoableIcon _icon(WidgetTester tester, String title, DoableIconData icon) =>
    tester.widget<DoableIcon>(
      find.descendant(
        of: _tile(title),
        matching: find.byWidgetPredicate(
          (widget) => widget is DoableIcon && widget.icon == icon,
        ),
      ),
    );
BoxDecoration _plane(WidgetTester tester, String title) =>
    tester
            .widget<DecoratedBox>(
              find
                  .ancestor(
                    of: _tile(title),
                    matching: find.byType(DecoratedBox),
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
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);
