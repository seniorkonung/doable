import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_text_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = TextStyle(fontSize: 16, height: 1.5);

void main() {
  testWidgets(
    'высота совпадает с высотой виджета Text той же ширины в масштабе '
    'текста системы, в том числе с переносом',
    (tester) async {
      for (final (textScale, width) in [
        (1.0, 200.0),
        (2.5, 200.0),
        (2.5, 40.0),
      ]) {
        await _pumpTexts(
          tester,
          textScale: textScale,
          width: width,
          texts: ['7', '28', 'Сегодня'],
        );

        final measured = tallestTextHeight(
          _context(tester),
          texts: ['7', '28', 'Сегодня'],
          style: _style,
          maxWidth: width,
        );

        expect(
          measured,
          _renderedHeights(tester).reduce((a, b) => a > b ? a : b),
          reason: 'масштаб $textScale, ширина $width',
        );
      }
    },
  );

  testWidgets('крупный текст выше обычного, а перенос добавляет строки', (
    tester,
  ) async {
    Future<double> heightOf(double textScale, double width) async {
      await _pumpTexts(
        tester,
        textScale: textScale,
        width: width,
        texts: const [],
      );
      return tallestTextHeight(
        _context(tester),
        texts: ['28'],
        style: _style,
        maxWidth: width,
      );
    }

    final line = await heightOf(1, 200);
    expect(line, 24);
    expect(await heightOf(2.5, 200), 2.5 * line);
    // Две цифры шириной в 40 пикселей тестового шрифта каждая не помещаются в
    // одну строку шириной 50.
    expect(await heightOf(2.5, 50), 2 * 2.5 * line);
  });

  testWidgets('учитывает системную настройку жирного текста', (tester) async {
    await _pumpTexts(
      tester,
      textScale: 1,
      width: 100,
      texts: ['Сегодня'],
      boldText: true,
    );

    expect(
      tallestTextHeight(
        _context(tester),
        texts: ['Сегодня'],
        style: _style,
        maxWidth: 100,
      ),
      _renderedHeights(tester).single,
    );
    final rendered = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    expect(rendered.text.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('отрицательную ширину измеряет как нулевую', (tester) async {
    await _pumpTexts(tester, textScale: 1, width: 100, texts: const []);

    expect(
      tallestTextHeight(
        _context(tester),
        texts: ['28'],
        style: _style,
        maxWidth: -4,
      ),
      tallestTextHeight(
        _context(tester),
        texts: ['28'],
        style: _style,
        maxWidth: 0,
      ),
    );
  });
}

/// Показывает [texts] виджетами `Text` в колонке ширины [width].
Future<void> _pumpTexts(
  WidgetTester tester, {
  required double textScale,
  required double width,
  required List<String> texts,
  bool boldText = false,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(boldText: boldText);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: const ValueKey('колонка'),
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final text in texts)
                Text(text, textAlign: TextAlign.center, style: _style),
            ],
          ),
        ),
      ),
    ),
  );
}

BuildContext _context(WidgetTester tester) =>
    tester.element(find.byKey(const ValueKey('колонка')));

List<double> _renderedHeights(WidgetTester tester) => [
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.byType(RichText),
  ))
    paragraph.size.height,
];
