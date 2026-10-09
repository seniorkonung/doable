import 'dart:async';

import 'package:auto_route/auto_route.dart';
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
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

enum _FailurePoint {
  none,
  beforeConfirmation,
  beforeRoot,
  afterRoot,
  afterResult,
}

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });
  for (final direction in ChoicePathDraftDirection.values) {
    for (final point in _FailurePoint.values) {
      testWidgets(
        'завершение $direction при $point сохраняет одну запись, исходную историю и выход',
        (tester) async {
          final app = await _launch(tester, direction, point);
          final history = app.session.originalHistory;
          final confirmationId = app.router.stackData.last.matchId;
          final oldConfirmation = tester.state<DailyChoiceCreationPageState>(
            find.byType(DailyChoiceCreationPage),
          );
          await _tap(tester, 'daily-choice-submit');
          await tester.pumpAndSettle();
          expect(app.completions, hasLength(1));
          expect(
            await app.database
                .customSelect('SELECT id FROM daily_choices')
                .get(),
            hasLength(1),
          );
          expect(app.session.canContinue, isFalse);
          expect(
            app.router.stackData
                .take(history.length)
                .map((route) => route.matchId),
            history,
          );
          final active = switch (app.session.state) {
            DailyChoiceCreationFlowActiveState value => value,
            DailyChoiceCreationFlowLeft(:final lastActiveState) =>
              lastActiveState,
          };
          expect(active, isA<DailyChoiceCreationFlowSaved>());
          expect(find.textContaining('Дневной выбор создан'), findsWidgets);
          if (point == _FailurePoint.none ||
              point == _FailurePoint.afterResult) {
            expect(app.router.stackData, hasLength(history.length + 1));
            expect(
              app.router.stackData.last.name,
              DailyChoiceDetailsRoute.name,
            );
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
            expect(oldConfirmation.mounted, isFalse);
            if (point == _FailurePoint.afterResult) {
              final resultMatchId = app.router.stackData.last.matchId;
              app.router.releaseFailure();
              await tester.pumpAndSettle();
              expect(app.router.stackData.last.matchId, resultMatchId);
              expect(find.byType(DailyChoiceDetailsPage), findsOneWidget);
            }
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
          } else {
            if (point == _FailurePoint.beforeConfirmation) {
              expect(app.router.stackData.last.matchId, confirmationId);
              await completeDailyChoiceCreation(
                router: app.router,
                session: app.session,
                confirmationMatchId: confirmationId,
                choiceId: durabilityChoice(201),
              );
              expect(app.errors, hasLength(1));
              expect(
                tester
                    .widget<FilledButton>(
                      find.byKey(const ValueKey('daily-choice-submit')),
                    )
                    .onPressed,
                isNull,
              );
              await tester.binding.handlePopRoute();
              await tester.pumpAndSettle();
            }
            if (point != _FailurePoint.afterRoot) {
              expect(
                app.router.stackData.last.matchId,
                app.session.rootMatchId,
              );
              expect(
                find.byKey(const ValueKey('choice-path-creation-status')),
                findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('choice-path-open-confirmation')),
                findsNothing,
              );
              expect(
                find.byKey(const ValueKey('choice-path-select-action')),
                findsNothing,
              );
              expect(
                find.byKey(const ValueKey('choice-path-select-source')),
                findsNothing,
              );
              expect(
                find.byKey(const ValueKey('choice-path-back-0')),
                findsNothing,
              );
              await tester.binding.handlePopRoute();
              await tester.pumpAndSettle();
            }
          }
          expect(app.router.stackData.map((route) => route.matchId), history);
          expect(find.byType(IntentionDetailsPage), findsOneWidget);
          expect(app.errors, hasLength(point == _FailurePoint.none ? 0 : 1));
          for (final error in app.errors) {
            expect(error.library, 'daily choice creation');
            expect(error.toString(), isNot(contains('Секретный черновик')));
            expect(error.toString(), isNot(contains(durabilityUuid(201))));
          }
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
          expect(
            app.router.replacements,
            point == _FailurePoint.beforeConfirmation ? 0 : 1,
          );
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
    for (final point in [_FailurePoint.beforeRoot, _FailurePoint.afterResult]) {
      testWidgets(
        'поздний отказ $point и прежнее завершение $direction сохраняют новую сессию',
        (tester) async {
          final app = await _launch(
            tester,
            direction,
            point,
            delayFailure: true,
          );
          final confirmationId = app.router.stackData.last.matchId;
          await _tap(tester, 'daily-choice-submit');
          expect(app.completions, hasLength(1));
          expect(app.errors, isEmpty);
          final savedHistory = app.router.stackData
              .map((route) => route.matchId)
              .toList();
          await completeDailyChoiceCreation(
            router: app.router,
            session: app.session,
            confirmationMatchId: confirmationId,
            choiceId: durabilityChoice(201),
          );
          expect(
            app.router.stackData.map((route) => route.matchId),
            savedHistory,
          );
          expect(app.router.replacements, 1);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(
            app.router.stackData.map((route) => route.matchId),
            app.session.originalHistory,
          );
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
          final newSession = tester
              .state<ChoicePathPageState>(find.byType(ChoicePathPage))
              .creationSession!;
          final newHistory = app.router.stackData
              .map((route) => route.matchId)
              .toList();
          expect(newSession.flowId, isNot(same(app.session.flowId)));
          app.router.releaseFailure();
          await tester.pumpAndSettle();
          await completeDailyChoiceCreation(
            router: app.router,
            session: app.session,
            confirmationMatchId: confirmationId,
            choiceId: durabilityChoice(201),
          );
          expect(
            app.router.stackData.map((route) => route.matchId),
            newHistory,
          );
          expect(newSession.state, isA<DailyChoiceCreationFlowEditing>());
          expect(app.completions, hasLength(1));
          expect(
            await app.database
                .customSelect('SELECT id FROM daily_choices')
                .get(),
            hasLength(1),
          );
          expect(app.router.replacements, 1);
          expect(app.errors, hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

final class _App {
  _App(this.router, this.database, this.session, this.completions, this.errors);
  final _FailingRouter router;
  final AppDatabase database;
  final DailyChoiceCreationFlowSession session;
  final List<DailyChoiceCommandCompletion> completions;
  final List<FlutterErrorDetails> errors;
}

Future<_App> _launch(
  WidgetTester tester,
  ChoicePathDraftDirection direction,
  _FailurePoint point, {
  bool delayFailure = false,
}) async {
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
  final router = _FailingRouter(point, delayFailure: delayFailure);
  final errors = <FlutterErrorDetails>[];
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.library == 'daily choice creation') {
      errors.add(details);
    } else {
      previousOnError?.call(details);
    }
  };
  final completions = <DailyChoiceCommandCompletion>[];
  final subscription = container
      .read(graphCommandCoordinatorProvider.notifier)
      .completions
      .where((completion) => completion is DailyChoiceCommandCompletion)
      .cast<DailyChoiceCommandCompletion>()
      .listen(completions.add);
  addTearDown(() async {
    FlutterError.onError = previousOnError;
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
  return _App(router, database, session, completions, errors);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Настоящий стек приложения с управляемыми отказами отдельных мутаций.
final class _FailingRouter extends RootStackRouter {
  _FailingRouter(this.point, {this.delayFailure = false});
  final _FailurePoint point;
  final bool delayFailure;
  final _gate = Completer<void>();
  var replacements = 0;
  @override
  List<AutoRoute> get routes => AppRouter().routes;

  void releaseFailure() => _gate.complete();

  @override
  void removeRoute(RouteData route, {bool notify = true}) {
    if (point == _FailurePoint.beforeConfirmation &&
        route.name == DailyChoiceCreationRoute.name) {
      throw StateError('Секретный черновик ${durabilityUuid(201)}');
    }
    super.removeRoute(route, notify: notify);
  }

  @override
  Future<T?> replace<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) {
    if (route.routeName != DailyChoiceDetailsRoute.name) {
      return super.replace<T>(route, onFailure: onFailure);
    }
    replacements++;
    if (point == _FailurePoint.beforeRoot) {
      if (delayFailure) {
        return _gate.future.then<T?>(
          (_) => throw StateError('Секретный черновик'),
        );
      }
      throw StateError('Секретный черновик');
    }
    if (point == _FailurePoint.afterRoot) {
      removeRoute(stackData.last, notify: false);
      return Future<T?>.error(StateError('Секретный черновик'));
    }
    if (point == _FailurePoint.afterResult) {
      unawaited(super.replace<T>(route, onFailure: onFailure));
      return _gate.future.then<T?>(
        (_) => throw StateError('Секретный черновик'),
      );
    }
    return super.replace<T>(route, onFailure: onFailure);
  }
}
