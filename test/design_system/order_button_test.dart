import 'dart:ui' as ui;

import 'package:doable/src/design_system/components/order_button.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('оба направления показывают соответствующий значок 20 в круге '
      '44 с цветами темы и без видимой подписи', (tester) async {
    for (final (direction, icon, brightness, colors) in [
      (
        OrderDirection.descending,
        DoableIconData.sortDesc,
        Brightness.light,
        DoableColors.light,
      ),
      (
        OrderDirection.ascending,
        DoableIconData.sortAsc,
        Brightness.dark,
        DoableColors.dark,
      ),
    ]) {
      await tester.pumpWidget(
        _app(direction: direction, brightness: brightness),
      );
      await tester.pumpAndSettle();

      final button = tester.getRect(find.byType(OrderButton));
      expect(button.size, const Size.square(44));
      final glyph = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(glyph.icon, icon);
      expect(glyph.color, colors.ink);
      expect(tester.getSize(find.byType(DoableIcon)), const Size.square(20));
      expect(tester.getCenter(find.byType(DoableIcon)), button.center);
      expect(find.byType(Text), findsNothing);
      final surface = tester.widget<Material>(
        find.descendant(
          of: find.byType(OrderButton),
          matching: find.byType(Material),
        ),
      );
      expect(surface.color, colors.fill);
      expect(surface.shape, const CircleBorder());
    }
  });

  testWidgets('название потребителя обновляется, касание и команда диктора '
      'передаются обработчику', (tester) async {
    final semantics = tester.ensureSemantics();
    var presses = 0;
    await tester.pumpWidget(_app(onPressed: () => presses++));

    expect(
      tester.getSemantics(find.bySemanticsLabel(_descendingLabel)),
      matchesSemantics(
        label: _descendingLabel,
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(find.byType(OrderButton));
    expect(presses, 1);

    await tester.pumpWidget(
      _app(
        direction: OrderDirection.ascending,
        label: _ascendingLabel,
        onPressed: () => presses++,
      ),
    );
    expect(find.bySemanticsLabel(_descendingLabel), findsNothing);
    final node = tester.getSemantics(find.bySemanticsLabel(_ascendingLabel));
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
    expect(presses, 2);
    semantics.dispose();
  });

  testWidgets('Tab показывает кольцо фокуса, Enter и пробел передают нажатие, '
      'а касание убирает кольцо', (tester) async {
    final boundaryKey = GlobalKey();
    var presses = 0;
    await tester.pumpWidget(
      _app(boundaryKey: boundaryKey, onPressed: () => presses++),
    );
    await tester.pumpAndSettle();
    expect(await _ringColors(tester, boundaryKey), [
      DoableColors.light.bg,
      DoableColors.light.bg,
    ]);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(await _ringColors(tester, boundaryKey), [
      DoableColors.light.accent,
      DoableColors.light.bg,
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(presses, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(presses, 2);

    await tester.tap(find.byType(OrderButton));
    await tester.pumpAndSettle();
    expect(presses, 3);
    expect(await _ringColors(tester, boundaryKey), [
      DoableColors.light.bg,
      DoableColors.light.bg,
    ]);
  });
}

const _descendingLabel =
    'Порядок: сначала новые. Переключить на сначала старые';
const _ascendingLabel = 'Порядок: сначала старые. Переключить на сначала новые';

Widget _app({
  OrderDirection direction = OrderDirection.descending,
  String label = _descendingLabel,
  Brightness brightness = Brightness.light,
  VoidCallback? onPressed,
  GlobalKey? boundaryKey,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: Center(
      child: RepaintBoundary(
        key: boundaryKey,
        child: ColoredBox(
          color: brightness == Brightness.light
              ? DoableColors.light.bg
              : DoableColors.dark.bg,
          child: SizedBox.square(
            dimension: 60,
            child: Center(
              child: OrderButton(
                direction: direction,
                label: label,
                onPressed: onPressed ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<List<Color>> _ringColors(WidgetTester tester, GlobalKey key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      // Центр круга — (30, 30), левый край — 8. Кольцо занимает 4–8:
      // внешние два пикселя accent, внутренние два — bg.
      return [
        for (final x in [5, 7])
          Color.fromARGB(
            bytes.getUint8((30 * image.width + x) * 4 + 3),
            bytes.getUint8((30 * image.width + x) * 4),
            bytes.getUint8((30 * image.width + x) * 4 + 1),
            bytes.getUint8((30 * image.width + x) * 4 + 2),
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}
