import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doable/src/design_system/components/path_glyph.dart';
import 'package:doable/src/design_system/components/relation_batch.dart';
import 'package:doable/src/design_system/components/relation_head.dart';
import 'package:doable/src/design_system/components/relation_stroke.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_theme.dart';

void main() {
  for (final direction in RelationBatchDirection.values) {
    testWidgets(
      'дерево $direction сохраняет направление, ветви и порядок отметок',
      (tester) async {
        await tester.pumpWidget(_app(_batch(direction: direction)));
        final anchor = tester.getTopLeft(find.text('Главное')).dy;
        final kind = tester.getTopLeft(find.text('Нужно')).dy;
        final first = tester.getTopLeft(find.text('Первое')).dy;
        final second = tester.getTopLeft(find.text('Второе')).dy;
        if (direction == RelationBatchDirection.outgoing) {
          expect(anchor, lessThan(kind));
          expect(kind, lessThan(first));
        } else {
          expect(second, lessThan(kind));
          expect(kind, lessThan(anchor));
        }
        expect(first, lessThan(second));
        final glyph = tester.widget<PathGlyph>(find.byType(PathGlyph));
        expect(
          glyph.shape,
          direction == RelationBatchDirection.outgoing
              ? PathGlyphShape.diamond
              : PathGlyphShape.ring,
        );
        final branches = tester
            .widgetList<RelationStroke>(find.byType(RelationStroke))
            .where((line) => line.axis == RelationStrokeAxis.horizontal)
            .toList();
        // Две ветви и отметка вида.
        expect(branches, hasLength(3));
        final branchRects = [
          for (final line in branches)
            if (tester.getSize(find.byWidget(line)).width == 21)
              tester.getRect(find.byWidget(line)),
        ];
        expect(branchRects, hasLength(2));
        for (final (index, name) in ['Первое', 'Второе'].indexed) {
          final text = tester.getRect(find.text(name));
          expect(branchRects[index].center.dy, text.top + 11);
          expect(branchRects[index].right, text.left - 14);
          expect(branchRects[index].left, 11);
        }
        expect(
          branches.every((line) => line.kind is RelationStrokeNeed),
          isTrue,
        );
        expect(
          branches.every(
            (line) =>
                (line.kind as RelationStrokeNeed).color ==
                DoableColors.light.grip,
          ),
          isTrue,
        );
      },
    );
  }

  testWidgets(
    'крестик снимает именно выбранную одноимённую отметку и имеет размер 48',
    (tester) async {
      final removed = <int>[];
      await tester.pumpWidget(
        _app(
          _batch(
            items: const [
              RelationBatchItem(value: 1, name: 'Одинаково'),
              RelationBatchItem(value: 2, name: 'Одинаково'),
            ],
            onRemove: removed.add,
          ),
        ),
      );
      final buttons = find.byTooltip('Снять: Одинаково');
      expect(buttons, findsNWidgets(2));
      expect(tester.getSize(buttons.last), const Size.square(48));
      await tester.tap(buttons.last);
      expect(removed, [2]);
    },
  );

  testWidgets('пустое дерево показывает подпись, ветвь и пунктир вида можно', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_batch(items: const [], kind: RelationHeadKind.can)),
    );
    expect(find.text('Пока пусто'), findsOneWidget);
    expect(find.text('Можно'), findsOneWidget);
    final lines = tester.widgetList<RelationStroke>(
      find.byType(RelationStroke),
    );
    expect(lines.every((line) => line.kind is RelationStrokeCan), isTrue);
    expect(
      lines.where((line) => line.axis == RelationStrokeAxis.horizontal),
      hasLength(2),
    );
  });

  testWidgets('длинные названия видны полностью, диктор слышит роли и вид', (
    tester,
  ) async {
    const long =
        'Длинное название намерения которое переносится на несколько строк и остаётся полностью видимым';
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        _batch(items: const [RelationBatchItem(value: 1, name: long)]),
        width: 220,
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(find.text(long));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.height, greaterThan(22));
    expect(
      find.bySemanticsLabel('Исходное намерение: Главное. Намерение страницы'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Связанное намерение: $long'), findsOneWidget);
    expect(find.bySemanticsLabel('Нужно'), findsOneWidget);
    expect(
      tester.getSemantics(find.byTooltip('Снять: $long')),
      matchesSemantics(
        tooltip: 'Снять: $long',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

RelationBatch<int> _batch({
  RelationBatchDirection direction = RelationBatchDirection.outgoing,
  RelationHeadKind kind = RelationHeadKind.need,
  List<RelationBatchItem<int>> items = const [
    RelationBatchItem(value: 1, name: 'Первое'),
    RelationBatchItem(value: 2, name: 'Второе'),
  ],
  ValueChanged<int>? onRemove,
}) => RelationBatch<int>(
  anchor: 'Главное',
  kind: kind,
  direction: direction,
  items: items,
  onRemove: onRemove ?? (_) {},
  anchorNote: 'Намерение страницы',
  emptyText: 'Пока пусто',
  needLabel: 'Нужно',
  canLabel: 'Можно',
  listLabel: 'Отмеченные намерения',
  anchorSemanticLabel: 'Исходное намерение: Главное',
  itemSemanticLabel: (name) => 'Связанное намерение: $name',
  removeLabel: (name) => 'Снять: $name',
);

Widget _app(Widget child, {double width = 400}) => MaterialApp(
  theme: doableTheme(Brightness.light),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);
