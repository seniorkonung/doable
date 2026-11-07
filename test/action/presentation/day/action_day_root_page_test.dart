import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/application/action_list_item.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_presentation.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/calendar_handle.dart';
import 'package:doable/src/design_system/components/day_heading.dart';
import 'package:doable/src/design_system/components/list_state.dart';
import 'package:doable/src/design_system/components/notice.dart';
import 'package:doable/src/design_system/components/scroll_top_button.dart';
import 'package:doable/src/design_system/components/section_header.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../../support/action_day_controls.dart';
import '../../../support/action_panel_controls.dart';
import '../../../support/app_root_pages.dart';
import '../../../support/controlled_local_date.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import '../../../support/intention_type_counts.dart';
import '../../../support/quick_creation.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import 'action_day_calendar_test_support.dart';
import 'action_day_page_test_support.dart';
import 'action_day_panel_repository.dart';

void main() {
  for (final onDate in [false, true]) {
    testWidgets(
      'флажок ${onDate ? "экрана дня на дату" : "корневого экрана дня"} меняет '
      'только выбранный дубликат и ждёт сохранения и согласования',
      (tester) async {
        final repository = ActionDayRepository();
        final day = date(2026, 10, 4);
        final first = actionDayItem(1, date: day);
        final second = actionDayItem(2, date: day);
        final router = await pumpActionDay(
          tester,
          ActionDayPanelRepository(repository),
          today: day,
          locale: const Locale('ru'),
          size: const Size(390, 1000),
          actionDayDate: onDate ? day : null,
        );
        repository.completeFirst(0, [first, second], total: 2);
        await tester.pumpAndSettle();
        final route = router.current.name;
        final checkbox = find.byKey(
          ValueKey('action-day-completion-${second.id.toCanonicalString()}'),
        );
        expect(checkbox, findsOneWidget);
        final rows = [
          find.byKey(const ValueKey('action-day-section-incomplete')),
          find.byKey(const ValueKey('action-day-row-1')),
          find.byKey(const ValueKey('action-day-row-2')),
          find.byKey(const ValueKey('action-day-section-completed')),
        ];
        final before = [for (final row in rows) tester.getRect(row)];
        await tester.tap(checkbox);
        await tester.pump();
        expect(router.current.name, route);
        expect(repository.completionCommands.single.actionId, second.id);
        expect(
          repository.completionCommands.single.patch.isCompleted,
          isA<ActionFieldSet<bool>>().having(
            (patch) => patch.value,
            'выполнение',
            true,
          ),
        );
        expect(actionCompletionState(tester, checkbox).completed, isFalse);
        expect(actionCompletionState(tester, checkbox).enabled, isFalse);
        expect(find.byType(Notice), findsNothing);
        expect(find.byType(OperationFailurePresentation), findsNothing);
        expect([for (final row in rows) tester.getRect(row)], before);
        expect(
          actionCompletionState(
            tester,
            find.byKey(
              ValueKey('action-day-completion-${first.id.toCanonicalString()}'),
            ),
          ).enabled,
          isTrue,
        );
        await tester.tap(checkbox);
        await tester.pump();
        expect(repository.completionCommands, hasLength(1));
        await tester.drag(calendarPeriodArea, const Offset(-300, 0));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
        expect(repository.queries, hasLength(1));

        repository.confirmCompletion(0, second, isCompleted: true, revision: 1);
        await tester.pump();
        await tester.pump();
        expect(find.byType(Notice), findsNothing);
        expect([for (final row in rows) tester.getRect(row)], before);
        expect(actionCompletionState(tester, checkbox).completed, isFalse);
        expect(actionCompletionState(tester, checkbox).enabled, isFalse);
        repository.completeFirst(
          1,
          [first, actionDayItem(2, date: day, isCompleted: true)],
          total: 2,
          revision: 1,
        );
        await tester.pumpAndSettle();
        expect(actionCompletionState(tester, checkbox).completed, isTrue);
        await tester.tap(checkbox);
        await tester.pump();
        expect(repository.completionCommands.last.actionId, second.id);
        expect(repository.completionCommands, hasLength(2));
        expect(
          repository.completionCommands.last.patch.isCompleted,
          isA<ActionFieldSet<bool>>().having(
            (patch) => patch.value,
            'снятие выполнения',
            false,
          ),
        );
        expect(actionCompletionState(tester, checkbox).completed, isTrue);
        await tester.tap(find.byKey(const ValueKey('action-day-row-2')));
        await tester.pump();
        expect(shownActionId(tester), second.id);
      },
    );
  }

  group('обновление выдачи', () {
    final day = date(2026, 10, 4);
    final open = actionDayItem(1, date: day);
    final done = actionDayItem(2, date: day, isCompleted: true);
    final refreshLine = find.byWidgetPredicate((widget) => widget is ListState);
    const size = Size(390, 1000);

    /// Строка занимает место всегда, поэтому вне обновления она только скрыта:
    /// не принимает нажатий и отсутствует в семантике.
    void expectRefreshLineHidden() {
      expect(refreshLine.hitTestable(), findsNothing);
      expect(find.semantics.byLabel('Обновляем…'), findsNothing);
    }

    /// Объявление читается с самой строки, а не с её текста: при крупном шрифте
    /// видимого слова нет.
    void expectRefreshLineShown(WidgetTester tester) {
      expect(refreshLine.hitTestable(), findsOneWidget);
      expect(
        tester.getSemantics(refreshLine),
        isSemantics(label: 'Обновляем…', isLiveRegion: true),
      );
    }

    /// Положения всего, что не должно сдвигаться при обновлении.
    List<Offset> positions(WidgetTester tester) => [
      for (final finder in [
        find.byType(DayHeading),
        find.byKey(const ValueKey('action-day-section-incomplete')),
        find.byKey(const ValueKey('action-day-section-completed')),
        find.byKey(const ValueKey('action-day-row-1')),
        find.byKey(const ValueKey('action-day-row-2')),
      ])
        tester.getTopLeft(finder),
    ];

    testWidgets('строка обновления стоит на линии заголовка дня, а её '
        'появление и исчезновение не двигают заголовки и карточки', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repository = ActionDayRepository();
      await pumpActionDay(
        tester,
        repository,
        today: day,
        locale: const Locale('ru'),
        size: size,
      );
      repository.completeFirst(0, [open, done], total: 2);
      await tester.pumpAndSettle();
      final before = positions(tester);
      expectRefreshLineHidden();

      await confirmOutsideActionChange(tester, repository, open, revision: 1);

      expectRefreshLineShown(tester);
      expect(positions(tester), before);
      final heading = tester.getRect(find.byType(DayHeading));
      final line = tester.getRect(refreshLine);
      expect(line.right, heading.right);
      expect(line.left, greaterThan(heading.left));
      expect(line.top, greaterThanOrEqualTo(heading.top));
      expect(line.bottom, lessThanOrEqualTo(heading.top + 24));

      repository.completeFirst(1, [open, done], total: 2, revision: 1);
      await tester.pumpAndSettle();
      expectRefreshLineHidden();
      expect(positions(tester), before);
      semantics.dispose();
    });

    testWidgets('при масштабе 200% строка обновления не ложится на текст '
        'заголовка дня, а её появление и исчезновение ничего не двигают', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();
      final repository = ActionDayRepository();
      await pumpActionDay(
        tester,
        repository,
        today: day,
        locale: const Locale('ru'),
        size: const Size(360, 2000),
      );
      repository.completeFirst(0, [open, done], total: 2);
      await tester.pumpAndSettle();
      final before = positions(tester);
      final heading = tester.getSize(find.byType(DayHeading));
      expectRefreshLineHidden();

      await confirmOutsideActionChange(tester, repository, open, revision: 1);

      expectRefreshLineShown(tester);
      expect(positions(tester), before);
      expect(tester.getSize(find.byType(DayHeading)), heading);
      final line = tester.getRect(refreshLine);
      for (final text in [
        find.textContaining('Воскресенье'),
        find.text('4 октября 2026'),
      ]) {
        expect(line.overlaps(tester.getRect(text)), isFalse);
      }

      repository.completeFirst(1, [open, done], total: 2, revision: 1);
      await tester.pumpAndSettle();
      expectRefreshLineHidden();
      expect(positions(tester), before);
      expect(tester.getSize(find.byType(DayHeading)), heading);
      semantics.dispose();
    });

    testWidgets('обновление после записи выполнения не двигает заголовки и '
        'карточки', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ActionDayRepository();
      await pumpActionDay(
        tester,
        repository,
        today: day,
        locale: const Locale('ru'),
        size: size,
      );
      repository.completeFirst(0, [open, done], total: 2);
      await tester.pumpAndSettle();
      // Запись идёт от последней карточки: всё, что могло бы сдвинуться,
      // стоит выше неё.
      await tester.tap(
        find.byKey(
          ValueKey('action-day-completion-${done.id.toCanonicalString()}'),
        ),
      );
      await tester.pump();
      final before = positions(tester);
      expectRefreshLineHidden();

      repository.confirmCompletion(0, done, isCompleted: false, revision: 1);
      await tester.pump();
      await tester.pump();

      expectRefreshLineShown(tester);
      expect(positions(tester), before);
      semantics.dispose();
    });

    testWidgets('устаревшая выдача показывает Notice с повтором только при '
        'доказанно временном отказе и сохраняет карточки', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ActionDayRepository();
      await pumpActionDay(
        tester,
        repository,
        today: day,
        locale: const Locale('ru'),
        size: size,
      );
      repository.completeFirst(0, [open, done], total: 2);
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('ru'));

      await confirmOutsideActionChange(tester, repository, open, revision: 1);
      repository.failUnavailable(1);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Notice),
          matching: find.text(l10n.actionDayUnavailable),
        ),
        findsOneWidget,
      );
      expectRefreshLineHidden();
      expect(find.byKey(const ValueKey('action-day-row-2')), findsOneWidget);

      await tester.tap(find.text(l10n.commonRetry));
      await tester.pump();
      expect(find.byType(Notice), findsNothing);
      expectRefreshLineShown(tester);

      repository.fail(2, const ActionDayCorruptionFailure());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Notice),
          matching: find.text(l10n.actionDayCorruption),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.commonRetry), findsNothing);
      semantics.dispose();
    });
  });

  for (final locale in const [Locale('ru'), Locale('en')]) {
    testWidgets('отказ флажка локализован, временный допускает повтор, '
        'а конфликт требует актуализации (${locale.languageCode})', (
      tester,
    ) async {
      final repository = ActionDayRepository();
      final day = date(2026, 10, 4);
      final item = actionDayItem(1, date: day);
      await pumpActionDay(
        tester,
        repository,
        today: day,
        locale: locale,
        size: const Size(390, 1000),
      );
      repository.completeFirst(0, [item], total: 1);
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(locale);
      final checkbox = actionCompletionControl;
      await tester.tap(checkbox);
      await tester.pump();
      repository.failCompletion(0, const ActionUnavailableFailure());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Notice),
          matching: find.text(l10n.actionOperationUnavailable),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OperationFailurePresentation>(
              find.byType(OperationFailurePresentation),
            )
            .claim,
        isNotNull,
      );
      expect(actionCompletionState(tester, checkbox).completed, isFalse);
      expect(actionCompletionNoticeAction(l10n.commonRetry), findsOne);
      expect(actionCompletionNoticeAction(l10n.actionRefresh), findsNothing);
      await tester.tap(actionCompletionNoticeAction(l10n.commonRetry));
      await tester.pump();
      expect(find.byType(Notice), findsNothing);
      expect(repository.completionCommands, hasLength(2));
      repository.failCompletion(1, const ActionConflictFailure());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Notice),
          matching: find.text(l10n.actionOperationConflict),
        ),
        findsOneWidget,
      );
      expect(actionCompletionNoticeAction(l10n.commonRetry), findsNothing);
      expect(actionCompletionNoticeAction(l10n.actionRefresh), findsOne);
      expect(actionCompletionState(tester, checkbox).enabled, isFalse);
      await tester.tap(actionCompletionNoticeAction(l10n.actionRefresh));
      await tester.pump();
      repository.completeFirst(1, [item], total: 1);
      await tester.pumpAndSettle();
      expect(find.byType(Notice), findsNothing);
      expect(find.text(l10n.actionOperationConflict), findsNothing);
      expect(actionCompletionState(tester, checkbox).enabled, isTrue);
      expect(repository.completionCommands, hasLength(2));
    });

    testWidgets('актуализация после неизвестного отказа возвращает флажок '
        'корневого экрана дня без повтора отклонённого изменения '
        '(${locale.languageCode})', (tester) async {
      final repository = ActionDayRepository();
      final day = date(2026, 10, 4);
      final item = actionDayItem(1, date: day);
      await pumpActionDay(
        tester,
        repository,
        today: day,
        locale: locale,
        size: const Size(390, 1000),
      );
      repository.completeFirst(0, [item], total: 1);
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(locale);
      final checkbox = actionCompletionControl;
      await tester.tap(checkbox);
      await tester.pump();
      repository.failCompletion(0, const ActionUnexpectedFailure());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Notice),
          matching: find.text(l10n.actionOperationUnexpected),
        ),
        findsOneWidget,
      );
      expect(actionCompletionNoticeAction(l10n.commonRetry), findsNothing);
      expect(actionCompletionState(tester, checkbox).enabled, isFalse);

      await tester.tap(actionCompletionNoticeAction(l10n.actionRefresh));
      await tester.pump();
      expect(repository.completionCommands, hasLength(1));
      repository.completeFirst(1, [item], total: 1);
      await tester.pumpAndSettle();
      expect(find.text(l10n.actionOperationUnexpected), findsNothing);
      expect(actionCompletionState(tester, checkbox).completed, isFalse);
      expect(actionCompletionState(tester, checkbox).enabled, isTrue);

      await tester.tap(checkbox);
      await tester.pump();
      expect(repository.completionCommands, hasLength(2));
      expect(
        repository.completionCommands.last.patch.isCompleted,
        isA<ActionFieldSet<bool>>().having(
          (patch) => patch.value,
          'выполнение',
          true,
        ),
      );
    });
  }

  testWidgets('корневой экран дня оставляет над календарём только безопасный '
      'отступ и меняет строку состояния вместе с темой', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final repository = _Repository();
    await _open(tester, repository, size: const Size(390, 844));
    repository.completeFirst([], total: 0);
    await tester.pumpAndSettle();

    final calendar = find.byType(ActionDayCalendar);
    expect(tester.getTopLeft(calendar).dy, greaterThanOrEqualTo(24));
    expect(tester.getTopLeft(calendar).dy, lessThan(24 + kToolbarHeight));
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
    expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.light);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
    expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.dark);
    expect(tester.getTopLeft(calendar).dy, greaterThanOrEqualTo(24));
    expect(repository.queries, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final locale in const [Locale('ru'), Locale('en')]) {
    testWidgets('экран дня без плавающей кнопки запускает создание намерения '
        'через общую панель на языке ${locale.languageCode}', (tester) async {
      final repository = _Repository();
      final router = await _open(tester, repository, locale: locale);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FloatingActionButton), findsNothing);
      repository.completeFirst([], total: 0);
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      final semantics = tester.ensureSemantics();
      final l10n = lookupAppLocalizations(locale);
      await openQuickCreation(
        tester,
        QuickCreationMode.intention,
        openedPage: find.byType(IntentionEditorPage),
      );
      expect(router.current.name, IntentionEditorRoute.name);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expectActionsRootPage(router);
      expect(repository.queries, hasLength(1));
      expect(quickCreationAction().hitTestable(), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '${l10n.quickCreationLabel}, ${QuickCreationMode.intention.title(l10n)}',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  }

  testWidgets('показывает все записи и открывает дубликат по id', (
    tester,
  ) async {
    final repository = _Repository();
    await _open(tester, repository);
    expect(find.text('Загружаем действия…'), findsOneWidget);
    repository.completeFirst([_item(1), _item(2)], total: 2);
    await tester.pumpAndSettle();
    expect(
      actionDaySectionCount(tester, section: ActionDaySection.incomplete),
      '2',
    );
    expect(find.text('Действие'), findsNWidgets(2));
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const ValueKey('action-day-row-2'))).label,
      contains('№ 2'),
    );
    await tester.tap(find.byKey(const ValueKey('action-day-row-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(shownActionId(tester), _id(2));
    semantics.dispose();
  });

  testWidgets(
    'секции независимо раскрываются без чтения и не изображают пустой день',
    (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      repository.completeFirst([_item(1)], total: 1);
      await tester.pumpAndSettle();
      final incomplete = find.byKey(
        const ValueKey('action-day-section-incomplete'),
      );
      final completed = find.byKey(
        const ValueKey('action-day-section-completed'),
      );
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(incomplete).flagsCollection.isExpanded,
        Tristate.isTrue,
      );
      expect(
        tester.getSemantics(completed).flagsCollection.isExpanded,
        Tristate.isTrue,
      );
      expect(find.text('Действие'), findsOneWidget);
      await tester.tap(incomplete);
      await tester.tap(completed);
      await tester.pumpAndSettle();
      expect(find.text('Действие'), findsNothing);
      expect(find.text('Нет действий на эту дату'), findsNothing);
      expect(repository.queries, hasLength(1));
      expect(
        tester.getSemantics(incomplete).flagsCollection.isExpanded,
        Tristate.isFalse,
      );
      expect(
        tester.getSemantics(completed).flagsCollection.isExpanded,
        Tristate.isFalse,
      );
      final next = date(2026, 9, 25);
      await tester.tap(calendarDay(next));
      await tester.pump();
      repository.completeFirst([_item(2, date: next)], index: 1, total: 1);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(incomplete).flagsCollection.isExpanded,
        Tristate.isFalse,
      );
      expect(
        tester.getSemantics(completed).flagsCollection.isExpanded,
        Tristate.isFalse,
      );
      expect(find.text('Действие'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('подгрузка невыполненных не мешает подгрузке выполненных', (
    tester,
  ) async {
    final repository = _Repository(
      completedItems: [_item(3, completed: true)],
      completedTotal: 2,
      completedCursor: const ActionDayTestCursor(),
    );
    await _open(tester, repository);
    repository.completeFirst(
      [_item(1)],
      total: 2,
      cursor: const ActionDayTestCursor(),
    );
    await _settleCalendar(tester);
    expect(find.text('Действие'), findsNWidgets(2));
    expect(
      actionDayPageFooter(section: ActionDaySection.incomplete),
      findsOneWidget,
    );
    expect(
      actionDayPageFooter(section: ActionDaySection.completed),
      findsOneWidget,
    );
    repository.completeMore(2, [_item(4, completed: true)]);
    repository.completeMore(1, [_item(2)]);
    await tester.pumpAndSettle();
    expect(find.text('Действие'), findsNWidgets(4));
    expect(
      actionDaySectionCount(tester, section: ActionDaySection.incomplete),
      '2',
    );
    expect(
      actionDaySectionCount(tester, section: ActionDaySection.completed),
      '2',
    );
  });

  group('подгрузка порции секции', () {
    const size = Size(360, 780);
    final day = date(2026, 10, 4);
    final rows = [
      for (var number = 1; number <= 20; number++)
        actionDayItem(number, date: day),
    ];

    testWidgets('конец загруженной части сам запрашивает одну порцию, и она '
        'встаёт перед выполненными, а далёкий конец порцию не запрашивает', (
      tester,
    ) async {
      final repository = ActionDayRepository();
      await pumpActionDay(
        tester,
        repository,
        today: day,
        locale: const Locale('ru'),
        size: size,
      );
      repository.completeFirst(
        0,
        [...rows, actionDayItem(101, date: day, isCompleted: true)],
        total: 22,
        cursor: const ActionDayTestCursor(),
      );
      await tester.pumpAndSettle();
      expect(repository.queries, hasLength(1));

      await scrollToActionDayEnd(tester, ActionDaySection.incomplete);
      expect(repository.queries, hasLength(2));
      expect(repository.queries[1].date, day);
      expect(repository.queries[1].section, ActionDaySection.incomplete);
      expect(repository.queries[1].cursor, isA<ActionDayTestCursor>());

      repository.completeMore(1, [actionDayItem(21, date: day)]);
      await tester.pumpAndSettle();
      expect(repository.queries, hasLength(2));
      await tester.ensureVisible(
        find.byKey(
          const ValueKey('action-day-section-completed'),
          skipOffstage: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('action-day-row-21'))).bottom,
        lessThan(
          tester
              .getRect(
                find.byKey(const ValueKey('action-day-section-completed')),
              )
              .top,
        ),
      );
    });

    testWidgets('при неактуальной выдаче подвал порцию не запрашивает, а на '
        'виду запрашивает её, когда выдача снова актуальна', (tester) async {
      final repository = ActionDayRepository();
      await pumpActionDay(
        tester,
        repository,
        today: day,
        locale: const Locale('ru'),
        size: size,
      );
      repository.completeFirst(
        0,
        rows,
        total: 21,
        cursor: const ActionDayTestCursor(),
      );
      await tester.pumpAndSettle();

      await confirmOutsideActionChange(
        tester,
        repository,
        rows.first,
        revision: 1,
      );
      expect(repository.queries, hasLength(2));
      await scrollToActionDayEnd(tester, ActionDaySection.incomplete);
      expect(repository.queries, hasLength(2));

      repository.completeFirst(
        1,
        rows,
        total: 21,
        cursor: const ActionDayTestCursor(),
        revision: 1,
      );
      await tester.pump();
      await tester.pump();
      expect(repository.queries, hasLength(3));
      expect(repository.queries[2].cursor, isA<ActionDayTestCursor>());
    });

    testWidgets('устаревшая выдача показывает в подвале отказ вместо кольца, '
        'а повтор предлагает только при доказанно временном отказе', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repository = ActionDayRepository();
      await pumpActionDay(
        tester,
        repository,
        today: day,
        locale: const Locale('ru'),
        size: size,
      );
      repository.completeFirst(
        0,
        rows,
        total: 21,
        cursor: const ActionDayTestCursor(),
      );
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('ru'));
      final footer = actionDayPageFooter(section: ActionDaySection.incomplete);
      Finder inFooter(Finder finder) =>
          find.descendant(of: footer, matching: finder);
      // Подвал строится за краем выдачи, а проверки читают видимый.
      Future<void> showFooter() async {
        await scrollToActionDayEnd(tester, ActionDaySection.incomplete);
        await tester.ensureVisible(
          actionDayPageFooter(
            section: ActionDaySection.incomplete,
            skipOffstage: false,
          ),
        );
        await tester.pump();
      }

      final ring = inFooter(find.bySemanticsLabel(l10n.actionDayLoadingMore));

      // На время обновления подвал показывает кольцо.
      await confirmOutsideActionChange(
        tester,
        repository,
        rows.first,
        revision: 1,
      );
      await showFooter();
      expect(ring, findsOneWidget);

      repository.failUnavailable(1);
      await tester.pumpAndSettle();
      await showFooter();
      expect(ring, findsNothing);
      expect(inFooter(find.text(l10n.actionDayUnavailable)), findsOneWidget);
      expect(inFooter(find.text(l10n.commonRetry)), findsOneWidget);
      expect(repository.queries, hasLength(2));

      await tester.tap(inFooter(find.text(l10n.commonRetry)));
      await tester.pump();
      expect(repository.queries, hasLength(3));
      await showFooter();
      expect(ring, findsOneWidget);

      repository.fail(2, const ActionDayCorruptionFailure());
      await tester.pumpAndSettle();
      await showFooter();
      expect(ring, findsNothing);
      expect(inFooter(find.text(l10n.actionDayCorruption)), findsOneWidget);
      expect(inFooter(find.text(l10n.commonRetry)), findsNothing);
      semantics.dispose();
    });
  });

  group('возврат к началу выдачи', () {
    const size = Size(360, 780);
    final day = date(2026, 10, 4);
    final rows = [
      for (var number = 1; number <= 30; number++)
        actionDayItem(number, date: day),
    ];
    final button = find.byType(ScrollTopButton);

    Future<ScrollPosition> openLongDay(
      WidgetTester tester,
      ActionDayRepository repository, {
      bool onDate = false,
    }) async {
      await pumpActionDay(
        tester,
        repository,
        today: day,
        locale: const Locale('ru'),
        size: size,
        actionDayDate: onDate ? day : null,
      );
      repository.completeFirst(0, rows, total: rows.length);
      await tester.pumpAndSettle();
      return tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            ),
          )
          .position;
    }

    Future<void> scrollPastViewport(
      WidgetTester tester,
      ScrollPosition position,
    ) async {
      position.jumpTo(position.viewportDimension + 1);
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);
    }

    for (final onDate in [false, true]) {
      final screen = onDate ? 'экран дня на дату' : 'корневой экран дня';

      testWidgets('$screen показывает кнопку за высотой видимой области на '
          'месте из макета, а нажатие плавно возвращает к заголовку дня и '
          'сохраняет дату и секции', (tester) async {
        final position = await openLongDay(
          tester,
          ActionDayRepository(),
          onDate: onDate,
        );
        expect(button, findsNothing);

        position.jumpTo(position.viewportDimension);
        await tester.pumpAndSettle();
        expect(button, findsNothing);

        await scrollPastViewport(tester, position);
        final rect = tester.getRect(button);
        expect(rect.right, size.width - 20);
        expect(
          rect.bottom,
          tester.getRect(find.byType(AppNavigationBar)).top - 12,
        );
        final start = position.pixels;

        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(position.pixels, inExclusiveRange(0, start));

        await tester.pumpAndSettle();
        expect(position.pixels, 0);
        expect(find.byType(DayHeading), findsOneWidget);
        expect(button, findsNothing);
        expect(shownActionDayDate(tester), day);
        expect(
          tester
              .widget<SectionHeader>(
                find.byKey(const ValueKey('action-day-section-incomplete')),
              )
              .open,
          isTrue,
        );
        expect(find.byKey(const ValueKey('action-day-row-1')), findsOneWidget);
      });

      testWidgets('$screen ставит показанное сообщение над кнопкой', (
        tester,
      ) async {
        final position = await openLongDay(
          tester,
          ActionDayRepository(),
          onDate: onDate,
        );
        await scrollPastViewport(tester, position);
        final rect = tester.getRect(button);

        ScaffoldMessenger.of(tester.element(button))
            .showSnackBar(const SnackBar(content: Text('Сообщение')));
        await tester.pumpAndSettle();

        expect(tester.getRect(button), rect);
        expect(
          tester.getRect(find.byType(SnackBar)).bottom,
          lessThanOrEqualTo(rect.top),
        );
      });
    }

    testWidgets('при уменьшении движения нажатие возвращает к началу сразу', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final position = await openLongDay(tester, ActionDayRepository());
      await scrollPastViewport(tester, position);

      await tester.tap(button);
      await tester.pump();

      expect(position.pixels, 0);
    });

    testWidgets('смена дня убирает кнопку', (tester) async {
      final repository = ActionDayRepository();
      final position = await openLongDay(tester, repository);
      await scrollPastViewport(tester, position);

      await selectActionDayDate(tester, date(2026, 10, 5));
      repository.completeFirst(1, rows, total: rows.length);
      await tester.pumpAndSettle();

      expect(position.pixels, 0);
      expect(button, findsNothing);
    });

    testWidgets('изменение высоты видимой области без прокрутки сдвигает '
        'границу показа кнопки', (tester) async {
      final position = await openLongDay(tester, ActionDayRepository());
      position.jumpTo(position.viewportDimension);
      await tester.pumpAndSettle();
      expect(button, findsNothing);

      await tester.tap(find.byType(CalendarHandle));
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);

      await tester.tap(find.byType(CalendarHandle));
      await tester.pumpAndSettle();
      expect(button, findsNothing);
    });

    testWidgets('конец перехода календаря не отменяет возврат к началу', (
      tester,
    ) async {
      final position = await openLongDay(tester, ActionDayRepository());
      await scrollPastViewport(tester, position);

      final hold = await tester.startGesture(
        tester.getCenter(find.byType(CalendarHandle)),
      );
      await hold.moveBy(const Offset(0, 20));
      await hold.moveBy(
        const Offset(0, 20),
        timeStamp: const Duration(seconds: 1),
      );
      await tester.pump();
      await tester.tap(button);
      await hold.up(timeStamp: const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(position.pixels, 0);
      expect(button, findsNothing);
    });
  });

  group('встроенный календарь', () {
    testWidgets('первое открытие выбирает сегодня в свёрнутой неделе и читает '
        'только этот день вместо ручного ввода даты', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);

      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 21), 1));
      expect(find.text(_selectedDateLabel(tester, _today)), findsOneWidget);
      final query = repository.queries.single;
      expect(query.date, _today);
      expect(query.section, ActionDaySection.incomplete);
      expect(query.cursor, isNull);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets(
      'календарь стоит первым в общей прокрутке над секциями и выдачей',
      (tester) async {
        final repository = _Repository();
        await _open(tester, repository);
        repository.completeFirst([_item(1)], total: 1);
        await tester.pumpAndSettle();

        final calendarBottom = tester
            .getRect(find.byType(ActionDayCalendar))
            .bottom;
        for (final key in [..._filterKeys, 'action-day-row-1']) {
          expect(
            tester.getRect(find.byKey(ValueKey(key))).top,
            greaterThanOrEqualTo(calendarBottom),
            reason: key,
          );
        }
      },
    );

    testWidgets('нажатие другого дня недели синхронно начинает пару первых '
        'порций с прежним раскрытием и не показывает выдачу прежнего дня', (
      tester,
    ) async {
      final repository = _Repository();
      await _open(tester, repository);
      repository.completeFirst(
        [_item(1)],
        total: 2,
        cursor: const ActionDayTestCursor(),
      );
      await _settleCalendar(tester);
      repository.completeMore(1, [_item(2)]);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('action-day-section-completed')),
      );
      await tester.pumpAndSettle();

      final nextDay = date(2026, 9, 25);
      await tester.tap(calendarDay(nextDay));

      // Выбор применён до следующего кадра.
      expect(repository.queries, hasLength(3));
      final query = repository.queries[2];
      expect(query.date, nextDay);
      expect(query.section, ActionDaySection.incomplete);
      expect(query.cursor, isNull);

      await tester.pump();
      _expectSelected(tester, nextDay);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 21), 1));
      expect(find.text('Загружаем действия…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('action-day-section-incomplete')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('action-day-row-1')), findsNothing);
      expect(
        actionDayPageFooter(section: ActionDaySection.incomplete),
        findsNothing,
      );

      repository.completeFirst([_item(3, date: nextDay)], index: 2, total: 1);
      await tester.pumpAndSettle();
      expect(
        actionDaySectionCount(tester, section: ActionDaySection.incomplete),
        '1',
      );
      expect(find.byKey(const ValueKey('action-day-row-1')), findsOneWidget);
      expect(repository.queries, hasLength(3));
    });

    testWidgets('в раскрытом месяце день выбирается после просмотра '
        'соседнего месяца, а календарь остаётся раскрытым', (tester) async {
      final selectedDay = date(2026, 10, 15);
      final repository = _Repository();
      await _open(tester, repository);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      repository.completeFirst([], total: 0);
      await tester.pumpAndSettle();

      await _tapCalendarCommand(tester, l10n.actionCalendarExpand);
      expect(
        find.bySemanticsLabel(l10n.actionCalendarCollapse),
        findsOneWidget,
      );
      await _tapCalendarCommand(tester, l10n.actionCalendarNextMonth);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 6));
      // Выбранный день вне просматриваемого месяца остаётся названным.
      expect(find.text(_selectedDateLabel(tester, _today)), findsOneWidget);
      expect(repository.queries, hasLength(1));

      await tester.tap(calendarDay(selectedDay));
      expect(repository.queries, hasLength(2));
      expect(repository.queries[1].date, selectedDay);
      expect(repository.queries[1].section, ActionDaySection.incomplete);

      await _settleCalendar(tester);
      _expectSelected(tester, selectedDay);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 6));
      expect(
        find.bySemanticsLabel(l10n.actionCalendarCollapse),
        findsOneWidget,
      );
      expect(
        find.text(_selectedDateLabel(tester, selectedDay)),
        findsOneWidget,
      );
      expect(repository.queries, hasLength(2));
    });

    testWidgets('перелистывание, раскрытие и сворачивание меняют только '
        'просмотр, не прерывая чтение и сохраняя выдачу', (tester) async {
      final today = date(2026, 10, 4);
      final repository = _Repository();
      await _open(tester, repository, today: today);
      final l10n = lookupAppLocalizations(const Locale('ru'));

      // Первое чтение ещё не завершено: просмотр его не отменяет и не
      // повторяет.
      await _swipeCalendar(tester, toNext: true);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
      await _swipeCalendar(tester, toNext: true);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 12), 1));
      await _swipeCalendar(tester, toNext: false);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
      expect(find.text('Загружаем действия…'), findsOneWidget);
      expect(repository.queries, hasLength(1));

      repository.completeFirst([
        _item(1, date: today),
        _item(2, date: today),
      ], total: 2);
      await tester.pumpAndSettle();
      final count = find.byKey(const ValueKey('action-day-section-incomplete'));
      expect(
        actionDaySectionCount(tester, section: ActionDaySection.incomplete),
        '2',
      );

      // Неделя с датой просмотра в ноябре раскрывается в ноябрь, сдвигая
      // выдачу вниз.
      await _swipeCalendar(tester, toNext: true);
      await _swipeCalendar(tester, toNext: true);
      await _swipeCalendar(tester, toNext: true);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 1));
      final weekCountTop = tester.getRect(count).top;
      await _tapCalendarCommand(tester, l10n.actionCalendarExpand);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      expect(tester.getRect(count).top, greaterThan(weekCountTop));

      await _swipeCalendar(tester, toNext: true);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 30), 6));
      await _tapCalendarCommand(tester, l10n.actionCalendarPreviousMonth);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      await _tapCalendarCommand(tester, l10n.actionCalendarCollapse);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 1));
      expect(tester.getRect(count).top, moreOrLessEquals(weekCountTop));

      // Свёрнутая неделя показывает точную дату просмотра из середины месяца.
      await _swipeCalendar(tester, toNext: true);
      await _swipeCalendar(tester, toNext: true);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 9), 1));
      await _tapCalendarCommand(tester, l10n.actionCalendarExpand);
      await _tapCalendarCommand(tester, l10n.actionCalendarCollapse);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 9), 1));

      expect(repository.queries, hasLength(1));
      _expectSelected(tester, today);
      expect(count, findsOneWidget);
      expect(find.byKey(const ValueKey('action-day-row-2')), findsOneWidget);
    });

    testWidgets('стрелки месяца возвращают неделю выбранного дня, сохраняя '
        'секции и выдачу без чтения', (tester) async {
      final selected = date(2026, 10, 15);
      final repository = _Repository();
      await _open(tester, repository, today: selected);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      repository.completeFirst([_item(1, date: selected)], total: 1);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('action-day-section-completed')),
      );
      await tester.pumpAndSettle();

      await _tapCalendarCommand(tester, l10n.actionCalendarExpand);
      await _tapCalendarCommand(tester, l10n.actionCalendarNextMonth);
      await _tapCalendarCommand(tester, l10n.actionCalendarPreviousMonth);
      await _tapCalendarCommand(tester, l10n.actionCalendarCollapse);

      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 12), 1));
      expect(dayCell(tester, selected).isSelected, isTrue);
      _expectSelected(tester, selected);
      expect(find.text('Невыполненные'), findsOneWidget);
      expect(
        actionDaySectionCount(tester, section: ActionDaySection.incomplete),
        '1',
      );
      expect(find.byKey(const ValueKey('action-day-row-1')), findsOneWidget);
      expect(repository.queries, hasLength(1));
      expect(repository.queries.last.date, selected);
      expect(repository.queries.last.section, ActionDaySection.incomplete);
    });

    testWidgets('повторное нажатие выбранного дня возвращает к нему просмотр '
        'без чтения', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      repository.completeFirst([_item(1)], total: 1);
      await tester.pumpAndSettle();

      await _tapCalendarCommand(tester, l10n.actionCalendarExpand);
      await _tapCalendarCommand(tester, l10n.actionCalendarNextMonth);
      await _tapCalendarCommand(tester, l10n.actionCalendarPreviousMonth);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 8, 31), 6));

      await tester.tap(calendarDay(_today));
      await _settleCalendar(tester);
      _expectSelected(tester, _today);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 8, 31), 6));
      await _tapCalendarCommand(tester, l10n.actionCalendarCollapse);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 21), 1));

      expect(repository.queries, hasLength(1));
      expect(
        actionDaySectionCount(tester, section: ActionDaySection.incomplete),
        '1',
      );
      expect(find.byKey(const ValueKey('action-day-row-1')), findsOneWidget);
    });

    testWidgets('при отказе выбранный день сохраняется, его повторное '
        'нажатие не заменяет повтор, а другой день выбирается', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      final futureDay = date(2026, 9, 26);
      await tester.tap(calendarDay(futureDay));
      await tester.pump();
      repository.failFirst(index: 1);
      await tester.pumpAndSettle();
      expect(find.text(l10n.actionDayUnavailable), findsOneWidget);
      expect(
        find.byKey(const ValueKey('action-day-section-incomplete')),
        findsNothing,
      );
      _expectSelected(tester, futureDay);

      await tester.tap(calendarDay(futureDay));
      await tester.pump();
      expect(repository.queries, hasLength(2));
      expect(find.text(l10n.actionDayUnavailable), findsOneWidget);

      await tester.tap(find.text(l10n.commonRetry));
      await tester.pump();
      expect(repository.queries, hasLength(3));
      expect(repository.queries[2].date, futureDay);
      expect(repository.queries[2].cursor, isNull);
      repository.failFirst(index: 2);
      await tester.pumpAndSettle();
      _expectSelected(tester, futureDay);

      final otherDay = date(2026, 9, 27);
      await tester.tap(calendarDay(otherDay));
      expect(repository.queries, hasLength(4));
      expect(repository.queries[3].date, otherDay);
      await tester.pump();
      _expectSelected(tester, otherDay);
      expect(find.text(l10n.actionDayUnavailable), findsNothing);
    });

    testWidgets('поздний ответ за 2026-10-05 не возвращает его выдачу после '
        'выбора 2026-10-06', (tester) async {
      final repository = _Repository();
      await _open(tester, repository, today: date(2026, 10, 7));
      final l10n = lookupAppLocalizations(const Locale('ru'));
      final firstDay = date(2026, 10, 5);
      final secondDay = date(2026, 10, 6);
      await tester.tap(calendarDay(firstDay));
      await tester.pump();
      await tester.tap(calendarDay(secondDay));
      await tester.pump();
      expect(repository.queries.map((query) => query.date), [
        date(2026, 10, 7),
        firstDay,
        secondDay,
      ]);

      repository.completeFirst([_item(3, date: secondDay)], index: 2, total: 1);
      await tester.pumpAndSettle();
      repository.completeFirst(
        [_item(1, date: firstDay), _item(2, date: firstDay)],
        index: 1,
        total: 3,
        cursor: const ActionDayTestCursor(),
      );
      repository.failFirst();
      await tester.pumpAndSettle();

      _expectSelected(tester, secondDay);
      expect(
        actionDaySectionCount(tester, section: ActionDaySection.incomplete),
        '1',
      );
      expect(find.byKey(const ValueKey('action-day-row-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('action-day-row-2')), findsNothing);
      expect(
        actionDayPageFooter(section: ActionDaySection.incomplete),
        findsNothing,
      );
      expect(find.text(l10n.actionDayUnavailable), findsNothing);
      expect(repository.queries, hasLength(3));
    });

    testWidgets('просмотр календаря до завершения первой порции и подгрузки '
        'выбранного дня не отменяет и не повторяет их', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      repository.completeFirst([], total: 0);
      await tester.pumpAndSettle();
      final selectedDay = date(2026, 9, 25);
      await tester.tap(calendarDay(selectedDay));
      await tester.pump();
      expect(repository.queries, hasLength(2));

      // Первая порция выбранного дня ещё читается.
      await _swipeCalendar(tester, toNext: true);
      await _tapCalendarCommand(tester, l10n.actionCalendarExpand);
      await _swipeCalendar(tester, toNext: true);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      expect(find.text(l10n.actionDayLoading), findsOneWidget);
      expect(repository.queries, hasLength(2));
      repository.completeFirst(
        [_item(1, date: selectedDay)],
        index: 1,
        total: 2,
        cursor: const ActionDayTestCursor(),
      );
      await _settleCalendar(tester);
      expect(
        actionDaySectionCount(tester, section: ActionDaySection.incomplete),
        '2',
      );
      expect(find.byKey(const ValueKey('action-day-row-1')), findsOneWidget);

      // Подгрузка выбранного дня ещё читается.
      expect(repository.queries, hasLength(3));
      expect(repository.queries[2].date, selectedDay);
      expect(repository.queries[2].cursor, isA<ActionDayTestCursor>());
      await _tapCalendarCommand(tester, l10n.actionCalendarPreviousMonth);
      await _tapCalendarCommand(tester, l10n.actionCalendarCollapse);
      await _swipeCalendar(tester, toNext: false);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 21), 1));
      expect(
        actionDayPageFooter(section: ActionDaySection.incomplete),
        findsOneWidget,
      );
      expect(repository.queries, hasLength(3));
      repository.completeMore(2, [_item(2, date: selectedDay)]);
      await _settleCalendar(tester);

      expect(find.byKey(const ValueKey('action-day-row-2')), findsOneWidget);
      expect(
        actionDayPageFooter(section: ActionDaySection.incomplete),
        findsNothing,
      );
      _expectSelected(tester, selectedDay);
      expect(repository.queries, hasLength(3));
    });

    testWidgets('повреждение и неизвестный отказ объясняются без повтора, '
        'временный отказ подгрузки повторяется для выбранного дня, а другой '
        'день выбирается из каждого отказа', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      final retry = find.text(l10n.commonRetry);

      repository.fail(0, const ActionDayCorruptionFailure());
      await tester.pumpAndSettle();
      expect(find.text(l10n.actionDayCorruption), findsOneWidget);
      expect(retry, findsNothing);

      final secondDay = date(2026, 9, 25);
      await tester.tap(calendarDay(secondDay));
      expect(repository.queries, hasLength(2));
      expect(repository.queries[1].date, secondDay);
      expect(repository.queries[1].cursor, isNull);
      repository.completeFirst(
        [_item(1, date: secondDay)],
        index: 1,
        total: 2,
        cursor: const ActionDayTestCursor(),
      );
      await _settleCalendar(tester);
      repository.fail(2, const ActionDayUnexpectedFailure());
      await tester.pumpAndSettle();
      expect(find.text(l10n.actionDayUnexpected), findsOneWidget);
      expect(retry, findsNothing);
      expect(find.byKey(const ValueKey('action-day-row-1')), findsOneWidget);

      final thirdDay = date(2026, 9, 26);
      await tester.tap(calendarDay(thirdDay));
      expect(repository.queries, hasLength(4));
      expect(repository.queries[3].date, thirdDay);
      expect(repository.queries[3].cursor, isNull);
      repository.completeFirst(
        [_item(2, date: thirdDay)],
        index: 3,
        total: 2,
        cursor: const ActionDayTestCursor(),
      );
      await _settleCalendar(tester);
      expect(find.text(l10n.actionDayUnexpected), findsNothing);
      repository.failFirst(index: 4);
      await tester.pumpAndSettle();
      expect(find.text(l10n.actionDayUnavailable), findsOneWidget);

      await tester.tap(retry);
      await tester.pump();
      expect(repository.queries, hasLength(6));
      expect(repository.queries[5].date, thirdDay);
      expect(repository.queries[5].section, ActionDaySection.incomplete);
      expect(repository.queries[5].cursor, isA<ActionDayTestCursor>());
      repository.completeMore(5, [_item(3, date: thirdDay)]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('action-day-row-2')), findsOneWidget);
      _expectSelected(tester, thirdDay);
    });

    testWidgets('пустая выдача сохраняет выбранный день и позволяет выбрать '
        'другой', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      repository.completeFirst([], total: 0);
      await tester.pumpAndSettle();
      expect(find.text('Нет действий на эту дату'), findsOneWidget);
      expect(
        find.text('Каждое действие здесь служит одному из ваших намерений.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('action-day-section-incomplete')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('action-day-section-completed')),
        findsNothing,
      );
      _expectSelected(tester, _today);

      final otherDay = date(2026, 9, 23);
      await tester.tap(calendarDay(otherDay));
      expect(repository.queries, hasLength(2));
      expect(repository.queries[1].date, otherDay);
      await tester.pump();
      _expectSelected(tester, otherDay);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 21), 1));
    });
  });

  testWidgets('различает ошибку чтения и повторную попытку на английском', (
    tester,
  ) async {
    final repository = _Repository();
    await _open(tester, repository, locale: const Locale('en'));
    repository.failFirst();
    await tester.pumpAndSettle();
    expect(find.text('Could not load actions.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    repository.completeFirst([_item(1)], index: 1, total: 1);
    await tester.pumpAndSettle();
    expect(find.text('Действие'), findsOneWidget);
  });
}

/// Локальное сегодня проверок страницы и дата строк фикстуры: первое чтение
/// экрана дня охватывает этот день.
final _today = CalendarDate.fromParts(2026, 9, 24);

/// Заголовки секций под календарём.
const _filterKeys = [
  'action-day-section-incomplete',
  'action-day-section-completed',
];

/// Заголовок дня называет выбранную дату [value].
void _expectSelected(WidgetTester tester, CalendarDate value) =>
    expect(find.text(_selectedDateLabel(tester, value)), findsOneWidget);

/// Полная выбранная дата в заголовке дня по текущей локали.
String _selectedDateLabel(WidgetTester tester, CalendarDate value) {
  final context = tester.element(find.byType(ActionDayCalendar));
  return DateFormat(
    'd MMMM y',
    Localizations.localeOf(context).toLanguageTag(),
  ).format(DateTime.utc(value.year, value.month, value.day));
}

/// Доводит до конца перелистывание календаря. Индикатор загрузки выдачи не
/// даёт дождаться покоя всех анимаций, поэтому время продвигается явно.
Future<void> _settleCalendar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Выполняет команду шапки календаря по её доступному названию.
Future<void> _tapCalendarCommand(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await _settleCalendar(tester);
}

/// Перелистывает календарь горизонтальным свайпом по дням периода.
Future<void> _swipeCalendar(WidgetTester tester, {required bool toNext}) async {
  await tester.drag(calendarPeriodArea, Offset(toNext ? -900 : 900, 0));
  await _settleCalendar(tester);
}

/// Открывает экран дня; [today] — локальное сегодня.
Future<AppRouter> _open(
  WidgetTester tester,
  _Repository repository, {
  CalendarDate? today,
  Locale locale = const Locale('ru'),
  Size size = const Size(1200, 2400),
}) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
        ControlledLocalDate(today ?? _today).override,
      ],
      retry: (count, error) => null,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        darkTheme: doableTheme(Brightness.dark),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  openActionsOn(router);
  await tester.pump();
  return router;
}

final class _Repository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  _Repository({
    this.completedItems = const [],
    this.completedTotal = 0,
    this.completedCursor,
  });
  final List<ActionListItem> completedItems;
  final int completedTotal;
  final ActionDayCursor? completedCursor;
  // Управляемые чтения невыполненных; выполненная секция фикстуры отвечает
  // сразу.
  final queries = <ActionDayQuery>[];
  final _requests = <Completer<ActionDayPageResult>>[];
  var _incompleteTotal = 0;

  @override
  Future<ActionDayStatusesReadResult> getActionDayStatuses(
    ActionDayStatusQuery query,
  ) => Completer<ActionDayStatusesReadResult>().future;

  @override
  Future<ActionDayPageResult> getActionDayPage(ActionDayQuery query) {
    if (query.section == ActionDaySection.completed && query.cursor == null) {
      return Future.value(
        ActionDayPageSuccess(
          ActionDayFirstPage(
            items: completedItems,
            incompleteCount: _incompleteTotal,
            completedCount: completedTotal,
            hasTimedActions: false,
            nextCursor: completedCursor,
            revision: const _Revision(),
          ),
        ),
      );
    }
    queries.add(query);
    final request = Completer<ActionDayPageResult>();
    _requests.add(request);
    return request.future;
  }

  void completeFirst(
    List<ActionListItem> items, {
    int index = 0,
    required int total,
    ActionDayCursor? cursor,
  }) {
    _incompleteTotal = total;
    _requests[index].complete(
      ActionDayPageSuccess(
        ActionDayFirstPage(
          items: items,
          incompleteCount: total,
          completedCount: completedTotal,
          hasTimedActions: false,
          nextCursor: cursor,
          revision: const _Revision(),
        ),
      ),
    );
  }

  void completeMore(int index, List<ActionListItem> items) {
    _requests[index].complete(
      ActionDayPageSuccess(
        ActionDayContinuationPage(
          items: items,
          nextCursor: null,
          revision: const _Revision(),
        ),
      ),
    );
  }

  void failFirst({int index = 0}) => _requests[index].complete(
    const ActionDayPageError(ActionDayUnavailableFailure()),
  );

  void fail(int index, ActionDayReadFailure failure) =>
      _requests[index].complete(ActionDayPageError(failure));

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) async => answerCatalogQuery(
    query,
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: const [],
        totalCount: 0,
        nextCursor: null,
        revision: const _Revision(),
      ),
    ),
  );

  @override
  Stream<ActionReadResult> watchAction(ActionId id) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}

ActionListItem _item(
  int number, {
  CalendarDate? date,
  bool completed = false,
}) => actionDayItem(number, date: date ?? _today, isCompleted: completed);

ActionId _id(int number) => _item(number).id;
