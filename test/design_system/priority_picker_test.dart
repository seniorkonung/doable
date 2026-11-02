import 'dart:ui' show FontFeature, ImageByteFormat;

import 'package:doable/src/design_system/components/priority_picker.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _pillLabels = {
  DoablePriority.p1: 'Приоритет P1, высший',
  DoablePriority.p2: 'Приоритет P2',
  DoablePriority.p3: 'Приоритет P3',
  DoablePriority.p4: 'Приоритет P4, низший',
};

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
    testWidgets('в $themeName теме пилюли P1–P4 касаются друг друга, '
        'выбранная лежит на fill, а цвет приоритета остаётся только в '
        'кольце', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          PriorityPicker(
            value: DoablePriority.p2,
            onChange: (_) {},
            label: 'Приоритет',
            name: _name,
            itemLabel: _itemLabel,
          ),
        ),
      );

      final priorityColors = {
        DoablePriority.p1: colors.p1,
        DoablePriority.p2: colors.p2,
        DoablePriority.p3: colors.p3,
        DoablePriority.p4: colors.p4,
      };
      var previousRight = 0.0;
      for (final priority in DoablePriority.values) {
        final name = _name(priority);
        final chosen = priority == DoablePriority.p2;
        final area = tester.getRect(_area(name));
        final plane = tester.getRect(_plane(name));
        final ring = tester.getRect(_ring(name));
        final text = tester.getRect(find.text(name));

        expect(area.left, previousRight, reason: name);
        previousRight = area.right;
        expect(area.height, 44, reason: name);
        expect(plane.height, 36, reason: name);
        expect(plane.center.dy, area.center.dy, reason: name);
        expect(plane.left, area.left, reason: name);
        expect(plane.right, area.right, reason: name);
        expect(ring.size, const Size.square(16), reason: name);
        expect(ring.left - plane.left, 7, reason: name);
        expect(ring.center.dy, plane.center.dy, reason: name);
        expect(text.left - ring.right, 4, reason: name);
        expect(plane.right - text.right, 8, reason: name);

        final planeDecoration =
            tester.widget<DecoratedBox>(_plane(name)).decoration
                as BoxDecoration;
        expect(planeDecoration.color, chosen ? colors.fill : isNull);
        expect(planeDecoration.borderRadius, BorderRadius.circular(9999));
        expect(planeDecoration.border, isNull, reason: name);

        final ringDecoration =
            tester.widget<DecoratedBox>(_ring(name)).decoration
                as BoxDecoration;
        final color = priorityColors[priority]!;
        expect(ringDecoration.shape, BoxShape.circle, reason: name);
        expect(
          ringDecoration.border,
          Border.all(color: color, width: 2),
          reason: name,
        );
        expect(
          ringDecoration.color,
          priority == DoablePriority.p4 ? isNull : color.withValues(alpha: .12),
          reason: name,
        );

        _expectStyle(
          _style(tester, name),
          (chosen ? DoableType.label : DoableType.caption).copyWith(
            color: chosen ? colors.ink : colors.muted,
          ),
        );
        expect(_style(tester, name).fontFeatures, [
          const FontFeature.tabularFigures(),
        ]);
      }
    });
  }

  testWidgets(
    'нажатие на другую пилюлю сообщает приоритет, а на выбранную ничего не '
    'делает',
    (tester) async {
      final changes = <DoablePriority>[];
      await tester.pumpWidget(
        _app(
          Brightness.light,
          PriorityPicker(
            value: DoablePriority.p3,
            onChange: changes.add,
            label: 'Приоритет',
            name: _name,
            itemLabel: _itemLabel,
          ),
        ),
      );

      await tester.tap(find.text('P3'));
      await tester.pump();
      expect(changes, isEmpty);

      await tester.tap(find.text('P1'));
      await tester.tap(find.text('P4'));
      await tester.pump();
      expect(changes, [DoablePriority.p1, DoablePriority.p4]);
    },
  );

  testWidgets(
    'диктор слышит название группы, порядок приоритетов и выбранную пилюлю, '
    'а без onChange пилюли недоступны',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final changes = <DoablePriority>[];
      var enabled = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        _app(
          Brightness.light,
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return PriorityPicker(
                value: DoablePriority.p2,
                onChange: enabled ? changes.add : null,
                label: 'Приоритет',
                name: _name,
                itemLabel: _itemLabel,
              );
            },
          ),
        ),
      );

      Matcher pill(DoablePriority priority, {required bool enabled}) {
        final chosen = priority == DoablePriority.p2;
        return matchesSemantics(
          label: _itemLabel(priority, chosen),
          isButton: true,
          hasEnabledState: true,
          isEnabled: enabled,
          hasSelectedState: true,
          isSelected: chosen,
          isInMutuallyExclusiveGroup: true,
          isFocusable: enabled,
          hasTapAction: enabled,
          hasFocusAction: enabled,
        );
      }

      expect(
        tester.getSemantics(find.bySemanticsLabel('Приоритет')),
        matchesSemantics(
          label: 'Приоритет',
          children: [
            for (final priority in DoablePriority.values)
              pill(priority, enabled: true),
          ],
        ),
      );

      rebuild(() => enabled = false);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Приоритет')),
        matchesSemantics(
          label: 'Приоритет',
          children: [
            for (final priority in DoablePriority.values)
              pill(priority, enabled: false),
          ],
        ),
      );
      await tester.tap(find.text('P4'));
      await tester.pump();
      expect(changes, isEmpty);
      semantics.dispose();
    },
  );

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме клавиатура обводит пилюлю focus-ring без '
        'заливки плоскости, и Enter выбирает её', (tester) async {
      final boundary = GlobalKey();
      final changes = <DoablePriority>[];
      await tester.pumpWidget(
        _app(
          brightness,
          PriorityPicker(
            value: DoablePriority.p1,
            onChange: changes.add,
            label: 'Приоритет',
            name: _name,
            itemLabel: _itemLabel,
          ),
          boundary: boundary,
        ),
      );
      final plane = tester.getRect(_plane('P2'));
      Future<Color> pixel(double dx, double dy) =>
          _pixel(tester, boundary, plane.topLeft + Offset(dx, dy));

      // Кольцо лежит над плоскостью пилюли: зазор bg в 2, затем accent в 2.
      expect(await pixel(20, -1), isSameColorAs(_ground));
      expect(await pixel(20, -3), isSameColorAs(_ground));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(await pixel(20, -1), isSameColorAs(colors.bg));
      expect(await pixel(20, -3), isSameColorAs(colors.accent));
      // Плоскость пилюли остаётся прозрачной: тень поверх неё бы закрасила.
      expect(await pixel(3, 18), isSameColorAs(_ground));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(changes, [DoablePriority.p2]);
    });
  }
}

String _name(DoablePriority priority) => switch (priority) {
  DoablePriority.p1 => 'P1',
  DoablePriority.p2 => 'P2',
  DoablePriority.p3 => 'P3',
  DoablePriority.p4 => 'P4',
};

String _itemLabel(DoablePriority priority, bool chosen) =>
    '${_pillLabels[priority]}${chosen ? ', выбран' : ''}';

/// Цвет, на котором стоит пикер в тестах: не совпадает с `bg` ни одной темы,
/// поэтому заливка плоскости пилюли и зазор focus-ring различимы.
const _ground = Color(0xff00ff00);

Finder _area(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(InkWell));

Finder _plane(String name) => find
    .ancestor(of: find.text(name), matching: find.byType(DecoratedBox))
    .first;

Finder _ring(String name) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(InkWell)),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        (widget.decoration as BoxDecoration).shape == BoxShape.circle,
  ),
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
