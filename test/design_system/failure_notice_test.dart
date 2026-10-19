import 'package:doable/src/design_system/components/failure_notice.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('действие сообщения об отказе — кнопка с названием, которая '
      'срабатывает по всей области нажатия выше своей плашки', (tester) async {
    final semantics = tester.ensureSemantics();
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: Scaffold(
          body: FailureNotice(
            message: const Text('Не удалось прочитать файл.'),
            action: (label: 'Повторить', onPressed: () => presses++),
          ),
        ),
      ),
    );

    final button = find.bySemanticsLabel('Повторить');
    final node = tester.getSemantics(button);
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(node.rect.height, greaterThanOrEqualTo(DoableMetrics.tapMin));
    await tester.tapAt(tester.getTopLeft(button) + const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(presses, 1);
    semantics.dispose();
  });
}
