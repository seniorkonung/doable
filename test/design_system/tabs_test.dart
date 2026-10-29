import 'dart:ui' show Tristate;

import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Section { overview, relations, statistics }

const _items = [
  TabItem(
    id: _Section.overview,
    label: 'Обзор',
    semanticLabel: 'Обзор намерения',
  ),
  TabItem(
    id: _Section.relations,
    label: 'Связи',
    count: 12,
    icon: DoableIconData.archive,
    semanticLabel: 'Связи: 12 активных, 3 архивированных',
  ),
  TabItem(
    id: _Section.statistics,
    label: 'Статистика',
    semanticLabel: 'Статистика',
  ),
];

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
    testWidgets('в $themeName теме пилюли выбирают вкладку через потребителя '
        'и объявляют её доступное название и выбранность', (tester) async {
      final semantics = tester.ensureSemantics();
      var value = _Section.overview;
      final changes = <_Section>[];
      await tester.pumpWidget(
        _app(
          brightness,
          StatefulBuilder(
            builder: (context, setState) => Tabs(
              items: _items,
              value: value,
              label: 'Разделы намерения',
              onChange: (next) => setState(() {
                changes.add(next);
                value = next;
              }),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(Tabs<_Section>)).height, 52);
      expect(tester.getRect(_tap('Обзор')).left, 20);
      expect(tester.getSize(_tap('Обзор')).height, 44);
      expect(_plane(tester, 'Обзор').color, colors.fill);
      expect(_plane(tester, 'Связи').color, isNull);
      _expectStyle(
        _style(tester, 'Обзор'),
        DoableType.section.copyWith(color: colors.ink),
      );
      _expectStyle(
        _style(tester, 'Связи'),
        DoableType.section.copyWith(color: colors.muted),
      );
      expect(
        tester.getRect(_tap('Связи')).left -
            tester.getRect(_tap('Обзор')).right,
        4,
      );
      final countStyle = _style(tester, '12');
      _expectStyle(
        countStyle,
        DoableType.label.copyWith(
          color: colors.muted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      expect(
        tester.getRect(find.text('12')).left -
            tester.getRect(find.text('Связи')).right,
        6,
      );
      final icon = find.byType(DoableIcon);
      expect(tester.widget<DoableIcon>(icon).icon, DoableIconData.archive);
      expect(tester.widget<DoableIcon>(icon).size, 14);
      expect(tester.widget<DoableIcon>(icon).color, colors.muted);
      expect(
        tester.getRect(icon).left - tester.getRect(find.text('12')).right,
        6,
      );
      expect(tester.getSize(_pill('Обзор')).height, 36);
      expect(
        tester.getRect(find.text('Обзор')).left -
            tester.getRect(_pill('Обзор')).left,
        14,
      );

      final bar = tester.getSemantics(
        find.bySemanticsLabel('Разделы намерения'),
      );
      expect(bar.getSemanticsData().role, SemanticsRole.tabBar);
      _expectTab(tester, 'Обзор намерения', selected: true);
      _expectTab(
        tester,
        'Связи: 12 активных, 3 архивированных',
        selected: false,
      );
      final width = tester.getSize(_tap('Связи')).width;
      await tester.tap(_tap('Связи'));
      await tester.pumpAndSettle();

      expect(changes, [_Section.relations]);
      expect(_plane(tester, 'Связи').color, colors.fill);
      expect(_plane(tester, 'Обзор').color, isNull);
      expect(_style(tester, 'Связи').fontWeight, DoableType.section.fontWeight);
      expect(tester.getSize(_tap('Связи')).width, width);
      _expectTab(
        tester,
        'Связи: 12 активных, 3 архивированных',
        selected: true,
      );
      _expectTab(tester, 'Обзор намерения', selected: false);
      semantics.dispose();
    });

    testWidgets('в $themeName теме полоса затухает по краям и показывает '
        'hairline только при закреплении без изменения высоты', (tester) async {
      for (final stuck in [false, true]) {
        await tester.pumpWidget(
          _app(
            brightness,
            Tabs(
              items: _items,
              value: _Section.overview,
              label: 'Разделы',
              stuck: stuck,
              onChange: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final lines = find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).border ==
                  Border(bottom: BorderSide(color: colors.hairline)),
        );
        expect(lines, stuck ? findsOneWidget : findsNothing);
        expect(tester.getSize(find.byType(Tabs<_Section>)).height, 52);
        final fades = find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).gradient != null,
        );
        expect(fades, findsNWidgets(2));
        final start =
            tester.widget<DecoratedBox>(fades.first).decoration
                as BoxDecoration;
        final end =
            tester.widget<DecoratedBox>(fades.last).decoration as BoxDecoration;
        expect((start.gradient! as LinearGradient).colors, [
          colors.bg,
          colors.bgFade,
        ]);
        expect((end.gradient! as LinearGradient).colors, [
          colors.bgFade,
          colors.bg,
        ]);
        expect(tester.getSize(fades.first).width, 16);
        expect(tester.getSize(fades.last).width, 28);
      }
    });

    testWidgets('в $themeName теме длинные подписи с крупным текстом '
        'не переполняют полосу и выбранная вкладка открывается при смене', (
      tester,
    ) async {
      final value = ValueNotifier(3);
      addTearDown(value.dispose);
      final items = [
        for (var index = 0; index < 4; index++)
          TabItem(
            id: index,
            label: index == 1
                ? 'Очень длинное название раздела на другом языке'
                : 'Раздел $index',
            semanticLabel: 'Раздел $index',
          ),
      ];
      await tester.pumpWidget(
        _app(
          brightness,
          ValueListenableBuilder(
            valueListenable: value,
            builder: (context, selected, _) => SizedBox(
              height: Tabs.heightFor(context),
              child: Tabs(
                items: items,
                value: selected,
                label: 'Разделы',
                onChange: (next) => value.value = next,
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();

      final longText = tester.renderObject<RenderParagraph>(
        find.text(items[1].label),
      );
      expect(longText.didExceedMaxLines, isFalse);
      expect(longText.textScaler.scale(15), 30);
      expect(tester.getSize(find.byType(Tabs<int>)).height, 72);
      _expectVisible(tester, 'Раздел 3');
      value.value = 0;
      await tester.pumpAndSettle();
      _expectVisible(tester, 'Раздел 0');
      await tester.drag(find.byType(Tabs<int>), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(_tap('Раздел 0')).right, lessThanOrEqualTo(0));
      value.value = 3;
      await tester.pumpAndSettle();
      _expectVisible(tester, 'Раздел 3');
      expect(tester.takeException(), isNull);
    });

    testWidgets('в $themeName теме клавиатура рисует focus-ring вокруг '
        'пилюли и Enter выбирает вкладку', (tester) async {
      final changes = <_Section>[];
      await tester.pumpWidget(
        _app(
          brightness,
          Tabs(
            items: _items,
            value: _Section.overview,
            label: 'Разделы',
            onChange: changes.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_plane(tester, 'Обзор').boxShadow, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_plane(tester, 'Обзор').boxShadow, [
        BoxShadow(color: colors.accent, spreadRadius: 4),
        BoxShadow(color: colors.bg, spreadRadius: 2),
      ]);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_plane(tester, 'Обзор').boxShadow, isNull);
      expect(_plane(tester, 'Связи').boxShadow, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(changes, [_Section.relations]);
    });
  }

  testWidgets('показ выбранной вкладки не сдвигает вертикальную прокрутку '
      'страницы при открытии и смене вкладки', (tester) async {
    final pageScroll = ScrollController(initialScrollOffset: 40);
    final value = ValueNotifier(3);
    addTearDown(pageScroll.dispose);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _app(
        Brightness.light,
        SingleChildScrollView(
          controller: pageScroll,
          child: Column(
            children: [
              const SizedBox(height: 120),
              ValueListenableBuilder(
                valueListenable: value,
                builder: (context, selected, _) => Tabs(
                  items: [
                    for (var index = 0; index < 4; index++)
                      TabItem(
                        id: index,
                        label: 'Длинный раздел $index',
                        semanticLabel: 'Раздел $index',
                      ),
                  ],
                  value: selected,
                  label: 'Разделы',
                  onChange: (next) => value.value = next,
                ),
              ),
              const SizedBox(height: 1000),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectVisible(tester, 'Длинный раздел 3');
    expect(pageScroll.offset, 40);
    value.value = 0;
    await tester.pumpAndSettle();
    _expectVisible(tester, 'Длинный раздел 0');
    expect(pageScroll.offset, 40);
  });
}

Finder _tap(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell));
Finder _pill(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(Ink));
BoxDecoration _plane(WidgetTester tester, String label) =>
    tester.widget<Ink>(_pill(label)).decoration! as BoxDecoration;
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

void _expectTab(WidgetTester tester, String label, {required bool selected}) {
  final data = tester
      .getSemantics(find.bySemanticsLabel(label))
      .getSemanticsData();
  expect(data.label, label);
  expect(data.role, SemanticsRole.tab);
  expect(
    data.flagsCollection.isSelected,
    selected ? Tristate.isTrue : Tristate.isFalse,
  );
  expect(data.hasAction(SemanticsAction.tap), isTrue);
}

void _expectVisible(WidgetTester tester, String label) {
  final strip = tester.getRect(find.byType(Tabs<int>));
  final tab = tester.getRect(_tap(label));
  expect(tab.left, greaterThanOrEqualTo(strip.left));
  expect(tab.right, lessThanOrEqualTo(strip.right));
}

Widget _app(Brightness brightness, Widget child, {double textScale = 1}) =>
    MaterialApp(
      theme: doableTheme(brightness),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 390, child: child),
          ),
        ),
      ),
    );
