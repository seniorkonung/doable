import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doable/src/design_system/components/path_builder.dart';
import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/design_system/doable_theme.dart';

void main() {
  testWidgets(
    'единственный корень и промежуточный шаг нажимаются, конечный — нет',
    (tester) async {
      final selected = <String>[];
      Future<void> pump(PathBuilderPath? path) => tester.pumpWidget(
        MaterialApp(
          theme: doableTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PathBuilder(
                path: path,
                priority: DoablePriority.p4,
                actionName: 'Действие',
                actionLabel: 'Путь ведёт к действию',
                emptyActionText: 'Новое действие',
                slotText: 'Выберите причину',
                slotLabel: 'Выбрать причину',
                onChooseRoot: () => selected.add('root'),
                onStep: selected.add,
                hint: 'Подсказка',
                switcher: const Text('Переключатель'),
                addText: 'Добавить',
                addLabel: 'Добавить связь',
                onAdd: () {},
              ),
            ),
          ),
        ),
      );
      const root = PathBuilderStep(
        id: 'a',
        name: 'Корень',
        label: 'Выбрать корень',
        openLabel: 'Открыть корень',
        onOpen: _noop,
      );
      await pump(const PathBuilderPath(root: root));
      await tester.tap(find.text('Корень'));
      expect(selected, ['root']);
      await pump(
        PathBuilderPath(
          root: root,
          links: [
            PathBuilderLink(
              step: PathBuilderStep(
                id: 'b',
                name: 'Промежуточное',
                label: 'Обрезать путь',
                openLabel: 'Открыть промежуточное',
                onOpen: _noop,
              ),
              relation: PathBuilderRelation(
                kind: PathBuilderRelationKind.need,
                priority: DoablePriority.p1,
                word: 'нужно',
                label: 'Связь',
                onOpen: _noop,
              ),
            ),
            PathBuilderLink(
              step: PathBuilderStep(
                id: 'c',
                name: 'Конечное',
                label: 'Конечное',
                openLabel: 'Открыть конечное',
                onOpen: _noop,
              ),
              relation: PathBuilderRelation(
                kind: PathBuilderRelationKind.can,
                priority: DoablePriority.p4,
                word: 'можно',
                label: 'Связь 2',
                onOpen: _noop,
              ),
            ),
          ],
        ),
      );
      for (final name in ['Корень', 'Промежуточное']) {
        final ink = find
            .ancestor(of: find.text(name), matching: find.byType(InkWell))
            .first;
        final bounds = tester.getRect(ink);
        final arrow = tester.getRect(
          find.byTooltip(
            name == 'Корень' ? 'Открыть корень' : 'Открыть промежуточное',
          ),
        );
        expect(bounds.left, tester.getTopLeft(find.text(name)).dx);
        expect(bounds.right, arrow.left);
        expect(bounds.height, greaterThanOrEqualTo(40));
        await tester.tapAt(Offset(bounds.right - 8, bounds.center.dy));
      }
      await tester.tap(find.text('Конечное'));
      expect(selected, ['root', 'root', 'b']);
    },
  );
  testWidgets(
    'пустой путь предлагает причину, после выбора доступны обе половины и пустая карточка',
    (tester) async {
      var rootChosen = false;
      var half = 'need';
      Widget build(PathBuilderPath? path) => StatefulBuilder(
        builder: (context, setState) => PathBuilder(
          path: path,
          priority: DoablePriority.p4,
          actionName: '',
          actionLabel: 'Путь ведёт к новому действию',
          emptyActionText: 'Новое действие',
          slotText: 'Выберите причину',
          slotLabel: 'Выбрать причину',
          onChooseRoot: () => rootChosen = true,
          onStep: (_) {},
          hint: 'Одного намерения достаточно',
          switcher: Tabs.toggle(
            items: const [
              TabItem(
                id: 'need',
                label: 'Нужно',
                count: 0,
                semanticLabel: 'Нужно: 0',
              ),
              TabItem(
                id: 'can',
                label: 'Можно',
                count: 1,
                semanticLabel: 'Можно: 1',
              ),
            ],
            value: half,
            onChange: (value) => setState(() => half = value),
            label: 'Вид связи',
            minWidth: 44,
          ),
          addText: 'Добавить',
          addLabel: 'Добавить связь',
          onAdd: () {},
          emptyHalf: (
            title: 'Пока ничего не нужно',
            text: 'Добавьте намерение',
          ),
        ),
      );
      Future<void> pump(PathBuilderPath? path) => tester.pumpWidget(
        MaterialApp(
          theme: doableTheme(Brightness.light),
          home: Scaffold(body: SingleChildScrollView(child: build(path))),
        ),
      );
      await pump(null);
      expect(find.text('Новое действие'), findsOneWidget);
      final slotInk = find
          .ancestor(
            of: find.text('Выберите причину'),
            matching: find.byType(InkWell),
          )
          .first;
      final slotBounds = tester.getRect(slotInk);
      expect(
        slotBounds.left,
        tester.getTopLeft(find.text('Выберите причину')).dx,
      );
      expect(slotBounds.right, tester.getRect(find.byType(PathBuilder)).right);
      expect(slotBounds.height, 40);
      await tester.tapAt(Offset(slotBounds.right - 8, slotBounds.center.dy));
      expect(rootChosen, isTrue);
      await pump(
        const PathBuilderPath(
          root: PathBuilderStep(
            id: 'a',
            name: 'Корень',
            label: 'Выбрать корень',
            openLabel: 'Открыть корень',
            onOpen: _noop,
          ),
        ),
      );
      expect(find.text('0'), findsOneWidget);
      expect(find.text('Пока ничего не нужно'), findsOneWidget);
      await tester.tap(find.text('Можно'));
      expect(half, 'can');
    },
  );
}

void _noop() {}
