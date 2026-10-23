import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/components/tag_row.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_shadows.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light ? 'светлой' : 'тёмной';

    testWidgets('в $theme теме строка, ручка, точка, название и галочка '
        'следуют токенам', (tester) async {
      final colors = _colorsOf(brightness);

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          row: TagRow(
            name: 'Работа',
            color: DoableTagColor.blue,
            mark: TagRowSelectionMark.checked,
            label: 'Работа',
            handle: const TagRowDragHandle(index: 0, enabled: true),
            onPressed: () {},
          ),
        ),
      );

      final row = tester.getRect(find.byType(TagRow));
      expect(row.height, 48);
      final ground = _decorationOf(tester);
      expect(ground.color, isNull, reason: 'у строки нет своего фона');
      expect(ground.boxShadow, isNull);
      expect(
        ground.borderRadius,
        BorderRadius.circular(DoableMetrics.radiusSm),
      );

      final handle = tester.getRect(_handleArea);
      expect(handle.left, row.left);
      expect(handle.width, 40);
      expect(
        handle.height,
        row.height,
        reason: 'ручка нажимается на всю высоту',
      );
      final grip = tester.widget<DoableIcon>(_grip);
      expect(grip.size, 16);
      expect(grip.color, colors.grip);
      final gripRect = tester.getRect(_grip);
      expect(gripRect.left - row.left, DoableMetrics.space2);
      expect(gripRect.center.dy, row.center.dy);

      final dot = tester.widget<TagDot>(find.byType(TagDot));
      expect(dot.size, TagDotSize.large);
      expect(dot.color, DoableTagColor.blue);
      final dotRect = tester.getRect(find.byType(TagDot));
      expect(dotRect.left - row.left, 40);
      expect(dotRect.center.dy, row.center.dy);

      final name = tester.getRect(find.text('Работа'));
      expect(name.left - dotRect.right, DoableMetrics.space3);
      final style = tester.widget<Text>(find.text('Работа')).style!;
      expect(style.fontSize, DoableType.action.fontSize);
      expect(style.fontWeight, DoableType.action.fontWeight);
      expect(style.color, colors.ink);

      final tick = tester.widget<DoableIcon>(_tick);
      expect(tick.size, 20);
      expect(tick.color, colors.accent);
      final tickRect = tester.getRect(_tick);
      expect(row.right - tickRect.right, DoableMetrics.space3);
      expect(tickRect.left - name.right, DoableMetrics.space3);
    });

    testWidgets('в $theme теме отметка «должен быть» — галочка accent, '
        'а «исключён» — перечёркнутый круг muted с приглушённым названием', (
      tester,
    ) async {
      final colors = _colorsOf(brightness);

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          row: _row(mark: TagRowFilterMark.mustBePresent),
        ),
      );
      expect(_exclude, findsNothing);
      final tick = tester.widget<DoableIcon>(_tick);
      expect(tick.size, 20);
      expect(tick.color, colors.accent);
      expect(_nameColor(tester), colors.ink);

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          row: _row(mark: TagRowFilterMark.mustBeAbsent),
        ),
      );
      expect(_tick, findsNothing);
      final exclude = tester.widget<DoableIcon>(_exclude);
      expect(exclude.size, 20);
      expect(exclude.color, colors.muted);
      final row = tester.getRect(find.byType(TagRow));
      final excludeRect = tester.getRect(_exclude);
      expect(row.right - excludeRect.right, DoableMetrics.space3);
      expect(
        excludeRect.left - tester.getRect(find.text('Работа')).right,
        DoableMetrics.space3,
      );
      expect(_nameColor(tester), colors.muted);

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          row: _row(mark: TagRowFilterMark.none),
        ),
      );
      expect(_tick, findsNothing);
      expect(_exclude, findsNothing);
      expect(_nameColor(tester), colors.ink);
    });

    testWidgets('в $theme теме удерживаемая строка получает фон fill, '
        'а поднятая — плоскость raised с тенью shadow-float', (tester) async {
      final colors = _colorsOf(brightness);
      final shadows = switch (brightness) {
        Brightness.light => DoableShadows.light,
        Brightness.dark => DoableShadows.dark,
      };

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          row: _row(ground: TagRowGround.held),
        ),
      );
      final held = _decorationOf(tester);
      expect(held.color, colors.fill);
      expect(held.boxShadow, isNull);

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          row: _row(ground: TagRowGround.lifted),
        ),
      );
      final lifted = _decorationOf(tester);
      expect(lifted.color, colors.raised);
      expect(lifted.boxShadow, shadows.shadowFloat);
    });
  }

  testWidgets('длинное название переносится целиком, а строка растёт', (
    tester,
  ) async {
    const name =
        'Подготовка к ежегодной встрече выпускников и поиск подарков '
        'для всех однокурсников';
    await tester.pumpWidget(
      _app(
        width: 240,
        row: TagRow(
          name: name,
          color: DoableTagColor.green,
          mark: TagRowSelectionMark.checked,
          label: name,
          handle: const TagRowDragHandle(index: 0, enabled: true),
          onPressed: () {},
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.getSize(find.text(name)).height, greaterThan(22 * 2));
    final row = tester.getRect(find.byType(TagRow));
    expect(row.height, greaterThan(48));
    expect(
      tester.getRect(_handleArea).height,
      row.height,
      reason: 'ручка растёт вместе со строкой',
    );
  });

  testWidgets('тег без цвета показан кольцом точки', (tester) async {
    await tester.pumpWidget(
      _app(
        row: TagRow(
          name: 'Разное',
          color: null,
          mark: TagRowSelectionMark.none,
          label: 'Разное',
          handle: const TagRowDragHandle(index: 0, enabled: true),
          onPressed: () {},
        ),
      ),
    );

    final dot = tester.widget<TagDot>(find.byType(TagDot));
    expect(dot.color, isNull);
    expect(dot.size, TagDotSize.large);
  });

  testWidgets('скрытая ручка сохраняет место, поэтому точка и название '
      'не смещаются', (tester) async {
    await tester.pumpWidget(_app(row: _row()));
    final dot = tester.getRect(find.byType(TagDot));
    final name = tester.getRect(find.text('Работа'));

    await tester.pumpWidget(
      _app(row: _row(handle: const TagRowHiddenHandle())),
    );

    expect(_grip, findsNothing);
    expect(tester.getRect(find.byType(TagDot)), dot);
    expect(tester.getRect(find.text('Работа')), name);
  });

  testWidgets('отметка видна галочкой и объявляется состоянием строки, '
      'а нажатие передаётся потребителю', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;

    await tester.pumpWidget(
      _app(
        row: TagRow(
          name: 'Работа',
          color: DoableTagColor.blue,
          mark: TagRowSelectionMark.none,
          label: 'Работа',
          handle: const TagRowDragHandle(index: 0, enabled: true),
          onPressed: () => taps++,
        ),
      ),
    );
    expect(_tick, findsNothing);
    expect(
      tester.getSemantics(find.byType(TagRow)),
      matchesSemantics(
        label: 'Работа',
        hasCheckedState: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );

    await tester.tap(find.text('Работа'));
    expect(taps, 1);

    await tester.pumpWidget(
      _app(
        row: TagRow(
          name: 'Работа',
          color: DoableTagColor.blue,
          mark: TagRowSelectionMark.checked,
          label: 'Работа',
          handle: const TagRowDragHandle(index: 0, enabled: true),
          onPressed: () => taps++,
        ),
      ),
    );
    expect(_tick, findsOneWidget);
    expect(
      tester.getSemantics(find.byType(TagRow)),
      matchesSemantics(
        label: 'Работа',
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('строка фильтра не объявляет состояние отметки выбора: '
      'надобность передаёт доступное название', (tester) async {
    final semantics = tester.ensureSemantics();

    for (final (mark, label) in [
      (TagRowFilterMark.none, 'Работа'),
      (TagRowFilterMark.mustBePresent, 'Работа, должен быть'),
      (TagRowFilterMark.mustBeAbsent, 'Работа, должен отсутствовать'),
    ]) {
      await tester.pumpWidget(
        _app(
          row: TagRow(
            name: 'Работа',
            color: DoableTagColor.blue,
            mark: mark,
            label: label,
            handle: const TagRowDragHandle(index: 0, enabled: true),
            onPressed: () {},
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(TagRow)),
        matchesSemantics(
          label: label,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
        reason: '$mark',
      );
    }
    semantics.dispose();
  });

  testWidgets('недоступная строка не принимает нажатие и объявляет '
      'недоступность, сохраняя отметку', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        row: const TagRow(
          name: 'Работа',
          color: DoableTagColor.blue,
          mark: TagRowSelectionMark.checked,
          label: 'Работа',
          handle: TagRowDragHandle(index: 0, enabled: false),
          onPressed: null,
        ),
      ),
    );

    expect(_tick, findsOneWidget);
    expect(
      tester.getSemantics(find.byType(TagRow)),
      matchesSemantics(
        label: 'Работа',
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('строка — один узел экранного диктора без отдельных ручки, '
      'точки и названия', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_app(row: _row()));

    final node = tester.getSemantics(find.byType(TagRow));
    expect(node.mergeAllDescendantsIntoThisNode, isTrue);
    expect(tester.getSemantics(_grip), same(node));
    expect(tester.getSemantics(find.byType(TagDot)), same(node));
    expect(tester.getSemantics(find.text('Работа')), same(node));
    semantics.dispose();
  });

  testWidgets('удержание и контекстный щелчок открывают меню потребителя, '
      'не меняя отметку', (tester) async {
    var opened = 0;
    var taps = 0;
    await tester.pumpWidget(
      _app(
        row: _row(
          onPressed: () => taps++,
          menu: TagRowMenu(
            holdHint: 'Удерживайте, чтобы открыть действия тега',
            onOpen: () => opened++,
            actions: const [],
          ),
        ),
      ),
    );

    await tester.longPress(find.text('Работа'));
    expect(opened, 1);

    await tester.tap(find.text('Работа'), buttons: kSecondaryButton);
    expect(opened, 2);
    expect(taps, 0);
  });

  testWidgets('действия меню и подсказка удержания объявляются на узле '
      'строки вместе с названием и однократной отметкой', (tester) async {
    final semantics = tester.ensureSemantics();
    final invoked = <String>[];

    await tester.pumpWidget(
      _app(
        row: _row(
          mark: TagRowSelectionMark.checked,
          menu: TagRowMenu(
            holdHint: 'Удерживайте, чтобы открыть действия тега',
            onOpen: () {},
            actions: [
              (label: 'Изменить тег', onInvoke: () => invoked.add('правка')),
              (label: 'Удалить тег', onInvoke: () => invoked.add('удаление')),
            ],
          ),
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(TagRow));
    expect(
      node,
      matchesSemantics(
        label: 'Работа',
        hint: 'Удерживайте, чтобы открыть действия тега',
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasLongPressAction: true,
        isFocusable: true,
        hasFocusAction: true,
        customActions: const [
          CustomSemanticsAction(label: 'Изменить тег'),
          CustomSemanticsAction(label: 'Удалить тег'),
        ],
      ),
    );

    tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction(label: 'Удалить тег'),
      ),
    );
    expect(invoked, ['удаление']);
    semantics.dispose();
  });

  testWidgets('в переставляемом списке перетаскивание за ручку переставляет '
      'строку, а за название и за выключенную ручку — нет', (tester) async {
    final reorders = <(int, int)>[];

    Future<void> pumpList({required bool enabled}) => tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: Scaffold(
          body: ReorderableListView(
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => reorders.add((from, to)),
            children: [
              for (final (index, name) in ['Работа', 'Дом', 'Спорт'].indexed)
                TagRow(
                  key: ValueKey(name),
                  name: name,
                  color: null,
                  mark: TagRowSelectionMark.none,
                  label: name,
                  handle: TagRowDragHandle(index: index, enabled: enabled),
                  onPressed: () {},
                ),
            ],
          ),
        ),
      ),
    );

    await pumpList(enabled: true);
    await tester.drag(find.text('Работа'), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(reorders, isEmpty);

    await tester.drag(_grip.first, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(reorders, [(0, 1)]);

    reorders.clear();
    await pumpList(enabled: false);
    await tester.drag(_grip.first, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(reorders, isEmpty);
  });
}

DoableColors _colorsOf(Brightness brightness) => switch (brightness) {
  Brightness.light => DoableColors.light,
  Brightness.dark => DoableColors.dark,
};

BoxDecoration _decorationOf(WidgetTester tester) =>
    tester
            .widget<DecoratedBox>(
              find
                  .descendant(
                    of: find.byType(TagRow),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

final _grip = find.byWidgetPredicate(
  (widget) => widget is DoableIcon && widget.icon == DoableIconData.grip,
);

final _handleArea = find.descendant(
  of: find.byType(TagRow),
  matching: find.byType(ReorderableDragStartListener),
);

final _tick = find.byWidgetPredicate(
  (widget) => widget is DoableIcon && widget.icon == DoableIconData.check,
);

final _exclude = find.byWidgetPredicate(
  (widget) => widget is DoableIcon && widget.icon == DoableIconData.exclude,
);

Color? _nameColor(WidgetTester tester) =>
    tester.widget<Text>(find.text('Работа')).style!.color;

TagRow _row({
  TagRowMark mark = TagRowSelectionMark.none,
  TagRowHandle handle = const TagRowDragHandle(index: 0, enabled: true),
  TagRowGround ground = TagRowGround.none,
  TagRowMenu? menu,
  VoidCallback? onPressed,
}) => TagRow(
  name: 'Работа',
  color: DoableTagColor.blue,
  mark: mark,
  label: 'Работа',
  handle: handle,
  ground: ground,
  menu: menu,
  onPressed: onPressed ?? () {},
);

Widget _app({
  required TagRow row,
  Brightness brightness = Brightness.light,
  double width = 360,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: width, child: row),
    ),
  ),
);
