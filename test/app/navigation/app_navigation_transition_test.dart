import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/navigation/ordinary_page_scaffold.dart';
import 'package:doable/src/app/quick_creation/quick_creation_button.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/shared/presentation/presentation_frame_evidence.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

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
      var mode = QuickCreationMode.intention;

      for (final title in ['Первая страница', 'Вторая страница']) {
        unawaited(router.pushNativeRoute<void>(_ordinary(title)));
        await _expectStationaryFrames(tester, rect, mode: mode);
        await tester.longPress(find.byType(QuickCreationButton));
        await tester.pumpAndSettle();
        final nextTitle = title == 'Первая страница'
            ? 'Новая связь'
            : 'Дневной выбор от действия';
        await tester.tap(find.widgetWithText(ListTile, nextTitle));
        await tester.pumpAndSettle();
        mode = title == 'Первая страница'
            ? QuickCreationMode.relation
            : QuickCreationMode.dailyChoiceFromAction;
        expect(tester.getRect(_bar), rect);
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
        await _expectStationaryFrames(tester, rect, mode: mode);
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
      await _expectStationaryFrames(tester, rect, mode: mode);
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
      await _expectStationaryFrames(tester, rect, mode: mode);
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

  for (final locale in [
    const Locale('ru'),
    const Locale('en'),
    const Locale('de'),
  ]) {
    testWidgets('меню изолирует действия и фокус обычной страницы, '
        'закрытие восстанавливает их: ${locale.languageCode}', (tester) async {
      final semantics = tester.ensureSemantics();
      final input = TextEditingController(text: 'Несохранённый ввод');
      final focus = FocusNode();
      addTearDown(input.dispose);
      addTearDown(focus.dispose);
      final router = await _start(tester);
      tester.platformDispatcher.localesTestValue = [locale];
      final route = MaterialPageRoute<void>(
        builder: (_) => OrdinaryPageScaffold(
          appBar: AppBar(title: const Text('Исходная страница')),
          body: Column(
            children: [
              TextField(controller: input, focusNode: focus),
              TextButton(
                onPressed: input.clear,
                child: const Text('Очистить ввод'),
              ),
            ],
          ),
        ),
      );
      unawaited(router.pushNativeRoute<void>(route));
      await tester.pumpAndSettle();
      final clearPosition = tester.getCenter(find.text('Очистить ввод'));
      final button = find.byType(QuickCreationButton);
      final node = tester.getSemantics(button);
      final changeMode = AppLocalizations.of(tester.element(button))
          .quickCreationChangeMode;
      final action = node
          .getSemanticsData()
          .customSemanticsActionIds!
          .map(CustomSemanticsAction.getAction)
          .whereType<CustomSemanticsAction>()
          .singleWhere((action) => action.label == changeMode);

      tester.semantics.customAction(find.semantics.byLabel(node.label), action);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.semantics.byLabel('Очистить ввод'), findsNothing);
      expect(find.semantics.byLabel(node.label), findsNothing);
      expect(
        tester.semantics.simulatedAccessibilityTraversal().where(
          (node) => node.role == SemanticsRole.tab,
        ),
        isEmpty,
      );
      expect(button.hitTestable(), findsNothing);
      for (var step = 0; step < 8; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(focus.hasFocus, isFalse);
        expect(
          FocusManager.instance.primaryFocus!.context!
              .findAncestorWidgetOfExactType<BottomSheet>(),
          isNotNull,
        );
      }

      // Касание фона закрывает барьер, не активируя кнопку под ним.
      await tester.tapAt(clearPosition);
      await tester.pumpAndSettle();
      expect(route.isCurrent, isTrue);
      expect(input.text, 'Несохранённый ввод');
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.semantics.byLabel('Очистить ввод'), findsOneWidget);
      expect(find.semantics.byLabel(node.label), findsOneWidget);
      expect(button.hitTestable(), findsOneWidget);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.tap(find.text('Очистить ввод'));
      await tester.pumpAndSettle();
      expect(input.text, isEmpty);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
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
Future<void> _expectStationaryFrames(
  WidgetTester tester,
  Rect rect, {
  required QuickCreationMode mode,
}) async {
  await tester.pump();
  for (var frame = 0; frame < 30; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    expect(_bar, findsOneWidget, reason: 'кадр $frame');
    expect(tester.getRect(_bar), rect, reason: 'кадр $frame');
    expect(tester.widget<AppNavigationBar>(_bar).selected, AppDestination.home);
    expect(
      tester.widget<QuickCreationButton>(find.byType(QuickCreationButton)).mode,
      mode,
    );
    expect(tester.takeException(), isNull, reason: 'кадр $frame');
  }
  await tester.pumpAndSettle();
  expect(_bar, findsOneWidget);
  expect(tester.getRect(_bar), rect);
}

Future<AppRouter> _start(WidgetTester tester) async {
  tester.platformDispatcher.localesTestValue = const [Locale('ru')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
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
