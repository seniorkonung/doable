import 'dart:ui' show CheckedState, SemanticsAction, Tristate;

import 'package:doable/src/design_system/components/segmented_control.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_shadows.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'равные половины показывают выбор, сообщают нажатие и состояние диктору',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final changes = <int>[];
      var value = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: doableTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 350,
                child: StatefulBuilder(
                  builder: (context, setState) => SegmentedControl<int>(
                    label: 'Вид намерения',
                    first: const SegmentItem(
                      id: 0,
                      label: 'Главное',
                      semanticLabel: 'Важное само по себе',
                      icon: DoableIconData.intention,
                    ),
                    second: const SegmentItem(
                      id: 1,
                      label: 'Вспомогательное',
                      semanticLabel: 'Служит главному',
                      icon: DoableIconData.supporting,
                    ),
                    value: value,
                    onChange: (next) {
                      changes.add(next);
                      setState(() => value = next);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final first = find.bySemanticsLabel('Важное само по себе');
      final second = find.bySemanticsLabel('Служит главному');
      BoxDecoration plane(String label) =>
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text(label),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(plane('Главное').color, DoableColors.light.raised);
      expect(plane('Главное').boxShadow, DoableShadows.light.sm);
      expect(plane('Вспомогательное').color, isNull);
      expect(tester.getSize(first), tester.getSize(second));
      expect(
        tester.getSize(find.byType(SegmentedControl<int>)),
        const Size(350, 44),
      );
      expect(
        tester.getSemantics(first),
        matchesSemantics(
          label: 'Важное само по себе',
          isInMutuallyExclusiveGroup: true,
          isChecked: true,
          isEnabled: true,
          hasEnabledState: true,
          hasCheckedState: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(second),
        matchesSemantics(
          label: 'Служит главному',
          isInMutuallyExclusiveGroup: true,
          isChecked: false,
          isEnabled: true,
          hasEnabledState: true,
          hasCheckedState: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.text('Главное'));
      expect(changes, isEmpty);
      await tester.tap(find.text('Вспомогательное'));
      await tester.pumpAndSettle();
      expect(changes, [1]);
      expect(plane('Главное').color, isNull);
      expect(plane('Вспомогательное').color, DoableColors.light.raised);
      expect(
        tester
            .getSemantics(second)
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );
      semantics.dispose();
    },
  );

  testWidgets('недоступная половина остаётся на месте и объясняет причину', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final changes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 350,
              child: SegmentedControl<int>(
                label: 'Вид',
                first: const SegmentItem(
                  id: 0,
                  label: 'Главное',
                  semanticLabel: 'Главное',
                ),
                second: const SegmentItem(
                  id: 1,
                  label: 'Вспомогательное',
                  semanticLabel: 'Нужна входящая связь',
                  disabled: true,
                ),
                value: 0,
                onChange: changes.add,
              ),
            ),
          ),
        ),
      ),
    );
    final disabled = find.bySemanticsLabel('Нужна входящая связь');
    expect(
      tester.getSemantics(disabled),
      matchesSemantics(
        label: 'Нужна входящая связь',
        isInMutuallyExclusiveGroup: true,
        isChecked: false,
        hasCheckedState: true,
        hasEnabledState: true,
      ),
    );
    expect(
      tester.widget<Text>(find.text('Вспомогательное')).style!.color,
      DoableColors.light.grip,
    );
    await tester.tap(find.text('Вспомогательное'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(changes, isEmpty);
    semantics.dispose();
  });

  testWidgets(
    'фокус клавиатуры выделен кольцом, Enter выбирает другую половину',
    (tester) async {
      final changes = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: doableTheme(Brightness.dark),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 350,
                child: SegmentedControl<int>(
                  label: 'Вид',
                  first: const SegmentItem(
                    id: 0,
                    label: 'Главное',
                    semanticLabel: 'Главное',
                  ),
                  second: const SegmentItem(
                    id: 1,
                    label: 'Вспомогательное',
                    semanticLabel: 'Вспомогательное',
                  ),
                  value: 0,
                  onChange: changes.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final container = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.text('Вспомогательное'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.boxShadow!.first.color, DoableColors.dark.accent);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(changes, [1]);
    },
  );

  testWidgets('весь переключатель может быть недоступен при крупном тексте', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
              child: SizedBox(
                width: 350,
                child: SegmentedControl<int>(
                  label: 'Вид',
                  first: const SegmentItem(
                    id: 0,
                    label: 'Главное',
                    semanticLabel: 'Главное',
                  ),
                  second: const SegmentItem(
                    id: 1,
                    label: 'Вспомогательное',
                    semanticLabel: 'Вспомогательное',
                  ),
                  value: 0,
                  onChange: null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (final label in ['Главное', 'Вспомогательное']) {
      final data = tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
    }
    expect(
      tester.getSize(find.byType(SegmentedControl<int>)).height,
      greaterThan(44),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
