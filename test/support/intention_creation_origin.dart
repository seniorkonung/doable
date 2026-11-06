import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';

/// Исходные страницы самостоятельного создания, включая глубокую страницу.
enum IntentionCreationOrigin {
  home('Главной', AppDestination.home),
  actions('экраном дня', AppDestination.actions),
  graph('каталогом намерений', AppDestination.intentionGraph),
  deep('страницей намерения над каталогом', AppDestination.intentionGraph);

  const IntentionCreationOrigin(this.description, this.destination);
  final String description;
  final AppDestination destination;

  Future<IntentionCreationHistory> open(
    WidgetTester tester,
    StackRouter router, {
    required IntentionId participantId,
    required RootPageWait waitFor,
  }) async {
    final selected = tester
        .widget<AppNavigationBar>(find.byType(AppNavigationBar))
        .selected;
    if (selected != destination) {
      switch (destination) {
        case AppDestination.home:
          await openHome(tester, waitFor: waitFor);
        case AppDestination.actions:
          await openActions(tester);
        case AppDestination.intentionGraph:
          await openIntentionGraph(tester, waitFor: waitFor);
      }
      await tester.pumpAndSettle();
    }
    if (this == deep) {
      unawaited(
        router.push<void>(IntentionDetailsRoute(intentionId: participantId)),
      );
      await waitFor(
        tester,
        find.byKey(const ValueKey('intention-details-title')),
      );
      await tester.pumpAndSettle();
    }
    return IntentionCreationHistory(this, List.of(router.stackData));
  }
}

/// Точные экземпляры исходных маршрутов под созданием.
final class IntentionCreationHistory {
  IntentionCreationHistory(this.origin, this.routes);
  final IntentionCreationOrigin origin;
  final List<RouteData> routes;

  void expectPrefix(StackRouter router) => expect(
    router.stackData.take(routes.length),
    orderedEquals(routes.map(same)),
  );

  void expectRestored(WidgetTester tester, StackRouter router) {
    expectPrefix(router);
    expect(router.stackData, hasLength(routes.length));
    expect(
      tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
      origin.destination,
    );
  }

  Future<void> expectUnderlyingTask(
    WidgetTester tester,
    StackRouter router,
  ) async {
    if (origin != IntentionCreationOrigin.deep) return;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      router.stackData,
      orderedEquals(routes.take(routes.length - 1).map(same)),
    );
  }
}
