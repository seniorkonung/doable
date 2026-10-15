import 'dart:ui' show Tristate;

import 'package:doable/src/design_system/components/calendar_handle.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ручка переключается по краям полосы и через экранный диктор', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var expanded = false;
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: StatefulBuilder(
                builder: (context, setState) => CalendarHandle(
                  isExpanded: expanded,
                  semanticLabel: expanded
                      ? 'Свернуть календарь'
                      : 'Раскрыть календарь',
                  onTap: () => setState(() {
                    expanded = !expanded;
                    presses++;
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final collapsed = find.bySemanticsLabel('Раскрыть календарь');
    expect(collapsed, findsOneWidget);
    final collapsedNode = tester.getSemantics(collapsed);
    expect(collapsedNode.flagsCollection.isButton, isTrue);
    expect(collapsedNode.flagsCollection.isExpanded, Tristate.isFalse);
    expect(
      collapsedNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(collapsedNode.rect.width, 360);
    expect(
      collapsedNode.rect.height,
      greaterThanOrEqualTo(DoableMetrics.tapMin),
    );

    await tester.tapAt(tester.getTopLeft(collapsed) + const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(presses, 1);
    expect(collapsed, findsNothing);
    final opened = find.bySemanticsLabel('Свернуть календарь');
    expect(opened, findsOneWidget);
    final openedNode = tester.getSemantics(opened);
    expect(openedNode.flagsCollection.isButton, isTrue);
    expect(openedNode.flagsCollection.isExpanded, Tristate.isTrue);

    await tester.tapAt(tester.getBottomRight(opened) - const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(presses, 2);
    expect(opened, findsNothing);
    expect(collapsed, findsOneWidget);
    expect(
      tester.getSemantics(collapsed).flagsCollection.isExpanded,
      Tristate.isFalse,
    );

    tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
      tester.getSemantics(collapsed).id,
      SemanticsAction.tap,
    );
    await tester.pumpAndSettle();
    expect(presses, 3);
    expect(opened, findsOneWidget);
    expect(
      tester.getSemantics(opened).flagsCollection.isExpanded,
      Tristate.isTrue,
    );
    semantics.dispose();
  });
}
