import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/presentation/daily_choice_picker_context.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_search_layout.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/catalog/catalog_reconciliation_test_support.dart';
import '../../intention/presentation/catalog/catalog_test_support.dart';
import '../../support/app_root_pages.dart';

/// Один контракт начального и вспомогательного поиска для обоих направлений.
void defineDailyChoicePickerContextTests({
  required PageRouteInfo Function(DailyChoicePickerContext) route,
  required String keyPrefix,
  required IntentionReadinessFilter readinessFilter,
  required String emptyMessage,
  required String noMatchesMessage,
  required String detailsTooltip,
}) {
  _defineKeyboardCancellationTests(route: route, keyPrefix: keyPrefix);
  for (final (language, cancelLabel) in [
    ('ru', 'Отменить создание'),
    ('en', 'Cancel creation'),
  ]) {
    testWidgets('$language: верхний крестик при клавиатуре прекращает только '
        'свой запуск и сохраняет вложенную историю', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      final (repository, router) = await _openApp(
        tester,
        language: language,
        textScaler: const TextScaler.linear(2.6),
      );
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
      final lateSelection = tester
          .widget<IntentionSummaryView>(find.byType(IntentionSummaryView).last)
          .onTap!;
      await tester.showKeyboard(find.byKey(ValueKey('$keyPrefix-filter')));
      _setPickerInsets(tester, keyboard: 260, safe: true);
      await tester.pumpAndSettle();
      final action = find.byKey(ValueKey('$keyPrefix-cancel'));
      expect(action, findsOneWidget);
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.getRect(action).bottom, lessThanOrEqualTo(540));
      expect(
        tester.getSemantics(action).getSemanticsData().tooltip,
        cancelLabel,
      );
      expect(
        tester
            .getSemantics(action)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await tester.tap(action);
      expect(launch.isActive, isFalse);
      lateSelection();
      await tester.pumpAndSettle();
      expect(await selection, isNull);
      expect([for (final data in router.stackData) data.matchId], history);
      expect(find.text(cancelLabel), findsNothing);
      expect(repository.dailyChoiceCommands, isEmpty);
      await router.maybePop();
      await tester.pumpAndSettle();
      expect(await auxiliary, isNull);
      semantics.dispose();
    });
  }

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

    await tester.tap(find.byTooltip(detailsTooltip).last);
    await _settleRoute(tester);
    expect(router.current.name, IntentionDetailsRoute.name);
    await router.maybePop();
    await _settleRoute(tester);
    expect(router.current.matchId, pickerId);
    expect(launch.isActive, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('intention-tag-conditions-add')),
    );
    await tester.pumpAndSettle();
    expect(router.current.name, TagConditionPickerRoute.name);
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(router.current.matchId, pickerId);
    expect(launch.isActive, isTrue);

    await tester.enterText(find.byKey(ValueKey('$keyPrefix-filter')), 'Гулять');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    repository.complete(2, result);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('intention-tag-conditions-add')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey(
          'tag-condition-picker-mustBePresent-${tag.id.toCanonicalString()}',
        ),
      ),
    );
    for (var frame = 0; frame < 100 && repository.queries.length < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(repository.queryAt(3).titleFilter?.map((value) => value), 'Гулять');
    expect(repository.queryAt(3).tagFilter.requiredTagIds, [tag.id]);
    expect(repository.queryAt(3).readinessFilter, readinessFilter);
    repository.complete(3, result);
    await tester.pumpAndSettle();
    expect(launch.isActive, isTrue);

    await tester.tap(find.text('Гулять').last);
    await tester.pumpAndSettle();
    expect(await selection, testSummary(index: 2).id);
    expect(launch.isActive, isTrue);
    expectIntentionGraphRootPage(router);
    expect(repository.dailyChoiceCommands, isEmpty);
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
    await tester.tap(find.byTooltip(detailsTooltip).last);
    await tester.pumpAndSettle();
    expect(router.current.matchId, pickerId);
    await tester.tap(find.text('Cancel creation'));
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
      expect(find.text('Cancel creation'), findsNothing);
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
    await tester.tap(find.text('Cancel creation'));
    await tester.pumpAndSettle();
    expect(await selection, isNull);
    expect(launch.isActive, isFalse);
    expect(repository.dailyChoiceCommands, isEmpty);
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
    final lateSelection = tester
        .widget<IntentionSummaryView>(find.byType(IntentionSummaryView).last)
        .onTap!;
    final lateCancel = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel creation'))
        .onPressed!;
    final oldElement = find
        .widgetWithText(TextButton, 'Cancel creation')
        .evaluate()
        .single;
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
    expect(find.text('Cancel creation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _defineKeyboardCancellationTests({
  required PageRouteInfo Function(DailyChoicePickerContext) route,
  required String keyPrefix,
}) {
  for (final language in ['ru', 'en']) {
    for (final scale in [1.0, 2.6]) {
      for (final size in [
        const Size(400, 800),
        const Size(800, 1280),
        const Size(1280, 800),
      ]) {
        for (final safe in [false, true]) {
          for (final keyboard in [0.0, 260.0]) {
            testWidgets('$language: текстовая отмена начального поиска, '
                '${size.width.toInt()}×${size.height.toInt()}, текст $scale, '
                'клавиатура $keyboard, безопасные отступы $safe', (
              tester,
            ) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              final semantics = tester.ensureSemantics();
              try {
                final (repository, router) = await _openApp(
                  tester,
                  language: language,
                  textScaler: TextScaler.linear(scale),
                );
                final underlying = router.push<IntentionId>(
                  route(const AuxiliaryDailyChoicePickerContext()),
                );
                await _settleRoute(tester);
                repository.complete(1, _page());
                await tester.pumpAndSettle();
                final filter = find.byKey(ValueKey('$keyPrefix-filter'));
                await tester.enterText(filter, 'Гул');
                await tester.pump(const Duration(milliseconds: 300));
                repository.complete(2, _page());
                await tester.pumpAndSettle();
                final history = [
                  for (final data in router.stackData) data.matchId,
                ];
                final launch = _Launch();
                final selection = router.push<IntentionId>(
                  route(InitialDailyChoicePickerContext(launch: launch)),
                );
                await _settleRoute(tester);
                repository.complete(3, _page());
                await tester.pumpAndSettle();
                await tester.enterText(filter, 'Гулять');
                await tester.pump(const Duration(milliseconds: 300));
                repository.complete(4, _page());
                await tester.pumpAndSettle();
                final lateSelection = tester
                    .widget<IntentionSummaryView>(
                      find.byType(IntentionSummaryView).last,
                    )
                    .onTap!;
                final label = language == 'ru'
                    ? 'Отменить создание'
                    : 'Cancel creation';
                final action = find.widgetWithText(TextButton, label);
                // Проверяем и появление, и скрытие клавиатуры на той же странице.
                for (final inset in [keyboard, 260 - keyboard, keyboard]) {
                  _setPickerInsets(tester, keyboard: inset, safe: safe);
                  await tester.pumpAndSettle();
                  _expectPickerCancelGeometry(tester, label, size);
                  expect(action.hitTestable(), findsOneWidget);
                  expect(
                    tester
                        .getSemantics(action)
                        .getSemanticsData()
                        .hasAction(SemanticsAction.tap),
                    isTrue,
                  );
                  expect(launch.isActive, isTrue);
                  expect(tester.takeException(), isNull);
                }
                // Параметры и выдача достижимы прокруткой даже в тесной области.
                for (final control in [
                  filter,
                  find.byKey(const ValueKey('intention-tag-conditions-add')),
                  find.text('Гулять').first,
                  filter,
                ]) {
                  await tester.ensureVisible(control);
                  await tester.pumpAndSettle();
                  expect(control.hitTestable(), findsOneWidget);
                }
                expect(
                  tester
                      .widget<EditableText>(find.byType(EditableText))
                      .focusNode
                      .hasFocus,
                  isTrue,
                );
                await tester.tap(action);
                expect(launch.isActive, isFalse);
                lateSelection();
                await tester.pumpAndSettle();
                expect(await selection, isNull);
                expect([
                  for (final data in router.stackData) data.matchId,
                ], history);
                expect(
                  tester.widget<TextField>(filter).controller!.text,
                  'Гул',
                );
                expect(
                  tester
                      .widget<ListView>(
                        find.byKey(PageStorageKey<String>('$keyPrefix-list')),
                      )
                      .childrenDelegate
                      .estimatedChildCount,
                  2,
                );
                expect(find.text(label), findsNothing);
                expect(repository.queries, hasLength(5));
                expect(repository.dailyChoiceCommands, isEmpty);
                expect(tester.takeException(), isNull);
                await router.maybePop();
                await tester.pumpAndSettle();
                expect(await underlying, isNull);
              } finally {
                semantics.dispose();
              }
            });
          }
        }
      }
    }
  }
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

void _expectPickerCancelGeometry(WidgetTester tester, String label, Size size) {
  final action = tester.getRect(find.widgetWithText(TextButton, label));
  final text = tester.getRect(find.text(label));
  final bottom =
      size.height - tester.view.viewInsets.bottom - tester.view.padding.bottom;
  for (final rect in [action, text]) {
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(tester.view.padding.top));
    expect(rect.right, lessThanOrEqualTo(size.width));
    expect(rect.bottom, lessThanOrEqualTo(bottom));
  }
  expect(action.bottom, closeTo(bottom, 0.01));
  expect(
    tester.getRect(find.byType(IntentionSearchLayout)).bottom,
    closeTo(action.top, 0.01),
  );
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
  TextScaler textScaler = TextScaler.noScaling,
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
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
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
