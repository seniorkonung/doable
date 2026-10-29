import 'package:doable/src/design_system/components/archived_fold.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _above = ValueKey('above');

void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме кнопка высотой tap-min стоит у левого края, '
        'занимает в списке 36, а значок 14, подпись, число и шеврон 16 идут '
        'через 6 в space-1 от края', (tester) async {
      await tester.pumpWidget(
        _app(brightness: brightness, child: _fold(count: 12)),
      );

      final fold = tester.getRect(find.byType(ArchivedFold));
      final button = tester.getRect(find.byType(TextButton));
      expect(fold.height, 36);
      expect(button.height, DoableMetrics.tapMin);
      expect(button.left, fold.left);
      expect(button.top, fold.top - 4);
      expect(button.bottom, fold.bottom + 4);

      final icons = tester.widgetList<DoableIcon>(find.byType(DoableIcon));
      expect(
        [for (final icon in icons) (icon.icon, icon.size, icon.color)],
        [
          (DoableIconData.archive, 14.0, colors.muted),
          (DoableIconData.chevronDown, 16.0, colors.muted),
        ],
      );
      final archive = tester.getRect(find.byType(DoableIcon).first);
      final word = tester.getRect(find.text('Архив'));
      final count = tester.getRect(find.text('12'));
      final chevron = tester.getRect(find.byType(DoableIcon).last);
      expect(archive.left - button.left, DoableMetrics.space1);
      expect(word.left - archive.right, 6);
      expect(count.left - word.right, 6);
      expect(chevron.left - count.right, 6);
      expect(button.right - chevron.right, DoableMetrics.space1);
      for (final part in [archive, word, count, chevron]) {
        expect(part.center.dy, button.center.dy);
      }

      for (final text in ['Архив', '12']) {
        final style = _style(tester, text);
        expect(style.color, colors.muted);
        expect(style.fontSize, DoableType.label.fontSize);
        expect(style.fontWeight, DoableType.label.fontWeight);
        expect(style.height, DoableType.label.height);
      }
      expect(_style(tester, '12').fontFeatures, [
        const FontFeature.tabularFigures(),
      ]);
    });
  }

  testWidgets('шеврон смотрит вниз у свёрнутого архива и вверх у раскрытого, '
      'а поворот между ними анимирован', (tester) async {
    await tester.pumpWidget(_app(child: _fold()));
    expect(_turns(tester), 0);

    await tester.pumpWidget(_app(child: _fold(open: true)));
    await tester.pump(const Duration(milliseconds: 60));
    expect(_turns(tester), inExclusiveRange(0, .5));
    await tester.pumpAndSettle();
    expect(_turns(tester), .5);

    await tester.pumpWidget(_app(child: _fold()));
    await tester.pumpAndSettle();
    expect(_turns(tester), 0);
  });

  testWidgets('при отключённых анимациях шеврон поворачивается сразу', (
    tester,
  ) async {
    await tester.pumpWidget(_app(child: _fold(), disableAnimations: true));
    await tester.pumpWidget(
      _app(child: _fold(open: true), disableAnimations: true),
    );
    await tester.pump();

    expect(_turns(tester), .5);
  });

  testWidgets('нажатие на кнопку вызывает обработчик', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(_app(child: _fold(onToggle: () => toggles++)));

    await tester.tap(find.text('Архив'));
    expect(toggles, 1);
    await tester.tap(find.byType(DoableIcon).last);
    expect(toggles, 2);
  });

  testWidgets('кнопка объявляет переданное доступное название и состояние '
      'раскрытости', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_app(child: _fold()));
    expect(
      tester.getSemantics(find.byType(TextButton)),
      matchesSemantics(
        label: 'Архив, можно использовать: 3',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasExpandedState: true,
        isExpanded: false,
      ),
    );

    await tester.pumpWidget(_app(child: _fold(open: true)));
    expect(
      tester.getSemantics(find.byType(TextButton)),
      matchesSemantics(
        label: 'Архив, можно использовать: 3',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasExpandedState: true,
        isExpanded: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('область нажатия выходит на 4 за строку вверх и вниз, а правее '
      'кнопки и дальше 4 касание не вызывает обработчик', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(
      _app(
        child: Column(
          spacing: DoableMetrics.space2,
          children: [
            const SizedBox(key: _above, height: 60, width: double.infinity),
            _fold(onToggle: () => toggles++),
            const SizedBox(height: 60, width: double.infinity),
          ],
        ),
      ),
    );

    final fold = tester.getRect(find.byType(ArchivedFold));
    final button = tester.getRect(find.byType(TextButton));
    final x = button.center.dx;
    expect(button.top, fold.top - 4);
    expect(tester.getRect(find.byKey(_above)).bottom, button.top - 4);

    await tester.tapAt(Offset(x, fold.top - 3));
    await tester.tapAt(Offset(x, fold.bottom + 3));
    expect(toggles, 2);

    await tester.tapAt(Offset(x, fold.top - 5));
    await tester.tapAt(Offset(button.right + 1, fold.center.dy));
    expect(toggles, 2);
  });

  testWidgets('при тексте масштаба 2 длинная подпись переносится, кнопка '
      'растёт без переполнения, а в списке занимает на 8 меньше своей '
      'высоты', (tester) async {
    const text = 'Архивные связи, которые больше не нужны, но сохранены';
    await tester.pumpWidget(
      _app(textScale: 2, width: 280, child: _fold(text: text, count: 128)),
    );

    expect(tester.takeException(), isNull);
    final fold = tester.getRect(find.byType(ArchivedFold));
    final button = tester.getRect(find.byType(TextButton));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.height, greaterThan(DoableType.label.height! * 26));
    expect(button.height, greaterThan(DoableMetrics.tapMin));
    expect(fold.height, button.height - 8);
    expect(button.right, lessThanOrEqualTo(280));
  });
}

ArchivedFold _fold({
  String text = 'Архив',
  int count = 3,
  bool open = false,
  VoidCallback? onToggle,
}) => ArchivedFold(
  text: text,
  count: count,
  open: open,
  label: 'Архив, можно использовать: $count',
  onToggle: onToggle ?? () {},
);

double _turns(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.descendant(
        of: find.byType(AnimatedRotation),
        matching: find.byType(RotationTransition),
      ),
    )
    .turns
    .value;

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
  bool disableAnimations = false,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: disableAnimations,
    ),
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
