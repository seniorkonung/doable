import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/presentation/daily_choice_picker_context.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/filter_button.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/shared/presentation/creation_exit_action.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/catalog/catalog_reconciliation_test_support.dart';
import '../../intention/presentation/catalog/catalog_test_support.dart';
import '../../intention/presentation/picker/intention_picker_test_support.dart';
import '../../support/app_root_pages.dart';
import '../../support/tag_positions.dart';

/// Один контракт начального и вспомогательного поиска для обоих направлений.
void defineDailyChoicePickerContextTests({
  required PageRouteInfo Function(DailyChoicePickerContext) route,
  required String keyPrefix,
  required IntentionReadinessFilter readinessFilter,
  required ({String title, String header, String auxiliaryCancel}) ruTexts,
  required String emptyMessage,
  required String noMatchesMessage,
}) {
  testWidgets('открывается экраном выбора: крестик с заголовком, поле поиска, '
      'кнопка фильтра без условий и заголовок выдачи с количеством, а других '
      'действий выхода нет', (tester) async {
    final semantics = tester.ensureSemantics();
    final (repository, router) = await _openApp(tester, language: 'ru');
    final items = [
      for (var index = 13; index >= 1; index--)
        testSummary(
          index: index,
          title: 'Кандидат $index',
          readiness: IntentionReadiness.ready,
        ),
    ];
    for (final (index, (pickerContext, cancelLabel)) in [
      (InitialDailyChoicePickerContext(launch: _Launch()), 'Отменить создание'),
      (const AuxiliaryDailyChoicePickerContext(), ruTexts.auxiliaryCancel),
    ].indexed) {
      final selection = router.push<IntentionId>(route(pickerContext));
      await _settleRoute(tester);
      repository.complete(
        index + 1,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: items,
            totalCount: items.length,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(TopBar),
          matching: find.text(ruTexts.title),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byKey(ValueKey('$keyPrefix-cancel'))),
        isSemantics(label: cancelLabel, isButton: true, hasTapAction: true),
      );
      expect(find.byKey(ValueKey('$keyPrefix-filter')), findsOneWidget);
      expect(tester.widget<FilterButton>(find.byType(FilterButton)).count, 0);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CatalogHeader &&
              widget.title == ruTexts.header &&
              widget.count == 13,
        ),
        findsOneWidget,
      );
      // Крестик — единственное действие выхода: нижней кнопки нет.
      expect(find.text(cancelLabel), findsNothing);
      expect(find.byType(CreationExitAction), findsNothing);

      await tester.tap(find.byKey(ValueKey('$keyPrefix-cancel')));
      await tester.pumpAndSettle();
      expect(await selection, isNull);
    }
    semantics.dispose();
  });

  testWidgets('стрелка открывает подробные данные без выбора, а поиск '
      'остаётся под ними в истории', (tester) async {
    final (repository, router) = await _openApp(tester);
    var selected = false;
    final selection = router.push<IntentionId>(
      route(const AuxiliaryDailyChoicePickerContext()),
    );
    unawaited(selection.then((_) => selected = true));
    await _settleRoute(tester);
    final pickerId = router.current.matchId;
    expect(repository.queryAt(1).scope, IntentionScope.active);
    expect(repository.queryAt(1).readinessFilter, readinessFilter);
    repository.complete(1, _page());
    await tester.pumpAndSettle();
    expect(intentionPickerRows, findsNWidgets(2));

    await tester.tap(intentionPickerArrow(intentionPickerRows.last));
    await _settleRoute(tester);
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(
      router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
      testSummary(index: 2).id,
    );
    expect(router.stackData[router.stackData.length - 2].matchId, pickerId);
    expect(selected, isFalse);

    await router.maybePop();
    await _settleRoute(tester);
    expect(router.current.matchId, pickerId);
    expect(selected, isFalse);
    await tester.tap(find.text('Гулять').last);
    await tester.pumpAndSettle();
    expect(await selection, testSummary(index: 2).id);
  });

  testWidgets('верхний крестик при клавиатуре прекращает только свой запуск '
      'и сохраняет вложенную историю', (tester) async {
    const language = 'ru';
    const cancelLabel = 'Отменить создание';
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final (repository, router) = await _openApp(tester, language: language);
    final auxiliary = router.push<IntentionId>(
      route(const AuxiliaryDailyChoicePickerContext()),
    );
    await _settleRoute(tester);
    repository.complete(1, _page());
    await tester.pumpAndSettle();
    final history = [for (final data in router.stackData) data.matchId];
    final launch = _Launch();
    final selection = router.push<IntentionId>(
      route(InitialDailyChoicePickerContext(launch: launch)),
    );
    await _settleRoute(tester);
    repository.complete(2, _page());
    await tester.pumpAndSettle();
    final lateSelection = intentionPickerPick(tester, intentionPickerRows.last);
    await tester.showKeyboard(find.byKey(ValueKey('$keyPrefix-filter')));
    _setPickerInsets(tester, keyboard: 260, safe: true);
    await tester.pumpAndSettle();
    final action = find.byKey(ValueKey('$keyPrefix-cancel'));
    expect(action, findsOneWidget);
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.getRect(action).bottom, lessThanOrEqualTo(540));
    expect(
      tester.getSemantics(action),
      isSemantics(label: cancelLabel, isButton: true, hasTapAction: true),
    );
    await tester.tap(action);
    expect(launch.isActive, isFalse);
    lateSelection();
    await tester.pumpAndSettle();
    expect(await selection, isNull);
    expect([for (final data in router.stackData) data.matchId], history);
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(await auxiliary, isNull);
    semantics.dispose();
  });

  testWidgets('начальный поиск сохраняет ID одноимённых кандидатов, '
      'поиск и запуск при возврате из подробностей и условий тегов', (
    tester,
  ) async {
    final (repository, router) = await _openApp(tester);
    final tag = Tag(
      id: switch (TagId.decode('00000000-0000-4000-8000-000000000001')) {
        TagIdDecodingSuccess(:final id) => id,
        InvalidTagIdDecoding() => throw StateError('Некорректный ID тега.'),
      },
      name: TagName.fromInput('Отдых'),
      color: null,
      position: tagPositionAt(1000),
    );
    repository.tagCatalogItems = [tag];
    final launch = _Launch();
    final selection = router.push<IntentionId>(
      route(InitialDailyChoicePickerContext(launch: launch)),
    );
    await _settleRoute(tester);
    final pickerId = router.current.matchId;
    expect(repository.queryAt(1).scope, IntentionScope.active);
    expect(repository.queryAt(1).readinessFilter, readinessFilter);
    final result = _page(
      secondReadiness: readinessFilter == IntentionReadinessFilter.all
          ? IntentionReadiness.notReady
          : IntentionReadiness.ready,
    );
    repository.complete(1, result);
    await tester.pumpAndSettle();

    await tester.tap(intentionPickerArrow(intentionPickerRows.last));
    await _settleRoute(tester);
    expect(router.current.name, IntentionDetailsRoute.name);
    await router.maybePop();
    await _settleRoute(tester);
    expect(router.current.matchId, pickerId);
    expect(launch.isActive, isTrue);

    await tester.tap(find.byType(FilterButton));
    await tester.pumpAndSettle();
    expect(find.text('Filter by tags'), findsOneWidget);
    // Системное «назад» закрывает только панель тегов.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Filter by tags'), findsNothing);
    expect(router.current.matchId, pickerId);
    expect(launch.isActive, isTrue);

    await tester.enterText(find.byKey(ValueKey('$keyPrefix-filter')), 'Гулять');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    repository.complete(2, result);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilterButton));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('tags-panel-row-${tag.id.toCanonicalString()}')),
    );
    for (var frame = 0; frame < 100 && repository.queries.length < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(repository.queryAt(3).titleFilter?.map((value) => value), 'Гулять');
    expect(repository.queryAt(3).tagFilter.requiredTagIds, [tag.id]);
    expect(repository.queryAt(3).readinessFilter, readinessFilter);
    repository.complete(3, result);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(router.current.matchId, pickerId);
    expect(launch.isActive, isTrue);

    await tester.tap(find.text('Гулять').last);
    await tester.pumpAndSettle();
    expect(await selection, testSummary(index: 2).id);
    expect(launch.isActive, isTrue);
    expectIntentionGraphRootPage(router);
  });

  testWidgets('утрата права запуска запрещает выбор кандидата и открытие '
      'подробностей, сохраняя доступную отмену поиска', (tester) async {
    final (repository, router) = await _openApp(tester);
    final launch = _Launch();
    final selection = router.push<IntentionId>(
      route(InitialDailyChoicePickerContext(launch: launch)),
    );
    await _settleRoute(tester);
    repository.complete(1, _page());
    await tester.pumpAndSettle();
    final pickerId = router.current.matchId;
    launch.cancel();
    await tester.tap(find.text('Гулять').last);
    await tester.tap(intentionPickerArrow(intentionPickerRows.last));
    await tester.pumpAndSettle();
    expect(router.current.matchId, pickerId);
    await tester.tap(find.byKey(ValueKey('$keyPrefix-cancel')));
    await tester.pumpAndSettle();
    expect(await selection, isNull);
    expectIntentionGraphRootPage(router);
  });

  testWidgets('обычный возврат из начального поиска прекращает запуск '
      'до окончания анимации и возвращает отсутствие ID', (tester) async {
    final (repository, router) = await _openApp(tester);
    final launch = _Launch();
    final selection = router.push<IntentionId>(
      route(InitialDailyChoicePickerContext(launch: launch)),
    );
    await _settleRoute(tester);
    repository.complete(1, _page());
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    expect(launch.isActive, isFalse);
    expect(await selection, isNull);
    await tester.pumpAndSettle();
    expectIntentionGraphRootPage(router);
  });

  testWidgets('вспомогательный выбор над начальным поиском возвращает '
      'результат и не отменяет нижележащий запуск', (tester) async {
    final (repository, router) = await _openApp(tester);
    final launch = _Launch();
    final initial = router.push<IntentionId>(
      route(InitialDailyChoicePickerContext(launch: launch)),
    );
    await _settleRoute(tester);
    repository.complete(1, _page());
    await tester.pumpAndSettle();
    final initialId = router.current.matchId;
    for (final choose in [false, true]) {
      final auxiliary = router.push<IntentionId>(
        route(const AuxiliaryDailyChoicePickerContext()),
      );
      await _settleRoute(tester);
      repository.complete(choose ? 3 : 2, _page());
      await tester.pumpAndSettle();
      if (choose) {
        await tester.tap(find.text('Гулять').last);
      } else {
        await tester.tap(find.byKey(ValueKey('$keyPrefix-cancel')));
      }
      await tester.pumpAndSettle();
      expect(await auxiliary, choose ? testSummary(index: 2).id : isNull);
      expect(router.current.matchId, initialId);
      expect(launch.isActive, isTrue);
    }
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(await initial, isNull);
  });

  testWidgets('пустой начальный поиск и отсутствие совпадений сохраняют '
      'объяснения и доступную отмену', (tester) async {
    final (repository, router) = await _openApp(tester);
    final launch = _Launch();
    final selection = router.push<IntentionId>(
      route(InitialDailyChoicePickerContext(launch: launch)),
    );
    await _settleRoute(tester);
    repository.complete(1, _page(empty: true));
    await tester.pumpAndSettle();
    expect(find.text(emptyMessage), findsOneWidget);
    await tester.enterText(find.byKey(ValueKey('$keyPrefix-filter')), 'Нет');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    repository.complete(2, _page(empty: true));
    await tester.pumpAndSettle();
    expect(find.text(noMatchesMessage), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('$keyPrefix-cancel')));
    await tester.pumpAndSettle();
    expect(await selection, isNull);
    expect(launch.isActive, isFalse);
  });

  testWidgets('поздний выбор и отмена прежней страницы не закрывают новый '
      'поиск во время обратной анимации', (tester) async {
    final (repository, router) = await _openApp(tester);
    final launch = _Launch();
    unawaited(
      router.push<IntentionId>(
        route(InitialDailyChoicePickerContext(launch: launch)),
      ),
    );
    await _settleRoute(tester);
    repository.complete(1, _page());
    await tester.pumpAndSettle();
    final lateSelection = intentionPickerPick(tester, intentionPickerRows.last);
    final lateCancel = tester.widget<TopBar>(find.byType(TopBar)).onClose;
    final oldElement = find.byType(TopBar).evaluate().single;
    await router.maybePop();
    final nextLaunch = _Launch();
    unawaited(
      router.push<IntentionId>(
        route(InitialDailyChoicePickerContext(launch: nextLaunch)),
      ),
    );
    await tester.pump();
    expect(oldElement.mounted, isTrue);
    final nextId = router.current.matchId;
    lateSelection();
    lateCancel();
    await _settleRoute(tester);
    repository.complete(2, _page());
    await tester.pumpAndSettle();
    expect(router.current.matchId, nextId);
    expect(launch.isActive, isFalse);
    expect(nextLaunch.isActive, isTrue);
    expect(
      tester.widget<TopBar>(find.byType(TopBar)).closeLabel,
      'Cancel creation',
    );
    expect(tester.takeException(), isNull);
  });
}

void _setPickerInsets(
  WidgetTester tester, {
  required double keyboard,
  required bool safe,
}) {
  final top = safe ? 24.0 : 0.0;
  final bottom = safe ? 32.0 : 0.0;
  tester.view.viewPadding = FakeViewPadding(top: top, bottom: bottom);
  tester.view.padding = FakeViewPadding(
    top: top,
    bottom: keyboard == 0 ? bottom : 0,
  );
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
}

final class _Launch implements DailyChoicePickerLaunch {
  @override
  bool isActive = true;

  @override
  void cancel() => isActive = false;
}

Result<IntentionCatalogFirstPage> _page({
  bool empty = false,
  IntentionReadiness secondReadiness = IntentionReadiness.ready,
}) => ResultSuccess(
  IntentionCatalogFirstPage(
    items: empty
        ? []
        : [
            testSummary(
              index: 1,
              title: 'Гулять',
              readiness: IntentionReadiness.ready,
            ),
            testSummary(index: 2, title: 'Гулять', readiness: secondReadiness),
          ],
    totalCount: empty ? 0 : 2,
    nextCursor: null,
    revision: const TestCatalogRevision(1),
  ),
);

Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<(ControlledCatalogRepository, AppRouter)> _openApp(
  WidgetTester tester, {
  String language = 'en',
}) async {
  final repository = ControlledCatalogRepository();
  final container = reconciliationCatalogContainer(repository);
  final router = AppRouter();
  addTearDown(container.dispose);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pump();
  await openIntentionGraph(tester);
  repository.complete(0, _page(empty: true));
  await tester.pumpAndSettle();
  return (repository, router);
}
