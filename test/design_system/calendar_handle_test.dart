import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat, Tristate;

import 'package:doable/src/design_system/components/calendar_handle.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ручка переключается по краям полосы, через экранный диктор '
      'и с клавиатуры', (tester) async {
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
                  expansionProgress: expanded ? 1 : 0,
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
    expect(collapsedNode.rect.height, 36);

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
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(presses, 4);
    expect(collapsed, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(presses, 5);
    expect(opened, findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'нажатие не заливает полосу, а фокус виден только возле шеврона',
    (tester) async {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: doableTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: 360,
                  child: CalendarHandle(
                    isExpanded: false,
                    expansionProgress: 0,
                    semanticLabel: 'Раскрыть календарь',
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final handle = find.byType(CalendarHandle);
      final rest = await _pixels(tester, boundaryKey);
      final gesture = await tester.startGesture(
        tester.getTopLeft(handle) + const Offset(1, 18),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(listEquals(await _pixels(tester, boundaryKey), rest), isTrue);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(listEquals(await _pixels(tester, boundaryKey), rest), isTrue);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final focused = await _pixels(tester, boundaryKey);
      final size = tester.getSize(handle);
      final focusArea = Rect.fromCenter(
        center: size.center(Offset.zero),
        width: 48,
        height: 28,
      );
      final changed = [
        for (var i = 0; i < rest.length; i++)
          if (rest[i] != focused[i])
            Offset(
              (i % size.width.toInt()).toDouble(),
              i ~/ size.width.toInt() * 1.0,
            ),
      ];
      expect(changed, isNotEmpty, reason: 'Фокус должен быть виден');
      expect(
        changed.every(focusArea.contains),
        isTrue,
        reason: 'Фокус не должен заливать полосу вне ручки',
      );

      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      expect(listEquals(await _pixels(tester, boundaryKey), rest), isTrue);
    },
  );
}

Future<Uint32List> _pixels(WidgetTester tester, GlobalKey boundaryKey) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
      return bytes.buffer.asUint32List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      );
    } finally {
      image.dispose();
    }
  }))!;
}
