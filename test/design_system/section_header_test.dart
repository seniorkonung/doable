import 'package:doable/src/design_system/components/section_header.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
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
    testWidgets('в $themeName теме заголовок высотой 44 ставит название, '
        'счётчик через space-2 и шеврон 18 ещё через space-2, а шеврон '
        'выходит на 2 в правое поле', (tester) async {
      await tester.pumpWidget(
        _app(brightness: brightness, child: _header(count: 12)),
      );

      final header = tester.getRect(find.byType(SectionHeader));
      expect(header.height, DoableMetrics.tapMin);
      final title = tester.getRect(find.text('Невыполненные'));
      final chip = tester.getRect(
        find.ancestor(of: find.text('12'), matching: find.byType(DecoratedBox)),
      );
      final chevron = tester.getRect(find.byType(DoableIcon));
      expect(title.left, header.left);
      expect(chip.left - title.right, closeTo(8, 0.001));
      expect(chevron.left - chip.right, closeTo(8, 0.001));
      expect(chevron.width, closeTo(18, 0.001));
      expect(chevron.height, closeTo(18, 0.001));
      expect(chevron.right - header.right, closeTo(2, 0.001));
      for (final part in [title, chip, chevron]) {
        expect(part.center.dy, header.center.dy);
      }

      final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(icon.icon, DoableIconData.chevronDown);
      expect(icon.color, colors.muted);
      final titleStyle = _style(tester, 'Невыполненные');
      expect(titleStyle.color, colors.ink);
      expect(titleStyle.fontSize, DoableType.section.fontSize);
      expect(titleStyle.fontWeight, DoableType.section.fontWeight);
      expect(titleStyle.height, DoableType.section.height);
    });

    testWidgets('в $themeName теме счётчик — плоскость fill высотой 24 с '
        'радиусом 12, тексты muted со стилем label и табличными '
        'цифрами', (tester) async {
      await tester.pumpWidget(
        _app(brightness: brightness, child: _header(count: 7)),
      );

      final chip = find.ancestor(
        of: find.text('7'),
        matching: find.byType(DecoratedBox),
      );
      final decoration = tester.widget<DecoratedBox>(chip).decoration;
      expect(decoration, isA<BoxDecoration>());
      expect((decoration as BoxDecoration).color, colors.fill);
      expect(decoration.borderRadius, BorderRadius.circular(12));
      final rect = tester.getRect(chip);
      expect(rect.height, 24);
      expect(rect.width, 24);

      final style = _style(tester, '7');
      expect(style.color, colors.muted);
      expect(style.fontSize, DoableType.label.fontSize);
      expect(style.fontWeight, DoableType.label.fontWeight);
      expect(style.height, DoableType.label.height);
      expect(style.fontFeatures, [const FontFeature.tabularFigures()]);
    });
  }

  testWidgets('счётчик шире двух знаков растёт, а у пустой секции показан 0', (
    tester,
  ) async {
    await tester.pumpWidget(_app(child: _header(count: 0)));
    expect(find.text('0'), findsOneWidget);
    final empty = tester.getSize(
      find.ancestor(of: find.text('0'), matching: find.byType(DecoratedBox)),
    );
    expect(empty, const Size(24, 24));

    await tester.pumpWidget(_app(child: _header(count: 1280)));
    final large = tester.getSize(
      find.ancestor(of: find.text('1280'), matching: find.byType(DecoratedBox)),
    );
    expect(large.width, greaterThan(24));
    expect(large.height, 24);
  });

  testWidgets('шеврон смотрит вниз у свёрнутой секции и вверх у раскрытой, '
      'а раскрытой секция считается по умолчанию', (tester) async {
    await tester.pumpWidget(_app(child: _header(open: false)));
    expect(_quarterTurns(tester), 0);

    await tester.pumpWidget(_app(child: _header(open: true)));
    expect(_quarterTurns(tester), 2);

    await tester.pumpWidget(
      _app(
        child: SectionHeader(title: 'Выполненные', count: 1, onToggle: () {}),
      ),
    );
    expect(_quarterTurns(tester), 2);
  });

  testWidgets('нажатие в любом месте заголовка вызывает обработчик, а '
      'касание за его границей — нет', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(_app(child: _header(onToggle: () => toggles++)));

    final header = tester.getRect(find.byType(SectionHeader));
    await tester.tap(find.text('Невыполненные'));
    await tester.tap(find.text('3'));
    await tester.tap(find.byType(DoableIcon));
    await tester.tapAt(Offset(header.center.dx, header.top + 1));
    await tester.tapAt(Offset(header.center.dx, header.bottom - 1));
    expect(toggles, 5);

    await tester.tapAt(Offset(header.center.dx, header.bottom + 1));
    expect(toggles, 5);
  });

  testWidgets('заголовок — одна кнопка: диктор читает название и счётчик '
      'как заголовок с состоянием раскрытости', (tester) async {
    final semantics = tester.ensureSemantics();

    for (final open in [false, true]) {
      await tester.pumpWidget(_app(child: _header(open: open)));
      expect(
        tester.getSemantics(find.byType(SectionHeader)),
        matchesSemantics(
          label: 'Невыполненные\n3',
          isHeader: true,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasExpandedState: true,
          isExpanded: open,
        ),
      );
    }
    semantics.dispose();
  });

  testWidgets('при тексте масштаба 2 длинное название переносится, а '
      'заголовок растёт без переполнения', (tester) async {
    const title = 'Невыполненные дневные выборы на выбранный день';
    await tester.pumpWidget(
      _app(textScale: 2, width: 280, child: _header(title: title, count: 128)),
    );

    expect(tester.takeException(), isNull);
    final header = tester.getRect(find.byType(SectionHeader));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.height, greaterThan(DoableType.section.height! * 30));
    expect(header.height, greaterThan(DoableMetrics.tapMin));
    expect(header.right, lessThanOrEqualTo(280));
  });
}

SectionHeader _header({
  String title = 'Невыполненные',
  int count = 3,
  bool open = true,
  VoidCallback? onToggle,
}) => SectionHeader(
  title: title,
  count: count,
  open: open,
  onToggle: onToggle ?? () {},
);

int _quarterTurns(WidgetTester tester) =>
    tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns;

TextStyle _style(WidgetTester tester, String text) => tester
    .renderObject<RenderParagraph>(
      find.descendant(
        of: find.text(text),
        matching: find.byType(RichText),
        matchRoot: true,
      ),
    )
    .text
    .style!;

Widget _app({
  required Widget child,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  double width = 800,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Column(children: [child]),
          ),
        ),
      ),
    ),
  ),
);
