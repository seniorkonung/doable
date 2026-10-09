import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/daily_choice_creation_launcher.dart';
import 'package:doable/src/daily_choice/presentation/daily_choice_picker_context.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/quick_creation.dart';

void main() {
  _defineLatePickerTests();
  for (final failPath in [false, true]) {
    testWidgets(
      'отказ открытия ${failPath ? 'пути' : 'поиска'} сохраняет историю и разрешает новый запуск',
      (tester) async {
        final errors = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.library == 'daily choice creation') {
            errors.add(details);
          } else {
            previousOnError?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = previousOnError);
        final router = _FailingLaunchRouter(failPath: failPath);
        await _openApp(tester, router: router);
        final source = await _sourceContext(tester, router);
        final history = router.stackData.map((route) => route.matchId).toList();
        final launcher = DailyChoiceCreationLauncher();
        final first = launcher.launch(
          sourceContext: source,
          direction: ChoicePathDraftDirection.topDown,
        );
        await tester.pumpAndSettle();
        if (failPath) {
          await _choose(tester, ChoicePathDraftDirection.topDown, 1);
        }
        await first;
        expect(router.stackData.map((route) => route.matchId), history);
        expect(errors, hasLength(1));
        expect(
          errors.single.exception.toString(),
          isNot(contains('Секретный текст')),
        );
        final next = launcher.launch(
          sourceContext: source,
          direction: ChoicePathDraftDirection.topDown,
        );
        await tester.pumpAndSettle();
        expect(router.current.name, DailyChoiceSourcePickerRoute.name);
        await tester.tap(find.text('Отменить создание'));
        await tester.pumpAndSettle();
        await next;
        expect(router.stackData.map((route) => route.matchId), history);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'общая панель запускает начальное создание от действия с отменой',
    (tester) async {
      final router = await _openApp(tester);
      final history = router.stackData.map((route) => route.matchId).toList();
      await openQuickCreation(
        tester,
        QuickCreationMode.dailyChoiceFromAction,
        openedPage: find.byType(DailyChoiceActionPickerPage),
        activate: (tester, button) async {
          await tester.tap(button);
          await tester.tap(button);
        },
      );
      expect(router.stackData, hasLength(history.length + 1));
      expect(router.current.name, DailyChoiceActionPickerRoute.name);
      expect(
        router.current.argsAs<DailyChoiceActionPickerRouteArgs>().pickerContext,
        isA<InitialDailyChoicePickerContext>(),
      );
      await tester.tap(find.text('Отменить создание'));
      await tester.pumpAndSettle();
      expect(router.stackData.map((route) => route.matchId), history);
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in ChoicePathDraftDirection.values) {
    for (final closeIcon in [false, true]) {
      testWidgets(
        '${_directionName(direction)}: ${closeIcon ? 'крестик' : 'текстовая отмена'} '
        'при клавиатуре сохраняет глубокую историю и запрещает поздний путь',
        (tester) async {
          final router = await _openApp(tester);
          final source = await _sourceContext(tester, router, deep: true);
          final history = router.stackData.map((data) => data.matchId).toList();
          final launcher = DailyChoiceCreationLauncher();
          final running = launcher.launch(
            sourceContext: source,
            direction: direction,
          );
          await tester.pumpAndSettle();
          final launch = _pickerContext(router).launch;
          final lateSelection = tester
              .widget<IntentionSummaryView>(
                find.byType(IntentionSummaryView).first,
              )
              .onTap!;
          final prefix = direction == ChoicePathDraftDirection.topDown
              ? 'source'
              : 'action';
          final filter = find.byKey(ValueKey('daily-choice-$prefix-filter'));
          await tester.enterText(filter, 'Намерение 3');
          tester.view.physicalSize = const Size(400, 800);
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          tester.platformDispatcher.textScaleFactorTestValue = 2.6;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpAndSettle();
          final action = closeIcon
              ? find.byKey(ValueKey('daily-choice-$prefix-cancel'))
              : find.widgetWithText(TextButton, 'Отменить создание');
          expect(action.hitTestable(), findsOneWidget);
          expect(tester.getRect(action).bottom, lessThanOrEqualTo(540));
          await tester.tap(action);
          expect(launch.isActive, isFalse);
          lateSelection();
          await tester.pumpAndSettle();
          await running;
          expect(router.stackData.map((data) => data.matchId), history);
          expect(find.byType(ChoicePathPage), findsNothing);

          final next = launcher.launch(
            sourceContext: source,
            direction: direction,
          );
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(filter).controller!.text, isEmpty);
          expect(_pickerContext(router).launch, isNot(same(launch)));
          await tester.tap(find.byKey(ValueKey('daily-choice-$prefix-cancel')));
          await tester.pumpAndSettle();
          await next;
          expect(router.stackData.map((data) => data.matchId), history);
          await router.maybePop();
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
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final deep in [false, true]) {
      testWidgets(
        '${_directionName(direction)}: явный выбор над ${deep ? 'глубокой страницей' : 'корнем'} '
        'закрывает поиск, строит путь и сохраняет исходную историю',
        (tester) async {
          final router = await _openApp(tester);
          final source = await _sourceContext(tester, router, deep: deep);
          final history = router.stackData
              .map((route) => route.matchId)
              .toList();
          final launcher = DailyChoiceCreationLauncher();
          final running = launcher.launch(
            sourceContext: source,
            direction: direction,
          );
          unawaited(
            launcher.launch(sourceContext: source, direction: direction),
          );
          await tester.pumpAndSettle();
          expect(router.stackData, hasLength(history.length + 1));
          expect(router.current.name, _pickerName(direction));
          expect(_pickerContext(router).launch.isActive, isTrue);
          expect(find.text('Отменить создание'), findsOneWidget);
          if (direction == ChoicePathDraftDirection.bottomUp) {
            expect(find.text('Намерение 1'), findsNothing);
          }
          await _choose(
            tester,
            direction,
            direction == ChoicePathDraftDirection.topDown ? 1 : 3,
          );
          final page = tester.widget<ChoicePathPage>(
            find.byType(ChoicePathPage),
          );
          final session = tester
              .state<ChoicePathPageState>(find.byType(ChoicePathPage))
              .creationSession!;
          expect(page.direction, direction);
          expect(
            page.sourceIntentionId,
            durabilityIntention(
              direction == ChoicePathDraftDirection.topDown ? 1 : 3,
            ),
          );
          expect(session.originalHistory, history);
          expect(
            router.stackData.map((route) => route.name),
            isNot(contains(_pickerName(direction))),
          );
          for (final relation
              in direction == ChoicePathDraftDirection.topDown
                  ? [101, 102]
                  : [102, 101]) {
            await _tapKey(
              tester,
              'choice-path-continue-${durabilityUuid(relation)}',
            );
          }
          expect(
            find.byKey(
              ValueKey(
                direction == ChoicePathDraftDirection.topDown
                    ? 'choice-path-select-action'
                    : 'choice-path-select-source',
              ),
            ),
            findsOneWidget,
          );
          await tester.tap(find.text('Отменить создание'));
          await tester.pumpAndSettle();
          await running;
          expect(router.stackData.map((route) => route.matchId), history);
          expect(
            router.innerRouterOf<TabsRouter>(AppShellRoute.name)!.activeIndex,
            1,
          );
          final next = launcher.launch(
            sourceContext: source,
            direction: direction,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Отменить создание'));
          await tester.pumpAndSettle();
          await next;
          expect(router.stackData.map((route) => route.matchId), history);
          if (deep) {
            await router.maybePop();
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
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      '${_directionName(direction)}: пустой граф объясняет отсутствие кандидатов и допускает отмену',
      (tester) async {
        final router = await _openApp(tester, empty: true);
        final source = await _sourceContext(tester, router);
        final running = DailyChoiceCreationLauncher().launch(
          sourceContext: source,
          direction: direction,
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(source);
        expect(
          find.text(
            direction == ChoicePathDraftDirection.topDown
                ? l10n.sourcePickerEmpty
                : l10n.actionPickerEmpty,
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Отменить создание'));
        await tester.pumpAndSettle();
        await running;
        expect(router.stackData, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${_directionName(direction)}: запуск над подробностями кандидата независим от нижнего поиска',
      (tester) async {
        final router = await _openApp(tester);
        final source = await _sourceContext(tester, router);
        final first = DailyChoiceCreationLauncher().launch(
          sourceContext: source,
          direction: direction,
        );
        await tester.pumpAndSettle();
        final firstContext = _pickerContext(router);
        final firstId = router.current.matchId;
        final prefix = direction == ChoicePathDraftDirection.topDown
            ? 'source'
            : 'action';
        await tester.enterText(
          find.byKey(ValueKey('daily-choice-$prefix-filter')),
          'Намерение 3',
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(source);
        await tester.tap(
          find.byTooltip(
            direction == ChoicePathDraftDirection.topDown
                ? l10n.sourcePickerOpenDetails
                : l10n.actionPickerOpenDetails,
          ),
        );
        await tester.pumpAndSettle();
        final nestedSource = tester.element(find.byType(IntentionDetailsPage));
        final nestedDirection = direction == ChoicePathDraftDirection.topDown
            ? ChoicePathDraftDirection.bottomUp
            : ChoicePathDraftDirection.topDown;
        final nested = DailyChoiceCreationLauncher().launch(
          sourceContext: nestedSource,
          direction: nestedDirection,
        );
        await tester.pumpAndSettle();
        expect(_pickerContext(router).launch, isNot(same(firstContext.launch)));
        expect(find.text('Намерение 4'), findsOneWidget);
        await _choose(
          tester,
          nestedDirection,
          nestedDirection == ChoicePathDraftDirection.topDown ? 1 : 3,
        );
        await tester.tap(find.text('Отменить создание'));
        await tester.pumpAndSettle();
        await nested;
        expect(firstContext.launch.isActive, isTrue);
        await router.maybePop();
        await tester.pumpAndSettle();
        expect(router.current.matchId, firstId);
        expect(
          tester
              .widget<TextField>(
                find.byKey(ValueKey('daily-choice-$prefix-filter')),
              )
              .controller!
              .text,
          'Намерение 3',
        );
        await _choose(tester, direction, 3);
        expect(router.current.name, ChoicePathRoute.name);
        await tester.tap(find.text('Отменить создание'));
        await tester.pumpAndSettle();
        await first;
        expect(router.stackData, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${_directionName(direction)}: отменённый запуск игнорирует задержанный выбранный ID',
      (tester) async {
        final router = _DelayedPickerRouter();
        await _openApp(tester, router: router);
        final source = await _sourceContext(tester, router);
        final launcher = DailyChoiceCreationLauncher();
        final first = launcher.launch(
          sourceContext: source,
          direction: direction,
        );
        await tester.pumpAndSettle();
        final oldLaunch = _pickerContext(router).launch;
        await _choose(
          tester,
          direction,
          direction == ChoicePathDraftDirection.topDown ? 1 : 3,
        );
        oldLaunch.cancel();
        final next = launcher.launch(
          sourceContext: source,
          direction: direction,
        );
        await tester.pumpAndSettle();
        final nextId = router.current.matchId;
        router.release();
        await first;
        await tester.pumpAndSettle();
        expect(router.current.matchId, nextId);
        expect(_pickerContext(router).launch.isActive, isTrue);
        await tester.tap(find.text('Отменить создание'));
        await tester.pumpAndSettle();
        await next;
        expect(router.stackData, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('одноимённые действия передаются в путь по выбранному ID', (
    tester,
  ) async {
    final router = await _openApp(tester, duplicateTitles: true);
    final source = await _sourceContext(tester, router);
    final running = DailyChoiceCreationLauncher().launch(
      sourceContext: source,
      direction: ChoicePathDraftDirection.bottomUp,
    );
    await tester.pumpAndSettle();
    expect(find.text('Намерение 3'), findsNWidgets(2));
    await _choose(tester, ChoicePathDraftDirection.bottomUp, 4);
    expect(
      tester
          .widget<ChoicePathPage>(find.byType(ChoicePathPage))
          .sourceIntentionId,
      durabilityIntention(4),
    );
    await _tapKey(tester, 'choice-path-continue-${durabilityUuid(103)}');
    expect(
      find.byKey(const ValueKey('choice-path-select-source')),
      findsOneWidget,
    );
    await tester.tap(find.text('Отменить создание'));
    await tester.pumpAndSettle();
    await running;
    expect(router.stackData, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'успешный выбор от основания освобождает запуск для нового создания',
    (tester) async {
      final router = await _openApp(tester);
      final source = await _sourceContext(tester, router);
      final launcher = DailyChoiceCreationLauncher();
      var launchFinished = false;
      unawaited(
        launcher
            .launch(
              sourceContext: source,
              direction: ChoicePathDraftDirection.topDown,
            )
            .then((_) => launchFinished = true),
      );
      await tester.pumpAndSettle();
      await _choose(tester, ChoicePathDraftDirection.topDown, 1);
      expect(launchFinished, isTrue);
      await _tapKey(tester, 'choice-path-continue-${durabilityUuid(103)}');
      await _tapKey(tester, 'choice-path-select-action');
      await _tapKey(tester, 'choice-path-open-confirmation');
      await _tapKey(tester, 'daily-choice-submit');
      expect(find.byType(DailyChoiceDetailsPage), findsOneWidget);
      await router.maybePop();
      await tester.pumpAndSettle();
      final next = launcher.launch(
        sourceContext: source,
        direction: ChoicePathDraftDirection.topDown,
      );
      await tester.pumpAndSettle();
      expect(router.current.name, DailyChoiceSourcePickerRoute.name);
      await tester.tap(find.text('Отменить создание'));
      await tester.pumpAndSettle();
      await next;
      expect(router.stackData, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}

void _defineLatePickerTests() {
  for (final direction in ChoicePathDraftDirection.values) {
    for (final deep in [false, true]) {
      for (final selected in [false, true]) {
        testWidgets(
          '${_directionName(direction)}: поздний ${selected ? 'ID' : 'возврат'} после сброса '
          '${deep ? 'глубокой страницы' : 'корня'} до освобождения страницы не меняет новый запуск',
          (tester) async {
            final router = _DelayedPickerRouter();
            await _openApp(tester, router: router);
            final source = await _sourceContext(tester, router, deep: deep);
            final launcher = DailyChoiceCreationLauncher();
            final old = launcher.launch(
              sourceContext: source,
              direction: direction,
            );
            await tester.pumpAndSettle();
            final oldLaunch = _pickerContext(router).launch;
            if (selected) {
              await _choose(
                tester,
                direction,
                direction == ChoicePathDraftDirection.topDown ? 1 : 3,
              );
            }
            router.popUntilRoot();
            // Корневая вкладка остаётся смонтированной даже при смене пункта.
            final tabs = router.innerRouterOf<TabsRouter>(AppShellRoute.name)!;
            tabs.setActiveIndex(0);
            tabs.setActiveIndex(1);
            expect(source.mounted, isTrue);
            expect(oldLaunch.isActive, isFalse);
            final rootSource = tester.element(
              find.byType(DailyChoiceCatalogPage, skipOffstage: false),
            );
            final next = launcher.launch(
              sourceContext: rootSource,
              direction: direction,
            );
            router.release();
            await old;
            expect(source.mounted, isTrue);
            expect(
              router.stackData.map((route) => route.name),
              isNot(contains(ChoicePathRoute.name)),
            );
            await tester.pumpAndSettle();
            expect(router.current.name, _pickerName(direction));
            expect(_pickerContext(router).launch, isNot(same(oldLaunch)));
            expect(_pickerContext(router).launch.isActive, isTrue);
            await _choose(
              tester,
              direction,
              direction == ChoicePathDraftDirection.topDown ? 1 : 3,
            );
            expect(router.current.name, ChoicePathRoute.name);
            await tester.tap(find.text('Отменить создание'));
            await tester.pumpAndSettle();
            await next;
            expect(router.stackData, hasLength(1));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

/// Задерживает доставку результата первого настоящего поиска его владельцу.
final class _DelayedPickerRouter extends RootStackRouter {
  final _gate = Completer<void>();
  bool _holdNextPicker = true;

  @override
  List<AutoRoute> get routes => AppRouter().routes;

  void release() => _gate.complete();

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    final hold =
        _holdNextPicker &&
        (route.routeName == DailyChoiceActionPickerRoute.name ||
            route.routeName == DailyChoiceSourcePickerRoute.name);
    if (hold) _holdNextPicker = false;
    final result = await super.push<T>(route, onFailure: onFailure);
    if (hold) await _gate.future;
    return result;
  }
}

final class _FailingLaunchRouter extends RootStackRouter {
  _FailingLaunchRouter({required this.failPath});

  final bool failPath;
  bool _failed = false;

  @override
  List<AutoRoute> get routes => AppRouter().routes;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) {
    if (!_failed &&
        route.routeName ==
            (failPath
                ? ChoicePathRoute.name
                : DailyChoiceSourcePickerRoute.name)) {
      _failed = true;
      return Future<T?>.error(StateError('Секретный текст'));
    }
    return super.push<T>(route, onFailure: onFailure);
  }
}

String _pickerName(ChoicePathDraftDirection direction) => switch (direction) {
  ChoicePathDraftDirection.topDown => DailyChoiceSourcePickerRoute.name,
  ChoicePathDraftDirection.bottomUp => DailyChoiceActionPickerRoute.name,
};

String _directionName(ChoicePathDraftDirection direction) =>
    switch (direction) {
      ChoicePathDraftDirection.topDown => 'Сверху вниз',
      ChoicePathDraftDirection.bottomUp => 'Снизу вверх',
    };

InitialDailyChoicePickerContext _pickerContext(RootStackRouter router) =>
    switch (router.current.args) {
      DailyChoiceSourcePickerRouteArgs(:final pickerContext) ||
      DailyChoiceActionPickerRouteArgs(
        :final pickerContext,
      ) => pickerContext as InitialDailyChoicePickerContext,
      _ => throw StateError('Ожидался начальный поиск.'),
    };

Future<BuildContext> _sourceContext(
  WidgetTester tester,
  RootStackRouter router, {
  bool deep = false,
}) async {
  if (!deep) return tester.element(find.byType(DailyChoiceCatalogPage));
  unawaited(
    router.push(
      RelationEditorRoute(editorContext: const RelationBlankCreationContext()),
    ),
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
  return tester.element(find.byType(IntentionDetailsPage));
}

Future<void> _choose(
  WidgetTester tester,
  ChoicePathDraftDirection direction,
  int number,
) async {
  final prefix = direction == ChoicePathDraftDirection.topDown
      ? 'source'
      : 'action';
  final row = find.byKey(
    ValueKey('daily-choice-$prefix-${durabilityUuid(number)}'),
  );
  await tester.tap(
    find.descendant(of: row, matching: find.byType(IntentionSummaryView)),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<RootStackRouter> _openApp(
  WidgetTester tester, {
  RootStackRouter? router,
  bool empty = false,
  bool duplicateTitles = false,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final database = AppDatabase(openInMemoryLocalDatabase());
  if (!empty) await seedDurabilityGraph(database);
  if (duplicateTitles) {
    await database.customStatement(
      'UPDATE intentions SET title = ? WHERE id = ?',
      ['Намерение 3', durabilityUuid(4)],
    );
  }
  final container = ProviderContainer(
    overrides: [
      inMemoryQuickCreationModeOverride,
      personalGraphRepositoryProvider.overrideWithValue(
        durabilityRepository(database),
      ),
    ],
  );
  final appRouter = router ?? AppRouter();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    appRouter.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: appRouter.config(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  appRouter.innerRouterOf<TabsRouter>(AppShellRoute.name)!.setActiveIndex(1);
  await tester.pumpAndSettle();
  return appRouter;
}
