import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
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
          header: const CatalogHeader(
            title: 'Действия',
            count: 0,
            summary: 'Создание, сначала новые',
          ),
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

      final pill = find.ancestor(
        of: find.text('Создание, сначала новые'),
        matching: find.byType(DecoratedBox),
      );
      expect(tester.getSize(pill).height, 32);
      expect(
        tester.getRect(pill).right,
        tester.getRect(find.byType(CatalogHeader)).right,
      );
      expect(
        (tester.widget<DecoratedBox>(pill).decoration as BoxDecoration).color,
        colors.fill,
      );
      final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(icon.icon, DoableIconData.sliders);
      expect(icon.size, 16);
      expect(icon.color, colors.muted);
      final summaryStyle = _style(tester, 'Создание, сначала новые');
      expect(summaryStyle.color, colors.ink);
      expect(summaryStyle.fontSize, DoableType.caption.fontSize);
      expect(
        tester.widget<Text>(find.text('Создание, сначала новые')).maxLines,
        1,
      );
    });

    testWidgets('в $themeName теме весь ряд — одна кнопка с названием '
        'и признаком раскрытия потребителя', (tester) async {
      final semantics = tester.ensureSemantics();
      const label = 'Показать и упорядочить. Действия, 13. Сначала новые.';
      var taps = 0;
      for (final expanded in [false, true]) {
        await tester.pumpWidget(
          _app(
            brightness: brightness,
            header: CatalogHeader(
              title: 'Действия',
              count: 13,
              summary: 'Создание, сначала новые',
              label: label,
              expanded: expanded,
              onOpen: () => taps++,
            ),
          ),
        );

        final header = find.byType(CatalogHeader);
        expect(find.semantics.byFlag(SemanticsFlag.isButton), findsOneWidget);
        expect(
          tester.getSemantics(header),
          isSemantics(
            label: label,
            isButton: true,
            hasTapAction: true,
            hasExpandedState: true,
            isExpanded: expanded,
            children: const [],
          ),
        );
        final rect = tester.getRect(header);
        expect(rect.width, 360);
        expect(rect.height, greaterThanOrEqualTo(DoableMetrics.tapMin));
        for (final point in [
          rect.topLeft + const Offset(1, 1),
          tester.getCenter(find.text('Действия')),
          rect.center,
          tester.getCenter(find.text('Создание, сначала новые')),
          rect.bottomRight - const Offset(1, 1),
        ]) {
          final before = taps;
          await tester.tapAt(point);
          expect(taps, before + 1);
        }
      }
      semantics.dispose();
    });
  }

  testWidgets('многозначное число расширяет плашку, не выходя за её края', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        header: const CatalogHeader(
          title: 'Намерения',
          count: 1234,
          summary: 'Название, от А до Я',
        ),
      ),
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
      _app(
        header: const CatalogHeader(
          title: 'Действия',
          count: 13,
          summary: 'Создание, сначала новые',
        ),
      ),
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
        header: CatalogHeader(
          title: 'Намерения',
          count: 13,
          summary: 'Изменение, сначала старые — длинная сводка сортировки',
          label: 'Показать и упорядочить. Намерения, 13. Сначала старые.',
          onOpen: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final chip = tester.getRect(_chip);
    final count = tester.getRect(find.text('13'));
    expect(chip.height, greaterThanOrEqualTo(count.height));
    expect(chip.contains(count.topLeft) && chip.contains(count.center), isTrue);
  });

  testWidgets(
    'до подтверждения выдачи заголовок и сортировка видны без плашки числа',
    (tester) async {
      await tester.pumpWidget(
        _app(
          header: const CatalogHeader(
            title: 'Все',
            summary: 'Название, от А до Я',
          ),
        ),
      );

      expect(find.text('Все'), findsOneWidget);
      expect(find.text('Название, от А до Я'), findsOneWidget);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Название, от А до Я'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(_chip, findsNothing);
      expect(find.text('0'), findsNothing);
    },
  );
}

final _chip = find.ancestor(
  of: find.textContaining(RegExp(r'^\d+$')),
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
