import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/presentation/daily_choice_creation_completion.dart';
import 'package:doable/src/daily_choice/presentation/daily_choice_creation_flow_session.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_page.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });
  for (final direction in ChoicePathDraftDirection.values) {
    testWidgets(
      'завершение $direction сохраняет одну запись, исходную историю и выход',
      (tester) async {
        final app = await _launch(tester, direction);
        final history = app.history;
        await _tap(tester, 'daily-choice-submit');
        await tester.pumpAndSettle();
        expect(app.completions, hasLength(1));
        expect(
          await app.database.customSelect('SELECT id FROM daily_choices').get(),
          hasLength(1),
        );
        expect(
          app.router.stackData
              .take(history.length)
              .map((route) => route.matchId),
          history,
        );
        expect(find.textContaining('Дневной выбор создан'), findsWidgets);
        expect(app.router.stackData, hasLength(history.length + 1));
        expect(app.router.stackData.last.name, DailyChoiceDetailsRoute.name);
        expect(
          tester
              .widget<DailyChoiceDetailsPage>(
                find.byType(DailyChoiceDetailsPage),
              )
              .choiceId,
          durabilityChoice(201),
        );
        expect(find.byType(ChoicePathPage), findsNothing);
        expect(find.byType(DailyChoiceCreationPage), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(app.router.stackData.map((route) => route.matchId), history);
        expect(find.byType(IntentionDetailsPage), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('relation-editor-description')),
              )
              .controller!
              .text,
          'Чужой черновик',
        );
        expect(app.completions, hasLength(1));
        await tester.pump(const Duration(seconds: 8));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('graph-operation-message')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final direction in ChoicePathDraftDirection.values) {
    testWidgets(
      'прежнее завершение $direction не меняет открытый результат и новую сессию',
      (tester) async {
        final app = await _launch(tester, direction);
        final confirmationId = app.router.stackData.last.matchId;
        await _tap(tester, 'daily-choice-submit');
        expect(app.completions, hasLength(1));
        final savedHistory = app.router.stackData
            .map((route) => route.matchId)
            .toList();
        expect(app.router.stackData.last.name, DailyChoiceDetailsRoute.name);
        completeDailyChoiceCreation(
          router: app.router,
          session: app.session,
          confirmationMatchId: confirmationId,
          choiceId: durabilityChoice(201),
        );
        await tester.pumpAndSettle();
        expect(
          app.router.stackData.map((route) => route.matchId),
          savedHistory,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(app.router.stackData.map((route) => route.matchId), app.history);
        unawaited(
          app.router.push(
            ChoicePathRoute(
              sourceIntentionId: durabilityIntention(
                direction == ChoicePathDraftDirection.topDown ? 1 : 3,
              ),
              direction: direction,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final newHistory = app.router.stackData
            .map((route) => route.matchId)
            .toList();
        completeDailyChoiceCreation(
          router: app.router,
          session: app.session,
          confirmationMatchId: confirmationId,
          choiceId: durabilityChoice(201),
        );
        await tester.pumpAndSettle();
        expect(app.router.stackData.map((route) => route.matchId), newHistory);
        expect(app.completions, hasLength(1));
        expect(
          await app.database.customSelect('SELECT id FROM daily_choices').get(),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final class _App {
  _App(
    this.router,
    this.database,
    this.session,
    this.history,
    this.completions,
  );
  final AppRouter router;
  final AppDatabase database;
  final DailyChoiceCreationFlowSession session;
  final List<LocalKey> history;
  final List<DailyChoiceCommandCompletion> completions;
}

Future<_App> _launch(
  WidgetTester tester,
  ChoicePathDraftDirection direction,
) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final database = AppDatabase(openInMemoryLocalDatabase());
  await seedDurabilityGraph(database);
  final repository = durabilityRepository(database);
  final container = ProviderContainer(
    overrides: [
      inMemoryQuickCreationModeOverride,
      personalGraphRepositoryProvider.overrideWithValue(repository),
    ],
  );
  final router = AppRouter();
  final completions = <DailyChoiceCommandCompletion>[];
  final subscription = container
      .read(graphCommandCoordinatorProvider.notifier)
      .completions
      .where((completion) => completion is DailyChoiceCommandCompletion)
      .cast<DailyChoiceCommandCompletion>()
      .listen(completions.add);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await subscription.cancel();
    container.dispose();
    router.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
        builder: (_, child) => GraphOperationPresenter(child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(
    router.push(IntentionDetailsRoute(intentionId: durabilityIntention(1))),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Связи'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const ValueKey('relation-neighborhood-create-relation')).first,
  );
  await tester.tap(
    find.byKey(const ValueKey('relation-neighborhood-create-relation')).first,
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('relation-editor-description')),
    'Чужой черновик',
  );
  unawaited(
    router.push(IntentionDetailsRoute(intentionId: durabilityIntention(2))),
  );
  await tester.pumpAndSettle();
  final history = [for (final route in router.stackData) route.matchId];
  unawaited(
    router.push(
      ChoicePathRoute(
        sourceIntentionId: durabilityIntention(
          direction == ChoicePathDraftDirection.topDown ? 1 : 3,
        ),
        direction: direction,
      ),
    ),
  );
  await tester.pumpAndSettle();
  final session = tester
      .state<ChoicePathPageState>(find.byType(ChoicePathPage))
      .creationSession!;
  for (final relation
      in direction == ChoicePathDraftDirection.topDown
          ? [101, 102]
          : [102, 101]) {
    await _tap(tester, 'choice-path-continue-${durabilityUuid(relation)}');
  }
  await _tap(
    tester,
    direction == ChoicePathDraftDirection.topDown
        ? 'choice-path-select-action'
        : 'choice-path-select-source',
  );
  await _tap(tester, 'choice-path-open-confirmation');
  return _App(router, database, session, history, completions);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
