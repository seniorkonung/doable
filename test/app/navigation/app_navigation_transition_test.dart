import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/navigation/ordinary_page_scaffold.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/shared/presentation/presentation_frame_evidence.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('панель неподвижна и единственна в кадрах переходов обычных '
        'страниц; задача закрывает её до возврата: ${platform.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.reset);
      final router = await _start(tester);
      final rect = tester.getRect(_bar);

      for (final title in ['Первая страница', 'Вторая страница']) {
        unawaited(router.pushNativeRoute<void>(_ordinary(title)));
        await _expectStationaryFrames(tester, rect);
      }
      if (platform == TargetPlatform.iOS) {
        // Отмена жеста оставляет верхнюю страницу и ту же панель.
        final cancelled = await tester.startGesture(const Offset(1, 390));
        await cancelled.moveBy(const Offset(120, 0));
        await tester.pump(const Duration(milliseconds: 80));
        expect(_bar, findsOneWidget);
        expect(tester.getRect(_bar), rect);
        await cancelled.moveBy(const Offset(-120, 0));
        await cancelled.up();
        await _expectStationaryFrames(tester, rect);
        expect(find.text('Вторая страница'), findsNWidgets(2));

        final committed = await tester.startGesture(const Offset(1, 390));
        await committed.moveBy(const Offset(300, 0));
        await tester.pump(const Duration(milliseconds: 80));
        expect(_bar, findsOneWidget);
        expect(tester.getRect(_bar), rect);
        await committed.up();
      } else {
        await tester.binding.handlePopRoute();
      }
      await _expectStationaryFrames(tester, rect);
      expect(find.text('Первая страница'), findsNWidgets(2));
      expect(find.text('Вторая страница'), findsNothing);

      unawaited(
        router.pushNativeRoute<void>(
          MaterialPageRoute(
            builder: (_) =>
                Scaffold(appBar: AppBar(title: const Text('Задача'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_bar, findsNothing);
      expect(find.text('Задача'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.getRect(_bar), rect);
      await tester.binding.handlePopRoute();
      await _expectStationaryFrames(tester, rect);
    }, variant: TargetPlatformVariant({platform}));
  }

  testWidgets('скрытая обычная страница не участвует в обходе фокуса и '
      'семантики и не подтверждает кадр сообщения до возврата', (tester) async {
    final semantics = tester.ensureSemantics();
    final subject = ValueNotifier<String?>(null);
    addTearDown(subject.dispose);
    final presented = <String>[];
    final router = await _start(tester);
    unawaited(
      router.pushNativeRoute<void>(
        MaterialPageRoute(
          builder: (_) => OrdinaryPageScaffold(
            appBar: AppBar(title: const Text('Скрытая страница')),
            body: ValueListenableBuilder<String?>(
              valueListenable: subject,
              builder: (_, value, _) => PresentationFrameEvidence<String>(
                subject: value,
                onPresented: presented.add,
                child: TextButton(
                  onPressed: () {},
                  child: const Text('Скрытое сообщение'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(router.pushNativeRoute<void>(_ordinary('Верхняя страница')));
    await tester.pumpAndSettle();

    subject.value = 'Сообщение';
    await tester.pumpAndSettle();
    expect(presented, isEmpty);
    final traversal = tester.semantics
        .simulatedAccessibilityTraversal()
        .toList();
    expect(traversal.any((node) => node.label.contains('Скрыт')), isFalse);
    expect(
      traversal.where(
        (node) =>
            node.label == 'Верхняя страница' && node.flagsCollection.isHeader,
      ),
      hasLength(1),
    );
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(ModalRoute.of(focused)?.isCurrent, isTrue);
    }
    expect(presented, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(presented, ['Сообщение']);
    expect(find.text('Скрытое сообщение').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

final _bar = find.byType(AppNavigationBar);

MaterialPageRoute<void> _ordinary(String title) => MaterialPageRoute(
  builder: (_) => OrdinaryPageScaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: TextButton(onPressed: () {}, child: Text(title)),
    ),
  ),
);

/// Измеряет промежуточные кадры, пока Hero находится в overlay, а также
/// конечное положение: проверка только после pumpAndSettle пропустит скачок.
Future<void> _expectStationaryFrames(WidgetTester tester, Rect rect) async {
  await tester.pump();
  for (var frame = 0; frame < 30; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    expect(_bar, findsOneWidget, reason: 'кадр $frame');
    expect(tester.getRect(_bar), rect, reason: 'кадр $frame');
    expect(tester.widget<AppNavigationBar>(_bar).selected, AppDestination.home);
    expect(tester.takeException(), isNull, reason: 'кадр $frame');
  }
  await tester.pumpAndSettle();
  expect(_bar, findsOneWidget);
  expect(tester.getRect(_bar), rect);
}

Future<AppRouter> _start(WidgetTester tester) async {
  final runtime = AppRuntime(
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
