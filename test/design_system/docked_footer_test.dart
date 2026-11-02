import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/docked_footer.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app({EdgeInsets padding = EdgeInsets.zero, double textScale = 1}) =>
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: padding,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              bottomNavigationBar: DockedFooter(
                child: Button.primary(label: 'Добавить', onPressed: () {}),
              ),
            ),
          ),
        ),
      );

  testWidgets('плоскость raised с линией hairline сверху высотой nav-height '
      'и системным отступом держит кнопку на всю ширину с полями space-5', (
    tester,
  ) async {
    await tester.pumpWidget(app(padding: const EdgeInsets.only(bottom: 20)));

    final footer = tester.getRect(find.byType(DockedFooter));
    expect(footer.height, DoableMetrics.navHeight + 20);
    expect(footer.bottom, tester.view.physicalSize.height / 3);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(DockedFooter),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, DoableColors.light.raised);
    final line = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(DockedFooter),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (line.decoration as BoxDecoration).border,
      Border(top: BorderSide(color: DoableColors.light.hairline)),
    );
    final button = tester.getRect(find.byType(FilledButton));
    expect(button.left, DoableMetrics.space5);
    expect(button.right, footer.right - DoableMetrics.space5);
    expect(button.center.dy, footer.top + DoableMetrics.navHeight / 2);
  });

  testWidgets('с крупным шрифтом нижняя часть растёт вместе с кнопкой', (
    tester,
  ) async {
    await tester.pumpWidget(app(textScale: 4));

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(DockedFooter)).height,
      greaterThan(DoableMetrics.navHeight),
    );
  });
}
