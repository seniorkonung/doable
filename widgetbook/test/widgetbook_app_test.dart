import 'package:doable_widgetbook/widgetbook_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('каталог показывает песочницу в панели навигации', (
    tester,
  ) async {
    // Панель навигации видна только в настольной компоновке Widgetbook,
    // то есть при ширине окна от 840 логических пикселей.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const WidgetbookApp());
    await tester.pumpAndSettle();

    expect(find.text('Песочница'), findsOneWidget);
  });
}
