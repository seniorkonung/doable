import 'dart:ui' show ImageByteFormat;

import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/path_glyph.dart';
import 'package:doable/src/design_system/components/priority_picker.dart';
import 'package:doable/src/design_system/components/relation_head.dart';
import 'package:doable/src/design_system/components/relation_stroke.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = 'Беречь здоровье';
const _target = 'Укреплять силу';

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
    testWidgets('в $themeName теме три строки не ниже tap-min несут ромб, '
        'сплошную линию и кольцо: ромб цвета приоритета, линия и кольцо его '
        'тона', (tester) async {
      await tester.pumpWidget(
        _app(brightness, _head(priority: DoablePriority.p2)),
      );

      final head = tester.getRect(find.byType(RelationHead));
      final source = tester.getRect(_open(_source));
      final target = tester.getRect(_open(_target));
      expect(source.top, head.top);
      expect(source.height, 44);
      expect(target.top - source.bottom, 44);
      expect(target.height, 44);
      expect(target.bottom, head.bottom);
      expect(source.left - head.left, 22);

      final tone = Color.lerp(colors.p2, colors.grip, .5)!;
      final glyphs = tester.widgetList<PathGlyph>(find.byType(PathGlyph));
      expect(glyphs.map((glyph) => glyph.shape), [
        PathGlyphShape.diamond,
        PathGlyphShape.ring,
      ]);
      expect(glyphs.map((glyph) => glyph.color), [colors.p2, tone]);
      final diamond = tester.getRect(find.byType(PathGlyph).first);
      final ring = tester.getRect(find.byType(PathGlyph).last);
      expect(diamond.size, const Size.square(14));
      expect(diamond.center, Offset(head.left + 11, head.top + 22));
      expect(ring.center, Offset(head.left + 11, target.top + 22));

      // Линия идёт от ромба через строку вида до кольца без разрывов.
      final strokes = _lines(tester);
      expect(strokes, hasLength(3));
      for (final (stroke, rect) in strokes) {
        expect(stroke.kind, isA<RelationStrokeNeed>());
        expect((stroke.kind as RelationStrokeNeed).color, tone);
        expect(rect.center.dx, head.left + 11);
        expect(rect.width, 2);
      }
      expect(strokes[0].$2.top, diamond.bottom);
      expect(strokes[0].$2.bottom, source.bottom);
      expect(strokes[1].$2.top, source.bottom);
      expect(strokes[1].$2.bottom, target.top);
      expect(strokes[2].$2.top, target.top);
      expect(strokes[2].$2.bottom, ring.top);

      for (final name in [_source, _target]) {
        final text = tester.getRect(find.text(name));
        expect(text.left - source.left, 12, reason: name);
        _expectStyle(
          _style(tester, name),
          DoableType.title.copyWith(color: colors.ink),
        );
      }
    });
  }

  testWidgets('связь «можно» идёт пунктирной линией', (tester) async {
    await tester.pumpWidget(
      _app(Brightness.light, _head(kind: RelationHeadKind.can)),
    );

    final strokes = _lines(tester);
    expect(strokes, hasLength(3));
    for (final (stroke, rect) in strokes) {
      expect(stroke.kind, isA<RelationStrokeCan>());
      expect(rect.width, 1.5);
    }
  });

  testWidgets('без onKind средняя строка — плитка 26 со значком связи и слово '
      'вида в нижнем регистре в space-2 справа; плитка подкрашена '
      'приоритетом на 12%, а у p4 лежит на fill', (tester) async {
    final colors = DoableColors.light;
    for (final (priority, color) in [
      (DoablePriority.p1, colors.p1),
      (DoablePriority.p3, colors.p3),
      (DoablePriority.p4, colors.p4),
    ]) {
      await tester.pumpWidget(
        _app(Brightness.light, _head(priority: priority)),
      );

      final head = tester.getRect(find.byType(RelationHead));
      final tile = tester.getRect(_tile());
      final word = tester.getRect(find.text('нужно'));
      expect(tile.size, const Size.square(26), reason: '$priority');
      expect(tile.left - head.left, 22 + 12, reason: '$priority');
      expect(tile.center.dy, head.top + 44 + 22, reason: '$priority');
      expect(word.left - tile.right, 8, reason: '$priority');
      expect(find.text('Нужно'), findsNothing, reason: '$priority');
      _expectStyle(
        _style(tester, 'нужно'),
        DoableType.section.copyWith(color: colors.ink),
      );

      final decoration =
          tester.widget<DecoratedBox>(_tile()).decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle, reason: '$priority');
      expect(
        decoration.color,
        priority == DoablePriority.p4
            ? colors.fill
            : color.withValues(alpha: .12),
        reason: '$priority',
      );
      final icon = tester.widget<DoableIcon>(
        find.descendant(of: _tile(), matching: find.byType(DoableIcon)),
      );
      expect(icon.icon, DoableIconData.relationMini, reason: '$priority');
      expect(icon.size, 16, reason: '$priority');
      expect(icon.color, color, reason: '$priority');
    }
  });

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме с onKind средняя строка — переключатель: '
        'выбранная пилюля лежит на fill, отметка выбранного вида в тоне '
        'приоритета, другая grip, а плитки со словом нет', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          _head(
            priority: DoablePriority.p3,
            status: RelationHeadActive(
              kindSwitch: RelationHeadKindSwitch(
                label: 'Вид связи',
                onChange: (_) {},
              ),
            ),
          ),
        ),
      );

      final head = tester.getRect(find.byType(RelationHead));
      final tone = Color.lerp(colors.p3, colors.grip, .5)!;
      expect(_tile(), findsNothing);
      expect(find.text('нужно'), findsNothing);

      final need = tester.getRect(_plane('Нужно'));
      final can = tester.getRect(_plane('Можно'));
      expect(need.height, 36);
      expect(can.height, 36);
      expect(need.left - head.left, 22 + 6);
      expect(can.left - need.right, 4);
      expect(need.center.dy, head.top + 44 + 22);
      expect(tester.getRect(_open('Нужно')).height, 44);

      final needMark = tester.getRect(_mark('Нужно'));
      expect(needMark.size, const Size(15, 2));
      expect(needMark.left - need.left, 12);
      expect(tester.getRect(find.text('Нужно')).left - needMark.right, 7);
      expect(need.right - tester.getRect(find.text('Нужно')).right, 14);

      expect(_planeColor(tester, 'Нужно'), colors.fill);
      expect(_planeColor(tester, 'Можно'), isNull);
      _expectStyle(
        _style(tester, 'Нужно'),
        DoableType.section.copyWith(color: colors.ink),
      );
      _expectStyle(
        _style(tester, 'Можно'),
        DoableType.section.copyWith(color: colors.muted),
      );
      expect((_markKind(tester, 'Нужно') as RelationStrokeNeed).color, tone);
      expect(
        (_markKind(tester, 'Можно') as RelationStrokeCan).color,
        colors.grip,
      );
    });
  }

  testWidgets('нажатие на другую пилюлю сообщает вид, а на выбранную ничего '
      'не делает', (tester) async {
    final changes = <RelationHeadKind>[];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _head(
          kind: RelationHeadKind.can,
          status: RelationHeadActive(
            kindSwitch: RelationHeadKindSwitch(
              label: 'Вид связи',
              onChange: changes.add,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Можно'));
    await tester.pump();
    expect(changes, isEmpty);

    await tester.tap(find.text('Нужно'));
    await tester.pump();
    expect(changes, [RelationHeadKind.need]);
  });

  testWidgets('диктор слышит название переключателя и пилюли с отметкой '
      'выбранной, а названия намерений — кнопками потребителя', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _head(
          source: _participant(_source, archived: true),
          status: RelationHeadActive(
            kindSwitch: RelationHeadKindSwitch(
              label: 'Вид связи',
              onChange: (_) {},
            ),
          ),
          menu: RelationHeadMenu(label: 'Параметры связи', onOpen: () {}),
        ),
      ),
    );

    Matcher pill(String label, {required bool chosen}) => matchesSemantics(
      label: label,
      isButton: true,
      hasToggledState: true,
      isToggled: chosen,
      isFocusable: true,
      hasTapAction: true,
      hasFocusAction: true,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Вид связи')),
      matchesSemantics(
        label: 'Вид связи',
        children: [pill('Нужно', chosen: true), pill('Можно', chosen: false)],
      ),
    );

    Matcher button(String label) => matchesSemantics(
      label: label,
      isButton: true,
      isFocusable: true,
      hasTapAction: true,
      hasFocusAction: true,
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Открыть страницу намерения: $_source. В архиве'),
      ),
      button('Открыть страницу намерения: $_source. В архиве'),
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Открыть страницу намерения: $_target'),
      ),
      button('Открыть страницу намерения: $_target'),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Параметры связи')),
      button('Параметры связи'),
    );
    semantics.dispose();
  });

  testWidgets('кнопка параметров появляется только с menu: круглая область '
      'tap-min со значком из трёх точек цвета muted у правого края строки '
      'вида, выходящая на 14 за край содержимого и принимающая там касания', (
    tester,
  ) async {
    final colors = DoableColors.light;
    await tester.pumpWidget(_app(Brightness.light, _head()));
    expect(_menuIcon(), findsNothing);

    var opened = 0;
    var sourceTaps = 0;
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _head(
          source: _participant(_source, onOpen: () => sourceTaps++),
          menu: RelationHeadMenu(
            label: 'Параметры связи',
            onOpen: () => opened++,
          ),
        ),
      ),
    );

    final head = tester.getRect(find.byType(RelationHead));
    final button = tester.getRect(_menuArea());
    final icon = tester.widget<DoableIcon>(_menuIcon());
    expect(button.size, const Size.square(44));
    expect(button.right - head.right, 14);
    expect(button.center.dy, head.top + 44 + 22);
    expect(icon.size, 24);
    expect(icon.color, colors.muted);
    expect(tester.getRect(_menuIcon()).center, button.center);

    // Названия намерений кончаются до области кнопки: её полоса за краем
    // принадлежит только кнопке.
    expect(tester.getRect(_open(_source)).right, head.right);
    await tester.tapAt(Offset(head.right + 10, button.center.dy));
    await tester.pump();
    expect(opened, 1);
    await tester.tapAt(Offset(head.right + 10, head.top + 22));
    await tester.pump();
    expect(opened, 1);
    expect(sourceTaps, 0);
  });

  testWidgets('длинное название переносится и не обрезается, рейка тянется '
      'на всю высоту строки, а нажатие открывает страницу намерения', (
    tester,
  ) async {
    const long =
        'Научиться спокойно разговаривать с людьми о деньгах, обязанностях '
        'и ожиданиях, не откладывая трудные разговоры на потом';
    var opened = 0;
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _head(
          source: _participant(_source),
          target: _participant(long, onOpen: () => opened++),
        ),
      ),
    );

    final text = tester.renderObject<RenderParagraph>(find.text(long));
    final target = tester.getRect(_open(long));
    expect(text.size.height, greaterThan(22 * 2));
    expect(text.didExceedMaxLines, isFalse);
    expect(target.height, text.size.height + 22);
    expect(tester.takeException(), isNull);

    final ring = tester.getRect(find.byType(PathGlyph).last);
    expect(ring.center.dy, target.top + 22);

    await tester.tap(find.text(long));
    await tester.pump();
    expect(opened, 1);
  });

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме архивированное намерение приглушено, '
        'его значок на рейке grip, а метка архива стоит после названия и '
        'переносится вместе с длинным', (tester) async {
      const long =
          'Научиться спокойно разговаривать с людьми о деньгах, '
          'обязанностях и ожиданиях';
      await tester.pumpWidget(
        _app(
          brightness,
          _head(
            source: _participant(_source, archived: true),
            target: _participant(long, archived: true),
          ),
        ),
      );

      final tone = Color.lerp(colors.p2, colors.grip, .5)!;
      final glyphs = tester.widgetList<PathGlyph>(find.byType(PathGlyph));
      expect(glyphs.map((glyph) => glyph.color), [colors.grip, colors.grip]);
      for (final name in [_source, long]) {
        _expectStyle(
          _style(tester, name),
          DoableType.title.copyWith(color: colors.muted),
        );
      }
      final badges = find.byType(BadgeArchived);
      expect(badges, findsNWidgets(2));
      expect(
        tester.widgetList<BadgeArchived>(badges).map((badge) => badge.word),
        everyElement('Архив'),
      );

      // Рядом с коротким названием метка стоит в space-2, после длинного
      // уходит на следующую строку в 2 под ним.
      final source = tester.getRect(find.text(_source));
      final sourceBadge = tester.getRect(badges.first);
      expect(sourceBadge.left - source.right, 8);
      expect(sourceBadge.center.dy, source.center.dy);
      final target = tester.getRect(find.text(long));
      final targetBadge = tester.getRect(badges.last);
      expect(targetBadge.top - target.bottom, 2);
      expect(targetBadge.left, target.left);

      // Линия связи остаётся её тоном: архивных намерений это не меняет.
      for (final (stroke, _) in _lines(tester)) {
        expect((stroke.kind as RelationStrokeNeed).color, tone);
      }
    });

    testWidgets('в $themeName теме архивированная связь серая: линия, ромб '
        'и кольцо grip, плитка на fill с приглушённым значком, слово muted '
        'с меткой архива, а строка под связью стоит в 34 от края', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          brightness,
          _head(
            kind: RelationHeadKind.can,
            priority: DoablePriority.p1,
            status: const RelationHeadArchived(
              note: 'Архивные связи остаются в сохранённых путях.',
            ),
          ),
        ),
      );

      final head = tester.getRect(find.byType(RelationHead));
      expect(
        tester
            .widgetList<PathGlyph>(find.byType(PathGlyph))
            .map((g) => g.color),
        [colors.grip, colors.grip],
      );
      for (final (stroke, _) in _lines(tester)) {
        expect(stroke.kind, isA<RelationStrokeCan>());
        expect((stroke.kind as RelationStrokeCan).color, colors.grip);
      }

      final decoration =
          tester.widget<DecoratedBox>(_tile()).decoration as BoxDecoration;
      expect(decoration.color, colors.fill);
      expect(
        tester
            .widget<DoableIcon>(
              find.descendant(of: _tile(), matching: find.byType(DoableIcon)),
            )
            .color,
        colors.muted,
      );
      _expectStyle(
        _style(tester, 'можно'),
        DoableType.section.copyWith(color: colors.muted),
      );
      final word = tester.getRect(find.text('можно'));
      final badge = tester.getRect(find.byType(BadgeArchived));
      expect(badge.left - word.right, 8);
      expect(badge.center.dy, word.center.dy);

      final note = tester.getRect(find.textContaining('Архивные связи'));
      final target = tester.getRect(_open(_target));
      expect(note.left - head.left, 34);
      expect(note.top - target.bottom, 2);
      expect(note.bottom, head.bottom);
      _expectStyle(
        _style(tester, 'Архивные связи остаются в сохранённых путях.'),
        DoableType.hint.copyWith(color: colors.muted),
      );
    });
  }

  testWidgets('у архивированной связи без строки под ней шапка кончается '
      'строкой связанного намерения', (tester) async {
    await tester.pumpWidget(
      _app(Brightness.light, _head(status: const RelationHeadArchived())),
    );

    final head = tester.getRect(find.byType(RelationHead));
    expect(head.bottom, tester.getRect(_open(_target)).bottom);
  });

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме клавиатура обводит пилюлю focus-ring без '
        'заливки её плоскости, и Enter выбирает её', (tester) async {
      final boundary = GlobalKey();
      final changes = <RelationHeadKind>[];
      await tester.pumpWidget(
        _app(
          brightness,
          _head(
            status: RelationHeadActive(
              kindSwitch: RelationHeadKindSwitch(
                label: 'Вид связи',
                onChange: changes.add,
              ),
            ),
          ),
          boundary: boundary,
        ),
      );
      final plane = tester.getRect(_plane('Можно'));
      Future<Color> pixel(double dx, double dy) =>
          _pixel(tester, boundary, plane.topLeft + Offset(dx, dy));

      // Кольцо лежит над плоскостью пилюли: зазор bg в 2, затем accent в 2.
      expect(await pixel(40, -1), isSameColorAs(_ground));
      expect(await pixel(40, -3), isSameColorAs(_ground));

      // Фокус обходит название исходного намерения, пилюлю «Нужно» и «Можно».
      for (var step = 0; step < 3; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      await tester.pumpAndSettle();

      expect(await pixel(40, -1), isSameColorAs(colors.bg));
      expect(await pixel(40, -3), isSameColorAs(colors.accent));
      // Плоскость пилюли остаётся прозрачной: тень поверх неё бы закрасила.
      expect(await pixel(3, 18), isSameColorAs(_ground));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(changes, [RelationHeadKind.can]);
    });
  }
}

RelationHeadParticipant _participant(
  String name, {
  bool archived = false,
  VoidCallback? onOpen,
}) => RelationHeadParticipant(
  name: name,
  semanticLabel:
      'Открыть страницу намерения: $name${archived ? '. В архиве' : ''}',
  onOpen: onOpen ?? () {},
  archived: archived,
);

String _kindName(RelationHeadKind kind) => switch (kind) {
  RelationHeadKind.need => 'Нужно',
  RelationHeadKind.can => 'Можно',
};

Widget _head({
  RelationHeadKind kind = RelationHeadKind.need,
  DoablePriority priority = DoablePriority.p2,
  RelationHeadParticipant? source,
  RelationHeadParticipant? target,
  RelationHeadStatus status = const RelationHeadActive(),
  RelationHeadMenu? menu,
}) => SizedBox(
  width: 400,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: RelationHead(
      kind: kind,
      priority: priority,
      source: source ?? _participant(_source),
      target: target ?? _participant(_target),
      status: status,
      menu: menu,
      kindName: _kindName,
      archivedWord: 'Архив',
    ),
  ),
);

/// Вертикальные отрезки линии связи сверху вниз с их границами.
List<(RelationStroke, Rect)> _lines(WidgetTester tester) {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is RelationStroke && widget.axis == RelationStrokeAxis.vertical,
  );
  return [
    for (final element in finder.evaluate())
      (
        element.widget as RelationStroke,
        tester.getRect(find.byWidget(element.widget)),
      ),
  ];
}

Finder _open(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(InkWell));

Finder _plane(String name) => find
    .ancestor(of: find.text(name), matching: find.byType(DecoratedBox))
    .first;

Color? _planeColor(WidgetTester tester, String name) =>
    (tester.widget<DecoratedBox>(_plane(name)).decoration as BoxDecoration)
        .color;

Finder _mark(String name) =>
    find.descendant(of: _plane(name), matching: find.byType(RelationKindMark));

RelationStrokeKind _markKind(WidgetTester tester, String name) =>
    tester.widget<RelationKindMark>(_mark(name)).kind;

Finder _tile() => find.byWidgetPredicate(
  (widget) =>
      widget is DecoratedBox &&
      (widget.decoration as BoxDecoration).shape == BoxShape.circle,
);

Finder _menuIcon() => find.byWidgetPredicate(
  (widget) => widget is DoableIcon && widget.icon == DoableIconData.more,
);

Finder _menuArea() =>
    find.ancestor(of: _menuIcon(), matching: find.byType(InkWell));

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

/// Цвет, на котором стоит шапка в тестах: не совпадает с `bg` ни одной темы,
/// поэтому заливка плоскости пилюли и зазор focus-ring различимы.
const _ground = Color(0xff00ff00);

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

Widget _app(Brightness brightness, Widget child, {GlobalKey? boundary}) =>
    MaterialApp(
      theme: doableTheme(brightness),
      home: Scaffold(
        body: RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: _ground,
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
