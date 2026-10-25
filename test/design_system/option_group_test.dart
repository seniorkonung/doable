import 'package:doable/src/design_system/components/option_group.dart';
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

  testWidgets('группа названа подписью, выбирает один вариант и передаёт '
      'нажатие потребителю без снятия выбора', (tester) async {
    final semantics = tester.ensureSemantics();
    var value = _Type.all;
    final changes = <_Type>[];

    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => OptionGroup(
            caption: 'Тип',
            items: _types,
            value: value,
            onChanged: (next) {
              changes.add(next);
              setState(() => value = next);
            },
          ),
        ),
      ),
    );

    final group = tester.getSemantics(find.bySemanticsLabel('Тип'));
    expect(group.getSemanticsData().role, SemanticsRole.radioGroup);
    expect(find.bySemanticsLabel('Тип'), findsOneWidget);
    for (final item in _types) {
      expect(
        tester.getSemantics(find.text(item.label)),
        matchesSemantics(
          label: item.label,
          hasCheckedState: true,
          isChecked: item.value == value,
          isInMutuallyExclusiveGroup: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
    }

    final pills = [
      for (final item in _types) tester.getRect(_pill(item.label)),
    ];
    for (var i = 0; i < pills.length; i++) {
      expect(pills[i].height, DoableMetrics.tapMin);
      expect(pills[i].width, closeTo((350 - 16) / 3, 0.001));
      expect(pills[i].top, pills.first.top);
      if (i > 0) expect(pills[i].left - pills[i - 1].right, 8);
    }

    await tester.tapAt(Offset(pills.last.center.dx, pills.last.top + 2));
    await tester.pumpAndSettle();
    expect(changes, [_Type.actions]);
    expect(
      tester
          .getSemantics(find.text('Действия'))
          .hasFlag(SemanticsFlag.isChecked),
      isTrue,
    );
    expect(
      tester.getSemantics(find.text('Все')).hasFlag(SemanticsFlag.isChecked),
      isFalse,
    );
    await tester.tap(find.text('Действия'));
    await tester.pumpAndSettle();
    expect(changes, [_Type.actions, _Type.actions]);
    semantics.dispose();
  });

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме пилюли, подпись и числа используют '
        'токены группы, а значок стоит перед названием', (tester) async {
      await tester.pumpWidget(
        _app(
          OptionGroup(
            caption: 'Тип',
            value: _Type.all,
            items: _countedTypes,
            onChanged: (_) {},
          ),
          brightness: brightness,
        ),
      );

      _expectStyle(
        _style(tester, 'Тип'),
        DoableType.caption.copyWith(color: colors.muted),
      );
      _expectStyle(
        _style(tester, 'Все'),
        DoableType.section.copyWith(color: colors.ink),
      );
      _expectStyle(
        _style(tester, 'Намерения'),
        DoableType.row.copyWith(color: colors.ink, letterSpacing: -0.15),
      );
      _expectStyle(
        _style(tester, '13'),
        DoableType.label.copyWith(
          color: colors.muted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      final selected = _material(tester, 'Все');
      final unselected = _material(tester, 'Намерения');
      final radius = BorderRadius.circular(DoableMetrics.radiusFull);
      expect(selected.color, colors.fill);
      expect(selected.shape, RoundedRectangleBorder(borderRadius: radius));
      expect(unselected.color, Colors.transparent);
      expect(
        unselected.shape,
        RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.hairline),
        ),
      );
      expect(
        tester.getRect(_pill('Все')).top -
            tester.getRect(find.text('Тип')).bottom,
        8,
      );
      expect(
        tester.getRect(find.text('13')).left -
            tester.getRect(find.text('Все')).right,
        6,
      );
      final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(icon.icon, DoableIconData.bolt);
      expect(icon.color, colors.muted);
      expect(tester.getSize(find.byType(DoableIcon)), const Size.square(16));
      expect(
        tester.getRect(find.byType(DoableIcon)).right,
        lessThan(tester.getRect(find.text('Действия')).left),
      );
    });

    testWidgets('в $themeName теме закреплённая группа сохраняет выбор, '
        'скрывает числа и объявляет недоступность с причиной', (tester) async {
      final semantics = tester.ensureSemantics();
      const note = 'Конечным в дневном выборе может быть только действие';
      await tester.pumpWidget(
        _app(
          const OptionGroup.disabled(
            caption: 'Тип',
            items: _countedTypes,
            value: _Type.actions,
            note: note,
          ),
          brightness: brightness,
        ),
      );

      final group = tester.getSemantics(find.bySemanticsLabel('Тип'));
      expect(group.getSemanticsData().role, SemanticsRole.radioGroup);
      expect(group.hint, note);
      expect(group.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
      expect(group.hasFlag(SemanticsFlag.isEnabled), isFalse);
      for (final item in _types) {
        final node = tester.getSemantics(find.text(item.label));
        expect(node.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
        expect(node.hasFlag(SemanticsFlag.isEnabled), isFalse);
        expect(
          node.hasFlag(SemanticsFlag.isChecked),
          item.value == _Type.actions,
        );
        expect(node.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
        expect(
          _style(tester, item.label).color,
          item.value == _Type.actions ? colors.muted : colors.grip,
        );
      }
      for (final count in ['13', '8', '5']) {
        expect(find.text(count), findsNothing);
      }
      expect(_material(tester, 'Действия').color, colors.fill);
      _expectStyle(
        _style(tester, note),
        DoableType.caption.copyWith(color: colors.muted),
      );
      expect(
        tester.getRect(find.text(note)).top -
            tester.getRect(_pill('Все')).bottom,
        8,
      );
      semantics.dispose();
    });
  }

  testWidgets('две пилюли порядка делят ширину поровну и читают число '
      'вместе с названием варианта', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        OptionGroup(
          caption: 'Порядок',
          items: _orders,
          value: true,
          onChanged: (_) {},
        ),
      ),
    );
    final first = tester.getRect(_pill('Сначала новые'));
    final second = tester.getRect(_pill('Сначала старые'));
    expect(first.width, 171);
    expect(second.width, first.width);
    expect(second.left - first.right, 8);
    expect(second.top, first.top);
    expect(first.height, 44);
    expect(second.height, 44);

    await tester.pumpWidget(
      _app(
        OptionGroup(
          caption: 'Тип',
          items: _countedTypes,
          value: _Type.all,
          onChanged: (_) {},
        ),
      ),
    );
    expect(tester.getSemantics(find.text('13')).label, 'Все\n13');
    semantics.dispose();
  });

  testWidgets('масштаб текста 2 сохраняет равные колонки, а подписи '
      'с числами и значками помещаются целиком', (tester) async {
    await tester.pumpWidget(
      _app(
        OptionGroup(
          caption: 'Тип',
          items: _countedTypes,
          value: _Type.all,
          onChanged: (_) {},
        ),
        textScale: 2,
      ),
    );
    _expectContentsFit(
      tester,
      ['Все', 'Намерения', 'Действия'],
      ['13', '8', '5'],
    );

    await tester.pumpWidget(
      _app(
        OptionGroup(
          caption: 'Порядок',
          items: _orders,
          value: true,
          onChanged: (_) {},
        ),
        textScale: 2,
      ),
    );
    _expectContentsFit(tester, ['Сначала новые', 'Сначала старые'], []);
  });

  testWidgets('клавиатура выделяет пилюлю кольцом фокуса и передаёт '
      'выбор потребителю', (tester) async {
    final changes = <_Type>[];
    await tester.pumpWidget(
      _app(
        OptionGroup(
          caption: 'Тип',
          items: _types,
          value: _Type.all,
          onChanged: changes.add,
        ),
      ),
    );
    final group = tester.renderObject(find.byType(OptionGroup<_Type>));
    expect(group, isNot(paints..rrect(color: DoableColors.light.accent)));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(group, paints..rrect(color: DoableColors.light.accent));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(changes, [_Type.all]);
  });
}

enum _Type { all, intentions, actions }

const _types = [
  OptionGroupItem(value: _Type.all, label: 'Все'),
  OptionGroupItem(value: _Type.intentions, label: 'Намерения'),
  OptionGroupItem(value: _Type.actions, label: 'Действия'),
];

const _countedTypes = [
  OptionGroupItem(value: _Type.all, label: 'Все', count: '13'),
  OptionGroupItem(value: _Type.intentions, label: 'Намерения', count: '8'),
  OptionGroupItem(
    value: _Type.actions,
    label: 'Действия',
    count: '5',
    icon: DoableIconData.bolt,
  ),
];

const _orders = [
  OptionGroupItem(
    value: true,
    label: 'Сначала новые',
    icon: DoableIconData.arrowDown,
  ),
  OptionGroupItem(
    value: false,
    label: 'Сначала старые',
    icon: DoableIconData.arrowUp,
  ),
];

void _expectContentsFit(
  WidgetTester tester,
  List<String> labels,
  List<String> counts,
) {
  expect(tester.takeException(), isNull);
  final first = tester.getRect(_pill(labels.first));
  for (final label in labels) {
    final pill = tester.getRect(_pill(label));
    expect(pill.width, closeTo(first.width, 0.001));
    expect(pill.top, first.top);
    expect(pill.height, first.height);
    expect(pill.height, greaterThanOrEqualTo(44));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.textScaler.scale(15), 30);
  }
  for (final text in [...labels, ...counts]) {
    final pill = tester.getRect(
      find.ancestor(of: find.text(text), matching: find.byType(InkWell)),
    );
    expect(pill.contains(tester.getTopLeft(find.text(text))), isTrue);
    expect(pill.contains(tester.getBottomRight(find.text(text))), isTrue);
  }
  for (final icon in find.byType(DoableIcon).evaluate()) {
    final pill = tester.getRect(
      find.ancestor(
        of: find.byWidget(icon.widget),
        matching: find.byType(InkWell),
      ),
    );
    expect(
      pill.contains(tester.getTopLeft(find.byWidget(icon.widget))),
      isTrue,
    );
    expect(
      pill.contains(tester.getBottomRight(find.byWidget(icon.widget))),
      isTrue,
    );
  }
}

Finder _pill(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell));

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

Material _material(WidgetTester tester, String label) =>
    tester.widget<Material>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );

Widget _app(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 350, child: child),
      ),
    ),
  ),
);
