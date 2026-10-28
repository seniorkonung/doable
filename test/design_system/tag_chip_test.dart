import 'package:doable/src/design_system/components/tag_chip.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
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
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме малый чип — фон bg с углами radius-xs, '
        'точка 7 и название caption цвета muted, а у выделенного — ink', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TagChip.small(name: 'Дом', color: DoableTagColor.blue),
              TagChip.small(name: 'Работа', color: null, strong: true),
            ],
          ),
        ),
      );

      final ground = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(TagChip).first,
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        ground.decoration,
        BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
        ),
      );
      final dots = tester.widgetList<TagDot>(find.byType(TagDot)).toList();
      expect([for (final dot in dots) dot.color], [DoableTagColor.blue, null]);
      expect(
        [for (final dot in dots) dot.size],
        [TagDotSize.small, TagDotSize.small],
      );

      final plain = _style(tester, 'Дом');
      expect(plain.color, colors.muted);
      expect(plain.fontSize, DoableType.caption.fontSize);
      expect(plain.fontWeight, DoableType.caption.fontWeight);
      expect(plain.height, DoableType.caption.height);
      expect(_style(tester, 'Работа').color, colors.ink);
    });
  }

  testWidgets('точка стоит в 7 от начала и в 5 перед названием, после '
      'названия остаётся 8, а высота — строка caption и по 1 сверху и снизу', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        child: const TagChip.small(name: 'Дом', color: DoableTagColor.teal),
      ),
    );

    final chip = tester.getRect(find.byType(TagChip));
    final dot = tester.getRect(find.byType(TagDot));
    final name = tester.getRect(find.text('Дом'));
    expect(dot.left - chip.left, 7);
    expect(name.left - dot.right, 5);
    expect(chip.right - name.right, DoableMetrics.space2);
    expect(chip.height, 20);
    expect(dot.center.dy, chip.center.dy);
  });

  testWidgets('при тексте масштаба 2 чип растёт по высоте, а длинное '
      'название в узком месте обрезается краем в одну строку', (tester) async {
    const name = 'Очень длинное название тега, которое не помещается';
    await tester.pumpWidget(
      _app(
        textScale: 2,
        child: const SizedBox(
          width: 120,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TagChip.small(name: name, color: DoableTagColor.pink),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(TagChip)), const Size(120, 38));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
    expect(paragraph.overflow, TextOverflow.clip);
    expect(paragraph.size.height, 36);
    expect(
      paragraph.getMaxIntrinsicWidth(double.infinity),
      greaterThan(paragraph.size.width),
    );
  });

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме чип формы — пилюля fill высотой 36 с углами '
        '18, точка 8 в 6 перед названием row цвета ink и крестик 16 цвета '
        'muted в области шириной 34 в конце пилюли', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          child: TagChip.medium(
            name: 'Дом',
            color: DoableTagColor.blue,
            removeLabel: 'Убрать тег: Дом',
            onRemove: () {},
            removeKey: const ValueKey('remove'),
          ),
        ),
      );

      final ground = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(TagChip),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        ground.decoration,
        BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(18),
        ),
      );
      expect(
        tester.widget<TagDot>(find.byType(TagDot)).size,
        TagDotSize.medium,
      );
      final name = _style(tester, 'Дом');
      expect(name.color, colors.ink);
      expect(name.fontSize, DoableType.row.fontSize);
      expect(name.fontWeight, DoableType.row.fontWeight);
      expect(name.height, DoableType.row.height);
      final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(
        (icon.icon, icon.size, icon.color),
        (DoableIconData.closeSmall, 16.0, colors.muted),
      );

      final chip = tester.getRect(find.byType(TagChip));
      final dot = tester.getRect(find.byType(TagDot));
      final text = tester.getRect(find.text('Дом'));
      final remove = tester.getRect(find.byKey(const ValueKey('remove')));
      expect(chip.height, DoableMetrics.controlHeightSm);
      expect(text.left - dot.right, 6);
      expect(dot.center.dy, chip.center.dy);
      expect(
        remove,
        Rect.fromLTRB(chip.right - 34, chip.top, chip.right, chip.bottom),
      );
      expect(tester.getCenter(find.byType(DoableIcon)).dy, chip.center.dy);
    });

    testWidgets('в $themeName теме клавиатура рисует focus-ring вокруг '
        'крестика и Enter снимает тег', (tester) async {
      var removals = 0;
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          child: TagChip.medium(
            name: 'Дом',
            color: null,
            removeLabel: 'Убрать тег: Дом',
            onRemove: () => removals++,
          ),
        ),
      );
      expect(_crossRing(tester), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_crossRing(tester), [
        BoxShadow(color: colors.accent, spreadRadius: 4),
        BoxShadow(color: colors.bg, spreadRadius: 2),
      ]);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(removals, 1);
    });
  }

  testWidgets('нажатие по ключу крестика вызывает обработчик, а крестик '
      'объявляет переданное название кнопкой', (tester) async {
    final semantics = tester.ensureSemantics();
    var removals = 0;
    await tester.pumpWidget(
      _app(
        child: TagChip.medium(
          name: 'Дом',
          color: DoableTagColor.teal,
          removeLabel: 'Убрать тег: Дом',
          onRemove: () => removals++,
          removeKey: const ValueKey('remove'),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Убрать тег: Дом')),
      matchesSemantics(
        label: 'Убрать тег: Дом',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('remove')));
    expect(removals, 1);
    await tester.tap(find.text('Дом'));
    expect(removals, 1);
    semantics.dispose();
  });

  testWidgets('недоступный крестик объявляет '
      'недоступность', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        child: const TagChip.medium(
          name: 'Дом',
          color: DoableTagColor.teal,
          removeLabel: 'Убрать тег: Дом',
          onRemove: null,
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Убрать тег: Дом')),
      matchesSemantics(
        label: 'Убрать тег: Дом',
        isButton: true,
        hasEnabledState: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('при тексте масштаба 2 длинное название чипа формы переносится '
      'без обрезки, пилюля не шире строки, а крестик тянется на её высоту', (
    tester,
  ) async {
    const name = 'Очень длинное название тега, которое не помещается';
    await tester.pumpWidget(
      _app(
        textScale: 2,
        child: SizedBox(
          width: 200,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TagChip.medium(
              name: name,
              color: DoableTagColor.pink,
              removeLabel: 'Убрать тег',
              onRemove: () {},
              removeKey: const ValueKey('remove'),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final chip = tester.getRect(find.byType(TagChip));
    expect(chip.width, lessThanOrEqualTo(200));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.height, greaterThan(40));
    expect(
      paragraph.getMaxIntrinsicHeight(paragraph.size.width),
      paragraph.size.height,
    );
    final remove = tester.getRect(find.byKey(const ValueKey('remove')));
    expect((remove.top, remove.bottom), (chip.top, chip.bottom));
    expect(remove.width, 34);
  });
}

TextStyle _style(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

List<BoxShadow>? _crossRing(WidgetTester tester) {
  final ring = tester.widget<DecoratedBox>(
    find
        .ancestor(
          of: find.byType(DoableIcon),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (ring.decoration as BoxDecoration).boxShadow;
}

Widget _app({
  required Widget child,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(body: Center(child: child)),
  ),
);
