import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме метка — плитка 22×20 на bg с углами '
        'radius-xs и иконкой 14 цвета ink по центру', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          child: const Badge.mark(icon: DoableIconData.bolt),
        ),
      );

      final mark = tester.getRect(find.byType(Badge));
      expect(mark.size, const Size(22, 20));
      final ground = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(Badge),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        ground.decoration,
        BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
        ),
      );
      final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(icon.icon, DoableIconData.bolt);
      expect(icon.size, 14);
      expect(icon.color, colors.ink);
      expect(tester.getCenter(find.byType(DoableIcon)), mark.center);
    });
  }

  testWidgets('метка не создаёт узла экранного диктора', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Прогулка',
          child: const Badge.mark(icon: DoableIconData.bolt),
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(Badge));
    expect(node.label, 'Прогулка');
    expect(node.childrenCount, 0);
    semantics.dispose();
  });
}

Widget _app({
  required Widget child,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(body: Center(child: child)),
);
