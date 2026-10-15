import 'package:doable/src/design_system/components/notice.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('сообщение об отказе объявляется без интерактивного действия', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const message = 'Отметки дней не загружены.';

    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: const Scaffold(body: Notice(message: message)),
      ),
    );

    expect(find.text(message), findsOne);
    final announcement = tester.getSemantics(find.bySemanticsLabel(message));
    expect(announcement.flagsCollection.isLiveRegion, isTrue);
    expect(find.semantics.byFlag(SemanticsFlag.isButton), findsNothing);
    expect(find.semantics.byAction(SemanticsAction.tap), findsNothing);
    semantics.dispose();
  });
}
