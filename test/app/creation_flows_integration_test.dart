import 'dart:async';
import 'dart:ui' show CheckedState, Tristate;

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/presentation/path/path_page.dart';
import 'package:doable/src/action/presentation/path_start/path_start_picker_page.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/time_dial.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    show IntentionCatalogOrder, IntentionScope;
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_row.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/controlled_local_date.dart';
import '../support/action_day_provider.dart';
import '../support/action_day_controls.dart';
import '../support/action_editor_controls.dart';
import '../support/action_seed.dart';
import '../support/graph_durability_fixture.dart';
import '../support/graph_seed.dart';
import '../support/intention_catalog_controls.dart';
import '../support/intention_creation_origin.dart';
import '../support/intention_actions_tab.dart';
import '../support/local_database_harness.dart';
import '../support/path_screen_controls.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/quick_creation.dart';

part 'creation_flows_test_support.dart';
part 'creation_flows_accessibility_scenarios.dart';
part 'creation_flows_relation_picker_scenarios.dart';
part 'quick_creation/quick_creation_flow_scenarios.dart';

void main() {
  setUp(
    () => WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
  _registerAccessibilityTests();
  _registerQuickCreationFlowTests();
  _registerRelationPickerIntentionTest();
  testWidgets('повторный выбор пункта сбрасывает пустой лист без вопроса', (
    tester,
  ) async {
    final app = await _start(tester);
    await _tap(tester, find.text('Новое действие'));
    await _tap(tester, actionEditorValue('Выберите причину'));
    final intention = find.bySemanticsLabel(
      'Открыть страницу намерения «Намерение 1»',
    );
    await _until(tester, () => intention.evaluate().isNotEmpty);
    await _tap(tester, intention);
    final tabs = app.router.innerRouterOf<TabsRouter>(AppShellRoute.name)!;
    final selected = tabs.activeIndex;
    tester
        .widget<AppNavigationBar>(find.byType(AppNavigationBar).last)
        .onSelected(AppDestination.values[selected]);
    await tester.pumpAndSettle();
    expect(find.text('Отменить новое действие?'), findsNothing);
    expect(app.router.stack.map((route) => route.name), [AppShellRoute.name]);
    expect(tabs.activeIndex, selected);
  });

  testWidgets('сброс истории спрашивает о черновиках ниже обычной страницы', (
    tester,
  ) async {
    final app = await _start(tester);
    await _tap(tester, find.text('Новое действие'));
    await tester.enterText(actionEditorTitleField, 'Первый черновик');
    await _tap(tester, actionEditorValue('Выберите причину'));
    final firstIntention = find.bySemanticsLabel(
      'Открыть страницу намерения «Намерение 1»',
    );
    await _until(tester, () => firstIntention.evaluate().isNotEmpty);
    await _tap(tester, firstIntention);
    final tabs = app.router.innerRouterOf<TabsRouter>(AppShellRoute.name)!;
    final selected = tabs.activeIndex;
    void selectGraph() => tester
        .widget<AppNavigationBar>(find.byType(AppNavigationBar).last)
        .onSelected(AppDestination.intentionGraph);
    final firstHistory = [
      for (final route in app.router.stackData) route.matchId,
    ];
    selectGraph();
    await tester.pumpAndSettle();
    expect(find.text('Отменить новое действие?'), findsOneWidget);
    await _tap(tester, find.text('Продолжить ввод'));
    expect(app.router.stackData.map((route) => route.matchId), firstHistory);
    expect(tabs.activeIndex, selected);
    await openIntentionActionsTab(
      tester,
      waitFor: (tester, finder) =>
          _until(tester, () => finder.evaluate().isNotEmpty),
      tap: _tap,
    );
    await _tap(tester, find.text('Добавить'));
    await tester.enterText(actionEditorDescriptionField, 'Второй черновик');
    await _tap(tester, actionEditorValue('Намерение 1'));
    await _until(tester, () => find.byType(PathPage).evaluate().isNotEmpty);
    await _tap(tester, find.text('Намерение 1'));
    final anotherIntention = find.bySemanticsLabel(
      'Открыть страницу намерения «Намерение 2»',
    );
    await _until(tester, () => anotherIntention.evaluate().isNotEmpty);
    await _tap(tester, anotherIntention);

    final history = [for (final route in app.router.stackData) route.matchId];
    selectGraph();
    await tester.pumpAndSettle();
    expect(find.text('Отменить новое действие?'), findsOneWidget);
    await _tap(tester, find.text('Продолжить ввод'));
    expect(app.router.stackData.map((route) => route.matchId), history);
    expect(tabs.activeIndex, selected);
    final texts = tester
        .widgetList<EditableText>(
          find.byType(EditableText, skipOffstage: false),
        )
        .map((field) => field.controller.text);
    expect(texts, containsAll(['Первый черновик', 'Второй черновик']));

    selectGraph();
    await tester.pumpAndSettle();
    expect(find.text('Отменить новое действие?'), findsOneWidget);
    await _tap(tester, find.text('Сбросить'));
    expect(app.router.stack.map((route) => route.name), [AppShellRoute.name]);
    expect(tabs.activeIndex, AppDestination.intentionGraph.index);
    expect(find.text('Отменить новое действие?'), findsNothing);
  });
  testWidgets('выбор причины сохраняет путь в листе и его введённые поля', (
    tester,
  ) async {
    final app = await _start(tester);
    await _until(
      tester,
      () => find.text('Новое действие').evaluate().isNotEmpty,
    );
    await _tap(tester, find.text('Новое действие'));
    await tester.enterText(actionEditorTitleField, 'Прогулка');
    await tester.enterText(actionEditorDescriptionField, 'В парке');
    await _tap(tester, actionEditorValue('Весь день'));
    await _tap(
      tester,
      find.descendant(of: find.byType(TimeDial), matching: find.text('18')),
    );
    await _tap(tester, actionEditorValue('P4'));
    await _tap(tester, find.text('P2').last);
    await _tap(tester, actionEditorValue('Выберите причину'));
    await _until(
      tester,
      () => find.byType(PathStartPickerPage).evaluate().isNotEmpty,
    );
    expect(find.text('Новое действие: с чего начинается путь'), findsOneWidget);
    await _until(tester, () => find.text('Намерение 1').evaluate().isNotEmpty);
    await _tap(tester, find.text('Намерение 1'));
    await _until(tester, () => find.byType(PathPage).evaluate().isNotEmpty);
    await _until(tester, () => find.text('Намерение 2').evaluate().isNotEmpty);
    await _tap(tester, find.text('Намерение 2'));
    await _tap(tester, find.text('Сохранить'));
    await _until(
      tester,
      () => actionEditorValue('Намерение 2').evaluate().isNotEmpty,
    );
    expect(actionEditorValue('Намерение 1'), findsOneWidget);
    expect(
      tester.widget<EditableText>(actionEditorTitleField).controller.text,
      'Прогулка',
    );
    expect(
      tester.widget<EditableText>(actionEditorDescriptionField).controller.text,
      'В парке',
    );
    expect(actionEditorCanCreate(tester), isTrue);
    expect(actionEditorValue('Вчера'), findsOneWidget);
    expect(actionEditorValue('18:00'), findsOneWidget);
    expect(actionEditorValue('P2'), findsOneWidget);
    expect(
      await tester.runAsync(() => durabilityRows(app.database, 'actions')),
      isEmpty,
    );
    await _tap(tester, actionEditorValue('Намерение 1'));
    await _until(tester, () => find.byType(PathPage).evaluate().isNotEmpty);
    expect(find.text('Прогулка'), findsOneWidget);
    await _tap(tester, find.text('Намерение 1'));
    await _until(
      tester,
      () => find.byType(PathStartPickerPage).evaluate().isNotEmpty,
    );
    await _tap(tester, find.text('Намерение 4'));
    await _until(tester, () => find.text('Намерение 4').evaluate().isNotEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Отменить'));
    expect(actionEditorValue('Намерение 1'), findsOneWidget);
    expect(actionEditorValue('Намерение 2'), findsOneWidget);
    await _tap(tester, actionEditorCreateButton);
    await _until(
      tester,
      () => actionEditorValue('Прогулка').evaluate().isEmpty,
    );
    final rows = await tester.runAsync(
      () => durabilityRows(app.database, 'action_path_items'),
    );
    expect(rows!.map((row) => row['intention_id']), [
      durabilityUuid(1),
      durabilityUuid(2),
    ]);
  });

  testWidgets('закрытие поиска возвращает пустой путь и черновик', (
    tester,
  ) async {
    await _start(tester);
    await _tap(tester, find.text('Новое действие'));
    await tester.enterText(actionEditorTitleField, 'Прогулка');
    await _tap(tester, actionEditorValue('Выберите причину'));
    await _until(
      tester,
      () => find.byType(PathStartPickerPage).evaluate().isNotEmpty,
    );
    await _tap(tester, _key('path-start-picker-cancel'));
    expect(actionEditorValue('Выберите причину'), findsOneWidget);
    expect(
      tester.widget<EditableText>(actionEditorTitleField).controller.text,
      'Прогулка',
    );
  });

  testWidgets(
    'созданное в поиске намерение начинает путь и остаётся при отмене',
    (tester) async {
      final app = await _start(tester);
      await _tap(tester, find.text('Новое действие'));
      await _tap(tester, actionEditorValue('Выберите причину'));
      await _until(
        tester,
        () => find.bySemanticsLabel('Создать намерение').evaluate().isNotEmpty,
      );
      await _tap(tester, find.bySemanticsLabel('Создать намерение'));
      await tester.enterText(_key('intention-editor-title'), 'Новый корень');
      app.observer.observe('intentions');
      await _submit(tester, app);
      await _until(tester, () => find.byType(PathPage).evaluate().isNotEmpty);
      await _until(
        tester,
        () => find.text('Новый корень').evaluate().isNotEmpty,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Созданное 1 намерение останется.'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Отменить'));
      expect(actionEditorValue('Выберите причину'), findsOneWidget);
      final rows = await tester.runAsync(
        () => durabilityRows(app.database, 'intentions'),
      );
      expect(rows!.any((row) => row['title'] == 'Новый корень'), isTrue);
    },
  );

  testWidgets('второй лист со страницы намерения не меняет первый черновик', (
    tester,
  ) async {
    await _start(tester);
    await _tap(tester, find.text('Новое действие'));
    await tester.enterText(actionEditorTitleField, 'Первый черновик');
    await _tap(tester, actionEditorValue('Выберите причину'));
    await _until(
      tester,
      () => find
          .bySemanticsLabel('Открыть страницу намерения «Намерение 1»')
          .evaluate()
          .isNotEmpty,
    );
    await _tap(
      tester,
      find.bySemanticsLabel('Открыть страницу намерения «Намерение 1»'),
    );
    await openIntentionActionsTab(
      tester,
      waitFor: (tester, finder) =>
          _until(tester, () => finder.evaluate().isNotEmpty),
      tap: _tap,
    );
    await _tap(tester, find.text('Добавить'));
    expect(actionEditorValue('Намерение 1'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Намерение 1'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _tap(tester, _key('path-start-picker-cancel'));
    expect(actionEditorValue('Выберите причину'), findsOneWidget);
    expect(
      tester.widget<EditableText>(actionEditorTitleField).controller.text,
      'Первый черновик',
    );
  });
  testWidgets('разорванный путь листа отмечен и открывается с первого целого '
      'участка, а создание отклоняется с сохранением полей', (tester) async {
    final app = await _start(tester);
    await _tap(tester, find.text('Новое действие'));
    await tester.enterText(actionEditorTitleField, 'Прогулка');
    await _tap(tester, actionEditorValue('Выберите причину'));
    await _until(tester, () => find.text('Намерение 1').evaluate().isNotEmpty);
    await _tap(tester, find.text('Намерение 1'));
    await _until(tester, () => find.text('Намерение 2').evaluate().isNotEmpty);
    await _tap(tester, find.text('Намерение 2'));
    await _until(tester, () => find.text('Намерение 3').evaluate().isNotEmpty);
    await _tap(tester, find.text('Намерение 3'));
    await _tap(tester, find.text('Сохранить'));
    await _until(
      tester,
      () => actionEditorValue('Намерение 3').evaluate().isNotEmpty,
    );

    final repository = app.container.read(personalGraphRepositoryProvider);
    var deleted = false;
    unawaited(() async {
      for (final command in [
        DeleteLongTermRelation(durabilityRelation(101)),
        DeleteLongTermRelation(durabilityRelation(103)),
        DeleteLongTermRelation(durabilityRelation(104)),
      ]) {
        expect(await repository.execute(command), isA<GraphCommandSucceeded>());
      }
      expect(
        await repository.execute(DeleteIntention(durabilityIntention(1))),
        isA<GraphCommandSucceeded>(),
      );
      deleted = true;
    }());
    await _until(tester, () => deleted);
    await _until(
      tester,
      () => actionEditorValue('Удалено').evaluate().isNotEmpty,
    );
    // Удалены корень и связь от него: отметка после названия и на пути.
    expect(actionEditorValue('Удалено'), findsNWidgets(2));
    expect(actionEditorValue('Намерение 1'), findsOneWidget);
    expect(actionEditorCanCreate(tester), isTrue);

    await _tap(tester, actionEditorValue('Намерение 1'));
    await settlePathScreen(tester);
    Finder onPath(String text) =>
        find.descendant(of: pathScreen, matching: find.text(text));
    expect(onPath('Намерение 1'), findsNothing);
    expect(
      tester.getTopLeft(onPath('Намерение 2')).dy,
      lessThan(tester.getTopLeft(onPath('Намерение 3')).dy),
    );
    expect(isPathSaveEnabled(tester), isTrue);
    await tapPathBack(tester);
    await _tap(tester, find.text('Отменить'));
    expect(actionEditorValue('Намерение 1'), findsOneWidget);
    expect(actionEditorValue('Удалено'), findsNWidgets(2));

    await _tap(tester, actionEditorCreateButton);
    await _until(
      tester,
      () =>
          actionEditorValue(app.l10n.actionPathConflict).evaluate().isNotEmpty,
    );
    expect(
      tester.widget<EditableText>(actionEditorTitleField).controller.text,
      'Прогулка',
    );
    expect(actionEditorValue('Намерение 3'), findsOneWidget);
    expect(
      await tester.runAsync(() => durabilityRows(app.database, 'actions')),
      isEmpty,
    );
  });

  testWidgets('пустой день открывает лист с выбранной датой и без пути', (
    tester,
  ) async {
    await _start(tester);
    final date = CalendarDate.fromParts(2026, 10, 6);
    await selectActionDayDate(tester, date);
    await _until(
      tester,
      () => find.text('Нет действий на эту дату').evaluate().isNotEmpty,
    );
    await _tap(tester, find.text('Новое действие'));
    expect(actionEditorValue('6 окт.'), findsOneWidget);
    expect(actionEditorValue('Выберите причину'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(shownActionDayDate(tester), date);
  });
  testWidgets('охват «Все» остаётся в каталоге при переходе к связям', (
    tester,
  ) async {
    final app = await _start(tester);
    await IntentionCreationOrigin.graph.open(
      tester,
      app.router,
      participantId: durabilityIntention(1),
      waitFor: (tester, finder) =>
          _until(tester, () => finder.evaluate().isNotEmpty),
    );
    await selectIntentionCatalogScope(tester, IntentionScope.all);
    await _until(
      tester,
      () => intentionCatalogRow('Намерение 1').evaluate().isNotEmpty,
    );
    expect(shownIntentionCatalogParameters(tester).scope, IntentionScope.all);
    await _tap(tester, intentionCatalogRow('Намерение 1'));
    await _until(
      tester,
      () => _key('intention-details-title').evaluate().isNotEmpty,
    );
    await _tap(tester, find.text(app.l10n.detailsRelationsTab).first);
    expect(find.text(app.l10n.detailsRelationsNeedsHint), findsOneWidget);
    expect(find.text(app.l10n.intentionPickerScopeAll), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(shownIntentionCatalogParameters(tester).scope, IntentionScope.all);
  });

  testWidgets(
    'закрытие чистой панели возвращает дату, секции и прокрутку экрана дня',
    (tester) async {
      final app = await _start(tester, seed: _seedActionsForReturn);
      final date = CalendarDate.fromParts(2026, 10, 7);
      await selectActionDayDate(tester, date);
      await _until(
        tester,
        () => _key('action-day-section-incomplete').evaluate().isNotEmpty,
      );
      await showActionDaySection(tester, ActionDaySection.incomplete);
      await showActionDaySection(tester, ActionDaySection.completed);
      final semantics = tester.ensureSemantics();
      void expectSections() {
        expect(
          tester
              .getSemantics(_key('action-day-section-incomplete'))
              .flagsCollection
              .isExpanded,
          Tristate.isFalse,
        );
        expect(
          tester
              .getSemantics(_key('action-day-section-completed'))
              .flagsCollection
              .isExpanded,
          Tristate.isTrue,
        );
      }

      expectSections();
      final position = _actionDayScrollPosition(tester);
      position.jumpTo(position.maxScrollExtent / 2);
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      final offset = position.pixels;
      expect(shownActionDayDate(tester), date);
      await _openIntentionEditor(tester, app, IntentionCreationOrigin.actions);
      await tester.tap(_key('intention-editor-close'));
      await _until(
        tester,
        () => _key('intention-editor-title').evaluate().isEmpty,
      );
      await tester.pumpAndSettle();
      expect(shownActionDayDate(tester), date);
      final restored = _actionDayScrollPosition(tester);
      expect(restored.pixels, offset);
      expect(
        tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
        AppDestination.actions,
      );
      // Заголовок невыполненных над прокрученной выдачей не построен.
      restored.jumpTo(0);
      await tester.pumpAndSettle();
      expectSections();
      semantics.dispose();
    },
  );
  testWidgets('создание при занятой поверхности закрывает форму и обновляет '
      'каталог до сообщения, а возвращение не повторяет результат', (
    tester,
  ) async {
    final app = await _start(tester, fileBacked: true);
    const origin = IntentionCreationOrigin.graph;
    final history = await origin.open(
      tester,
      app.router,
      participantId: durabilityIntention(2),
      waitFor: (tester, finder) =>
          _until(tester, () => finder.evaluate().isNotEmpty),
    );
    await _openIntentionEditor(tester, app, origin);
    await _fillIntentionEditor(tester);
    const title = 'Намерение новое';
    await tester.enterText(_key('intention-editor-title'), title);
    final coordinator = app.container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final completions = <GraphCommandCompletion>[];
    final subscription = coordinator.completions.listen(completions.add);
    addTearDown(subscription.cancel);
    coordinator.acceptRelationDelete(
      DeleteLongTermRelation(durabilityRelation(104)),
    );
    await _until(tester, () => completions.length == 1);
    await tester.pumpAndSettle();
    final first = app.l10n.graphOperationMessage(
      app.l10n.graphOperationDelete,
      app.l10n.graphOperationRelation,
      app.l10n.relationDeleted,
    );
    final createdMessage = app.l10n.graphOperationMessage(
      app.l10n.graphOperationCreate,
      title,
      app.l10n.editorCreated,
    );
    expect(find.text(first).hitTestable(), findsOneWidget);

    app.observer.observe(_intentionsTable);
    await _submit(tester, app);
    await _until(
      tester,
      () => app.router.current.name == IntentionDetailsRoute.name,
    );
    await tester.pumpAndSettle();
    expect(_key('intention-editor-title'), findsNothing);
    expect(find.text(title), findsOneWidget);
    expect(find.text(first).hitTestable(), findsOneWidget);
    expect(find.text(createdMessage, skipOffstage: false), findsNothing);
    final stored = (await tester.runAsync(
      () => durabilityRows(app.database, _intentionsTable),
    ))!;
    expect(stored, hasLength(_initialIntentionRows + 1));
    expect(stored.last['title'], title);
    expect(stored.last['description'], 'Сохранённое описание');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    history.expectRestored(tester, app.router);
    expect(find.text(title), findsOneWidget);
    expect(intentionCatalogTotal(6), findsOneWidget);
    expect(find.text(first).hitTestable(), findsOneWidget);
    expect(find.text(createdMessage, skipOffstage: false), findsNothing);
    await tester.drag(find.text(first), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text(createdMessage).hitTestable(), findsOneWidget);
    await tester.drag(find.text(createdMessage), const Offset(600, 0));
    await tester.pumpAndSettle();
    await _tap(tester, find.text(title));
    await _until(
      tester,
      () => app.router.current.name == IntentionDetailsRoute.name,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    history.expectRestored(tester, app.router);
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
    expect(app.observer.attempts, 1);
    expect(completions, hasLength(2));
    expect(
      await tester.runAsync(
        () => durabilityRows(app.database, _intentionsTable),
      ),
      stored,
    );
    expect(tester.takeException(), isNull);
  });

  for (final origin in const [
    IntentionCreationOrigin.actions,
    IntentionCreationOrigin.deep,
  ]) {
    testWidgets('намерение: успех над ${origin.description} сохраняет '
        'ID, историю, выбранный пункт и параметры каталогов', (tester) async {
      final app = await _start(tester);
      final history = await origin.open(
        tester,
        app.router,
        participantId: durabilityIntention(2),
        waitFor: (tester, finder) =>
            _until(tester, () => finder.evaluate().isNotEmpty),
      );
      final catalogs = app.catalogs;
      await _openIntentionEditor(tester, app, origin);
      history.expectPrefix(app.router);
      await _fillIntentionEditor(tester);
      app.observer.observe(_intentionsTable);
      await _tap(tester, _key(_intentionSubmit));
      await _until(
        tester,
        () => app.router.current.name == IntentionDetailsRoute.name,
      );
      await tester.pumpAndSettle();
      history.expectPrefix(app.router);
      expect(app.router.stackData, hasLength(history.routes.length + 1));
      expect(
        tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
        origin.destination,
      );
      final rows = (await tester.runAsync(
        () => durabilityRows(app.database, _intentionsTable),
      ))!;
      final created = rows.last;
      expect(rows, hasLength(_initialIntentionRows + 1));
      expect(app.observer.attempts, 1);
      final resultId = switch (app.router.current.args) {
        IntentionDetailsRouteArgs(:final intentionId) =>
          intentionId.toCanonicalString(),
        _ => throw StateError('Ожидался маршрут созданной сущности.'),
      };
      expect(resultId, created['id']);
      _expectIntentionStored(created);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      history.expectRestored(tester, app.router);
      expect(app.catalogs, catalogs);
      await history.expectUnderlyingTask(tester, app.router);
      expect(tester.takeException(), isNull);
    });
  }
  for (final origin in const [
    IntentionCreationOrigin.actions,
    IntentionCreationOrigin.deep,
  ]) {
    for (final leave in [false, true]) {
      testWidgets('намерение: ${leave ? 'выход во время записи' : 'отмена'} '
          'над ${origin.description} сохраняет исходную сессию', (
        tester,
      ) async {
        final app = await _start(tester);
        final history = await origin.open(
          tester,
          app.router,
          participantId: durabilityIntention(2),
          waitFor: (tester, finder) =>
              _until(tester, () => finder.evaluate().isNotEmpty),
        );
        final catalogs = app.catalogs;
        await _openIntentionEditor(tester, app, origin);
        await _fillIntentionEditor(tester);
        app.observer.observe(_intentionsTable, hold: leave);
        if (leave) await _submit(tester, app);
        await _closeCreation(tester, app);
        history.expectRestored(tester, app.router);
        final current = app.router.stackData.last.matchId;
        app.observer.release();
        if (leave) {
          await _until(
            tester,
            () => _key('graph-operation-message').evaluate().isNotEmpty,
          );
          await tester.pumpAndSettle();
        }
        expect(app.router.stackData.last.matchId, current);
        history.expectRestored(tester, app.router);
        expect(app.catalogs, catalogs);
        final rows = await durabilityRows(app.database, _intentionsTable);
        expect(rows, hasLength(_initialIntentionRows + (leave ? 1 : 0)));
        expect(app.observer.attempts, leave ? 1 : 0);
        if (leave) _expectIntentionStored(rows.last);
        await history.expectUnderlyingTask(tester, app.router);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
