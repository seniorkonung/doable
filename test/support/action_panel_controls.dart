/// Общие действия и наблюдения панели действия.
library;

import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/presentation/panel/action_panel.dart';
import 'package:doable/src/design_system/components/action_head.dart';
import 'package:flutter_test/flutter_test.dart';

/// Открытая панель. Панель, перекрытая страницей, не считается.
Finder get actionPanel => find.byType(ActionPanel);

/// Действие, открытое в панели.
ActionId shownActionId(WidgetTester tester) =>
    tester.widget<ActionPanel>(actionPanel).actionId;

/// Панель загрузила действие и готова к изменениям.
Finder get actionPanelReady =>
    find.descendant(of: actionPanel, matching: find.byType(ActionHead));

/// Шапка панели с выполнением и приоритетом действия.
ActionHead shownActionHead(WidgetTester tester) =>
    tester.widget<ActionHead>(actionPanelReady);

/// Значение [value] поля на вкладке «Обзор».
Finder actionPanelField(String value) =>
    find.descendant(of: actionPanel, matching: find.text(value));

/// Закрывает панель.
Future<void> closeActionPanel(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(actionPanel, findsNothing);
}
