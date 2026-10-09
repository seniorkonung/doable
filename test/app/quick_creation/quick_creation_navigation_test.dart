import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_button.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_presentation.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  testWidgets(
    'режим общий для оболочки и глубокой страницы; поиски независимы',
    (tester) async {
      final router = await _start(tester);
      await _selectMode(tester, QuickCreationMode.dailyChoiceFromAction);
      await tester.tap(find.byType(QuickCreationButton));
      await tester.pumpAndSettle();
      final firstPicker = router.current.matchId;
      await tester.enterText(_key('daily-choice-action-filter'), 'Намерение 3');
      unawaited(
        router.push(IntentionDetailsRoute(intentionId: durabilityIntention(3))),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<QuickCreationButton>(find.byType(QuickCreationButton))
            .mode,
        QuickCreationMode.dailyChoiceFromAction,
      );
      await tester.tap(find.byType(QuickCreationButton));
      await tester.pumpAndSettle();
      expect(router.current.name, DailyChoiceActionPickerRoute.name);
      expect(router.current.matchId, isNot(firstPicker));
      expect(
        tester
            .widget<TextField>(_key('daily-choice-action-filter'))
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(find.text('Отменить создание'));
      await tester.pumpAndSettle();
      await _selectMode(tester, QuickCreationMode.relation);
      await router.maybePop();
      await tester.pumpAndSettle();
      expect(router.current.matchId, firstPicker);
      expect(
        tester
            .widget<TextField>(_key('daily-choice-action-filter'))
            .controller!
            .text,
        'Намерение 3',
      );
      await tester.tap(find.text('Отменить создание'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<QuickCreationButton>(find.byType(QuickCreationButton))
            .mode,
        QuickCreationMode.relation,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _selectMode(WidgetTester tester, QuickCreationMode mode) async {
  final localizations = AppLocalizations.of(
    tester.element(find.byType(AppNavigationBar)),
  );
  await tester.longPress(find.byType(QuickCreationButton));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, mode.title(localizations)));
  await tester.pumpAndSettle();
  expect(
    tester.widget<QuickCreationButton>(find.byType(QuickCreationButton)).mode,
    mode,
  );
}

Future<AppRouter> _start(WidgetTester tester) async {
  tester.platformDispatcher.localesTestValue = const [Locale('ru')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late AppDatabase database;
  final runtime = AppRuntime(
    connectionFactory: openInMemoryLocalDatabase,
    diagnosticsSink: InMemoryDiagnosticsSink(),
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    repositoryFactory: (value) {
      database = value;
      return durabilityRepository(value);
    },
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = await runtime.bootstrap() as AppRuntimeReady;
  await seedDurabilityGraph(database);
  await tester.pumpWidget(MainApp(runtime: runtime));
  await tester.pumpAndSettle();
  return ready.container.read(appRouterProvider);
}
