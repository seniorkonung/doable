import 'package:doable/src/design_system/components/flow_steps.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
    testWidgets('в $themeName теме текущий шаг выделен кругом accent и '
        'отметкой, а остальные — кольцом hairline', (tester) async {
      await tester.pumpWidget(_app(_steps(), brightness: brightness));

      final current = _circle(tester, '1');
      expect(current.shape, BoxShape.circle);
      expect(current.color, colors.accent);
      expect(current.border, isNull);
      for (final number in ['2', '3']) {
        final other = _circle(tester, number);
        expect(other.shape, BoxShape.circle);
        expect(other.color, isNull);
        expect(other.border, Border.all(color: colors.hairline, width: 1.5));
      }
      for (final number in ['1', '2', '3']) {
        expect(tester.getSize(_circleBox(number)), const Size.square(28));
      }

      final numberStyle = DoableType.label.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      _expectStyle(
        _style(tester, '1'),
        numberStyle.copyWith(color: colors.onAccent),
      );
      _expectStyle(
        _style(tester, '2'),
        numberStyle.copyWith(color: colors.muted),
      );
      _expectStyle(
        _style(tester, 'Исходное намерение'),
        DoableType.section.copyWith(color: colors.ink),
      );
      _expectStyle(
        _style(tester, 'Шаги вниз до действия'),
        DoableType.row.copyWith(color: colors.ink, letterSpacing: -0.15),
      );
      _expectStyle(
        _style(tester, 'Вы здесь'),
        DoableType.label.copyWith(color: colors.accent),
      );
      _expectStyle(
        _style(tester, 'Каждый следующий шаг нужен предыдущему'),
        DoableType.hint.copyWith(color: colors.muted),
      );
      expect(find.text('Вы здесь'), findsOneWidget);

      final lines = _lines(tester, colors.hairline);
      expect(lines, hasLength(2));
      for (final (index, line) in lines.indexed) {
        expect(line.width, 2);
        expect(line.center.dx, tester.getCenter(_circleBox('1')).dx);
        expect(line.top, tester.getRect(_circleBox('${index + 1}')).bottom);
        expect(line.bottom, tester.getRect(_circleBox('${index + 2}')).top);
      }
    });
  }

  testWidgets('первая строка названия стоит по центру круга через space-3, '
      'а отметка и пояснение идут под ней', (tester) async {
    await tester.pumpWidget(_app(_steps()));

    for (final (number, title) in [
      ('1', 'Исходное намерение'),
      ('2', 'Шаги вниз до действия'),
    ]) {
      final circle = tester.getRect(_circleBox(number));
      final text = tester.getRect(find.text(title));
      expect(text.left - circle.right, 12);
      expect(text.center.dy, circle.center.dy);
    }
    final title = tester.getRect(find.text('Исходное намерение'));
    final mark = tester.getRect(find.text('Вы здесь'));
    expect(mark.top - title.bottom, 2);
    expect(mark.left, title.left);
    final note = tester.getRect(
      find.text('Каждый следующий шаг нужен предыдущему'),
    );
    expect(
      note.top - tester.getRect(find.text('Шаги вниз до действия')).bottom,
      2,
    );
  });

  testWidgets('отметка стоит у переданного текущего шага, даже если он '
      'не первый', (tester) async {
    await tester.pumpWidget(
      _app(
        const FlowSteps(
          steps: [
            FlowStep(title: 'Первый'),
            FlowStep(title: 'Второй'),
          ],
          current: 1,
          currentMark: 'Сейчас',
        ),
      ),
    );

    expect(_circle(tester, '1').color, isNull);
    expect(_circle(tester, '2').color, DoableColors.light.accent);
    expect(_style(tester, 'Второй').fontWeight, DoableType.section.fontWeight);
    expect(
      tester.getRect(find.text('Сейчас')).top,
      greaterThan(tester.getRect(find.text('Второй')).bottom),
    );
    expect(_lines(tester, DoableColors.light.hairline), hasLength(1));
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets('при масштабе текста $textScale длинные название и пояснение '
        'переносятся без обрезки и переполнения', (tester) async {
      final semantics = tester.ensureSemantics();
      const longTitle =
          'Дата, время, приоритет и заметка к новому дневному выбору, '
          'которые можно поменять позже';
      const longNote =
          'Необязательно: зачем нужно действие, шаг за шагом вверх до самой '
          'далёкой причины';
      await tester.pumpWidget(
        _app(
          const FlowSteps(
            steps: [
              FlowStep(title: longTitle, note: longNote),
              FlowStep(title: 'Конечное действие'),
            ],
            current: 0,
            currentMark: 'Вы здесь',
          ),
          textScale: textScale,
        ),
      );

      expect(tester.takeException(), isNull);
      final body = tester.getRect(find.byType(FlowSteps));
      for (final text in [longTitle, 'Вы здесь', longNote]) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.textScaler.scale(13), 13 * textScale);
        final rect = tester.getRect(find.text(text));
        expect(rect.right, lessThanOrEqualTo(body.right));
        expect(rect.bottom, lessThanOrEqualTo(body.bottom));
      }
      for (final text in [longTitle, longNote]) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          greaterThan(tester.getSize(find.text(text)).width),
        );
      }

      final circle = tester.getRect(_circleBox('1'));
      final number = tester.getRect(find.text('1'));
      expect(circle.contains(number.topLeft), isTrue);
      expect(circle.contains(number.bottomRight), isTrue);
      final titleLine =
          DoableType.section.fontSize! * DoableType.section.height! * textScale;
      expect(
        tester.getRect(find.text(longTitle)).top + titleLine / 2,
        closeTo(circle.center.dy, 0.001),
      );
      expect(
        tester.getRect(_circleBox('2')).top,
        greaterThanOrEqualTo(tester.getRect(find.text(longNote)).bottom),
      );
      semantics.dispose();
    });
  }

  testWidgets('экранный диктор слышит каждый шаг одним узлом без нажатия: '
      'номер, название, отметку и пояснение', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(_steps()));

    expect(
      tester.getSemantics(find.text('Исходное намерение')),
      matchesSemantics(label: '1\nИсходное намерение\nВы здесь'),
    );
    expect(
      tester.getSemantics(find.text('Шаги вниз до действия')),
      matchesSemantics(
        label:
            '2\nШаги вниз до действия\n'
            'Каждый следующий шаг нужен предыдущему',
      ),
    );
    expect(
      tester.getSemantics(find.text('Дата, время, приоритет и заметка')),
      matchesSemantics(label: '3\nДата, время, приоритет и заметка'),
    );
    semantics.dispose();
  });
}

FlowSteps _steps() => const FlowSteps(
  steps: [
    FlowStep(title: 'Исходное намерение'),
    FlowStep(
      title: 'Шаги вниз до действия',
      note: 'Каждый следующий шаг нужен предыдущему',
    ),
    FlowStep(title: 'Дата, время, приоритет и заметка'),
  ],
  current: 0,
  currentMark: 'Вы здесь',
);

Finder _circleBox(String number) => find.ancestor(
  of: find.text(number),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).shape == BoxShape.circle,
  ),
);

BoxDecoration _circle(WidgetTester tester, String number) =>
    tester.widget<DecoratedBox>(_circleBox(number)).decoration as BoxDecoration;

List<Rect> _lines(WidgetTester tester, Color color) => [
  for (final element
      in find
          .byWidgetPredicate(
            (widget) => widget is ColoredBox && widget.color == color,
          )
          .evaluate())
    tester.getRect(find.byWidget(element.widget)),
]..sort((a, b) => a.top.compareTo(b.top));

TextStyle _style(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

void _expectStyle(TextStyle actual, TextStyle expected) {
  expect(actual.color, expected.color);
  expect(actual.fontFamily, expected.fontFamily);
  expect(actual.fontSize, expected.fontSize);
  expect(actual.fontWeight, expected.fontWeight);
  expect(actual.height, expected.height);
  expect(actual.letterSpacing, expected.letterSpacing);
  expect(actual.fontFeatures, expected.fontFeatures);
}

/// Ширина тела листа на телефоне 360 dp: поля листа 12 и тела 8.
Widget _app(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: 320, child: child),
        ),
      ),
    ),
  ),
);
