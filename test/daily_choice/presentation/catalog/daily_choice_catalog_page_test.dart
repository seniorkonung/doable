import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_presentation.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/daily_choice_local_date.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import 'daily_choice_calendar_test_support.dart';
import 'daily_choice_catalog_page_test_support.dart';

import '../../../support/in_memory_quick_creation_mode_store.dart';
import '../../../support/quick_creation.dart';
import '../../../support/intention_type_counts.dart';

void main() {
  for (final onDate in [false, true]) {
    testWidgets(
      'флажок ${onDate ? "каталога на дату" : "корневого каталога"} меняет только '
      'выбранный дубликат и ждёт сохранения и согласования',
      (tester) async {
        final repository = CatalogPageRepository();
        final day = date(2026, 10, 4);
        final first = catalogPageItem(1, date: day);
        final second = catalogPageItem(2, date: day);
        final router = await pumpCatalogPage(
          tester,
          repository,
          today: day,
          locale: const Locale('ru'),
          size: const Size(390, 1000),
          catalogDate: onDate ? day : null,
        );
        repository.completeFirst(0, [first, second], total: 2);
        await tester.pumpAndSettle();
        final route = router.current.name;
        final checkbox = find.byKey(
          ValueKey('daily-choice-completion-${second.id.toCanonicalString()}'),
        );
        expect(checkbox, findsOneWidget);
        await tester.tap(checkbox);
        await tester.pump();
        expect(router.current.name, route);
        expect(repository.completionCommands.single.choiceId, second.id);
        expect(
          repository.completionCommands.single.patch.isCompleted,
          isA<DailyChoiceFieldSet<bool>>().having(
            (patch) => patch.value,
            'выполнение',
            true,
          ),
        );
        expect(tester.widget<Checkbox>(checkbox).value, isFalse);
        expect(tester.widget<Checkbox>(checkbox).onChanged, isNull);
        expect(find.text('Сохраняем выполнение…'), findsOneWidget);
        expect(
          tester
              .widget<Checkbox>(
                find.byKey(
                  ValueKey(
                    'daily-choice-completion-${first.id.toCanonicalString()}',
                  ),
                ),
              )
              .onChanged,
          isNotNull,
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
        expect(
          find.text('Выполнение сохранено. Обновляем каталог…'),
          findsOneWidget,
        );
        expect(tester.widget<Checkbox>(checkbox).value, isFalse);
        expect(tester.widget<Checkbox>(checkbox).onChanged, isNull);
        repository.completeFirst(
          1,
          [first, catalogPageItem(2, date: day, isCompleted: true)],
          total: 2,
          revision: 1,
        );
        await tester.pumpAndSettle();
        expect(checkbox, findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('daily-choice-section-true')),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<Checkbox>(checkbox).value, isTrue);
        await tester.tap(checkbox);
        await tester.pump();
        expect(repository.completionCommands.last.choiceId, second.id);
        expect(repository.completionCommands, hasLength(2));
        expect(
          repository.completionCommands.last.patch.isCompleted,
          isA<DailyChoiceFieldSet<bool>>().having(
            (patch) => patch.value,
            'снятие выполнения',
            false,
          ),
        );
        expect(tester.widget<Checkbox>(checkbox).value, isTrue);
        await tester.tap(find.byKey(const ValueKey('daily-choice-row-2')));
        await tester.pump();
        expect(router.current.name, DailyChoiceDetailsRoute.name);
        expect(
          router.current.argsAs<DailyChoiceDetailsRouteArgs>().choiceId,
          second.id,
        );
      },
    );
  }

  for (final locale in const [Locale('ru'), Locale('en')]) {
    testWidgets('отказ флажка локализован, временный допускает повтор, '
        'а конфликт требует актуализации (${locale.languageCode})', (
      tester,
    ) async {
      final repository = CatalogPageRepository();
      final day = date(2026, 10, 4);
      final item = catalogPageItem(1, date: day);
      await pumpCatalogPage(
        tester,
        repository,
        today: day,
        locale: locale,
        size: const Size(390, 1000),
      );
      repository.completeFirst(0, [item], total: 1);
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(locale);
      final checkbox = find.byType(Checkbox);
      await tester.tap(checkbox);
      await tester.pump();
      repository.failCompletion(0, const DailyChoiceUnavailableFailure());
      await tester.pumpAndSettle();
      expect(find.text(l10n.dailyChoiceOperationUnavailable), findsOneWidget);
      expect(
        tester
            .widget<OperationFailurePresentation>(
              find.byType(OperationFailurePresentation),
            )
            .claim,
        isNotNull,
      );
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      await tester.tap(find.widgetWithText(TextButton, l10n.commonRetry));
      await tester.pump();
      expect(repository.completionCommands, hasLength(2));
      repository.failCompletion(
        1,
        const DailyChoiceConflictFailure(
          DailyChoiceConflictReason.dependencyChanged,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.dailyChoiceOperationConflict), findsOneWidget);
      expect(find.text(l10n.commonRetry), findsNothing);
      expect(tester.widget<Checkbox>(checkbox).onChanged, isNull);
      await tester.tap(
        find.widgetWithText(
          TextButton,
          locale.languageCode == 'ru' ? 'Обновить выбор' : 'Refresh choice',
        ),
      );
      await tester.pump();
      repository.completeFirst(1, [item], total: 1);
      await tester.pumpAndSettle();
      expect(find.text(l10n.dailyChoiceOperationConflict), findsNothing);
      expect(tester.widget<Checkbox>(checkbox).onChanged, isNotNull);
      expect(repository.completionCommands, hasLength(2));
    });

    testWidgets('актуализация после неизвестного отказа возвращает флажок '
        'корневого каталога без повтора отклонённого изменения '
        '(${locale.languageCode})', (tester) async {
      final repository = CatalogPageRepository();
      final day = date(2026, 10, 4);
      final item = catalogPageItem(1, date: day);
      await pumpCatalogPage(
        tester,
        repository,
        today: day,
        locale: locale,
        size: const Size(390, 1000),
      );
      repository.completeFirst(0, [item], total: 1);
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(locale);
      final checkbox = find.byType(Checkbox);
      await tester.tap(checkbox);
      await tester.pump();
      repository.failCompletion(0, const DailyChoiceUnexpectedFailure());
      await tester.pumpAndSettle();
      expect(find.text(l10n.dailyChoiceOperationUnexpected), findsOneWidget);
      expect(find.text(l10n.commonRetry), findsNothing);
      expect(tester.widget<Checkbox>(checkbox).onChanged, isNull);

      await tester.tap(
        find.widgetWithText(
          TextButton,
          locale.languageCode == 'ru' ? 'Обновить выбор' : 'Refresh choice',
        ),
      );
      await tester.pump();
      expect(repository.completionCommands, hasLength(1));
      repository.completeFirst(1, [item], total: 1);
      await tester.pumpAndSettle();
      expect(find.text(l10n.dailyChoiceOperationUnexpected), findsNothing);
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      expect(tester.widget<Checkbox>(checkbox).onChanged, isNotNull);

      await tester.tap(checkbox);
      await tester.pump();
      expect(repository.completionCommands, hasLength(2));
      expect(
        repository.completionCommands.last.patch.isCompleted,
        isA<DailyChoiceFieldSet<bool>>().having(
          (patch) => patch.value,
          'выполнение',
          true,
        ),
      );
    });
  }

  testWidgets('корневой каталог оставляет над календарём только безопасный '
      'отступ и меняет строку состояния вместе с темой', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final repository = _Repository();
    await _open(tester, repository, size: const Size(390, 844));
    repository.completeFirst([], total: 0);
    await tester.pumpAndSettle();

    final calendar = find.byType(DailyChoiceCalendar);
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

  // Направление и язык независимы: диагональ покрывает оба направления и языка.
  for (final (locale, direction, route, cancelKey, name) in const [
    (
      Locale('ru'),
      ChoicePathDraftDirection.topDown,
      DailyChoiceSourcePickerRoute.name,
      'daily-choice-source-cancel',
      'дневной выбор от намерения',
    ),
    (
      Locale('en'),
      ChoicePathDraftDirection.bottomUp,
      DailyChoiceActionPickerRoute.name,
      'daily-choice-action-cancel',
      'дневной выбор от действия',
    ),
  ]) {
    testWidgets(
      'каталог без собственной кнопки запускает $name через общую панель '
      'на языке ${locale.languageCode}',
      (tester) async {
        final repository = _Repository();
        final router = await _open(tester, repository, locale: locale);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(FloatingActionButton), findsNothing);
        repository.completeFirst([], total: 0);
        await tester.pumpAndSettle();
        expect(find.byType(FloatingActionButton), findsNothing);
        final semantics = tester.ensureSemantics();
        final l10n = lookupAppLocalizations(locale);
        expect(
          find.bySemanticsLabel(l10n.dailyChoiceCreateFromAction),
          findsNothing,
        );
        await openDailyChoiceQuickCreation(
          tester,
          direction,
          openedPage: find.byKey(ValueKey(cancelKey)),
        );
        expect(router.current.name, route);
        await tester.tap(find.byKey(ValueKey(cancelKey)));
        await tester.pump(const Duration(milliseconds: 400));
        expectDailyChoicesRootPage(router);
        expect(repository.queries, hasLength(1));
        expect(quickCreationAction().hitTestable(), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            '${l10n.quickCreationLabel}, ${QuickCreationMode.dailyChoice.title(l10n)}',
          ),
          findsOneWidget,
        );
        semantics.dispose();
      },
    );
  }

  testWidgets('показывает все записи, количество и открывает дубликат по id', (
    tester,
  ) async {
    final repository = _Repository();
    final router = await _open(tester, repository);
    expect(find.text('Загружаем дневные выборы…'), findsOneWidget);
    repository.completeFirst([_item(1), _item(2)], total: 2);
    await tester.pumpAndSettle();
    expect(find.text('Всего дневных выборов: 2'), findsOneWidget);
    expect(find.text('Чтобы Основание, я сегодня Действие'), findsNWidgets(2));
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('daily-choice-row-2')))
          .label,
      contains('№ 2'),
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-row-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(router.current.name, DailyChoiceDetailsRoute.name);
    expect(
      router.current.argsAs<DailyChoiceDetailsRouteArgs>().choiceId,
      _id(2),
    );
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
        const ValueKey('daily-choice-section-false'),
      );
      final completed = find.byKey(const ValueKey('daily-choice-section-true'));
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(incomplete).flagsCollection.isExpanded,
        Tristate.isTrue,
      );
      expect(
        tester.getSemantics(completed).flagsCollection.isExpanded,
        Tristate.isFalse,
      );
      await tester.tap(incomplete);
      await tester.tap(completed);
      await tester.pumpAndSettle();
      expect(find.text('Чтобы Основание, я сегодня Действие'), findsNothing);
      expect(find.text('На этот день нет дневных выборов.'), findsNothing);
      expect(repository.queries, hasLength(1));
      expect(
        tester.getSemantics(incomplete).flagsCollection.isExpanded,
        Tristate.isFalse,
      );
      expect(
        tester.getSemantics(completed).flagsCollection.isExpanded,
        Tristate.isTrue,
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
        Tristate.isTrue,
      );
      expect(find.text('Чтобы Основание, я сегодня Действие'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'подгрузка невыполненных сохраняет доступ к выполненным и их продолжению',
    (tester) async {
      final repository = _Repository(
        completedItems: [_item(3, completed: true)],
        completedTotal: 2,
        completedCursor: const _Cursor(),
      );
      await _open(tester, repository);
      repository.completeFirst([_item(1)], total: 2, cursor: const _Cursor());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('daily-choice-section-true')));
      await tester.pumpAndSettle();
      expect(
        find.text('Чтобы Основание, я сегодня Действие'),
        findsNWidgets(2),
      );
      await tester.tap(
        find.byKey(const ValueKey('daily-choice-load-more-false')),
      );
      await tester.pump();
      expect(
        find.text(
          lookupAppLocalizations(const Locale('ru'))
              .dailyChoiceCatalogLoadingMore,
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('daily-choice-load-more-true')),
      );
      await tester.pump();
      repository.completeMore(2, [_item(4, completed: true)]);
      repository.completeMore(1, [_item(2)]);
      await tester.pumpAndSettle();
      expect(
        find.text('Чтобы Основание, я сегодня Действие'),
        findsNWidgets(4),
      );
      expect(find.text('Всего дневных выборов: 4'), findsOneWidget);
    },
  );

  group('встроенный календарь', () {
    testWidgets('первое открытие выбирает сегодня в свёрнутой неделе и читает '
        'только этот день вместо ручного ввода даты', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);

      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 21), 1));
      expect(find.text(_selectedDateLabel(tester, _today)), findsOneWidget);
      final query = repository.queries.single;
      expect(query.date, _today);
      expect(query.isCompleted, isFalse);
      expect(query.cursor, isNull);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.byKey(const ValueKey('daily-choice-apply-date')),
        findsNothing,
      );
    });

    testWidgets(
      'календарь стоит первым в общей прокрутке над секциями и выдачей',
      (tester) async {
        final repository = _Repository();
        await _open(tester, repository);
        repository.completeFirst([_item(1)], total: 1);
        await tester.pumpAndSettle();

        final calendarBottom = tester
            .getRect(find.byType(DailyChoiceCalendar))
            .bottom;
        for (final key in [..._filterKeys, 'daily-choice-row-1']) {
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
      repository.completeFirst([_item(1)], total: 2, cursor: const _Cursor());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('daily-choice-load-more-false')),
      );
      await tester.pump();
      repository.completeMore(1, [_item(2)]);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('daily-choice-section-true')));
      await tester.pumpAndSettle();

      final nextDay = date(2026, 9, 25);
      await tester.tap(calendarDay(nextDay));

      // Выбор применён до следующего кадра.
      expect(repository.queries, hasLength(3));
      final query = repository.queries[2];
      expect(query.date, nextDay);
      expect(query.isCompleted, false);
      expect(query.cursor, isNull);

      await tester.pump();
      _expectSelected(tester, nextDay);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 21), 1));
      expect(find.text('Загружаем дневные выборы…'), findsOneWidget);
      expect(find.text('Всего дневных выборов: 3'), findsNothing);
      expect(find.byKey(const ValueKey('daily-choice-row-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('daily-choice-load-more-false')),
        findsNothing,
      );

      repository.completeFirst([_item(3, date: nextDay)], index: 2, total: 1);
      await tester.pumpAndSettle();
      expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);
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

      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarExpand);
      expect(
        find.bySemanticsLabel(l10n.dailyChoiceCalendarCollapse),
        findsOneWidget,
      );
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarNextMonth);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 6));
      // Выбранный день вне просматриваемого месяца остаётся названным.
      expect(find.text(_selectedDateLabel(tester, _today)), findsOneWidget);
      expect(repository.queries, hasLength(1));

      await tester.tap(calendarDay(selectedDay));
      expect(repository.queries, hasLength(2));
      expect(repository.queries[1].date, selectedDay);
      expect(repository.queries[1].isCompleted, isFalse);

      await _settleCalendar(tester);
      _expectSelected(tester, selectedDay);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 6));
      expect(
        find.bySemanticsLabel(l10n.dailyChoiceCalendarCollapse),
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
      expect(find.text('Загружаем дневные выборы…'), findsOneWidget);
      expect(repository.queries, hasLength(1));

      repository.completeFirst([
        _item(1, date: today),
        _item(2, date: today),
      ], total: 2);
      await tester.pumpAndSettle();
      final count = find.text('Всего дневных выборов: 2');
      expect(count, findsOneWidget);

      // Неделя с датой просмотра в ноябре раскрывается в ноябрь, сдвигая
      // выдачу вниз.
      await _swipeCalendar(tester, toNext: true);
      await _swipeCalendar(tester, toNext: true);
      await _swipeCalendar(tester, toNext: true);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 1));
      final weekCountTop = tester.getRect(count).top;
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarExpand);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      expect(tester.getRect(count).top, greaterThan(weekCountTop));

      await _swipeCalendar(tester, toNext: true);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 30), 6));
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarPreviousMonth);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarCollapse);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 1));
      expect(tester.getRect(count).top, moreOrLessEquals(weekCountTop));

      // Свёрнутая неделя показывает точную дату просмотра из середины месяца.
      await _swipeCalendar(tester, toNext: true);
      await _swipeCalendar(tester, toNext: true);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 9), 1));
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarExpand);
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarCollapse);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 11, 9), 1));

      expect(repository.queries, hasLength(1));
      _expectSelected(tester, today);
      expect(count, findsOneWidget);
      expect(find.byKey(const ValueKey('daily-choice-row-2')), findsOneWidget);
    });

    testWidgets('стрелки месяца возвращают неделю выбранного дня, сохраняя '
        'секции и выдачу без чтения', (tester) async {
      final selected = date(2026, 10, 15);
      final repository = _Repository();
      await _open(tester, repository, today: selected);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      repository.completeFirst([_item(1, date: selected)], total: 1);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('daily-choice-section-true')));
      await tester.pumpAndSettle();

      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarExpand);
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarNextMonth);
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarPreviousMonth);
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarCollapse);

      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 12), 1));
      expect(dayCell(tester, selected).isSelected, isTrue);
      _expectSelected(tester, selected);
      expect(find.text('Не выполненные'), findsOneWidget);
      expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);
      expect(repository.queries, hasLength(1));
      expect(repository.queries.last.date, selected);
      expect(repository.queries.last.isCompleted, isFalse);
    });

    testWidgets('повторное нажатие выбранного дня возвращает к нему просмотр '
        'без чтения', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      repository.completeFirst([_item(1)], total: 1);
      await tester.pumpAndSettle();

      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarExpand);
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarNextMonth);
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarPreviousMonth);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 8, 31), 6));

      await tester.tap(calendarDay(_today));
      await _settleCalendar(tester);
      _expectSelected(tester, _today);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 8, 31), 6));
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarCollapse);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 21), 1));

      expect(repository.queries, hasLength(1));
      expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);
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
      expect(find.text(l10n.dailyChoiceCatalogUnavailable), findsOneWidget);
      _expectSelected(tester, futureDay);

      await tester.tap(calendarDay(futureDay));
      await tester.pump();
      expect(repository.queries, hasLength(2));
      expect(find.text(l10n.dailyChoiceCatalogUnavailable), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, l10n.commonRetry));
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
      expect(find.text(l10n.dailyChoiceCatalogUnavailable), findsNothing);
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
        cursor: const _Cursor(),
      );
      repository.failFirst();
      await tester.pumpAndSettle();

      _expectSelected(tester, secondDay);
      expect(find.text('Всего дневных выборов: 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-choice-row-2')), findsNothing);
      expect(
        find.textContaining(secondDay.toCanonicalString()),
        findsOneWidget,
      );
      expect(find.textContaining(firstDay.toCanonicalString()), findsNothing);
      expect(
        find.byKey(const ValueKey('daily-choice-load-more-false')),
        findsNothing,
      );
      expect(find.text(l10n.dailyChoiceCatalogUnavailable), findsNothing);
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
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarExpand);
      await _swipeCalendar(tester, toNext: true);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
      expect(find.text(l10n.dailyChoiceCatalogLoading), findsOneWidget);
      expect(repository.queries, hasLength(2));
      repository.completeFirst(
        [_item(1, date: selectedDay)],
        index: 1,
        total: 2,
        cursor: const _Cursor(),
      );
      await _settleCalendar(tester);
      expect(find.text('Всего дневных выборов: 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);

      // Подгрузка выбранного дня ещё читается.
      await tester.tap(
        find.byKey(const ValueKey('daily-choice-load-more-false')),
      );
      await tester.pump();
      expect(repository.queries, hasLength(3));
      expect(repository.queries[2].date, selectedDay);
      expect(repository.queries[2].cursor, isA<_Cursor>());
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarPreviousMonth);
      await _tapCalendarCommand(tester, l10n.dailyChoiceCalendarCollapse);
      await _swipeCalendar(tester, toNext: false);
      expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 21), 1));
      expect(find.text(l10n.dailyChoiceCatalogLoadingMore), findsOneWidget);
      expect(repository.queries, hasLength(3));
      repository.completeMore(2, [_item(2, date: selectedDay)]);
      await _settleCalendar(tester);

      expect(find.byKey(const ValueKey('daily-choice-row-2')), findsOneWidget);
      expect(find.text(l10n.dailyChoiceCatalogLoadingMore), findsNothing);
      _expectSelected(tester, selectedDay);
      expect(repository.queries, hasLength(3));
    });

    testWidgets('повреждение и неизвестный отказ объясняются без повтора, '
        'временный отказ подгрузки повторяется для выбранного дня, а другой '
        'день выбирается из каждого отказа', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      final retry = find.widgetWithText(TextButton, l10n.commonRetry);
      final loadMore = find.byKey(
        const ValueKey('daily-choice-load-more-false'),
      );

      repository.fail(0, const DailyChoiceCatalogCorruptionFailure());
      await tester.pumpAndSettle();
      expect(find.text(l10n.dailyChoiceCatalogCorruption), findsOneWidget);
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
        cursor: const _Cursor(),
      );
      await tester.pumpAndSettle();
      await tester.tap(loadMore);
      await tester.pump();
      repository.fail(2, const DailyChoiceCatalogUnexpectedFailure());
      await tester.pumpAndSettle();
      expect(find.text(l10n.dailyChoiceCatalogUnexpected), findsOneWidget);
      expect(retry, findsNothing);
      expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);

      final thirdDay = date(2026, 9, 26);
      await tester.tap(calendarDay(thirdDay));
      expect(repository.queries, hasLength(4));
      expect(repository.queries[3].date, thirdDay);
      expect(repository.queries[3].cursor, isNull);
      repository.completeFirst(
        [_item(2, date: thirdDay)],
        index: 3,
        total: 2,
        cursor: const _Cursor(),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.dailyChoiceCatalogUnexpected), findsNothing);
      await tester.tap(loadMore);
      await tester.pump();
      repository.failFirst(index: 4);
      await tester.pumpAndSettle();
      expect(find.text(l10n.dailyChoiceCatalogUnavailable), findsOneWidget);

      await tester.tap(retry);
      await tester.pump();
      expect(repository.queries, hasLength(6));
      expect(repository.queries[5].date, thirdDay);
      expect(repository.queries[5].isCompleted, isFalse);
      expect(repository.queries[5].cursor, isA<_Cursor>());
      repository.completeMore(5, [_item(3, date: thirdDay)]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('daily-choice-row-2')), findsOneWidget);
      _expectSelected(tester, thirdDay);
    });

    testWidgets('пустая выдача сохраняет выбранный день и позволяет выбрать '
        'другой', (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      repository.completeFirst([], total: 0);
      await tester.pumpAndSettle();
      expect(find.text('На этот день нет дневных выборов.'), findsOneWidget);
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
    expect(
      find.text('Could not load daily choices. Try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pump();
    repository.completeFirst([_item(1)], index: 1, total: 1);
    await tester.pumpAndSettle();
    expect(find.text('To Основание, today I Действие'), findsOneWidget);
  });
}

/// Локальное сегодня проверок страницы и дата строк фикстуры: первое чтение
/// каталога охватывает этот день.
final _today = CalendarDate.fromParts(2026, 9, 24);

/// Заголовки секций под календарём.
const _filterKeys = ['daily-choice-section-false', 'daily-choice-section-true'];

/// Заголовок дня называет выбранную дату [value].
void _expectSelected(WidgetTester tester, CalendarDate value) =>
    expect(find.text(_selectedDateLabel(tester, value)), findsOneWidget);

/// Полная выбранная дата в заголовке дня по текущей локали.
String _selectedDateLabel(WidgetTester tester, CalendarDate value) {
  final context = tester.element(find.byType(DailyChoiceCalendar));
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

/// Открывает каталог дневных выборов; [today] — локальное сегодня.
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
        ControlledDailyChoiceLocalDate(today ?? _today).override,
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
  openDailyChoicesOn(router);
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
  final List<DailyChoiceCatalogItem> completedItems;
  final int completedTotal;
  final DailyChoiceCatalogCursor? completedCursor;
  // Управляемые чтения невыполненных; выполненная секция фикстуры пуста.
  final queries = <DailyChoiceCatalogQuery>[];
  final _requests = <Completer<DailyChoiceCatalogPageResult>>[];

  @override
  Future<DailyChoiceDayStatusesReadResult> getDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  ) => Completer<DailyChoiceDayStatusesReadResult>().future;

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) {
    if (query.isCompleted == true && query.cursor == null) {
      return Future.value(
        DailyChoiceCatalogPageSuccess(
          DailyChoiceCatalogFirstPage(
            items: completedItems,
            totalCount: completedTotal,
            hasTimedChoices: false,
            nextCursor: completedCursor,
            revision: const _Revision(),
          ),
        ),
      );
    }
    queries.add(query);
    final request = Completer<DailyChoiceCatalogPageResult>();
    _requests.add(request);
    return request.future;
  }

  void completeFirst(
    List<DailyChoiceCatalogItem> items, {
    int index = 0,
    required int total,
    DailyChoiceCatalogCursor? cursor,
  }) {
    _requests[index].complete(
      DailyChoiceCatalogPageSuccess(
        DailyChoiceCatalogFirstPage(
          items: items,
          totalCount: total,
          hasTimedChoices: false,
          nextCursor: cursor,
          revision: const _Revision(),
        ),
      ),
    );
  }

  void completeMore(int index, List<DailyChoiceCatalogItem> items) {
    _requests[index].complete(
      DailyChoiceCatalogPageSuccess(
        DailyChoiceCatalogContinuationPage(
          items: items,
          nextCursor: null,
          revision: const _Revision(),
        ),
      ),
    );
  }

  void failFirst({int index = 0}) => _requests[index].complete(
    const DailyChoiceCatalogPageError(DailyChoiceCatalogUnavailableFailure()),
  );

  void fail(int index, DailyChoiceCatalogReadFailure failure) =>
      _requests[index].complete(DailyChoiceCatalogPageError(failure));

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
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}

final class _Cursor implements DailyChoiceCatalogCursor {
  const _Cursor();
}

DailyChoiceCatalogItem _item(
  int number, {
  CalendarDate? date,
  bool completed = false,
}) => DailyChoiceCatalogItem(
  id: _id(number),
  source: DailyChoiceCatalogParticipant(
    id: _intentionId(1),
    title: 'Основание',
    archiveState: IntentionArchiveState.archived,
    readiness: IntentionReadiness.notReady,
  ),
  selected: DailyChoiceCatalogParticipant(
    id: _intentionId(2),
    title: 'Действие',
    archiveState: IntentionArchiveState.active,
    readiness: IntentionReadiness.ready,
  ),
  date: date ?? _today,
  isCompleted: completed,
  schedule: const DailyChoiceAllDay(),
  priority: DailyChoicePriority.p4,
  description: null,
  pathIntentionCount: 2,
);

DailyChoiceId _id(int number) => (DailyChoiceId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as DailyChoiceIdDecodingSuccess).id;

IntentionId _intentionId(int number) => (IntentionId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;
