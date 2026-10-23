import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме заголовок section цвета ink, а через '
        'space-2 — плашка fill высотой 24 с углами radius-sm и числом label '
        'цвета muted', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          header: const CatalogHeader(title: 'Действия', count: 0),
        ),
      );

      final titleStyle = _style(tester, 'Действия');
      expect(titleStyle.color, colors.ink);
      expect(titleStyle.fontSize, DoableType.section.fontSize);
      expect(titleStyle.fontWeight, DoableType.section.fontWeight);
      expect(titleStyle.height, DoableType.section.height);

      final countStyle = _style(tester, '0');
      expect(countStyle.color, colors.muted);
      expect(countStyle.fontSize, DoableType.label.fontSize);
      expect(countStyle.fontWeight, DoableType.label.fontWeight);

      final chip = tester.getRect(_chip);
      expect(chip.height, 24);
      expect(chip.width, greaterThanOrEqualTo(24));
      expect(chip.left - tester.getRect(find.text('Действия')).right, 8);
      expect(tester.getCenter(find.text('0')), chip.center);
      expect(
        tester.widget<DecoratedBox>(_chip).decoration,
        BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(DoableMetrics.radiusSm),
        ),
      );
    });
  }

  testWidgets('многозначное число расширяет плашку, не выходя за её края', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(header: const CatalogHeader(title: 'Намерения', count: 1234)),
    );

    final chip = tester.getRect(_chip);
    final count = tester.getRect(find.text('1234'));
    expect(chip.height, 24);
    expect(chip.width, greaterThan(24));
    expect(count.left - chip.left, 7);
    expect(chip.right - count.right, 7);
  });

  testWidgets('заголовок объявляется заголовком, а число читается после '
      'него', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(header: const CatalogHeader(title: 'Действия', count: 13)),
    );

    expect(
      tester.getSemantics(find.text('Действия')),
      isSemantics(label: 'Действия', isHeader: true),
    );
    expect(
      tester.getSemantics(find.text('13')),
      isSemantics(label: '13', isHeader: false),
    );
    expect(find.semantics.byFlag(SemanticsFlag.isButton), findsNothing);
    semantics.dispose();
  });

  testWidgets('с текстом масштаба 2 плашка растёт вместе с числом без '
      'переполнения', (tester) async {
    await tester.pumpWidget(
      _app(
        textScale: 2,
        header: const CatalogHeader(title: 'Намерения', count: 13),
      ),
    );

    expect(tester.takeException(), isNull);
    final chip = tester.getRect(_chip);
    final count = tester.getRect(find.text('13'));
    expect(chip.height, greaterThanOrEqualTo(count.height));
    expect(chip.contains(count.topLeft) && chip.contains(count.center), isTrue);
  });
}

final _chip = find.descendant(
  of: find.byType(CatalogHeader),
  matching: find.byType(DecoratedBox),
);

TextStyle _style(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

Widget _app({
  required CatalogHeader header,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 360, child: header),
      ),
    ),
  ),
);
