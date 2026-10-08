import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_button.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_presentation.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_root_pages.dart';
import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  for (final mode in QuickCreationMode.values) {
    final modeName = switch (mode) {
      QuickCreationMode.intention => 'Новое намерение',
      QuickCreationMode.relation => 'Новая связь',
      QuickCreationMode.dailyChoiceFromIntention =>
        'Дневной выбор от намерения',
      QuickCreationMode.dailyChoiceFromAction => 'Дневной выбор от действия',
    };
    for (final origin in [
      'Главная',
      'Дневные выборы',
      'Граф намерений',
      'Глубокая страница',
    ]) {
      testWidgets('$modeName: панель запускает один поток над $origin', (
        tester,
      ) async {
        final router = await _start(tester);
        final destination = switch (origin) {
          'Главная' => AppDestination.home,
          'Граф намерений' => AppDestination.intentionGraph,
          _ => AppDestination.dailyChoices,
        };
        await tester.tap(appNavigationDestination(destination));
        await tester.pumpAndSettle();
        if (origin == 'Глубокая страница') {
          unawaited(
            router.push(
              RelationEditorRoute(
                editorContext: const RelationBlankCreationContext(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            _key('relation-editor-description'),
            'Чужой черновик',
          );
          unawaited(
            router.push(
              IntentionDetailsRoute(intentionId: durabilityIntention(2)),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(_key('intention-details-edit'));
          await tester.pumpAndSettle();
          await tester.enterText(
            _key('intention-details-edit-title'),
            'Несохранённое название',
          );
        }
        final history = _history(router);
        await _selectMode(tester, mode);
        expect(_history(router), history);
        expect(router.hasPagelessTopRoute, isFalse);
        expect(
          tester
              .widget<AppNavigationBar>(find.byType(AppNavigationBar))
              .selected,
          destination,
        );
        await tester.tap(find.byType(QuickCreationButton));
        await tester.tap(find.byType(QuickCreationButton));
        await tester.pumpAndSettle();
        expect(router.current.name, switch (mode) {
          QuickCreationMode.intention => IntentionEditorRoute.name,
          QuickCreationMode.relation => RelationEditorRoute.name,
          QuickCreationMode.dailyChoiceFromIntention =>
            DailyChoiceSourcePickerRoute.name,
          QuickCreationMode.dailyChoiceFromAction =>
            DailyChoiceActionPickerRoute.name,
        });
        expect(_history(router).take(history.length), history);
        expect(router.stackData, hasLength(history.length + 1));
        switch (mode) {
          case QuickCreationMode.intention:
            await tester.tap(_key('intention-editor-close'));
          case QuickCreationMode.relation:
            expect(
              router.current.argsAs<RelationEditorRouteArgs>().editorContext,
              isA<RelationBlankCreationContext>(),
            );
            await tester.tap(find.text('Отменить создание'));
          case QuickCreationMode.dailyChoiceFromIntention ||
              QuickCreationMode.dailyChoiceFromAction:
            final topDown = mode == QuickCreationMode.dailyChoiceFromIntention;
            final candidate = topDown ? 1 : 3;
            await tester.tap(
              find.descendant(
                of: _key(
                  'daily-choice-${topDown ? 'source' : 'action'}-${durabilityUuid(candidate)}',
                ),
                matching: find.byType(IntentionSummaryView),
              ),
            );
            await tester.pumpAndSettle();
            final path = tester.widget<ChoicePathPage>(
              find.byType(ChoicePathPage),
            );
            expect(path.sourceIntentionId, durabilityIntention(candidate));
            expect(
              path.direction,
              topDown
                  ? ChoicePathDraftDirection.topDown
                  : ChoicePathDraftDirection.bottomUp,
            );
            expect(_history(router).take(history.length), history);
            expect(router.stackData, hasLength(history.length + 1));
            await tester.tap(find.text('Отменить создание'));
        }
        await tester.pumpAndSettle();
        expect(_history(router), history);
        expect(
          tester
              .widget<AppNavigationBar>(find.byType(AppNavigationBar))
              .selected,
          destination,
        );
        if (origin == 'Глубокая страница') {
          expect(
            tester
                .widget<TextField>(_key('intention-details-edit-title'))
                .controller!
                .text,
            'Несохранённое название',
          );
          await router.maybePop();
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextField>(_key('relation-editor-description'))
                .controller!
                .text,
            'Чужой черновик',
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

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
List<LocalKey> _history(AppRouter router) => [
  for (final route in router.stackData) route.matchId,
];

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
