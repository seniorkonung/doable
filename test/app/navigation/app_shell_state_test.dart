import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/application/intention_actions.dart';
import 'package:doable/src/action/application/path_candidates.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar_viewport.dart';
import 'package:doable/src/action/presentation/day/action_day_date_page.dart';
import 'package:doable/src/action/presentation/day/action_day_root_page.dart'
    as day_page;
import 'package:doable/src/action/presentation/day/action_day_state.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/calendar_handle.dart';
import 'package:doable/src/design_system/components/date_grid.dart';
import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/design_system/components/detail_row.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as catalog_page;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_options.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_day_controls.dart';
import '../../support/action_day_provider.dart';
import '../../support/action_panel_controls.dart';
import '../../support/action_seed.dart';
import '../../support/app_root_pages.dart';
import '../../support/controlled_local_date.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/intention_catalog_controls.dart';
import '../../support/intention_edit_screen.dart';
import '../../support/intention_options.dart';
import '../../support/tag_positions.dart';
import '../../support/intention_holding_read_contract_test_fallback.dart';

/// Активные намерения «Намерение 01» … «Намерение 40»: выдача каталога
/// длиннее экрана.
const _activeCount = 40;

/// Активные намерения «Обычное 1» … «Обычное 5», которые исключает фильтр
/// названия «Намерение».
const _firstPlain = 41;
const _plainCount = 5;

/// Архивированные намерения «Архив 001» … «Архив 250» с тегом «Здоровье»:
/// выдача архивного охвата с фильтром и условием по тегу занимает три порции.
const _firstArchived = 101;
const _archivedCount = 250;

/// Архивированные намерения «Архив без тега 01» … «Архив без тега 10»:
/// фильтр названия их оставляет, а условие по тегу исключает.
const _firstUntagged = 401;
const _untaggedCount = 10;

const _healthTag = 601;

/// Связь «Намерение 01» → «Намерение 02» — путь каждого действия.
const _relation = 501;

/// Действия на одну дату с корневым намерением «Намерение 01»: чётные по
/// порядку создания не выполнены, нечётные выполнены.
const _firstAction = 1001;
const _actionCount = 240;
const _actionTitle = 'Пробежка';
final _actionDate = CalendarDate.fromParts(2026, 9, 25);

/// Локальное сегодня приложения — следующий день: на экране дня выбирается
/// прошлый день действий, отличный от начального.
final _today = CalendarDate.fromParts(2026, 9, 26);

/// Дата просмотра подготовленного календаря экрана дня: за четыре недели до
/// выбранного дня. Раскрытый календарь показывает её месяц, а сама она не
/// совпадает ни с выбранным днём, ни с началом месяца.
final _viewedDate = CalendarDate.fromParts(2026, 8, 28);

/// Последний день месяца просмотра. Раскрытый календарь показывает его в
/// последней строке сетки августа, а в листе даты сентября только он
/// называется числом 31.
final _movedDate = CalendarDate.fromParts(2026, 8, 31);

/// Размеры порций каталога намерений и экрана дня.
const _intentionPageSize = 100;
const _actionDayPageSize = 50;

const _message = ValueKey('graph-operation-message');

void main() {
  for (final fromMonths in [false, true]) {
    final level = fromMonths ? 'месяцев' : 'лет';
    testWidgets('после возврата ручки открытая страница $level сохраняется '
        'вместе с экраном дня при смене пункта, повторном выборе и возврате '
        'из панели действия', (tester) async {
      final app = await _start(tester);
      await _prepareActionDay(tester, app);
      final before = _actionDayView(tester, app);
      for (final distance in [-400.0, 400.0]) {
        await tester.drag(find.byType(CalendarHandle), Offset(0, distance));
        await tester.pumpAndSettle();
      }
      expect(_actionDayView(tester, app), before);
      await _tap(
        tester,
        find.bySemanticsLabel(app.l10n.actionCalendarChooseYearAndMonth),
      );
      await _tap(
        tester,
        find.bySemanticsLabel(app.l10n.actionCalendarNextYears),
      );
      if (fromMonths) {
        await _tap(tester, find.text('2035'));
        await _tap(
          tester,
          find.bySemanticsLabel(app.l10n.actionCalendarNextYear),
        );
      }
      await tester.pumpAndSettle();
      final title = fromMonths ? '2036' : '2032–2043';
      final position = _actionDayPosition(tester).pixels;

      void expectPreserved() {
        expect(find.text(title), findsOneWidget);
        expect(_actionDayPosition(tester).pixels, position);
        expect(app.actionDay.selection.date, _actionDate);
        expect(app.actionDay.selection.completedExpanded, isFalse);
        expect(_actionDayIds(app), before['загруженные записи']);
        expect(app.repository.actionDayReads, before['чтения выдачи']);
      }

      final height = tester.getSize(actionDayDateControl).height;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CalendarHandle)),
      );
      await gesture.moveBy(const Offset(0, -20));
      await gesture.moveBy(
        const Offset(0, -40),
        timeStamp: const Duration(seconds: 1),
      );
      await tester.pump();
      expect(tester.getSize(actionDayDateControl).height, lessThan(height));
      expect(_actionDayPosition(tester).pixels, position);
      await gesture.up(timeStamp: const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expectPreserved();

      await _select(tester, AppDestination.home);
      await _select(tester, AppDestination.actions);
      expectPreserved();
      await _select(tester, AppDestination.actions);
      expectPreserved();
      await tester.tap(_actionDayRows.hitTestable().first);
      await _until(tester, actionPanel);
      await tester.pumpAndSettle();
      await closeActionPanel(tester);
      expectPreserved();

      await _tap(
        tester,
        find.bySemanticsLabel(app.l10n.actionCalendarBackToMonthDays),
      );
      await tester.pumpAndSettle();
      expect(_actionDayView(tester, app), before);
      expect(tester.takeException(), isNull);
    });
  }

  group('повторный выбор уже выбранного пункта', () {
    for (final destination in _rootPageStates.keys) {
      testWidgets('«${_names[destination]}»: состояние страницы не меняется', (
        tester,
      ) async {
        final page = _rootPageStates[destination]!;
        final app = await _start(tester);
        await page.prepare(tester, app);
        final before = page.view(tester, app);

        await _select(tester, destination);
        await _select(tester, destination);

        expect(_selected(tester), destination);
        expect(page.view(tester, app), before);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('сброс истории со страницы намерения', () {
    testWidgets('пункт «Действия» над экраном дня на дату открывает '
        'корневой экран дня с прежним состоянием', (tester) async {
      final app = await _start(tester);
      await _prepareActionDay(tester, app);
      final before = _actionDayView(tester, app);
      await _select(tester, AppDestination.intentionGraph);
      final router = app.container.read(appRouterProvider);
      await tester.tap(intentionCatalogRows.hitTestable().first);
      await _until(tester, find.byType(IntentionDetailsPage));
      await tester.pumpAndSettle();
      unawaited(router.push(ActionDayDateRoute(date: _viewedDate)));
      await _until(tester, find.byType(ActionDayDatePage));
      await tester.pumpAndSettle();
      expect(_selected(tester), AppDestination.intentionGraph);

      await _select(tester, AppDestination.actions);

      expect(router.stack.map((page) => page.name), [AppShellRoute.name]);
      expect(find.byType(ActionDayDatePage, skipOffstage: false), findsNothing);
      expect(
        find.byType(IntentionDetailsPage, skipOffstage: false),
        findsNothing,
      );
      expect(_selected(tester), AppDestination.actions);
      // Экран дня на дату читал свою выдачу тем же счётчиком.
      expect(
        {..._actionDayView(tester, app)}..remove('чтения выдачи'),
        {...before}..remove('чтения выдачи'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('позднее архивирование один раз согласует сохранённые корни '
        'на настоящем хранилище после сброса истории', (tester) async {
      final app = await _start(tester);
      await _prepareActionDay(tester, app);
      final dayBefore = _actionDayParameters(tester, app);
      await _select(tester, AppDestination.intentionGraph);
      await _enterTitle(tester, 'Намерение', total: _activeCount);
      await _selectOldestFirst(tester);
      final catalogBefore = _intentionCatalogParameters(tester);
      final target = app.intentionCatalog.items.first;
      final router = app.container.read(appRouterProvider);
      await tester.tap(intentionCatalogRow(target.title).hitTestable());
      await _until(tester, find.byType(IntentionDetailsPage));
      await tester.pumpAndSettle();
      app.repository.holdNextCommand();
      await _chooseIntentionOption(tester, IntentionOption.archive);
      await _waitFor(tester, () => app.repository.isHolding);

      await _select(tester, AppDestination.home);
      expect(
        app.raw.select('SELECT is_archived FROM intentions WHERE id = ?', [
          target.id.toCanonicalString(),
        ]).single['is_archived'],
        0,
      );

      app.repository.releaseCommand();
      await _waitFor(
        tester,
        () => app.intentionCatalog.items.every((item) => item.id != target.id),
      );
      await _settle(tester);
      expect(
        app.raw.select('SELECT is_archived FROM intentions WHERE id = ?', [
          target.id.toCanonicalString(),
        ]).single['is_archived'],
        1,
      );
      expect(router.stack.map((page) => page.name), [AppShellRoute.name]);
      expect(
        find.byType(IntentionDetailsPage, skipOffstage: false),
        findsNothing,
      );
      // Успех архивирования виден в согласованных корнях, а не в сообщении.
      expect(_builtMessages, findsNothing);
      expect(app.repository.commands.single, isA<ArchiveIntention>());

      await _select(tester, AppDestination.intentionGraph);
      expect(intentionCatalogTotal(_activeCount - 1), findsOneWidget);
      expect(find.text(target.title), findsNothing);
      expect(_intentionCatalogParameters(tester), catalogBefore);
      await _select(tester, AppDestination.actions);
      expect(_actionDayParameters(tester, app), dayBefore);
      expect(_builtMessages, findsNothing);
      expect(tester.takeException(), isNull);
    });

    // Сброс одинаков для всех пунктов: достаточно повторного выбора текущего
    // пункта и перехода на другой.
    for (final (origin, destination) in [
      (AppDestination.intentionGraph, AppDestination.intentionGraph),
      (AppDestination.intentionGraph, AppDestination.actions),
    ]) {
      testWidgets('из «${_names[origin]}» в «${_names[destination]}» '
          'сохраняет состояние всех корневых страниц без повторного чтения', (
        tester,
      ) async {
        final app = await _start(tester);
        final before = <AppDestination, Map<String, Object?>>{};
        for (final entry in _rootPageStates.entries) {
          await entry.value.prepare(tester, app);
          before[entry.key] = entry.value.view(tester, app);
        }
        await _select(tester, origin);
        final router = app.container.read(appRouterProvider);
        await tester.tap(intentionCatalogRows.hitTestable().first);
        await _until(tester, find.byType(IntentionDetailsPage));
        await tester.pumpAndSettle();
        expect(_selected(tester), origin);
        // Вторая страница создаёт глубокую историю над тем же пунктом.
        unawaited(
          router.push(
            IntentionDetailsRoute(
              intentionId: app.intentionCatalog.items[1].id,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(_selected(tester), origin);

        await _select(tester, destination);

        expect(router.stack.map((page) => page.name), [AppShellRoute.name]);
        expect(
          find.byType(IntentionDetailsPage, skipOffstage: false),
          findsNothing,
        );
        expect(_selected(tester), destination);
        for (final entry in _rootPageStates.entries) {
          await _select(tester, entry.key);
          expect(entry.value.view(tester, app), before[entry.key]);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('невыбранная корневая страница согласуется с подтверждёнными '
      'изменениями', () {
    testWidgets('переименование намерения из пути действия видно в строке '
        'каталога намерений без сброса его параметров и '
        'позиции', (tester) async {
      final app = await _start(tester);
      final renamed = _activeTitle(2);
      const newTitle = 'Намерение 02 после переименования';
      await _select(tester, AppDestination.intentionGraph);
      await _enterTitle(tester, 'Намерение', total: _activeCount);
      await _selectOldestFirst(tester);
      // Строка переименуемого намерения остаётся в видимой части.
      intentionCatalogListPosition(tester).jumpTo(60);
      await tester.pumpAndSettle();
      expect(intentionCatalogRow(renamed), findsOneWidget);
      final before = _intentionCatalogParameters(tester);

      await _select(tester, AppDestination.actions);
      await _selectDay(tester, app, _actionDate, incomplete: _actionCount ~/ 2);
      await _tap(tester, _actionDayRows.first);
      await _openPanelPathIntention(tester, app, renamed);
      await _until(tester, find.byType(IntentionDetailsPage));
      await _open(tester, intentionHeadTitle, IntentionEditPage);
      await tester.enterText(intentionEditTitleField, newTitle);
      await _tap(tester, intentionEditSave);
      await _waitFor(
        tester,
        () => find.byType(IntentionEditPage).evaluate().isEmpty,
      );
      await _until(
        tester,
        find.descendant(
          of: find.byType(IntentionDetailsPage),
          matching: find.text(newTitle),
        ),
      );
      await _select(tester, AppDestination.intentionGraph);

      expect(intentionCatalogRow(newTitle), findsOneWidget);
      expect(intentionCatalogRow(renamed), findsNothing);
      expect(_intentionCatalogParameters(tester), before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('изменение действия на странице дня на дату обновляет отметки '
        'скрытого экрана дня: календарь, секции и позиция сохраняются, а '
        'количество и продолжение выдачи относятся к новой '
        'ревизии', (tester) async {
      final app = await _start(tester);
      // Первое созданное невыполненное действие уходит из выдачи в пустой
      // просматриваемый день: там появляется галочка, а количество
      // исходного дня уменьшается.
      const changed = _firstAction;
      expect(_isCompleted(changed), isFalse);
      await _prepareActionDay(tester, app);
      final before = _actionDayParameters(tester, app);
      await _tap(
        tester,
        find.bySemanticsLabel(app.l10n.actionCalendarChooseYearAndMonth),
      );
      await _tap(tester, find.text('2028'));
      final rootProvider = openedActionDayProvider(app.container);
      final marksProvider = openedActionDayMarksProvider(app.container);
      await _waitFor(tester, () {
        expect(app.container.exists(marksProvider), isTrue);
        return app.container.read(marksProvider).dayStatuses != null;
      });
      expect(
        app.container.read(marksProvider).dayStatuses!.statuses[_movedDate],
        isNull,
      );

      // Корневой экран дня скрыт: действие меняют на другой странице дня.
      await _select(tester, AppDestination.intentionGraph);
      unawaited(
        app.container
            .read(appRouterProvider)
            .push(ActionDayDateRoute(date: _actionDate)),
      );
      await _until(tester, find.byType(ActionDayDatePage));
      await _tap(tester, _actionDayRows.first);
      await _until(tester, actionPanelReady);
      expect(shownActionId(tester), _actionId(changed));
      await _tap(
        tester,
        find.descendant(
          of: find.widgetWithText(DetailRow, app.l10n.actionFieldDate),
          matching: find.byType(Button),
        ),
      );
      await _tap(
        tester,
        find.descendant(
          of: find.byType(DateGrid),
          matching: find.text('${_movedDate.day}'),
        ),
      );
      await _waitFor(
        tester,
        () =>
            app.raw.select('SELECT date FROM actions WHERE id = ?', [
              tagFixtureId(changed),
            ]).single['date'] ==
            _movedDate.toCanonicalString(),
      );
      // Пока принятое изменение действия не завершено, другое не принимается.
      await _waitFor(tester, () => !app.isActionRunning(_actionId(changed)));
      await closeActionPanel(tester);
      await selectActionDayDate(tester, _movedDate, tap: _tap);
      final completion = find.byKey(
        ValueKey('action-day-completion-${tagFixtureId(changed)}'),
      );
      await _until(tester, completion);
      expect(actionCompletionState(tester, completion).completed, isFalse);
      await _tap(tester, completion);
      // Существующая модель скрытого экрана согласуется до возврата.
      await _waitFor(tester, () {
        expect(app.container.exists(marksProvider), isTrue);
        return app.container
                .read(marksProvider)
                .dayStatuses
                ?.statuses[_movedDate] ==
            ActionDayStatus.allCompleted;
      });
      expect(find.byType(day_page.ActionDayRootPage), findsNothing);
      final hiddenRoot = app.container.read(rootProvider) as ActionDayLoaded;
      expect(hiddenRoot.selection.date, _actionDate);
      expect(hiddenRoot.totalCount, _actionCount - 1);
      expect(hiddenRoot.incomplete.items, hasLength(100));
      await _closeTop(tester, ActionDayDatePage);
      await _select(tester, AppDestination.actions);
      await _waitFor(
        tester,
        () => app.actionDay.freshness == ActionDayFreshness.current,
      );
      await tester.pumpAndSettle();

      // Невыполненные действия дня после изменения в порядке выдачи: более
      // ранние по созданию раньше.
      final expected = [
        for (
          var action = _firstAction;
          action < _firstAction + _actionCount;
          action++
        )
          if (!_isCompleted(action) && action != changed) tagFixtureId(action),
      ];
      expect(find.text('2028'), findsOneWidget);
      await _tap(
        tester,
        find.bySemanticsLabel(app.l10n.actionCalendarBackToMonthDays),
      );
      await tester.pumpAndSettle();
      expect(_actionDayParameters(tester, app), before);
      expect(
        actionDaySectionWithCount(
          section: ActionDaySection.incomplete,
          count: _actionCount ~/ 2 - 1,
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        app.actionDay.incomplete.items
            .map((item) => item.id.toCanonicalString())
            .toList(),
        expected.take(app.actionDay.incomplete.items.length).toList(),
      );

      // Продолжение новой ревизии дополняет выдачу без пропусков и повторов.
      await _closeMessage(tester);
      await scrollToActionDayEnd(tester, ActionDaySection.incomplete);
      await _waitFor(
        tester,
        () => app.actionDay.incomplete.items.length == expected.length,
      );
      await tester.pumpAndSettle();

      expect(
        app.actionDay.incomplete.items
            .map((item) => item.id.toCanonicalString())
            .toList(),
        expected,
      );
      expect(
        actionDaySectionWithCount(
          section: ActionDaySection.incomplete,
          count: _actionCount ~/ 2 - 1,
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        actionDayPageFooter(
          section: ActionDaySection.incomplete,
          skipOffstage: false,
        ),
        findsNothing,
      );
      await showActionDayPeriod(tester, _movedDate, tap: _tap);
      expect(actionDayDayMark(_movedDate, mark: DayMark.done), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('возврат из панели действия', () {
    testWidgets('экран дня сохраняет календарь, секции, загруженные записи и '
        'позицию прокрутки без повторного получения', (tester) async {
      final app = await _start(tester);
      await _prepareActionDay(tester, app);
      final before = _actionDayView(tester, app);

      // Строка в видимой части открывается нажатием без прокрутки страницы.
      await tester.tap(_actionDayRows.hitTestable().first);
      await _until(tester, actionPanel);
      await tester.pumpAndSettle();
      await closeActionPanel(tester);

      expect(_actionDayView(tester, app), before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('изменение действия будущего дня видно на экране дня, а '
        'выбранный день, просматриваемый месяц, раскрытие календаря, секции и '
        'позиция сохраняются', (tester) async {
      // Выбираемый день действий наступит через пять дней.
      final app = await _start(
        tester,
        today: CalendarDate.fromParts(2026, 9, 20),
      );
      // Первое созданное действие — первая строка экрана дня.
      const changed = _firstAction;
      // Только оно не выполнено: его изменение должно заменить кружок галочкой.
      seedRawGraph(app.raw, () {
        app.raw.execute(
          'UPDATE actions SET is_completed = CASE WHEN id = ? THEN 0 ELSE 1 END',
          [tagFixtureId(changed)],
        );
      });
      const wasCompleted = false;
      await _select(tester, AppDestination.actions);
      await _selectDay(tester, app, _actionDate, incomplete: 1);
      await _until(tester, actionDayDayMark(_actionDate));
      expect(actionDayDayMark(_actionDate, mark: DayMark.todo), findsOneWidget);
      // Раскрытый календарь показывает следующий месяц.
      await expandActionDayCalendar(tester, tap: _tap);
      await showActionDayPeriod(
        tester,
        CalendarDate.fromParts(2026, 10, 15),
        tap: _tap,
      );
      // Первая строка остаётся в видимой части.
      _actionDayPosition(tester).jumpTo(30);
      await tester.pumpAndSettle();
      expect(
        shownActionDayViewport(tester),
        ActionDayCalendarViewport(
          focusedDate: CalendarDate.fromParts(2026, 10, 1),
          mode: ActionDayCalendarMode.month,
        ),
      );
      final completion = find.byKey(
        ValueKey('action-day-completion-${tagFixtureId(changed)}'),
      );
      expect(actionCompletionState(tester, completion).completed, wasCompleted);
      final before = _actionDayParameters(tester, app);

      // Строка открывается нажатием без прокрутки страницы.
      await tester.tap(find.byKey(const ValueKey('action-day-row-1')));
      await _until(tester, actionPanel);
      await tester.pumpAndSettle();
      await closeActionPanel(tester);
      // Флажок нажимается там, где он есть: прокрутка к нему изменила бы
      // позицию, которую проверяет тест.
      await _until(tester, completion);
      await tester.pumpAndSettle();
      await tester.tap(completion);
      await tester.pump();
      final marksProvider = openedActionDayMarksProvider(app.container);
      await _waitFor(tester, () {
        expect(app.container.exists(marksProvider), isTrue);
        return app.container
                .read(marksProvider)
                .dayStatuses
                ?.statuses[_actionDate] ==
            ActionDayStatus.allCompleted;
      });
      await _waitFor(
        tester,
        () => app.actionDay.freshness == ActionDayFreshness.current,
      );
      await tester.pumpAndSettle();

      expect(app.actionDay.incomplete.totalCount, 0);
      expect(app.actionDay.completed.totalCount, _actionCount);
      expect(_actionDayParameters(tester, app), before);
      await showActionDayPeriod(tester, _actionDate, tap: _tap);
      await _waitFor(
        tester,
        () => actionDayDayMark(
          _actionDate,
          mark: DayMark.done,
        ).evaluate().isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('смена языка интерфейса', () {
    testWidgets('русский и английский переводят только '
        'системные подписи экрана дня, а календарь, секции, '
        'выдача, пользовательский текст и позиция сохраняются без новых '
        'чтений', (tester) async {
      final app = await _start(tester);
      await _prepareActionDay(tester, app);
      final before = _actionDayView(tester, app);

      for (final (platform, resolved) in [
        (const Locale('ru', 'RU'), const Locale('ru')),
        (const Locale('en', 'GB'), const Locale('en')),
      ]) {
        tester.binding.platformDispatcher.localesTestValue = [platform];
        await tester.pumpAndSettle();

        final reason = '$platform';
        final page = find.byType(day_page.ActionDayRootPage);
        expect(Localizations.localeOf(tester.element(page)), resolved);
        for (final (locale, labels) in _catalogLabels.entries.map(
          (entry) => (entry.key, entry.value),
        )) {
          for (final (scope, texts, skipOffstage) in [
            (actionDayDateControl, labels.calendar, true),
            (find.byType(CustomScrollView), labels.content, false),
          ]) {
            for (final label in texts) {
              expect(
                find.descendant(
                  of: scope,
                  matching: find.text(label, skipOffstage: skipOffstage),
                  skipOffstage: skipOffstage,
                ),
                locale == resolved ? findsOneWidget : findsNothing,
                reason: '$reason: «$label»',
              );
            }
          }
        }
        for (final (locale, commands) in _calendarCommands.entries.map(
          (entry) => (entry.key, entry.value),
        )) {
          for (final command in commands) {
            expect(
              find.descendant(
                of: page,
                matching: find.bySemanticsLabel(command, skipOffstage: false),
                skipOffstage: false,
              ),
              locale == resolved ? findsOneWidget : findsNothing,
              reason: '$reason: «$command»',
            );
          }
        }
        // Строка показывает прежние названия корневого намерения и действия
        // на любом языке.
        for (final text in [_activeTitle(1), _actionTitle]) {
          expect(
            find.descendant(
              of: _actionDayRows.hitTestable().first,
              matching: find.text(text),
            ),
            findsOneWidget,
            reason: '$reason: «$text»',
          );
        }
        expect(_actionDayView(tester, app), before, reason: reason);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('операция, принятая до смены пункта', () {
    for (final fails in [false, true]) {
      testWidgets(
        fails
            ? 'отказ архивирования предъявляется один раз, а смена пункта не '
                  'повторяет и не откладывает операцию'
            : 'архивирование завершается без сообщения, а смена пункта '
                  'не отменяет, не повторяет и не откладывает операцию',
        (tester) async {
          final app = await _start(tester);
          final l10n = app.l10n;
          final archived = _plainTitle(2);
          final id = tagFixtureId(_plain(2));
          int archiveState() =>
              app.raw.select(
                    'SELECT is_archived FROM intentions WHERE id = ?',
                    [id],
                  ).single['is_archived']
                  as int;
          await _select(tester, AppDestination.intentionGraph);
          await _open(
            tester,
            intentionCatalogRow(archived),
            IntentionDetailsPage,
          );
          app.repository.holdNextCommand();
          if (fails) app.faults.failNextArchiveWrite();
          await _chooseIntentionOption(tester, IntentionOption.archive);
          // Операция принята и дошла до хранилища до смены пункта.
          await _waitFor(tester, () => app.repository.isHolding);
          await _closeTop(tester, IntentionDetailsPage);

          await _select(tester, AppDestination.home);
          await _select(tester, AppDestination.actions);
          await _select(tester, AppDestination.actions);

          expect(_builtMessages, findsNothing);
          expect(archiveState(), 0);

          app.repository.releaseCommand();
          if (fails) {
            // Отказ приходит, пока выбран другой пункт, и предъявляется
            // сразу на его странице, а не при возвращении к началу перехода.
            await _until(tester, find.byKey(_message));
            await tester.pumpAndSettle();

            final message = find.text(
              l10n.graphOperationMessage(
                l10n.graphOperationArchive,
                archived,
                l10n.detailsStateChangeUnavailable,
              ),
            );
            expect(find.byKey(_message), findsOneWidget);
            expect(
              find.descendant(
                of: find.byType(day_page.ActionDayRootPage),
                matching: message,
              ),
              findsOneWidget,
            );
            // Смена пункта не предъявляет отказ заново.
            await _select(tester, AppDestination.home);
            expect(find.byKey(_message), findsOneWidget);
            expect(message, findsOneWidget);
            await _select(tester, AppDestination.intentionGraph);
            expect(find.byKey(_message), findsOneWidget);
            expect(intentionCatalogRow(archived), findsOneWidget);
            await _closeMessage(tester);
          } else {
            // Успех виден в согласованных данных каталога, а не в сообщении.
            await _select(tester, AppDestination.intentionGraph);
            await _waitFor(
              tester,
              () => intentionCatalogRow(archived).evaluate().isEmpty,
            );
            await tester.pumpAndSettle();
            expect(_builtMessages, findsNothing);
          }
          expect(app.repository.commands.single, isA<ArchiveIntention>());

          for (final destination in AppDestination.values) {
            await _select(tester, destination);
            expect(_builtMessages, findsNothing, reason: destination.name);
          }
          expect(archiveState(), fails ? 0 : 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}

const _names = {
  AppDestination.home: 'Главная',
  AppDestination.actions: 'Действия',
  AppDestination.intentionGraph: 'Граф намерений',
};

/// Корневая страница каждого пункта.
const _rootPages = {
  AppDestination.home: HomePage,
  AppDestination.actions: day_page.ActionDayRootPage,
  AppDestination.intentionGraph: catalog_page.IntentionCatalogPage,
};

/// Подготовка корневой страницы пункта и её наблюдаемое состояние.
typedef _RootPageState = ({
  Future<void> Function(WidgetTester tester, _App app) prepare,
  Map<String, Object?> Function(WidgetTester tester, _App app) view,
});

const _rootPageStates = <AppDestination, _RootPageState>{
  AppDestination.actions: (prepare: _prepareActionDay, view: _actionDayView),
  AppDestination.intentionGraph: (
    prepare: _prepareIntentionCatalog,
    view: _intentionCatalogView,
  ),
};

String _activeTitle(int number) =>
    'Намерение ${number.toString().padLeft(2, '0')}';

int _plain(int number) => _firstPlain + number - 1;

String _plainTitle(int number) => 'Обычное $number';

/// Выполнено ли действие с номером [action] фикстуры.
bool _isCompleted(int action) => (action - _firstAction).isOdd;

/// Действие, засеянное под номером [number].
ActionId _actionId(int number) =>
    (ActionId.decode(tagFixtureId(number)) as ActionIdDecodingSuccess).id;

/// Запущенное приложение на реальном хранилище с наблюдаемым репозиторием.
final class _App {
  _App(this.raw, this.container, this.repository, this.faults);

  final sqlite.Database raw;
  final ProviderContainer container;
  final _ObservedRepository repository;
  final _ArchiveWriteFaults faults;
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));

  IntentionCatalogLoaded get intentionCatalog => switch (container
      .read(intentionCatalogViewModelProvider(const BrowseIntentionCatalog()))
      .value) {
    final IntentionCatalogLoaded loaded => loaded,
    final other => fail('Каталог намерений не показывает выдачу: $other'),
  };

  ActionDayLoaded get actionDay =>
      switch (container.read(openedActionDayProvider(container))) {
        final ActionDayLoaded loaded => loaded,
        final other => fail('Экран дня без выдачи: $other'),
      };

  /// Принятое изменение действия [id] ещё не завершено.
  bool isActionRunning(ActionId id) => container
      .read(graphCommandCoordinatorProvider.notifier)
      .isActionRunning(id);

  /// Экран дня показывает полученную выдачу, в том числе пустую.
  bool get hasActionDayResult =>
      container.read(openedActionDayProvider(container)) is ActionDayLoaded;
}

/// Запускает приложение на засеянном хранилище и ждёт Главную.
///
/// [today] — локальное сегодня приложения; по умолчанию [_today].
Future<_App> _start(WidgetTester tester, {CalendarDate? today}) async {
  // Общая поверхность показывает сообщения только работающему приложению.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  // Широкий экран: подписи тестового шрифта шире настоящих.
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late sqlite.Database raw;
  late _ObservedRepository repository;
  final faults = _ArchiveWriteFaults();
  final diagnostics = InMemoryDiagnosticsSink();
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => observeConfiguredLocalDatabaseConnection(
      openInMemoryLocalDatabase(setup: (database) => raw = database),
      faults,
    ),
    diagnosticsSink: diagnostics,
    localDateSource: ControlledLocalDate(today ?? _today).read,
    repositoryFactory: (database) => repository = _ObservedRepository(
      DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.now().toUtc(),
        diagnostics,
        relationIdGenerator: UuidV7LongTermRelationIdGenerator(),
      ),
    ),
  );
  addTearDown(() async {
    repository.releaseCommand();
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  _seed(raw);
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _until(tester, find.byType(HomePage));
  await _waitFor(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
  return _App(raw, ready.container, repository, faults);
}

void _seed(sqlite.Database database) {
  database.execute('BEGIN');
  seedRawGraph(database, () {
    void insertIntention(int number, String title, {bool archived = false}) =>
        database.execute(
          'INSERT INTO intentions (id, title, is_action_ready, is_archived, '
          'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
          [tagFixtureId(number), title, 1, archived ? 1 : 0, number, number],
        );
    void assignHealth(int number) => database.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(_healthTag), tagFixtureId(number)],
    );

    database.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
      tagFixtureId(_healthTag),
      'Здоровье',
      tagPositionKey(_healthTag),
    ]);
    for (var number = 1; number <= _activeCount; number++) {
      insertIntention(number, _activeTitle(number));
    }
    for (var number = 1; number <= _plainCount; number++) {
      insertIntention(_plain(number), _plainTitle(number));
    }
    for (var index = 0; index < _archivedCount; index++) {
      final number = _firstArchived + index;
      insertIntention(
        number,
        'Архив ${(index + 1).toString().padLeft(3, '0')}',
        archived: true,
      );
      assignHealth(number);
    }
    for (var index = 0; index < _untaggedCount; index++) {
      insertIntention(
        _firstUntagged + index,
        'Архив без тега ${(index + 1).toString().padLeft(2, '0')}',
        archived: true,
      );
    }
    database.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, '
      'related_intention_id, type, priority, is_archived, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, 0, 0)',
      [tagFixtureId(_relation), tagFixtureId(1), tagFixtureId(2), 'need', 2, 0],
    );
    for (var index = 0; index < _actionCount; index++) {
      final action = _firstAction + index;
      seedAction(
        database,
        id: tagFixtureId(action),
        path: [tagFixtureId(1), tagFixtureId(2)],
        title: _actionTitle,
        date: _actionDate.toCanonicalString(),
        isCompleted: _isCompleted(action),
      );
    }
  });
  database.execute('COMMIT');
}

/// Каталог намерений: архивный охват, оба вида, фильтр названия, условие по
/// тегу, порядок от старых к новым, две загруженные порции из трёх и прокрутка
/// внутри второй порции.
Future<void> _prepareIntentionCatalog(WidgetTester tester, _App app) async {
  await _select(tester, AppDestination.intentionGraph);
  await selectIntentionCatalogScope(tester, IntentionScope.archived, tap: _tap);
  await _settle(tester);
  await selectIntentionCatalogKind(
    tester,
    IntentionKindFilter.mainAndSupporting,
    tap: _tap,
  );
  await _settle(tester);
  await _enterTitle(tester, 'Архив', total: _archivedCount + _untaggedCount);
  await addIntentionCatalogTagCondition(
    tester,
    (TagId.decode(tagFixtureId(_healthTag)) as TagIdDecodingSuccess).id,
    IntentionTagRequirement.mustBePresent,
    tap: _tap,
    waitFor: _until,
  );
  await _until(tester, intentionCatalogTotal(_archivedCount));
  await tester.pumpAndSettle();
  await _selectOldestFirst(tester);
  // Лист не забирает фокус у поля названия, а поле с фокусом после возврата
  // на страницу показало бы каретку.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();

  // Конец первой порции запрашивает вторую.
  jumpIntentionCatalog(tester, 1);
  await _waitFor(
    tester,
    () => app.intentionCatalog.items.length == 2 * _intentionPageSize,
  );
  await tester.pumpAndSettle();
  // Середина второй порции далека от её конца: третья порция не нужна.
  jumpIntentionCatalog(tester, 0.6);
  await _settle(tester);

  final catalog = app.intentionCatalog;
  expect(catalog.items, hasLength(2 * _intentionPageSize));
  expect(catalog.totalCount, _archivedCount);
  expect(catalog.nextCursor, isNotNull);
  expect(
    catalog.selection.show,
    const IntentionShowChosen(
      scope: IntentionScope.archived,
      kind: IntentionKindFilter.mainAndSupporting,
    ),
  );
  expect(catalog.selection.order, IntentionCatalogOrder.createdAtAscending);
  expect(
    shownIntentionCatalogParameters(tester).kind,
    IntentionKindFilter.mainAndSupporting,
  );
  expect(catalog.items.first.title, 'Архив 001');
  expect(shownIntentionCatalogParameters(tester).tagConditions, 1);
  expect(shownIntentionCatalogOffsets(tester), everyElement(greaterThan(0)));
}

/// Экран дня: прошлый день и невыполненные, календарь раскрыт на месяце другой
/// даты просмотра, две загруженные порции из трёх и прокрутка внутри них.
Future<void> _prepareActionDay(WidgetTester tester, _App app) async {
  final incomplete = _actionCount ~/ 2;
  await _select(tester, AppDestination.actions);
  await _selectDay(tester, app, _actionDate, incomplete: incomplete);
  await showActionDaySection(tester, ActionDaySection.incomplete);

  // Неделя даты просмотра раскрывается в её месяц.
  await showActionDayPeriod(tester, _viewedDate, tap: _tap);
  await expandActionDayCalendar(tester, tap: _tap);
  await scrollToActionDayEnd(tester, ActionDaySection.incomplete);
  await _waitFor(
    tester,
    () =>
        app.actionDay.incomplete.items.length == 2 * _actionDayPageSize &&
        app.actionDay.freshness == ActionDayFreshness.current,
  );
  await tester.pumpAndSettle();
  final position = _actionDayPosition(tester);
  position.jumpTo(position.maxScrollExtent / 2);
  await _settle(tester);

  final day = app.actionDay;
  expect(shownActionDayDate(tester), _actionDate);
  expect(
    shownActionDayViewport(tester),
    ActionDayCalendarViewport(
      focusedDate: _viewedDate,
      mode: ActionDayCalendarMode.month,
    ),
  );
  expect(day.selection.date, _actionDate);
  expect(day.totalCount, _actionCount);
  expect(day.incomplete.totalCount, incomplete);
  expect(day.incomplete.nextCursor, isNotNull);
  expect(day.selection.completedExpanded, isFalse);
  expect(day.incomplete.items.every((item) => !item.isCompleted), isTrue);
  expect(position.pixels, greaterThan(0));
}

/// Наблюдаемое состояние каталога намерений: страница, выдача, параметры,
/// позиция и число обращений к выдаче в хранилище.
Map<String, Object?> _intentionCatalogView(WidgetTester tester, _App app) {
  final catalog = app.intentionCatalog;
  return {
    ..._intentionCatalogParameters(tester),
    'загруженные намерения': [for (final item in catalog.items) item.title],
    'всего': catalog.totalCount,
    'чтения выдачи': app.repository.catalogReads,
    'чтения первой порции': app.repository.firstCatalogPortions,
  };
}

/// Параметры и позиция каталога намерений, как их видит человек.
Map<String, Object?> _intentionCatalogParameters(WidgetTester tester) => {
  'параметры': shownIntentionCatalogParameters(tester),
  'прокрутка': shownIntentionCatalogOffsets(tester),
};

/// Наблюдаемое состояние экрана дня: страница, календарь и общая прокрутка,
/// выдача, параметры, позиция и число обращений к выдаче в хранилище.
Map<String, Object?> _actionDayView(WidgetTester tester, _App app) {
  final day = app.actionDay;
  return {
    ..._actionDayParameters(tester, app),
    'загруженные записи': [
      for (final item in day.items) item.id.toCanonicalString(),
    ],
    'чтения выдачи': app.repository.actionDayReads,
  };
}

/// Календарь, секции и позиция экрана дня, как их видит человек.
///
/// Календарь и секции прокручиваются вместе с выдачей, поэтому на
/// прокрученной странице они могут стоять за верхним краем.
Map<String, Object?> _actionDayParameters(WidgetTester tester, _App app) => {
  'выбранный день': shownActionDayDate(tester),
  'просмотр календаря': shownActionDayViewport(tester),
  'секции': (
    app.actionDay.selection.incompleteExpanded,
    app.actionDay.selection.completedExpanded,
  ),
  'позиция прокрутки': _actionDayPosition(tester).pixels,
};

/// Системные подписи подготовленного экрана дня на каждом языке: выбранный
/// день, месяц и дни недели календаря и название секции выполнения.
final _catalogLabels = {
  Locale('ru'): (
    calendar: ['Август 2026', 'Пн', 'Вс'],
    content: ['Пятница', '25 сентября 2026', 'Невыполненные'],
  ),
  Locale('en'): (
    calendar: ['August 2026', 'Mon', 'Sun'],
    content: ['Friday', '25 September 2026', 'Not completed'],
  ),
};

/// Названия команд раскрытого календаря на каждом языке.
final _calendarCommands = {
  Locale('ru'): ['Предыдущий месяц', 'Следующий месяц', 'Свернуть календарь'],
  Locale('en'): ['Previous month', 'Next month', 'Collapse calendar'],
};

/// Общая прокрутка экрана дня: календарь и выдача прокручиваются вместе.
final _actionDayScrollView = find.descendant(
  of: find.byType(day_page.ActionDayRootPage),
  matching: find.byType(CustomScrollView),
);

/// Владелец общей прокрутки экрана дня.
///
/// Позицию прокрутки владелец создаёт заново при смене зависимостей, например
/// языка, и переносит в неё смещение; сам он живёт столько же, сколько
/// страница.
ScrollableState _actionDayScrollable(WidgetTester tester) => tester.state(
  find
      .descendant(of: _actionDayScrollView, matching: find.byType(Scrollable))
      .first,
);

ScrollPosition _actionDayPosition(WidgetTester tester) =>
    _actionDayScrollable(tester).position;

/// Идентификаторы загруженных записей экрана дня в порядке выдачи.
List<String> _actionDayIds(_App app) => [
  for (final item in app.actionDay.items) item.id.toCanonicalString(),
];

/// Строки выдачи экрана дня.
final _actionDayRows = find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) => value.startsWith('action-day-row-'),
    _ => false,
  },
);

/// Сообщения общей поверхности в дереве, включая невыбранные вкладки.
final _builtMessages = find.byKey(_message, skipOffstage: false);

AppDestination _selected(WidgetTester tester) =>
    tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected;

/// Упорядочивает каталог намерений от старых к новым и ждёт выдачу.
Future<void> _selectOldestFirst(WidgetTester tester) async {
  await selectIntentionCatalogOrder(
    tester,
    IntentionCatalogOrder.createdAtAscending,
    tap: _tap,
  );
  await _settle(tester);
}

/// Вводит название в каталоге намерений и ждёт выдачу с [total] совпадениями.
Future<void> _enterTitle(
  WidgetTester tester,
  String title, {
  required int total,
}) async {
  await enterIntentionCatalogTitle(tester, title);
  await _until(tester, intentionCatalogTotal(total));
  await tester.pumpAndSettle();
}

/// Выбирает [date] днём экрана дня, когда выдача начального дня уже получена,
/// и ждёт выдачу выбранного дня с [incomplete] невыполненными записями.
Future<void> _selectDay(
  WidgetTester tester,
  _App app,
  CalendarDate date, {
  required int incomplete,
}) async {
  await _waitFor(tester, () => app.hasActionDayResult);
  await selectActionDayDate(tester, date, tap: _tap);
  await _until(
    tester,
    actionDaySectionWithCount(
      section: ActionDaySection.incomplete,
      count: incomplete,
    ),
  );
  await tester.pumpAndSettle();
}

/// Выбирает пункт панели и ждёт его корневую страницу.
Future<void> _select(WidgetTester tester, AppDestination destination) async {
  await tester.tap(appNavigationDestination(destination));
  await _until(tester, find.byType(_rootPages[destination]!));
  await _settle(tester);
}

/// Открывает на вкладке «Путь» панели действия намерение с названием [title].
Future<void> _openPanelPathIntention(
  WidgetTester tester,
  _App app,
  String title,
) async {
  await _until(tester, actionPanelReady);
  // Панель могла ещё въезжать, и нажатие пришлось бы мимо вкладки.
  await tester.pumpAndSettle();
  await _tap(
    tester,
    find.descendant(
      of: actionPanel,
      matching: find.text(app.l10n.actionPanelPathTab),
    ),
  );
  await tester.pumpAndSettle();
  await _tap(
    tester,
    find.descendant(of: actionPanel, matching: find.text(title)),
  );
}

/// Нажимает [entry] и ждёт, пока страница [page] откроется целиком.
Future<void> _open(WidgetTester tester, Finder entry, Type page) async {
  await _tap(tester, entry);
  await _until(tester, find.byType(page));
  await tester.pumpAndSettle();
}

/// Закрывает верхнюю страницу системным действием «назад».
Future<void> _closeTop(WidgetTester tester, Type page) async {
  await tester.binding.handlePopRoute();
  await _waitFor(tester, () => find.byType(page).evaluate().isEmpty);
  await tester.pumpAndSettle();
}

/// Ждёт закрытия видимого сообщения по истечении его времени показа.
Future<void> _closeMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// Даёт хранилищу завершить начатые обращения и дожидается покоя кадров.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _chooseIntentionOption(
  WidgetTester tester,
  IntentionOption option,
) async {
  await _tap(tester, intentionOptionsButton);
  await _tap(tester, intentionOption(option));
}

/// Отказывает ближайшей записи архивирования недоступностью хранилища:
/// транзакция команды откатывается самим адаптером.
final class _ArchiveWriteFaults extends LocalDatabaseConnectionObserver {
  var _failNext = false;

  void failNextArchiveWrite() => _failNext = true;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (!_failNext ||
        statement.operation == LocalDatabaseSqlOperation.select ||
        !statement.statements.any(
          (sql) => sql.contains('intentions') && sql.contains('is_archived'),
        )) {
      return;
    }
    _failNext = false;
    throw sqlite.SqliteException(
      extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
      message: 'Управляемый отказ архивирования',
    );
  }
}

/// Реальный адаптер, который считает обращения корневых страниц к своим
/// выдачам и команды, а команду намерения удерживает до [releaseCommand].
/// Удержание происходит до транзакции, поэтому чтения не ждут.
final class _ObservedRepository
    with IntentionHoldingReadContractTestFallback
    implements PersonalGraphRepository {
  _ObservedRepository(this._delegate);

  final PersonalGraphRepository _delegate;
  Completer<void>? _gate;

  /// Команды, дошедшие до хранилища.
  final commands = <GraphCommand<GraphCommandOutcome, GraphCommandFailure>>[];

  /// Команда намерения принята координатором и ждёт [releaseCommand].
  var isHolding = false;

  /// Обращения к выдаче каталога намерений: первая порция и продолжения.
  var catalogReads = 0;

  /// Получения первой порции выдачи каталога намерений.
  var firstCatalogPortions = 0;

  /// Обращения к выдаче экрана дня.
  var actionDayReads = 0;

  void holdNextCommand() => _gate = Completer<void>();

  void releaseCommand() {
    final gate = _gate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<ActionDayStatusesReadResult> getActionDayStatuses(
    ActionDayStatusQuery query,
  ) => _delegate.getActionDayStatuses(query);

  @override
  Stream<ActionReadResult> watchAction(ActionId id) =>
      _delegate.watchAction(id);

  @override
  Stream<ActionPathStateReadResult> watchActionPathState(
    ActionDraftPath path,
  ) => _delegate.watchActionPathState(path);

  @override
  Future<IntentionActionsPageResult> getIntentionActionsPage(
    IntentionActionsQuery query,
  ) => _delegate.getIntentionActionsPage(query);

  @override
  Future<PathCandidatesResult> getPathCandidates(PathCandidatesQuery query) =>
      _delegate.getPathCandidates(query);

  @override
  Future<StatisticsPageResult> getStatisticsPage(StatisticsQuery query) =>
      _delegate.getStatisticsPage(query);

  @override
  Future<IntentionStatisticsSectionResult> getIntentionStatisticsSection(
    IntentionStatisticsQuery query,
  ) => _delegate.getIntentionStatisticsSection(query);

  @override
  Future<IntentionStatisticsBreakdownResult<T>>
  getIntentionStatisticsBreakdown<T>(StatisticsBreakdownCursor<T> cursor) =>
      _delegate.getIntentionStatisticsBreakdown(cursor);

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands.add(command);
    if (command is ArchiveIntention) {
      final gate = _gate;
      if (gate != null) {
        isHolding = true;
        await gate.future;
        isHolding = false;
        _gate = null;
      }
    }
    return _delegate.execute(command);
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) {
    catalogReads++;
    if (query.cursor == null) firstCatalogPortions++;
    return _delegate.getCatalogPage(query);
  }

  @override
  Future<ActionDayPageResult> getActionDayPage(ActionDayQuery query) {
    actionDayReads++;
    return _delegate.getActionDayPage(query);
  }

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => _delegate.watchIntention(id);

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  ) => _delegate.getRelationGroupPage(query);

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      _delegate.watchRelation(id);

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) =>
      _delegate.getTagCatalog(mode);

  @override
  Future<TagAssignmentsResult> getTagAssignments(IntentionId intentionId) =>
      _delegate.getTagAssignments(intentionId);

  @override
  Stream<TagReadResult> watchTag(TagId id) => _delegate.watchTag(id);
}
