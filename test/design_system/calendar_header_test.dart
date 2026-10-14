import 'dart:ui' show Tristate;

import 'package:doable/src/design_system/components/calendar_header.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('стрелки вызывают свои команды по всей области нажатия', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var previousPresses = 0;
    var nextPresses = 0;
    await tester.pumpWidget(
      _host(
        CalendarHeader(
          title: 'Октябрь 2026',
          previousLabel: 'Предыдущий месяц',
          nextLabel: 'Следующий месяц',
          onPrevious: () => previousPresses++,
          onNext: () => nextPresses++,
        ),
      ),
    );

    for (final label in ['Предыдущий месяц', 'Следующий месяц']) {
      final button = find.bySemanticsLabel(label);
      expect(button, findsOneWidget);
      final node = tester.getSemantics(button);
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(node.rect.width, greaterThanOrEqualTo(DoableMetrics.tapMin));
      expect(node.rect.height, greaterThanOrEqualTo(DoableMetrics.tapMin));
      await tester.tapAt(tester.getTopLeft(button) + const Offset(1, 1));
      await tester.pumpAndSettle();
    }
    expect(previousPresses, 1);
    expect(nextPresses, 1);

    final nextNode = tester.getSemantics(
      find.bySemanticsLabel('Следующий месяц'),
    );
    tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
      nextNode.id,
      SemanticsAction.tap,
    );
    await tester.pumpAndSettle();
    expect(nextPresses, 2);

    final title = tester.getSemantics(find.text('Октябрь 2026'));
    expect(title.flagsCollection.isButton, isFalse);
    expect(title.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  for (final disablePrevious in [true, false]) {
    testWidgets(
      '${disablePrevious ? 'Предыдущая' : 'Следующая'} стрелка недоступна без команды',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var presses = 0;
        await tester.pumpWidget(
          _host(
            CalendarHeader(
              title: 'Октябрь 2026',
              previousLabel: 'Предыдущий месяц',
              nextLabel: 'Следующий месяц',
              onPrevious: disablePrevious ? null : () => presses++,
              onNext: disablePrevious ? () => presses++ : null,
            ),
          ),
        );

        final disabled = find.bySemanticsLabel(
          disablePrevious ? 'Предыдущий месяц' : 'Следующий месяц',
        );
        final node = tester.getSemantics(disabled);
        expect(node.flagsCollection.isButton, isTrue);
        expect(node.flagsCollection.isEnabled, Tristate.isFalse);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
        await tester.tap(disabled);
        await tester.pumpAndSettle();
        expect(presses, 0);

        await tester.tap(
          find.bySemanticsLabel(
            disablePrevious ? 'Следующий месяц' : 'Предыдущий месяц',
          ),
        );
        await tester.pumpAndSettle();
        expect(presses, 1);
        semantics.dispose();
      },
    );
  }
}

Widget _host(Widget child) => MaterialApp(
  theme: doableTheme(Brightness.light),
  home: Scaffold(
    body: Center(child: SizedBox(width: 360, child: child)),
  ),
);
