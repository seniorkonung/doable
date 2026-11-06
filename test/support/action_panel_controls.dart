/// Общие действия и наблюдения панели действия.
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/presentation/panel/action_panel.dart';
import 'package:doable/src/design_system/components/action_head.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/shared/presentation/local_day/local_date_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_panel_fixture.dart';
import 'controlled_local_date.dart';
import 'ordinary_page_test_app.dart';

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

/// Открывает панель над страницей; действие приходит из
/// [ActionPanelRepository.emit]. Сегодня — 2026-10-08. [routes] — страницы,
/// которые панель открывает поверх себя.
Future<ActionPanelRepository> openActionPanel(
  WidgetTester tester, {
  List<AutoRoute> routes = const [],
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = ActionPanelRepository();
  addTearDown(repository.dispose);
  final localDate = ControlledLocalDate(CalendarDate.fromParts(2026, 10, 8));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
        localDateSourceProvider.overrideWithValue(localDate.read),
      ],
      child: OrdinaryPageTestApp(
        locale: const Locale('ru'),
        routes: routes,
        builder: (context, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  unawaited(showActionPanel(context, actionIdOf(1))),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Открыть'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return repository;
}
