import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/navigation/ordinary_page_scaffold.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_root_pages.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  for (final bottomPadding in [0.0, 24.0]) {
    testWidgets('каркас размещает панель под телом с безопасным отступом '
        '$bottomPadding и общей меткой Hero', (tester) async {
      tester.view.padding = FakeViewPadding(
        bottom: bottomPadding * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetPadding);
      final router = await _start(tester);
      expect(
        tester.getSize(find.byType(AppNavigationBar)).height,
        AppNavigationBar.height + bottomPadding,
      );

      unawaited(router.pushNativeRoute<void>(_ordinaryRoute()));
      await tester.pumpAndSettle();

      final bar = find.byType(AppNavigationBar);
      expect(bar, findsOneWidget);
      expect(
        tester.getSize(bar).height,
        AppNavigationBar.height + bottomPadding,
      );
      expect(
        tester.getBottomLeft(find.byKey(_bodyKey)).dy,
        tester.getTopLeft(bar).dy,
      );
      expect(tester.getBottomLeft(bar).dy, 600);
      expect(tester.takeException(), isNull);
    });
  }

  // Сброс истории не зависит от пункта; берём другой пункт, с которого
  // «назад» ведёт на Главную.
  const destination = AppDestination.intentionGraph;
  testWidgets('выбор ${destination.name} удаляет типизированную и '
      'безымянную историю без подтверждения', (tester) async {
    final semantics = tester.ensureSemantics();
    final router = await _start(tester);
    await _select(tester, AppDestination.dailyChoices);
    unawaited(router.push<void>(TagCatalogRoute()));
    await tester.pumpAndSettle();
    var popRequests = 0;
    final taskResult = router.pushNativeRoute<String>(
      MaterialPageRoute(
        builder: (_) => PopScope<String>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) popRequests += 1;
          },
          child: const Scaffold(body: Text('Незавершённая задача')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(router.pushNativeRoute<void>(_ordinaryRoute()));
    await tester.pumpAndSettle();
    _expectSelected(tester, AppDestination.dailyChoices);

    await _select(tester, destination);

    expect(await taskResult, isNull);
    expect(popRequests, 0);
    expect(router.stack.map((page) => page.name), [AppShellRoute.name]);
    expect(router.hasPagelessTopRoute, isFalse);
    expect(router.topRoute.name, destination.page.name);
    _expectSelected(tester, destination);
    expect(
      find.byType(OrdinaryPageScaffold, skipOffstage: false),
      findsNothing,
    );
    expect(
      find.text('Незавершённая задача', skipOffstage: false),
      findsNothing,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(router.stack.map((page) => page.name), [AppShellRoute.name]);
    expect(router.hasPagelessTopRoute, isFalse);
    expect(router.topRoute.name, HomeRoute.name);
    expect(find.byType(HomePage), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('обычное «назад» закрывает только верхний каркас', (
    tester,
  ) async {
    final router = await _start(tester);
    unawaited(router.pushNativeRoute<void>(_ordinaryRoute()));
    await tester.pumpAndSettle();
    unawaited(router.pushNativeRoute<void>(_ordinaryRoute()));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(OrdinaryPageScaffold), findsOneWidget);
    expect(router.hasPagelessTopRoute, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(router.hasPagelessTopRoute, isFalse);
    expect(tester.takeException(), isNull);
  });
}

const _bodyKey = ValueKey('ordinary-page-body');

MaterialPageRoute<void> _ordinaryRoute() => MaterialPageRoute(
  builder: (_) => OrdinaryPageScaffold(
    appBar: AppBar(title: const Text('Обычная страница')),
    body: const SizedBox.expand(key: _bodyKey),
  ),
);

Future<AppRouter> _start(WidgetTester tester) async {
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => openInMemoryLocalDatabase(),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  await tester.pumpWidget(MainApp(runtime: runtime));
  await tester.pumpAndSettle();
  final ready = await runtime.bootstrap() as AppRuntimeReady;
  return ready.container.read(appRouterProvider);
}

Future<void> _select(WidgetTester tester, AppDestination destination) async {
  final entry = appNavigationDestination(destination);
  expect(entry.hitTestable(), findsOneWidget);
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

/// Выбор объявляется ровно у одного из трёх доступных пунктов.
void _expectSelected(WidgetTester tester, AppDestination selected) {
  expect(appNavigationDestinations(), findsExactly(3));
  for (final destination in AppDestination.values) {
    expect(
      tester
          .getSemantics(appNavigationDestination(destination))
          .flagsCollection
          .isSelected,
      destination == selected ? Tristate.isTrue : Tristate.isFalse,
      reason: destination.name,
    );
  }
}
