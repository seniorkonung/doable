import 'dart:ui' show Tristate;

import 'package:doable/src/design_system/components/period_picker.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'пустые позиции не выбираются, показанный текущий период доступен',
    (tester) async {
      final semantics = tester.ensureSemantics();
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: doableTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: PeriodPicker(
                cells: [
                  null,
                  PeriodPickerCell(
                    text: '2026',
                    semanticLabel: '2026, текущий год',
                    isShown: true,
                    isCurrent: true,
                    onTap: () => picked = '2026',
                  ),
                  for (var year = 2027; year <= 2035; year++)
                    PeriodPickerCell(
                      text: '$year',
                      semanticLabel: '$year',
                      onTap: () => picked = '$year',
                    ),
                  null,
                ],
              ),
            ),
          ),
        ),
      );
      final shown = tester.getSemantics(
        find.bySemanticsLabel('2026, текущий год'),
      );
      expect(shown.flagsCollection.isButton, isTrue);
      expect(shown.flagsCollection.isSelected, Tristate.isTrue);
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        shown.id,
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();
      expect(picked, '2026');

      final other = find.bySemanticsLabel('2027');
      expect(
        tester.getSemantics(other).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      await tester.tap(other);
      await tester.pumpAndSettle();
      expect(picked, '2027');

      // Пустые места не создают доступных команд.
      expect(find.bySemanticsLabel(RegExp(r'^20\d\d')), findsNWidgets(10));
      await tester.tapAt(const Offset(30, 28));
      await tester.pumpAndSettle();
      expect(picked, '2027');
      semantics.dispose();
    },
  );
}
