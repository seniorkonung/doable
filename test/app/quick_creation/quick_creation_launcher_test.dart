import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/home/home_page.dart';
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

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

part 'quick_creation_launcher_test_support.dart';

void main() {
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
