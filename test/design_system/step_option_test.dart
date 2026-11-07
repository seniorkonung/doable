import 'package:doable/src/design_system/components/step_option.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('выбор и открытие кандидата независимы, новая связь обозначена', (
    tester,
  ) async {
    final events = <String>[];
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: Scaffold(
          body: StepOption(
            name: 'Подготовиться',
            priority: DoablePriority.p1,
            freshText: 'Новое',
            label: 'Выбрать: Подготовиться. Нужно. P1. Добавлено сейчас',
            openLabel: 'Открыть намерение',
            onPick: () => events.add('выбор'),
            onOpen: () => events.add('открытие'),
          ),
        ),
      ),
    );
    expect(find.text('Новое'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Выбрать: Подготовиться. Нужно. P1. Добавлено сейчас',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Подготовиться'));
    await tester.tap(find.byTooltip('Открыть намерение'));
    expect(events, ['выбор', 'открытие']);
    semantics.dispose();
  });
}
