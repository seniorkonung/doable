import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/daily_choice_creation_flow_session.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_page.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/shared/presentation/creation_exit_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

enum _Step { path, preview, confirmation }

enum _Failure { none, confirmation, root, afterRoot }

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });
  for (final direction in ChoicePathDraftDirection.values) {
    for (final step in _Step.values) {
      testWidgets(
        'отмена $direction из $step сохраняет историю и чужой черновик',
        (tester) async {
          final app = await _launch(tester, direction, step);
          final exit = find.byType(CreationExitAction);
          expect(exit, findsOneWidget);
          await tester.ensureVisible(exit);
          await tester.tap(
            find.descendant(of: exit, matching: find.byType(TextButton)),
          );
          expect(app.session.state, isA<DailyChoiceCreationFlowLeft>());
          expect(app.session.canContinue, isFalse);
          await tester.pumpAndSettle();
          await _expectOriginalHistory(tester, app);
          expect(app.completions, isEmpty);
          expect(app.repository.commands, 0);
          expect(
            await app.database
                .customSelect('SELECT id FROM daily_choices')
                .get(),
            hasLength(1),
          );
          expect(app.errors, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final fromPath in [false, true]) {
      for (final succeeds in [false, true]) {
        testWidgets(
          'выход $direction ${fromPath ? 'из пути' : 'из подтверждения'} '
          'сохраняет одну запись и поздний ${succeeds ? 'успех' : 'отказ'} не меняет новую сессию',
          (tester) async {
            final app = await _launch(tester, direction, _Step.confirmation);
            await tester.enterText(
              find.byKey(const ValueKey('daily-choice-description')),
              'Сохранить один раз',
            );
            await _tap(tester, 'daily-choice-submit');
            expect(app.repository.commands, 1);
            if (fromPath) {
              await tester.binding.handlePopRoute();
              await tester.pumpAndSettle();
              expect(
                find.byKey(const ValueKey('choice-path-open-confirmation')),
                findsNothing,
              );
            }
            final exit = tester.widget<CreationExitAction>(
              find.byType(CreationExitAction),
            );
            expect(exit.state, CreationExitState.submitting);
            expect(find.text('Выйти из создания'), findsOneWidget);
            exit.onExit();
            expect(app.session.state, isA<DailyChoiceCreationFlowLeft>());
            await tester.pumpAndSettle();
            expect(
              app.router.stackData.map((r) => r.matchId),
              app.session.originalHistory,
            );
            unawaited(
              app.router.push(
                ChoicePathRoute(
                  sourceIntentionId: durabilityIntention(1),
                  direction: ChoicePathDraftDirection.topDown,
                ),
              ),
            );
            await tester.pumpAndSettle();
            final newSession = tester
                .state<ChoicePathPageState>(find.byType(ChoicePathPage))
                .creationSession!;
            final newHistory = app.router.stackData
                .map((r) => r.matchId)
                .toList();
            app.repository.result.complete(succeeds);
            await tester.pumpAndSettle();
            exit.onExit();
            expect(app.router.stackData.map((r) => r.matchId), newHistory);
            expect(newSession.canContinue, isTrue);
            expect(app.repository.commands, 1);
            expect(app.completions, hasLength(1));
            expect(
              await app.database
                  .customSelect('SELECT id FROM daily_choices')
                  .get(),
              hasLength(succeeds ? 2 : 1),
            );
            expect(
              find.byKey(const ValueKey('graph-operation-message')),
              findsOneWidget,
            );
            await tester.pump(const Duration(seconds: 8));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('graph-operation-message')),
              findsNothing,
            );
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            await _expectOriginalHistory(tester, app);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
    for (final cancelFirst in [true, false]) {
      testWidgets(
        'гонка $direction: ${cancelFirst ? 'отмена' : 'отправка'} первой до кадра',
        (tester) async {
          final app = await _launch(tester, direction, _Step.confirmation);
          final submit = tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('daily-choice-submit')),
              )
              .onPressed!;
          final exit = tester
              .widget<CreationExitAction>(find.byType(CreationExitAction))
              .onExit;
          if (cancelFirst) {
            exit();
            submit();
          } else {
            submit();
            exit();
          }
          expect(app.session.canContinue, isFalse);
          await tester.pumpAndSettle();
          expect(app.repository.commands, cancelFirst ? 0 : 1);
          if (!cancelFirst) {
            app.repository.result.complete(true);
            await tester.pumpAndSettle();
          }
          await _expectOriginalHistory(tester, app);
          expect(app.completions, hasLength(cancelFirst ? 0 : 1));
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final failure in _Failure.values.where(
      (value) => value != _Failure.none,
    )) {
      testWidgets(
        'отказ выхода $direction при $failure допускает только повтор выхода',
        (tester) async {
          final app = await _launch(tester, direction, _Step.confirmation);
          final confirmation = app.router.current.matchId;
          app.router.failure = failure;
          final exit = tester
              .widget<CreationExitAction>(find.byType(CreationExitAction))
              .onExit;
          exit();
          await tester.pumpAndSettle();
          expect(app.errors, hasLength(1));
          expect(
            app.errors.single.toString(),
            isNot(contains('Секретный черновик')),
          );
          expect(
            app.errors.single.toString(),
            isNot(contains(durabilityUuid(201))),
          );
          expect(app.session.state, isA<DailyChoiceCreationFlowLeft>());
          expect(app.router.leftBeforeRemoval, isTrue);
          if (failure == _Failure.confirmation) {
            expect(app.router.current.matchId, confirmation);
            expect(
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('daily-choice-submit')),
                  )
                  .onPressed,
              isNull,
            );
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('daily-choice-description')),
                  )
                  .enabled,
              isFalse,
            );
          }
          if (failure != _Failure.afterRoot) {
            final retry = tester.widget<CreationExitAction>(
              find.byType(CreationExitAction),
            );
            expect(retry.state, CreationExitState.terminal);
            retry.onExit();
            await tester.pumpAndSettle();
          }
          await _expectOriginalHistory(tester, app);
          exit();
          expect(app.repository.commands, 0);
          expect(app.completions, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'отказ команды $direction сохраняет ввод и допускает явную отмену',
      (tester) async {
        final app = await _launch(tester, direction, _Step.confirmation);
        await tester.enterText(
          find.byKey(const ValueKey('daily-choice-description')),
          'Сохранить ввод после отказа',
        );
        await _tap(tester, 'daily-choice-submit');
        app.repository.result.complete(false);
        await tester.pumpAndSettle();
        expect(app.session.canContinue, isTrue);
        expect(find.text('Сохранить ввод после отказа'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('daily-choice-submit')),
              )
              .onPressed,
          isNotNull,
        );
        final exit = tester.widget<CreationExitAction>(
          find.byType(CreationExitAction),
        );
        expect(exit.state, CreationExitState.cancellable);
        exit.onExit();
        await tester.pumpAndSettle();
        await _expectOriginalHistory(tester, app);
        expect(app.repository.commands, 1);
        expect(app.completions, hasLength(1));
        expect(
          await app.database.customSelect('SELECT id FROM daily_choices').get(),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'отказ удаления после подсказки $direction оставляет безопасный повтор',
      (tester) async {
        final app = await _launch(tester, direction, _Step.preview);
        app.router.failure = _Failure.root;
        tester
            .widget<CreationExitAction>(find.byType(CreationExitAction))
            .onExit();
        await tester.pumpAndSettle();
        expect(app.errors, hasLength(1));
        expect(app.router.current.matchId, app.session.rootMatchId);
        expect(app.router.pagelessRoutesObserver.hasPagelessTopRoute, isFalse);
        expect(app.session.canContinue, isFalse);
        expect(
          find.byKey(const ValueKey('choice-suggestion-select-0')),
          findsNothing,
        );
        final retry = tester.widget<CreationExitAction>(
          find.byType(CreationExitAction),
        );
        expect(retry.state, CreationExitState.terminal);
        retry.onExit();
        await tester.pumpAndSettle();
        await _expectOriginalHistory(tester, app);
        expect(app.repository.commands, 0);
        expect(tester.takeException(), isNull);
      },
    );
    for (final failure in [_Failure.confirmation, _Failure.root]) {
      testWidgets(
        'поздний отказ записи $direction после частичного выхода при $failure не возобновляет поток',
        (tester) async {
          final app = await _launch(tester, direction, _Step.confirmation);
          await _tap(tester, 'daily-choice-submit');
          app.router.failure = failure;
          tester
              .widget<CreationExitAction>(find.byType(CreationExitAction))
              .onExit();
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<CreationExitAction>(find.byType(CreationExitAction))
                .state,
            CreationExitState.submitting,
          );
          app.repository.result.complete(false);
          await tester.pumpAndSettle();
          expect(app.session.canContinue, isFalse);
          final retry = tester.widget<CreationExitAction>(
            find.byType(CreationExitAction),
          );
          expect(retry.state, CreationExitState.terminal);
          retry.onExit();
          await tester.pumpAndSettle();
          await _expectOriginalHistory(tester, app);
          expect(app.repository.commands, 1);
          expect(app.completions, hasLength(1));
          expect(app.errors, hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'прежние действия пути и подсказки $direction не закрывают другую верхнюю страницу',
      (tester) async {
        final app = await _launch(tester, direction, _Step.path);
        final rootExit = tester
            .widget<CreationExitAction>(find.byType(CreationExitAction))
            .onExit;
        await _tap(tester, 'choice-suggestion-view-0');
        final previewExit = tester
            .widget<CreationExitAction>(find.byType(CreationExitAction))
            .onExit;
        rootExit();
        expect(app.session.canContinue, isTrue);
        expect(app.router.pagelessRoutesObserver.hasPagelessTopRoute, isTrue);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        previewExit();
        expect(app.session.canContinue, isTrue);
        await _tap(tester, 'choice-suggestion-select-0');
        rootExit();
        previewExit();
        expect(app.session.canContinue, isTrue);
        expect(app.router.current.name, DailyChoiceCreationRoute.name);
        tester
            .widget<CreationExitAction>(find.byType(CreationExitAction))
            .onExit();
        await tester.pumpAndSettle();
        await _expectOriginalHistory(tester, app);
        expect(app.repository.commands, 0);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'назад из подсказки и подтверждения $direction сохраняет поток',
      (tester) async {
        final app = await _launch(tester, direction, _Step.preview);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(app.session.canContinue, isTrue);
        await _tap(tester, 'choice-suggestion-select-0');
        await tester.enterText(
          find.byKey(const ValueKey('daily-choice-description')),
          'Черновик подтверждения',
        );
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        expect(find.byType(DailyChoiceCreationPage), findsOneWidget);
        expect(app.session.canContinue, isTrue);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(app.router.current.matchId, app.session.rootMatchId);
        expect(app.session.canContinue, isTrue);
        await _tap(tester, 'choice-suggestion-select-0');
        tester
            .widget<CreationExitAction>(find.byType(CreationExitAction))
            .onExit();
        await tester.pumpAndSettle();
        await _expectOriginalHistory(tester, app);
        expect(app.repository.commands, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final class _App {
  _App(
    this.router,
    this.database,
    this.repository,
    this.session,
    this.completions,
    this.errors,
  );
  final _Router router;
  final AppDatabase database;
  final _Repository repository;
  final DailyChoiceCreationFlowSession session;
  final List<DailyChoiceCommandCompletion> completions;
  final List<FlutterErrorDetails> errors;
}

Future<_App> _launch(
  WidgetTester tester,
  ChoicePathDraftDirection direction,
  _Step step,
) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final database = AppDatabase(openInMemoryLocalDatabase());
  await seedDurabilityGraph(database);
  await durabilityRepository(database).execute(durabilityCreate());
  final repository = _Repository(
    durabilityRepository(database, choiceNumber: 202, firstStepNumber: 303),
  );
  final container = ProviderContainer(
    overrides: [
      inMemoryQuickCreationModeOverride,
      personalGraphRepositoryProvider.overrideWithValue(repository),
    ],
  );
  final router = _Router();
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
  await _tap(tester, 'relation-neighborhood-create-relation');
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
  router.session = session;
  switch (step) {
    case _Step.path:
      break;
    case _Step.preview:
      await _tap(tester, 'choice-suggestion-view-0');
    case _Step.confirmation:
      await _tap(tester, 'choice-suggestion-select-0');
      expect(find.byType(DailyChoiceCreationPage), findsOneWidget);
  }
  return _App(router, database, repository, session, completions, errors);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key)).first;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _expectOriginalHistory(WidgetTester tester, _App app) async {
  expect(
    app.router.stackData.map((route) => route.matchId),
    app.session.originalHistory,
  );
  expect(app.router.pagelessRoutesObserver.hasPagelessTopRoute, isFalse);
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
}

final class _Router extends RootStackRouter {
  var failure = _Failure.none;
  DailyChoiceCreationFlowSession? session;
  var leftBeforeRemoval = false;
  @override
  List<AutoRoute> get routes => AppRouter().routes;

  @override
  void removeRoute(RouteData route, {bool notify = true}) {
    leftBeforeRemoval = session?.state is DailyChoiceCreationFlowLeft;
    final shouldFail = switch (failure) {
      _Failure.none => false,
      _Failure.confirmation => route.name == DailyChoiceCreationRoute.name,
      _Failure.root || _Failure.afterRoot => route.name == ChoicePathRoute.name,
    };
    if (!shouldFail) {
      super.removeRoute(route, notify: notify);
      return;
    }
    if (failure == _Failure.afterRoot) super.removeRoute(route, notify: false);
    failure = _Failure.none;
    throw StateError('Секретный черновик ${durabilityUuid(201)}');
  }
}

/// Чтения идут в настоящее хранилище, а принятую запись завершает проверка.
final class _Repository implements PersonalGraphRepository {
  _Repository(this.delegate);
  final PersonalGraphRepository delegate;
  final result = Completer<bool>();
  var commands = 0;

  @override
  Future<GraphCommandResult<S, F>> execute<
    S extends GraphCommandOutcome,
    F extends GraphCommandFailure
  >(GraphCommand<S, F> command) async {
    if (command is CreateDailyChoice) {
      commands++;
      if (!await result.future) {
        return GraphCommandFailed<S, F>(
          const DailyChoiceUnavailableFailure() as F,
        );
      }
    }
    return delegate.execute(command);
  }

  @override
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) => delegate.getChoicePathSuggestions(query);
  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => delegate.getChoicePathContinuations(query);
  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      delegate.watchDailyChoice(id);
  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => delegate.watchIntention(id);
  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId id,
  ) => delegate.getRelationCounts(id);
  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => delegate.getRelationGroupPage(query);
  @override
  Future<FavoriteIntentionsResult> getFavoriteIntentions() =>
      delegate.getFavoriteIntentions();
  @override
  Future<TagAssignmentsResult> getTagAssignments(IntentionId id) =>
      delegate.getTagAssignments(id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
