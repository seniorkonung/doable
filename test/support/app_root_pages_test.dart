import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';
import 'in_memory_diagnostics_sink.dart';
import 'tag_storage_fixture.dart';

final _intention =
    (IntentionId.decode(tagFixtureId(1)) as IntentionIdDecodingSuccess).id;

void main() {
  testWidgets('возврат после создания оставляет уже открытый каталог', (
    tester,
  ) async {
    final router = await _start(tester);
    final catalog = tester.element(find.byType(IntentionCatalogPage));

    await returnToIntentionGraphAfterCreation(tester, router);

    expectIntentionGraphRootPage(router);
    expect(tester.element(find.byType(IntentionCatalogPage)), same(catalog));
  });

  testWidgets('возврат после создания закрывает одну страницу намерения '
      'и сохраняет исходный каталог', (tester) async {
    final router = await _start(tester);
    final catalog = tester.element(find.byType(IntentionCatalogPage));
    unawaited(router.push(IntentionDetailsRoute(intentionId: _intention)));
    await _settle(tester);

    await returnToIntentionGraphAfterCreation(tester, router);

    expectIntentionGraphRootPage(router);
    expect(tester.element(find.byType(IntentionCatalogPage)), same(catalog));
    expect(tester.takeException(), isNull);
  });

  testWidgets('возврат после создания не скрывает форму под страницей '
      'намерения', (tester) async {
    final router = await _start(tester);
    unawaited(router.push(const IntentionEditorRoute()));
    await tester.pumpAndSettle();
    unawaited(router.push(IntentionDetailsRoute(intentionId: _intention)));
    await _settle(tester);
    final pages = router.stack.toList();

    await expectLater(
      () => returnToIntentionGraphAfterCreation(tester, router),
      throwsA(isA<TestFailure>()),
    );

    expect(router.stack, pages);
  });

  testWidgets('возврат после создания не закрывает неожиданную страницу', (
    tester,
  ) async {
    final router = await _start(tester);
    unawaited(router.push(TagCatalogRoute()));
    await _settle(tester);
    final pages = router.stack.toList();

    await expectLater(
      () => returnToIntentionGraphAfterCreation(tester, router),
      throwsA(isA<TestFailure>()),
    );

    expect(router.stack, pages);
  });

  testWidgets('возврат после создания не удаляет цепочку страниц намерений', (
    tester,
  ) async {
    final router = await _start(tester);
    for (var number = 1; number <= 2; number++) {
      final id = (IntentionId.decode(
        tagFixtureId(number),
      ) as IntentionIdDecodingSuccess).id;
      unawaited(router.push(IntentionDetailsRoute(intentionId: id)));
      await _settle(tester);
    }
    final pages = router.stack.toList();
    expect(pages, hasLength(3));

    await expectLater(
      () => returnToIntentionGraphAfterCreation(tester, router),
      throwsA(isA<TestFailure>()),
    );

    expect(router.stack, pages);
  });

  testWidgets('возврат после создания не скрывает оставшийся диалог', (
    tester,
  ) async {
    final router = await _start(tester);
    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(IntentionCatalogPage)),
        builder: (_) => const AlertDialog(title: Text('Подтверждение ухода')),
      ),
    );
    await tester.pumpAndSettle();
    final pages = router.stack.toList();

    await expectLater(
      () => returnToIntentionGraphAfterCreation(tester, router),
      throwsA(isA<TestFailure>()),
    );

    expect(router.stack, pages);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}

Future<AppRouter> _start(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final runtime = AppRuntime(
    connectionFactory: openInMemoryLocalDatabase,
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  await tester.pumpWidget(MainApp(runtime: runtime));
  await openIntentionGraph(tester, waitFor: _until);
  await _settle(tester);
  return ready.container.read(appRouterProvider);
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _wait(tester, () => finder.evaluate().isNotEmpty);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await _wait(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
}

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}
