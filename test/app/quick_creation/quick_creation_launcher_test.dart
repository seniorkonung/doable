import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/action/presentation/editor/action_editor_page.dart';
import 'package:doable/src/action/presentation/path_start/path_start_picker_page.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/quick_creation/quick_creation_launcher.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_durability_fixture.dart';
import '../../support/action_day_controls.dart';
import '../../support/controlled_local_date.dart';
import '../../support/quick_creation.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

part 'quick_creation_launcher_test_support.dart';

void main() {
  for (final origin in [
    'главная',
    'страница намерения',
    'корневой экран дня',
    'экран дня на дату',
  ]) {
    testWidgets('Действие над $origin получает выбранную дату и пустой путь', (
      tester,
    ) async {
      final today = CalendarDate.fromParts(2026, 10, 7);
      final selected = CalendarDate.fromParts(2026, 10, 9);
      final router = await _openApp(tester, today: today);
      if (origin == 'страница намерения') {
        await _source(tester, router, _Origin.deep);
      } else if (origin == 'корневой экран дня') {
        router
            .innerRouterOf<TabsRouter>(AppShellRoute.name)!
            .setActiveIndex(AppDestination.actions.index);
        await tester.pumpAndSettle();
        await selectActionDayDate(tester, selected);
        await tester.pumpAndSettle();
      } else if (origin == 'экран дня на дату') {
        unawaited(router.push(ActionDayDateRoute(date: today)));
        await tester.pumpAndSettle();
        await selectActionDayDate(tester, selected);
        await tester.pumpAndSettle();
      }
      final history = _history(router);
      await openQuickCreation(
        tester,
        QuickCreationMode.action,
        openedPage: find.byType(ActionEditorPage),
      );
      expect(_history(router).take(history.length), history);
      expect(router.stackData, hasLength(history.length + 1));
      final editor = tester.widget<ActionEditorPage>(
        find.byType(ActionEditorPage),
      );
      expect(
        editor.launch.date,
        origin == 'главная' || origin == 'страница намерения'
            ? today
            : selected,
      );
      expect(editor.launch.path, isNull);
      expect(find.byType(PathStartPickerPage), findsNothing);
      expect(find.text('Выберите причину'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Повторные запуски действия открывают один лист', (tester) async {
    final router = await _openApp(tester);
    final source = await _source(tester, router, _Origin.home);
    final history = _history(router);
    final launcher = QuickCreationLauncher();
    unawaited(
      launcher.launch(sourceContext: source, mode: QuickCreationMode.action),
    );
    unawaited(
      launcher.launch(sourceContext: source, mode: QuickCreationMode.action),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ActionEditorPage), findsOneWidget);
    expect(router.stackData, hasLength(history.length + 1));
    expect(_history(router).take(history.length), history);
    expect(tester.takeException(), isNull);
  });

  // Корневые пункты запускают одним путём: достаточно Главной и глубокой
  // страницы, над которой лежит чужая история.
  for (final origin in [_Origin.home, _Origin.deep]) {
    testWidgets('Намерение над ${origin.label}: один поток сохраняет историю', (
      tester,
    ) async {
      final router = await _openApp(tester);
      final source = await _source(tester, router, origin);
      final history = _history(router);
      final tabs = router.innerRouterOf<TabsRouter>(AppShellRoute.name)!;
      final selected = tabs.activeIndex;
      final launcher = QuickCreationLauncher();
      var finished = false;
      final running = launcher
          .launch(sourceContext: source, mode: QuickCreationMode.intention)
          .then((_) => finished = true);
      unawaited(
        launcher.launch(
          sourceContext: source,
          mode: QuickCreationMode.intention,
        ),
      );
      await tester.pumpAndSettle();
      expect(router.current.name, IntentionEditorRoute.name);
      expect(_history(router).take(history.length), history);
      expect(router.stackData, hasLength(history.length + 1));
      expect(tabs.activeIndex, selected);
      expect(finished, isTrue);
      await tester.tap(_key('intention-editor-close'));
      await tester.pumpAndSettle();
      await running;
      expect(_history(router), history);
      expect(tabs.activeIndex, selected);
      expect(tester.takeException(), isNull);
    });
  }
}
