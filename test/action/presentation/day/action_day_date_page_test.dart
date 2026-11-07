import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/presentation/day/action_day_body.dart';
import 'package:doable/src/action/presentation/day/action_day_date_page.dart';
import 'package:doable/src/action/presentation/day/action_day_root_page.dart';
import 'package:doable/src/action/presentation/day/action_day_state.dart';
import 'package:doable/src/action/presentation/day/action_day_view_model.dart';
import 'package:doable/src/design_system/components/calendar_handle.dart';
import 'package:doable/src/design_system/components/day_heading.dart';
import 'package:doable/src/design_system/components/notice.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/action_day_controls.dart';
import '../../../support/action_panel_controls.dart';
import '../../../support/app_root_pages.dart';
import '../../../support/controlled_local_date.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import 'action_day_calendar_test_support.dart';
import 'action_day_page_test_support.dart';

void main() {
  for (final onDate in [false, true]) {
    testWidgets(
      '${onDate ? "экран дня на дату" : "корневой экран дня"}: успех флажка не '
      'объявляется сообщением, а счётчик свёрнутой секции выполненных растёт',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final repository = ActionDayRepository();
        final selected = date(2026, 10, 7);
        final router = await _start(
          tester,
          repository,
          ControlledLocalDate(selected),
        );
        if (onDate) {
          await _pushDate(tester, router, selected);
        } else {
          await openActions(tester);
        }
        final open = actionDayItem(1, date: selected);
        final doneFirst = actionDayItem(2, date: selected, isCompleted: true);
        final doneSecond = actionDayItem(3, date: selected, isCompleted: true);
        repository.completeFirst(0, [open, doneFirst, doneSecond], total: 3);
        repository.completeDayStatuses(0, {});
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('action-day-section-completed')),
        );
        await tester.pumpAndSettle();
        expect(
          actionDaySectionCount(tester, section: ActionDaySection.incomplete),
          '1',
        );
        expect(
          actionDaySectionCount(tester, section: ActionDaySection.completed),
          '2',
        );

        await tester.tap(actionCompletionControl);
        await tester.pump();
        repository.confirmCompletion(0, open, isCompleted: true, revision: 1);
        await tester.pump();
        await tester.pump();
        repository.completeFirst(
          1,
          [
            actionDayItem(1, date: selected, isCompleted: true),
            doneFirst,
            doneSecond,
          ],
          total: 3,
          revision: 1,
        );
        await tester.pumpAndSettle();

        expect(
          actionDaySectionCount(tester, section: ActionDaySection.incomplete),
          '0',
        );
        expect(
          actionDaySectionCount(tester, section: ActionDaySection.completed),
          '3',
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(repository.completionCommands, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final closePage in [false, true]) {
    testWidgets(
      'флажок: ${closePage ? 'закрытие экрана дня на дату' : 'уход из корневого экрана дня'} сохраняет поздний отказ без смены маршрута',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final repository = ActionDayRepository();
        final selected = date(2026, 10, 7);
        final router = await _start(
          tester,
          repository,
          ControlledLocalDate(selected),
        );
        if (closePage) {
          await _pushDate(tester, router, selected);
        } else {
          await openActions(tester);
        }
        final item = actionDayItem(1, date: selected);
        repository.completeFirst(0, [item], total: 1);
        repository.completeDayStatuses(0, {});
        await tester.pumpAndSettle();
        await tester.tap(actionCompletionControl);
        await tester.pump();
        if (closePage) {
          await _back(tester);
        } else {
          await openHome(tester);
        }
        repository.failCompletion(0, const ActionUnavailableFailure());
        await tester.pumpAndSettle();
        expectHomeRootPage(router);
        expect(find.byType(SnackBar), findsOneWidget);
        await _dismissCompletionMessage(tester);
        if (closePage) {
          await _pushDate(tester, router, selected);
          repository.completeFirst(1, [item], total: 1);
          repository.completeDayStatuses(1, {});
        } else {
          await openActions(tester);
        }
        await tester.pumpAndSettle();
        final checkbox = actionCompletionState(tester, actionCompletionControl);
        expect(checkbox.completed, isFalse);
        expect(checkbox.enabled, isTrue);
        expect(find.byType(OperationFailurePresentation), findsNothing);
        // Повтор принадлежит только сессии, получившей отказ.
        expect(find.byType(Notice), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(repository.completionCommands, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (presented, buildMessage) in [
    (false, true),
    (true, true),
    (false, false),
  ]) {
    testWidgets(
      'флажок: исчезновение ${!buildMessage
          ? 'ещё не построенной'
          : presented
          ? 'предъявленной'
          : 'ещё не предъявленной'} инлайн-ошибки сохраняет единственного получателя результата',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.view.physicalSize = const Size(800, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repository = ActionDayRepository();
        final selected = date(2026, 10, 7);
        await _start(tester, repository, ControlledLocalDate(selected));
        await openActions(tester);
        repository.completeFirst(0, [
          actionDayItem(1, date: selected),
        ], total: 1);
        repository.completeDayStatuses(0, {});
        await tester.pumpAndSettle();
        await tester.tap(actionCompletionControl);
        await tester.pump();
        if (!presented) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        if (buildMessage) {
          repository.failCompletion(0, const ActionUnavailableFailure());
          await tester.pumpAndSettle();
          expect(find.byType(OperationFailurePresentation), findsOneWidget);
        } else {
          // Команда завершена, но кадра с её сообщением ещё не было.
          await tester.runAsync(() async {
            repository.failCompletion(0, const ActionUnavailableFailure());
            await Future<void>.delayed(Duration.zero);
          });
          expect(find.byType(OperationFailurePresentation), findsNothing);
        }
        expect(find.byType(SnackBar), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('action-day-section-incomplete')),
        );
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.byType(OperationFailurePresentation), findsNothing);
        if (!presented) {
          expect(find.byType(SnackBar), findsOneWidget);
          await _dismissCompletionMessage(tester);
        }
        expect(find.byType(SnackBar), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('action-day-section-incomplete')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(OperationFailurePresentation), findsNothing);
        expect(
          actionCompletionState(tester, actionCompletionControl).enabled,
          isTrue,
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(repository.completionCommands, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final changeDate in [false, true]) {
    testWidgets(
      'флажок: ${changeDate ? 'смена даты отдельного экрана дня' : 'сворачивание корневой секции'} до отказа передаёт результат оболочке один раз',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final repository = ActionDayRepository();
        final selected = date(2026, 10, 7);
        final next = date(2026, 10, 8);
        final router = await _start(
          tester,
          repository,
          ControlledLocalDate(selected),
        );
        if (changeDate) {
          await _pushDate(tester, router, selected);
        } else {
          await openActions(tester);
        }
        final item = actionDayItem(1, date: selected);
        repository.completeFirst(0, [item], total: 1);
        repository.completeDayStatuses(0, {});
        await tester.pumpAndSettle();
        await tester.tap(actionCompletionControl);
        await tester.pump();
        if (changeDate) {
          await tester.tap(calendarDay(next));
          await tester.pump();
          repository.completeFirst(1, [], total: 0);
        } else {
          await tester.tap(
            find.byKey(const ValueKey('action-day-section-incomplete')),
          );
        }
        await tester.pumpAndSettle();
        expect(actionCompletionControl, findsNothing);
        repository.failCompletion(0, const ActionUnavailableFailure());
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.byType(OperationFailurePresentation), findsNothing);
        expect(
          dayCell(tester, changeDate ? next : selected).isSelected,
          isTrue,
        );
        await _dismissCompletionMessage(tester);

        if (changeDate) {
          await tester.tap(calendarDay(selected));
          await tester.pump();
          repository.completeFirst(2, [item], total: 1);
        } else {
          await tester.tap(
            find.byKey(const ValueKey('action-day-section-incomplete')),
          );
        }
        await tester.pumpAndSettle();
        final checkbox = actionCompletionState(tester, actionCompletionControl);
        expect(checkbox.completed, isFalse);
        expect(checkbox.enabled, isTrue);
        expect(find.byType(OperationFailurePresentation), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(repository.completionCommands, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'флажок: конфликт, переданный оболочке при уходе из корневого экрана дня, '
    'не показывается у вернувшейся строки и требует актуализации действия',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final repository = ActionDayRepository();
      final selected = date(2026, 10, 7);
      await _start(tester, repository, ControlledLocalDate(selected));
      await openActions(tester);
      final item = actionDayItem(1, date: selected);
      repository.completeFirst(0, [item], total: 1);
      repository.completeDayStatuses(0, {});
      await tester.pumpAndSettle();
      final checkbox = actionCompletionControl;
      await tester.tap(checkbox);
      await tester.pump();
      await openHome(tester);
      repository.failCompletion(0, const ActionConflictFailure());
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      await _dismissCompletionMessage(tester);

      await openActions(tester);
      await tester.pumpAndSettle();
      expect(find.byType(OperationFailurePresentation), findsNothing);
      expect(actionCompletionState(tester, checkbox).enabled, isFalse);
      // Вернувшаяся строка сохраняет в уведомлении только актуализацию.
      expect(find.byType(Notice), findsOneWidget);
      expect(actionCompletionNoticeAction('Повторить'), findsNothing);
      await tester.tap(actionCompletionNoticeAction('Обновить действие'));
      await tester.pump();
      repository.completeFirst(1, [item], total: 1);
      await tester.pumpAndSettle();
      expect(actionCompletionState(tester, checkbox).completed, isFalse);
      expect(actionCompletionState(tester, checkbox).enabled, isTrue);
      expect(find.byType(OperationFailurePresentation), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(repository.completionCommands, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  for (final onDate in [false, true]) {
    testWidgets(
      '${onDate ? 'экран дня на дату' : 'корневой экран дня'}: смена дня после двух порций сохраняет свёрнутые невыполненные и раскрытые выполненные',
      (tester) async {
        final repository = ActionDayRepository();
        final selected = date(2026, 10, 7);
        final next = date(2026, 10, 8);
        await pumpActionDay(
          tester,
          repository,
          today: selected,
          locale: const Locale('ru'),
          size: const Size(360, 900),
          actionDayDate: onDate ? selected : null,
        );
        repository.completeFirst(
          0,
          [
            for (var number = 1; number <= 50; number++)
              actionDayItem(number, date: selected, isCompleted: true),
          ],
          total: 60,
          cursor: const ActionDayTestCursor(),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('action-day-section-incomplete')),
        );
        await tester.pumpAndSettle();
        final body = tester.widget<ActionDayBody>(find.byType(ActionDayBody));
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ActionDayBody)),
        );
        final provider = actionDayViewModelProvider(body.instance);
        final scrollable = find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        await scrollToActionDayEnd(tester, ActionDaySection.completed);
        repository.completeMore(1, [
          for (var number = 51; number <= 60; number++)
            actionDayItem(number, date: selected, isCompleted: true),
        ]);
        await tester.pumpAndSettle();
        expect(
          (container.read(provider) as ActionDayLoaded).completed.items,
          hasLength(60),
        );
        expect(position.pixels, greaterThan(0));
        await tester.tap(calendarDay(next));
        await tester.pump();
        expect(container.read(provider), isA<ActionDayInitialLoad>());
        expect(container.read(provider).selection.incompleteExpanded, isFalse);
        expect(container.read(provider).selection.completedExpanded, isTrue);
        expect(position.pixels, 0);
        expect(repository.queries.last.date, next);
        expect(repository.queries.last.cursor, isNull);
        repository.completeFirst(2, [
          actionDayItem(201, date: next, isCompleted: true),
        ], total: 1);
        await tester.pumpAndSettle();
        final loaded = container.read(provider) as ActionDayLoaded;
        expect(loaded.completed.items.single.date, next);
        expect(loaded.completed.nextCursor, isNull);
        expect(loaded.selection.incompleteExpanded, isFalse);
        expect(loaded.selection.completedExpanded, isTrue);
        expect(find.byType(DayHeading).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'после возврата ручки пролистанные годы и месяцы независимы '
    'у двух экранов дня на одну дату и корневого; новый экземпляр начинает с недели',
    (tester) async {
      final repository = ActionDayRepository();
      final today = date(2026, 10, 12);
      final selected = date(2026, 10, 7);
      final router = await _start(
        tester,
        repository,
        ControlledLocalDate(today),
      );
      await openActions(tester);
      repository.completeFirst(0, [actionDayItem(1, date: today)], total: 1);
      repository.completeDayStatuses(0, {});
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CalendarHandle), const Offset(0, 500));
      await tester.pumpAndSettle();
      await _calendarCommand(tester, 'Выбрать год и месяц');
      await tester.tap(find.text('2028'));
      await tester.pumpAndSettle();
      await _calendarCommand(tester, 'Следующий год');

      await _pushDate(tester, router, selected);
      repository.completeFirst(1, [actionDayItem(2, date: selected)], total: 1);
      repository.completeDayStatuses(1, {});
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CalendarHandle), const Offset(0, 500));
      await tester.pumpAndSettle();
      await _calendarCommand(tester, 'Выбрать год и месяц');
      await tester.drag(find.text('2025'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('2032–2043'), findsOneWidget);
      await _returnHandle(tester);
      expect(find.text('2032–2043'), findsOneWidget);

      await _pushDate(tester, router, selected);
      repository.completeFirst(2, [actionDayItem(3, date: selected)], total: 1);
      repository.completeDayStatuses(2, {});
      await tester.pumpAndSettle();
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
      await tester.drag(find.byType(CalendarHandle), const Offset(0, 500));
      await tester.pumpAndSettle();
      await _calendarCommand(tester, 'Выбрать год и месяц');
      expect(find.text('2020–2031'), findsOneWidget);
      await tester.tap(find.text('2029'));
      await tester.pumpAndSettle();
      await _calendarCommand(tester, 'Следующий год');
      expect(find.text('2030'), findsOneWidget);
      await _returnHandle(tester);
      expect(find.text('2030'), findsOneWidget);
      expect(find.text('7 октября 2026'), findsOneWidget);
      final row = find.byKey(const ValueKey('action-day-row-1'));
      await tester.scrollUntilVisible(
        row,
        100,
        scrollable: find.descendant(
          of: find.byType(CustomScrollView),
          matching: _verticalScroll,
        ),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(actionPanel, findsOneWidget);
      await _back(tester);
      expect(find.text('2030'), findsOneWidget);
      expect(find.text('Январь'), findsOneWidget);

      await _back(tester);
      expect(find.text('2032–2043'), findsOneWidget);
      expect(find.text('Январь'), findsNothing);
      expect(find.text('7 октября 2026'), findsOneWidget);
      await _calendarCommand(tester, 'Вернуться к дням месяца');
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 6));
      expect(dayCell(tester, selected).isSelected, isTrue);
      await _calendarCommand(tester, 'Выбрать год и месяц');
      await tester.tap(find.text('2030'));
      await tester.pumpAndSettle();

      await _back(tester);
      expectActionsRootPage(router);
      expect(find.text('2029'), findsOneWidget);
      expect(find.text('Январь'), findsOneWidget);
      expect(find.text('12 октября 2026'), findsOneWidget);
      expect(repository.queries, hasLength(3));
      expect(repository.dayStatusQueries, hasLength(3));

      await _pushDate(tester, router, selected);
      expect(repository.queries, hasLength(4));
      expect(repository.queries.last.date, selected);
      expect(repository.queries.last.section, ActionDaySection.incomplete);
      expect(repository.queries.last.cursor, isNull);
      repository.completeFirst(3, [actionDayItem(1, date: selected)], total: 1);
      repository.completeDayStatuses(3, {});
      await tester.pumpAndSettle();
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
      expect(dayCell(tester, selected).isSelected, isTrue);
      expect(find.bySemanticsLabel('Развернуть календарь'), findsOneWidget);
      expect(find.text('Невыполненные'), findsOneWidget);
      await _back(tester);
      expect(find.text('2029'), findsOneWidget);
      await _calendarCommand(tester, 'Вернуться к дням месяца');
      expect(dayCell(tester, today).isSelected, isTrue);
      expect(repository.queries, hasLength(4));
      expect(tester.takeException(), isNull);
    },
  );

  for (final (locale, weekday, heading, todayLabel, back) in const [
    (Locale('ru'), 'Среда', '7 октября 2026', 'Сегодня', 'Назад'),
    (Locale('en'), 'Wednesday', '7 October 2026', 'Today', 'Back'),
  ]) {
    testWidgets('экран дня на дату получает только заданный день и не создаёт '
        'корневой экран дня до выбора пункта (${locale.languageCode})', (
      tester,
    ) async {
      final repository = ActionDayRepository();
      final clock = ControlledLocalDate(date(2026, 10, 6));
      final router = await _start(tester, repository, clock, locale: locale);
      final selected = date(2026, 10, 7);

      unawaited(router.push(ActionDayDateRoute(date: selected)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.queries, hasLength(1));
      expect(repository.queries.single.date, selected);
      expect(repository.queries.single.section, ActionDaySection.incomplete);
      repository.completeFirst(0, [actionDayItem(1, date: selected)], total: 1);
      repository.completeDayStatuses(0, {});
      await tester.pumpAndSettle();

      expect(find.byType(ActionDayDatePage), findsOneWidget);
      expect(
        find.widgetWithText(
          AppBar,
          lookupAppLocalizations(locale).appDestinationActions,
        ),
        findsOneWidget,
      );
      expect(find.byType(ActionDayRootPage, skipOffstage: false), findsNothing);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
      expect(dayCell(tester, selected).isSelected, isTrue);
      expect(find.text(weekday, findRichText: true), findsOneWidget);
      expect(find.text(heading), findsOneWidget);
      expect(find.text(todayLabel), findsNothing);
      expect(
        find.text(lookupAppLocalizations(locale).actionDaySectionIncomplete),
        findsOneWidget,
      );
      expect(
        tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
        AppDestination.home,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.today = selected;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(todayLabel), findsOneWidget);
      expect(find.text(heading), findsOneWidget);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
      expect(
        find.text(lookupAppLocalizations(locale).actionDaySectionIncomplete),
        findsOneWidget,
      );
      expect(repository.queries, hasLength(1));
      expect(repository.dayStatusQueries, hasLength(1));

      await tester.tap(find.byTooltip(back));
      await tester.pumpAndSettle();
      expectHomeRootPage(router);
      clock.today = date(2026, 10, 13);
      await openActions(tester);
      expect(repository.queries, hasLength(2));
      expect(repository.queries.last.date, clock.today);
      repository.completeFirst(1, [], total: 0);
      repository.completeDayStatuses(1, {});
      await tester.pumpAndSettle();
      expect(dayCell(tester, clock.today).isSelected, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('после раскрытия жестом два открытия одной даты разделяют '
      'секции, просмотр, отметки и порции; возврат из подробностей сохраняет '
      'прокрутку', (tester) async {
    final repository = ActionDayRepository();
    final selected = date(2026, 10, 7);
    final router = await _start(
      tester,
      repository,
      ControlledLocalDate(date(2026, 10, 12)),
    );
    await _pushDate(tester, router, selected);
    repository.completeFirst(
      0,
      [
        for (var number = 1; number <= 50; number++)
          actionDayItem(number, date: selected, isCompleted: true),
      ],
      total: 51,
      cursor: const ActionDayTestCursor(),
    );
    repository.completeDayStatuses(0, {});
    await tester.pumpAndSettle();

    await showActionDaySection(tester, ActionDaySection.completed);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CalendarHandle), const Offset(0, 500));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Следующий месяц'));
    await tester.pumpAndSettle();
    final marked = date(2026, 11, 7);
    repository.completeDayStatuses(1, {marked: ActionDayStatus.allCompleted});
    await tester.pumpAndSettle();
    expect(dayCell(tester, marked).status, ActionDayStatus.allCompleted);

    await scrollToActionDayEnd(tester, ActionDaySection.completed);
    repository.completeMore(1, [
      actionDayItem(51, date: selected, isCompleted: true),
    ]);
    await tester.pumpAndSettle();
    final row = find.byKey(
      const ValueKey('action-day-row-50'),
      skipOffstage: false,
    );
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    final position = tester.getTopLeft(row).dy;
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(shownActionId(tester), actionDayItem(50, date: selected).id);
    await _back(tester);
    expect(tester.getTopLeft(row).dy, closeTo(position, 1));

    await _pushDate(tester, router, selected);
    expect(repository.queries, hasLength(3));
    expect(repository.queries.last.date, selected);
    expect(repository.queries.last.section, ActionDaySection.incomplete);
    expect(repository.queries.last.cursor, isNull);
    repository.completeFirst(2, [actionDayItem(200, date: selected)], total: 1);
    repository.failDayStatuses(2);
    await tester.pumpAndSettle();
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
    expect(dayCell(tester, selected).isSelected, isTrue);
    expect(find.text('Невыполненные'), findsOneWidget);
    expect(find.text('Отметки дней не загружены.'), findsOneWidget);
    expect(
      actionDaySectionCount(tester, section: ActionDaySection.incomplete),
      '1',
    );

    await _back(tester);
    expect(tester.getTopLeft(row).dy, closeTo(position, 1));
    tester.state<ScrollableState>(_verticalScroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Свернуть календарь'), findsOneWidget);
    expect(dayCell(tester, marked).status, ActionDayStatus.allCompleted);
    expect(find.text('Отметки дней не загружены.'), findsNothing);
    await tester.ensureVisible(
      find.byKey(
        const ValueKey('action-day-section-completed'),
        skipOffstage: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      actionDaySectionCount(tester, section: ActionDaySection.completed),
      '51',
    );
    expect(repository.queries, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'закрытие освобождает экран дня на дату, поздние ответы не меняют '
    'корневой экран дня, повторное открытие начинает с параметров маршрута',
    (tester) async {
      final repository = ActionDayRepository();
      final today = date(2026, 10, 12);
      final selected = date(2026, 10, 7);
      final router = await _start(
        tester,
        repository,
        ControlledLocalDate(today),
      );
      await openActions(tester);
      repository.completeFirst(0, [actionDayItem(1, date: today)], total: 1);
      repository.completeDayStatuses(0, {});
      await tester.pumpAndSettle();
      await showActionDaySection(tester, ActionDaySection.incomplete);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Развернуть календарь'));
      await tester.pumpAndSettle();

      await _pushDate(tester, router, selected);
      await tester.pump(const Duration(seconds: 1));
      await _back(tester);
      repository.completeFirst(1, [
        actionDayItem(2, date: selected, isCompleted: true),
      ], total: 1);
      repository.failDayStatuses(1);
      await tester.pumpAndSettle();
      expectActionsRootPage(router);
      expect(dayCell(tester, today).isSelected, isTrue);
      expect(find.text('Невыполненные'), findsOneWidget);
      expect(find.bySemanticsLabel('Свернуть календарь'), findsOneWidget);
      expect(
        actionDaySectionCount(tester, section: ActionDaySection.incomplete),
        '1',
      );
      expect(find.text('Отметки дней не загружены.'), findsNothing);

      await _pushDate(tester, router, selected);
      expect(repository.queries.last.date, selected);
      expect(repository.queries.last.section, ActionDaySection.incomplete);
      expect(repository.queries.last.cursor, isNull);
      repository.completeFirst(2, [], total: 0);
      repository.completeDayStatuses(2, {});
      await tester.pumpAndSettle();
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
      expect(dayCell(tester, selected).isSelected, isTrue);
      expect(find.text('Невыполненные'), findsNothing);
      expect(find.text('Нет действий на эту дату'), findsOneWidget);
      expect(
        tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
        AppDestination.actions,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

final _verticalScroll = find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

Future<void> _calendarCommand(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
}

Future<void> _returnHandle(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(CalendarHandle)),
  );
  await gesture.moveBy(const Offset(0, -20));
  await gesture.moveBy(
    const Offset(0, -40),
    timeStamp: const Duration(seconds: 1),
  );
  await tester.pump();
  await gesture.up(timeStamp: const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

Future<void> _pushDate(
  WidgetTester tester,
  AppRouter router,
  CalendarDate date,
) async {
  unawaited(router.push(ActionDayDateRoute(date: date)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> _dismissCompletionMessage(WidgetTester tester) async {
  final message = find.byKey(const ValueKey('graph-operation-message'));
  ScaffoldMessenger.of(tester.element(message)).hideCurrentSnackBar();
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar), findsNothing);
}

Future<AppRouter> _start(
  WidgetTester tester,
  ActionDayRepository repository,
  ControlledLocalDate clock, {
  Locale locale = const Locale('ru'),
}) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(
          _PanelOpeningRepository(repository),
        ),
        clock.override,
      ],
      retry: (count, error) => null,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
        builder: (context, child) => GraphOperationPresenter(child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Репозиторий экрана дня, у которого строка может открыть панель действия.
///
/// Выдачу, отметки и команды ведёт [day]. Панель получает отказ чтения: этим
/// сценариям важно, что открыто действие нажатой строки, а не его содержимое.
final class _PanelOpeningRepository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  _PanelOpeningRepository(this.day);

  final ActionDayRepository day;

  @override
  Future<ActionDayPageResult> getActionDayPage(ActionDayQuery query) =>
      day.getActionDayPage(query);

  @override
  Future<ActionDayStatusesReadResult> getActionDayStatuses(
    ActionDayStatusQuery query,
  ) => day.getActionDayStatuses(query);

  @override
  Future<GraphCommandResult<T, F>> execute<
    T extends GraphCommandOutcome,
    F extends GraphCommandFailure
  >(GraphCommand<T, F> command) => day.execute(command);

  @override
  Stream<ActionReadResult> watchAction(ActionId id) =>
      Stream.value(const ActionReadError(ActionReadUnexpectedFailure()));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
