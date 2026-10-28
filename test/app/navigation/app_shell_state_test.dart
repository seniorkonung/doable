import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart'
    as daily_page;
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_date_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/calendar_handle.dart';
import 'package:doable/src/design_system/components/day_mark.dart';
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
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/app_root_pages.dart';
import '../../support/daily_choice_catalog_controls.dart';
import '../../support/daily_choice_catalog_provider.dart';
import '../../support/daily_choice_local_date.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/inline_text.dart';
import '../../support/tag_positions.dart';

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

/// Связь «Намерение 01» → «Намерение 02» — путь каждого дневного выбора.
const _relation = 501;

/// Дневные выборы на одну дату с источником «Намерение 01»: чётные по
/// порядку создания не выполнены, нечётные выполнены.
const _firstChoice = 1001;
const _choiceCount = 240;
const _firstPathStep = 2001;
final _choiceDate = CalendarDate.fromParts(2026, 9, 25);

/// Локальное сегодня приложения — следующий день: в каталоге выбирается
/// прошлый день дневных выборов, отличный от начального.
final _today = CalendarDate.fromParts(2026, 9, 26);

/// Дата просмотра подготовленного календаря каталога дневных выборов: за
/// четыре недели до выбранного дня. Раскрытый календарь показывает её месяц,
/// а сама она не совпадает ни с выбранным днём, ни с началом месяца.
final _viewedDate = CalendarDate.fromParts(2026, 8, 28);

/// Размеры порций каталога намерений и каталога дневных выборов.
const _intentionPageSize = 100;
const _dailyChoicePageSize = 50;

const _message = ValueKey('graph-operation-message');

void main() {
  for (final fromMonths in [false, true]) {
    final level = fromMonths ? 'месяцев' : 'лет';
    testWidgets('после возврата ручки открытая страница $level сохраняется '
        'вместе с каталогом при смене пункта, повторном выборе и возврате '
        'из подробностей', (tester) async {
      final app = await _start(tester);
      await _prepareDailyChoiceCatalog(tester, app);
      final before = _dailyChoiceCatalogView(tester, app);
      for (final distance in [-400.0, 400.0]) {
        await tester.drag(find.byType(CalendarHandle), Offset(0, distance));
        await tester.pumpAndSettle();
      }
      expect(_dailyChoiceCatalogView(tester, app), before);
      await _tap(
        tester,
        find.bySemanticsLabel(app.l10n.dailyChoiceCalendarChooseYearAndMonth),
      );
      await _tap(
        tester,
        find.bySemanticsLabel(app.l10n.dailyChoiceCalendarNextYears),
      );
      if (fromMonths) {
        await _tap(tester, find.text('2035'));
        await _tap(
          tester,
          find.bySemanticsLabel(app.l10n.dailyChoiceCalendarNextYear),
        );
      }
      await tester.pumpAndSettle();
      final title = fromMonths ? '2036' : '2032–2043';
      final position = _dailyChoicePosition(tester).pixels;

      void expectPreserved() {
        expect(find.text(title), findsOneWidget);
        expect(_dailyChoicePosition(tester).pixels, position);
        expect(app.dailyChoiceCatalog.selection.date, _choiceDate);
        expect(app.dailyChoiceCatalog.selection.completedExpanded, isFalse);
        expect(_dailyChoiceIds(app), before['загруженные записи']);
        expect(app.repository.dailyChoiceCatalogReads, before['чтения выдачи']);
      }

      final height = tester.getSize(dailyChoiceCatalogDateControl).height;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CalendarHandle)),
      );
      await gesture.moveBy(const Offset(0, -20));
      await gesture.moveBy(
        const Offset(0, -40),
        timeStamp: const Duration(seconds: 1),
      );
      await tester.pump();
      expect(
        tester.getSize(dailyChoiceCatalogDateControl).height,
        lessThan(height),
      );
      expect(_dailyChoicePosition(tester).pixels, position);
      await gesture.up(timeStamp: const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expectPreserved();

      await _select(tester, AppDestination.home);
      await _select(tester, AppDestination.dailyChoices);
      expectPreserved();
      await _select(tester, AppDestination.dailyChoices);
      expectPreserved();
      await tester.tap(_dailyChoiceRows.hitTestable().first);
      await _until(tester, find.byType(DailyChoiceDetailsPage));
      await tester.pumpAndSettle();
      await _closeTop(tester, DailyChoiceDetailsPage);
      expectPreserved();

      await _tap(
        tester,
        find.bySemanticsLabel(app.l10n.dailyChoiceCalendarBackToMonthDays),
      );
      await tester.pumpAndSettle();
      expect(_dailyChoiceCatalogView(tester, app), before);
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
    testWidgets('позднее архивирование один раз согласует сохранённые корни '
        'на настоящем хранилище после сброса истории', (tester) async {
      final app = await _start(tester);
      await _prepareDailyChoiceCatalog(tester, app);
      final dailyBefore = _dailyChoiceParameters(tester, app);
      await _select(tester, AppDestination.intentionGraph);
      await _enterTitleFilter(tester, app, 'Намерение', total: _activeCount);
      await _selectOrder(tester, app.l10n.catalogOrderCreatedOldest);
      final catalogBefore = _intentionCatalogParameters(tester, app);
      final target = app.intentionCatalog.items.first;
      final router = app.container.read(appRouterProvider);
      await tester.tap(_catalogRow(target.title).hitTestable());
      await _until(tester, find.byType(IntentionDetailsPage));
      await tester.pumpAndSettle();
      app.repository.holdNextCommand();
      await _tap(
        tester,
        find.byKey(const ValueKey('intention-details-archive')),
      );
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
      expect(find.byKey(_message), findsOneWidget);
      expect(app.repository.commands.single, isA<ArchiveIntention>());
      await _closeMessage(tester);

      await _select(tester, AppDestination.intentionGraph);
      expect(
        find.text('Total intentions: ${_activeCount - 1}'),
        findsOneWidget,
      );
      expect(find.text(target.title), findsNothing);
      expect(_intentionCatalogParameters(tester, app), catalogBefore);
      await _select(tester, AppDestination.dailyChoices);
      expect(_dailyChoiceParameters(tester, app), dailyBefore);
      await _closeMessage(tester);
      expect(_builtMessages, findsNothing);
      expect(tester.takeException(), isNull);
    });

    // Сброс одинаков для всех пунктов: достаточно повторного выбора текущего
    // пункта и перехода на другой.
    for (final (origin, destination) in [
      (AppDestination.intentionGraph, AppDestination.intentionGraph),
      (AppDestination.intentionGraph, AppDestination.dailyChoices),
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
        await tester.tap(
          find
              .descendant(
                of: find.byType(catalog_page.IntentionCatalogPage),
                matching: find.byType(IntentionSummaryView),
              )
              .hitTestable()
              .first,
        );
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
    testWidgets('переименование участника дневного выбора видно в строке '
        'каталога намерений без сброса его параметров и '
        'позиции', (tester) async {
      final app = await _start(tester);
      final renamed = _activeTitle(2);
      const newTitle = 'Намерение 02 после переименования';
      await _select(tester, AppDestination.intentionGraph);
      await _enterTitleFilter(tester, app, 'Намерение', total: _activeCount);
      await _selectOrder(tester, app.l10n.catalogOrderCreatedOldest);
      // Строка переименуемого намерения остаётся в видимой части.
      _catalogPosition(tester).jumpTo(60);
      await tester.pumpAndSettle();
      expect(_catalogRow(renamed), findsOneWidget);
      final before = _intentionCatalogParameters(tester, app);

      await _select(tester, AppDestination.dailyChoices);
      await _selectDay(tester, app, _choiceDate, total: _choiceCount);
      await _open(tester, _dailyChoiceRows.first, DailyChoiceDetailsPage);
      await _open(
        tester,
        find.byKey(const ValueKey('daily-choice-intention-2')),
        IntentionDetailsPage,
      );
      await _tap(tester, find.byKey(const ValueKey('intention-details-edit')));
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-title')),
        newTitle,
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('intention-details-edit-submit')),
      );
      await _until(tester, find.text(newTitle));
      await _select(tester, AppDestination.intentionGraph);

      expect(_catalogRow(newTitle), findsOneWidget);
      expect(_catalogRow(renamed), findsNothing);
      expect(_intentionCatalogParameters(tester, app), before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('изменение дневного выбора через страницу намерения '
        'обновляет отметки скрытого каталога: календарь, фильтры '
        'и позиция сохраняются, а количество и продолжение выдачи относятся к '
        'новой ревизии', (tester) async {
      final app = await _start(tester);
      // Последний невыполненный выбор уходит из выдачи в пустой просматриваемый
      // день: там появляется галочка, а количество исходного дня уменьшается.
      const changed = _firstChoice + _choiceCount - 2;
      expect(_isCompleted(changed), isFalse);
      await _prepareDailyChoiceCatalog(tester, app);
      final before = _dailyChoiceParameters(tester, app);
      await _tap(
        tester,
        find.bySemanticsLabel(app.l10n.dailyChoiceCalendarChooseYearAndMonth),
      );
      await _tap(tester, find.text('2028'));
      final rootProvider = openedDailyChoiceCatalogProvider(app.container);
      final marksProvider = openedDailyChoiceDayMarksProvider(app.container);
      await _waitFor(tester, () {
        expect(app.container.exists(marksProvider), isTrue);
        return app.container.read(marksProvider).dayStatuses != null;
      });
      expect(
        app.container.read(marksProvider).dayStatuses!.statuses[_viewedDate],
        isNull,
      );

      await _select(tester, AppDestination.intentionGraph);
      await _enterTitleFilter(tester, app, _activeTitle(1), total: 1);
      await _open(tester, _catalogRow(_activeTitle(1)), IntentionDetailsPage);
      await _tap(tester, find.text('Relations').first);
      await _tap(
        tester,
        find.byKey(
          const ValueKey('relation-neighborhood-daily-source'),
          skipOffstage: false,
        ),
      );
      await _open(
        tester,
        find.byKey(
          ValueKey('relation-neighborhood-daily-row-${tagFixtureId(changed)}'),
        ),
        DailyChoiceDetailsPage,
      );
      await _tap(tester, find.byKey(const ValueKey('daily-choice-edit-open')));
      await _until(
        tester,
        find.byKey(const ValueKey('daily-choice-edit-date')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-edit-date')),
        _viewedDate.toCanonicalString(),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-edit-submit')),
      );
      await _until(
        tester,
        find.byKey(const ValueKey('daily-choice-edit-open')),
      );
      await _closeTop(tester, DailyChoiceDetailsPage);
      await _tap(tester, find.text(app.l10n.statisticsSectionTitle).first);
      // Флажок доступен в другом каталоге; корневой остаётся скрытым.
      final dayLabel = app.l10n.statisticsCalendarDaySemantics(
        DateTime.utc(_choiceDate.year, _choiceDate.month, _choiceDate.day),
        '',
      );
      final statisticsDay = find.bySemanticsLabel(
        RegExp('^${RegExp.escape(dayLabel)}'),
      );
      await tester.scrollUntilVisible(
        statisticsDay,
        -500,
        scrollable: find
            .descendant(
              of: find.byType(IntentionDetailsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await _open(tester, statisticsDay, DailyChoiceDateCatalogPage);
      await selectDailyChoiceCatalogDate(tester, _viewedDate, tap: _tap);
      final completion = find.byKey(
        ValueKey('daily-choice-completion-${tagFixtureId(changed)}'),
      );
      await _until(tester, completion);
      expect(tester.widget<Checkbox>(completion).value, isFalse);
      await _tap(tester, completion);
      // Существующая модель скрытого каталога согласуется до возврата.
      await _waitFor(tester, () {
        expect(app.container.exists(marksProvider), isTrue);
        return app.container
                .read(marksProvider)
                .dayStatuses
                ?.statuses[_viewedDate] ==
            DailyChoiceDayStatus.allCompleted;
      });
      expect(find.byType(daily_page.DailyChoiceCatalogPage), findsNothing);
      final hiddenRoot =
          app.container.read(rootProvider) as DailyChoiceCatalogLoaded;
      expect(hiddenRoot.selection.date, _choiceDate);
      expect(hiddenRoot.totalCount, _choiceCount - 1);
      expect(hiddenRoot.incomplete.items, hasLength(100));
      await _closeTop(tester, DailyChoiceDateCatalogPage);
      await _closeTop(tester, IntentionDetailsPage);
      await _select(tester, AppDestination.dailyChoices);
      await _waitFor(
        tester,
        () =>
            app.dailyChoiceCatalog.freshness ==
            DailyChoiceCatalogFreshness.current,
      );
      await tester.pumpAndSettle();

      // Невыполненные выборы дня после изменения в порядке выдачи: более
      // поздние по созданию раньше.
      final expected = [
        for (var choice = _firstChoice; choice < changed; choice++)
          if (!_isCompleted(choice)) tagFixtureId(choice),
      ];
      expect(find.text('2028'), findsOneWidget);
      await _tap(
        tester,
        find.bySemanticsLabel(app.l10n.dailyChoiceCalendarBackToMonthDays),
      );
      await tester.pumpAndSettle();
      expect(_dailyChoiceParameters(tester, app), before);
      expect(
        find.text(
          app.l10n.dailyChoiceCatalogTotalCount(_choiceCount - 1),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        app.dailyChoiceCatalog.incomplete.items
            .map((item) => item.id.toCanonicalString())
            .toList(),
        expected.take(app.dailyChoiceCatalog.incomplete.items.length).toList(),
      );

      // Продолжение новой ревизии дополняет выдачу без пропусков и повторов.
      await _closeMessage(tester);
      final position = _dailyChoicePosition(tester);
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        find
            .byKey(const ValueKey('daily-choice-load-more-false'))
            .hitTestable(),
        findsOneWidget,
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-load-more-false')),
      );
      await _waitFor(
        tester,
        () => app.dailyChoiceCatalog.incomplete.items.length == expected.length,
      );
      await tester.pumpAndSettle();

      expect(
        app.dailyChoiceCatalog.incomplete.items
            .map((item) => item.id.toCanonicalString())
            .toList(),
        expected,
      );
      expect(
        find.text(
          app.l10n.dailyChoiceCatalogTotalCount(_choiceCount - 1),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('daily-choice-load-more-false')),
        findsNothing,
      );
      await showDailyChoiceCatalogPeriod(tester, _viewedDate, tap: _tap);
      expect(
        dailyChoiceCatalogDayMark(_viewedDate, mark: DayMark.done),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('возврат из подробного просмотра дневного выбора', () {
    testWidgets('каталог сохраняет календарь, фильтры, загруженные записи и '
        'позицию прокрутки без повторного получения', (tester) async {
      final app = await _start(tester);
      await _prepareDailyChoiceCatalog(tester, app);
      final before = _dailyChoiceCatalogView(tester, app);

      // Строка в видимой части открывается нажатием без прокрутки страницы.
      await tester.tap(_dailyChoiceRows.hitTestable().first);
      await _until(tester, find.byType(DailyChoiceDetailsPage));
      await tester.pumpAndSettle();
      await _closeTop(tester, DailyChoiceDetailsPage);

      expect(_dailyChoiceCatalogView(tester, app), before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('изменение выбора будущего дня видно в каталоге, а выбранный '
        'день, просматриваемый месяц, раскрытие календаря, фильтры и позиция '
        'сохраняются', (tester) async {
      // Выбираемый день дневных выборов наступит через пять дней.
      final app = await _start(
        tester,
        today: CalendarDate.fromParts(2026, 9, 20),
      );
      // Последний созданный выбор — первая строка каталога.
      const changed = _firstChoice + _choiceCount - 1;
      // Только он не выполнен: его изменение должно заменить кружок галочкой.
      seedRawGraph(app.raw, () {
        app.raw.execute(
          'UPDATE daily_choices SET is_completed = CASE WHEN id = ? THEN 0 ELSE 1 END',
          [tagFixtureId(changed)],
        );
      });
      const wasCompleted = false;
      await _select(tester, AppDestination.dailyChoices);
      await _selectDay(tester, app, _choiceDate, total: _choiceCount);
      await _until(tester, dailyChoiceCatalogDayMark(_choiceDate));
      expect(
        dailyChoiceCatalogDayMark(_choiceDate, mark: DayMark.todo),
        findsOneWidget,
      );
      // Раскрытый календарь показывает следующий месяц.
      await expandDailyChoiceCatalogCalendar(tester, tap: _tap);
      await showDailyChoiceCatalogPeriod(
        tester,
        CalendarDate.fromParts(2026, 10, 15),
        tap: _tap,
      );
      // Первая строка остаётся в видимой части.
      _dailyChoicePosition(tester).jumpTo(30);
      await tester.pumpAndSettle();
      expect(
        shownDailyChoiceCatalogViewport(tester),
        DailyChoiceCalendarViewport(
          focusedDate: CalendarDate.fromParts(2026, 10, 1),
          mode: DailyChoiceCalendarMode.month,
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('daily-choice-row-1')),
          matching: find.text(_completion(app.l10n, wasCompleted)),
        ),
        findsOneWidget,
      );
      final before = _dailyChoiceParameters(tester, app);

      // Строка открывается нажатием без прокрутки страницы.
      await tester.tap(find.byKey(const ValueKey('daily-choice-row-1')));
      await _until(tester, find.byType(DailyChoiceDetailsPage));
      await tester.pumpAndSettle();
      await _closeTop(tester, DailyChoiceDetailsPage);
      await _tap(
        tester,
        find.byKey(
          ValueKey('daily-choice-completion-${tagFixtureId(changed)}'),
        ),
      );
      final marksProvider = openedDailyChoiceDayMarksProvider(app.container);
      await _waitFor(tester, () {
        expect(app.container.exists(marksProvider), isTrue);
        return app.container
                .read(marksProvider)
                .dayStatuses
                ?.statuses[_choiceDate] ==
            DailyChoiceDayStatus.allCompleted;
      });
      await _waitFor(
        tester,
        () =>
            app.dailyChoiceCatalog.freshness ==
            DailyChoiceCatalogFreshness.current,
      );
      await tester.pumpAndSettle();

      expect(app.dailyChoiceCatalog.incomplete.totalCount, 0);
      expect(app.dailyChoiceCatalog.completed.totalCount, _choiceCount);
      expect(_dailyChoiceParameters(tester, app), before);
      await showDailyChoiceCatalogPeriod(tester, _choiceDate, tap: _tap);
      await _waitFor(
        tester,
        () => dailyChoiceCatalogDayMark(
          _choiceDate,
          mark: DayMark.done,
        ).evaluate().isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('смена языка интерфейса', () {
    testWidgets('русский и английский переводят только '
        'системные подписи каталога дневных выборов, а календарь, фильтры, '
        'выдача, пользовательский текст и позиция сохраняются без новых '
        'чтений', (tester) async {
      final app = await _start(tester);
      await _prepareDailyChoiceCatalog(tester, app);
      final before = _languageIndependent(_dailyChoiceCatalogView(tester, app));

      for (final (platform, resolved) in [
        (const Locale('ru', 'RU'), const Locale('ru')),
        (const Locale('en', 'GB'), const Locale('en')),
      ]) {
        tester.binding.platformDispatcher.localesTestValue = [platform];
        await tester.pumpAndSettle();

        final reason = '$platform';
        final page = find.byType(daily_page.DailyChoiceCatalogPage);
        expect(Localizations.localeOf(tester.element(page)), resolved);
        for (final (locale, labels) in _catalogLabels.entries.map(
          (entry) => (entry.key, entry.value),
        )) {
          for (final (scope, texts, skipOffstage) in [
            (dailyChoiceCatalogDateControl, labels.calendar, true),
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
        // Формулировка строки собирается из системных слов языка и прежних
        // названий намерений.
        expect(
          find.descendant(
            of: _dailyChoiceRows.hitTestable().first,
            matching: find.text(
              lookupAppLocalizations(resolved)
                  .dailyChoiceDetailsPhrase(_activeTitle(1), _activeTitle(2)),
            ),
          ),
          findsOneWidget,
          reason: reason,
        );
        expect(
          _languageIndependent(_dailyChoiceCatalogView(tester, app)),
          before,
          reason: reason,
        );
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
            : 'архивирование завершается и предъявляется один раз, а смена пункта '
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
          await _open(tester, _catalogRow(archived), IntentionDetailsPage);
          app.repository.holdNextCommand();
          if (fails) app.faults.failNextArchiveWrite();
          await _tap(
            tester,
            find.byKey(const ValueKey('intention-details-archive')),
          );
          // Операция принята и дошла до хранилища до смены пункта.
          await _waitFor(tester, () => app.repository.isHolding);
          await _closeTop(tester, IntentionDetailsPage);

          await _select(tester, AppDestination.home);
          await _select(tester, AppDestination.dailyChoices);
          await _select(tester, AppDestination.dailyChoices);

          expect(_builtMessages, findsNothing);
          expect(archiveState(), 0);

          // Результат приходит, пока выбран другой пункт, и предъявляется
          // сразу на его странице, а не при возвращении к началу перехода.
          app.repository.releaseCommand();
          await _until(tester, find.byKey(_message));
          await tester.pumpAndSettle();

          final message = find.text(
            l10n.graphOperationMessage(
              l10n.graphOperationArchive,
              archived,
              fails
                  ? l10n.detailsStateChangeUnavailable
                  : l10n.detailsArchivedSuccess,
            ),
          );
          expect(find.byKey(_message), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(daily_page.DailyChoiceCatalogPage),
              matching: message,
            ),
            findsOneWidget,
          );
          expect(app.repository.commands.single, isA<ArchiveIntention>());
          expect(archiveState(), fails ? 0 : 1);
          // Смена пункта не предъявляет результат заново.
          await _select(tester, AppDestination.home);
          expect(find.byKey(_message), findsOneWidget);
          expect(message, findsOneWidget);
          await _select(tester, AppDestination.intentionGraph);
          expect(find.byKey(_message), findsOneWidget);
          expect(_catalogRow(archived), fails ? findsOneWidget : findsNothing);

          await _closeMessage(tester);
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
  AppDestination.dailyChoices: 'Дневные выборы',
  AppDestination.intentionGraph: 'Граф намерений',
};

/// Корневая страница каждого пункта.
const _rootPages = {
  AppDestination.home: HomePage,
  AppDestination.dailyChoices: daily_page.DailyChoiceCatalogPage,
  AppDestination.intentionGraph: catalog_page.IntentionCatalogPage,
};

/// Подготовка корневой страницы пункта и её наблюдаемое состояние.
typedef _RootPageState = ({
  Future<void> Function(WidgetTester tester, _App app) prepare,
  Map<String, Object?> Function(WidgetTester tester, _App app) view,
});

const _rootPageStates = <AppDestination, _RootPageState>{
  AppDestination.dailyChoices: (
    prepare: _prepareDailyChoiceCatalog,
    view: _dailyChoiceCatalogView,
  ),
  AppDestination.intentionGraph: (
    prepare: _prepareIntentionCatalog,
    view: _intentionCatalogView,
  ),
};

String _activeTitle(int number) =>
    'Намерение ${number.toString().padLeft(2, '0')}';

int _plain(int number) => _firstPlain + number - 1;

String _plainTitle(int number) => 'Обычное $number';

/// Выполнен ли дневной выбор с номером [choice] фикстуры.
bool _isCompleted(int choice) => (choice - _firstChoice).isOdd;

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

  DailyChoiceCatalogLoaded get dailyChoiceCatalog =>
      switch (container.read(openedDailyChoiceCatalogProvider(container))) {
        final DailyChoiceCatalogLoaded loaded => loaded,
        final other => fail('Каталог дневных выборов без записей: $other'),
      };

  /// Каталог дневных выборов показывает полученную выдачу, в том числе пустую.
  bool get hasDailyChoiceCatalogResult =>
      container.read(openedDailyChoiceCatalogProvider(container))
          is DailyChoiceCatalogLoaded;
}

/// Запускает приложение на засеянном хранилище и ждёт Главную.
///
/// [today] — локальное сегодня приложения; по умолчанию [_today].
Future<_App> _start(WidgetTester tester, {CalendarDate? today}) async {
  // Общая поверхность показывает сообщения только работающему приложению.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  // Широкий экран: подписи тестового шрифта шире настоящих, и на узком экране
  // расширенная кнопка создания дневного выбора закрывает продолжение выдачи.
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
    dailyChoiceLocalDateSource: ControlledDailyChoiceLocalDate(today ?? _today)
        .read,
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
      'related_intention_id, type, priority, is_archived) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(_relation), tagFixtureId(1), tagFixtureId(2), 'need', 2, 0],
    );
    for (var index = 0; index < _choiceCount; index++) {
      final choice = _firstChoice + index;
      database.execute(
        'INSERT INTO daily_choices (id, source_intention_id, '
        'selected_intention_id, choice_date, is_completed) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          tagFixtureId(choice),
          tagFixtureId(1),
          tagFixtureId(2),
          _choiceDate.toCanonicalString(),
          _isCompleted(choice) ? 1 : 0,
        ],
      );
      database.execute(
        'INSERT INTO daily_choice_path_steps (id, daily_choice_id, '
        'long_term_relation_id) VALUES (?, ?, ?)',
        [
          tagFixtureId(_firstPathStep + index),
          tagFixtureId(choice),
          tagFixtureId(_relation),
        ],
      );
    }
  });
  database.execute('COMMIT');
}

/// Каталог намерений: архивный охват, фильтр названия, условие по тегу,
/// порядок от старых к новым, две загруженные порции из трёх и прокрутка
/// внутри второй порции.
Future<void> _prepareIntentionCatalog(WidgetTester tester, _App app) async {
  await _select(tester, AppDestination.intentionGraph);
  await _selectScope(tester, app.l10n.catalogScopeArchived);
  await _enterTitleFilter(
    tester,
    app,
    'Архив',
    total: _archivedCount + _untaggedCount,
  );
  await _tap(
    tester,
    find.byKey(const ValueKey('intention-tag-conditions-add')),
  );
  await _tap(
    tester,
    find.byKey(ValueKey('tags-panel-row-${tagFixtureId(_healthTag)}')),
  );
  // Панель фильтра применяет условие сразу, а «назад» только закрывает её.
  await tester.binding.handlePopRoute();
  await _waitFor(
    tester,
    () => find
        .byKey(ValueKey('tags-panel-row-${tagFixtureId(_healthTag)}'))
        .evaluate()
        .isEmpty,
  );
  await _until(tester, find.text(app.l10n.catalogTotalCount(_archivedCount)));
  await tester.pumpAndSettle();
  await _selectOrder(tester, app.l10n.catalogOrderCreatedOldest);

  // Конец первой порции запрашивает вторую.
  final position = _catalogPosition(tester);
  position.jumpTo(position.maxScrollExtent);
  await _waitFor(
    tester,
    () => app.intentionCatalog.items.length == 2 * _intentionPageSize,
  );
  await tester.pumpAndSettle();
  // Середина второй порции далека от её конца: третья порция не нужна.
  position.jumpTo(position.maxScrollExtent * 0.6);
  await _settle(tester);

  // Параметры поиска прокручиваются вместе с выдачей: страница стоит между
  // ними и концом выдачи.
  final page = _catalogPagePosition(tester);
  page.jumpTo(page.maxScrollExtent / 2);
  await _settle(tester);

  final catalog = app.intentionCatalog;
  expect(catalog.items, hasLength(2 * _intentionPageSize));
  expect(catalog.totalCount, _archivedCount);
  expect(catalog.nextCursor, isNotNull);
  expect(catalog.selection.scope, IntentionScope.archived);
  expect(catalog.selection.order, IntentionCatalogOrder.createdAtAscending);
  expect(catalog.items.first.title, 'Архив 001');
  expect(_conditions(tester), ['Здоровье']);
  expect(position.pixels, greaterThan(0));
  expect(page.pixels, greaterThan(0));
}

/// Каталог дневных выборов: прошлый день и невыполненные, календарь раскрыт
/// на месяце другой даты просмотра, две загруженные порции из трёх и
/// прокрутка внутри них.
Future<void> _prepareDailyChoiceCatalog(WidgetTester tester, _App app) async {
  final incomplete = _choiceCount ~/ 2;
  await _select(tester, AppDestination.dailyChoices);
  await _selectDay(tester, app, _choiceDate, total: _choiceCount);
  await showDailyChoiceCatalogSection(tester, false);

  // Неделя даты просмотра раскрывается в её месяц.
  await showDailyChoiceCatalogPeriod(tester, _viewedDate, tap: _tap);
  await expandDailyChoiceCatalogCalendar(tester, tap: _tap);
  final position = _dailyChoicePosition(tester);
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
  await _tap(
    tester,
    find.byKey(const ValueKey('daily-choice-load-more-false')),
  );
  await _waitFor(
    tester,
    () =>
        app.dailyChoiceCatalog.incomplete.items.length ==
            2 * _dailyChoicePageSize &&
        app.dailyChoiceCatalog.freshness == DailyChoiceCatalogFreshness.current,
  );
  await tester.pumpAndSettle();
  position.jumpTo(position.maxScrollExtent / 2);
  await _settle(tester);

  final catalog = app.dailyChoiceCatalog;
  expect(shownDailyChoiceCatalogDate(tester), _choiceDate);
  expect(
    shownDailyChoiceCatalogViewport(tester),
    DailyChoiceCalendarViewport(
      focusedDate: _viewedDate,
      mode: DailyChoiceCalendarMode.month,
    ),
  );
  expect(catalog.selection.date, _choiceDate);
  expect(catalog.totalCount, _choiceCount);
  expect(catalog.incomplete.totalCount, incomplete);
  expect(catalog.incomplete.nextCursor, isNotNull);
  expect(catalog.selection.completedExpanded, isFalse);
  expect(catalog.incomplete.items.every((item) => !item.isCompleted), isTrue);
  expect(position.pixels, greaterThan(0));
}

/// Наблюдаемое состояние каталога намерений: страница, выдача, параметры,
/// позиция и число обращений к выдаче в хранилище.
Map<String, Object?> _intentionCatalogView(WidgetTester tester, _App app) {
  final catalog = app.intentionCatalog;
  return {
    ..._intentionCatalogParameters(tester, app),
    'загруженные намерения': [for (final item in catalog.items) item.title],
    'всего': catalog.totalCount,
    'чтения выдачи': app.repository.catalogReads,
    'чтения первой порции': app.repository.firstCatalogPortions,
  };
}

/// Параметры и позиция каталога намерений, как их видит человек.
Map<String, Object?> _intentionCatalogParameters(
  WidgetTester tester,
  _App app,
) => {
  'охват': _texts(find.byKey(const ValueKey('catalog-scope-control'))),
  'фильтр названия': tester
      .widget<TextField>(find.byKey(const ValueKey('catalog-filter-field')))
      .controller!
      .text,
  'условия по тегам': _conditions(tester),
  'порядок': _texts(find.byKey(const ValueKey('catalog-order-control'))),
  'позиция прокрутки': _catalogPosition(tester).pixels,
  'позиция прокрутки страницы': _catalogPagePosition(tester).pixels,
};

/// Наблюдаемое состояние каталога дневных выборов: страница, календарь и
/// общая прокрутка, выдача, параметры, позиция и число обращений к выдаче в
/// хранилище.
Map<String, Object?> _dailyChoiceCatalogView(WidgetTester tester, _App app) {
  final catalog = app.dailyChoiceCatalog;
  return {
    ..._dailyChoiceParameters(tester, app),
    'загруженные записи': [
      for (final item in catalog.items) item.id.toCanonicalString(),
    ],
    'чтения выдачи': app.repository.dailyChoiceCatalogReads,
  };
}

/// Календарь, фильтры и позиция каталога дневных выборов, как их видит
/// человек.
///
/// Календарь и фильтры прокручиваются вместе с выдачей, поэтому на
/// прокрученной странице они могут стоять за верхним краем.
Map<String, Object?> _dailyChoiceParameters(WidgetTester tester, _App app) => {
  'выбранный день': shownDailyChoiceCatalogDate(tester),
  'просмотр календаря': shownDailyChoiceCatalogViewport(tester),
  'секции': (
    app.dailyChoiceCatalog.selection.incompleteExpanded,
    app.dailyChoiceCatalog.selection.completedExpanded,
  ),
  'позиция прокрутки': _dailyChoicePosition(tester).pixels,
};

/// Наблюдаемое состояние каталога дневных выборов без подписей фильтра
/// выполнения, которые следуют языку интерфейса.
Map<String, Object?> _languageIndependent(Map<String, Object?> view) =>
    Map.of(view)..remove('секции');

/// Системные подписи подготовленного каталога дневных выборов на каждом
/// языке: выбранный день, месяц и дни недели календаря, название фильтра
/// выполнения и количество.
final _catalogLabels = {
  Locale('ru'): (
    calendar: ['Август 2026', 'Пн', 'Вс'],
    content: [
      'Пятница',
      '25 сентября 2026',
      'Не выполненные',
      'Всего дневных выборов: 240',
    ],
  ),
  Locale('en'): (
    calendar: ['August 2026', 'Mon', 'Sun'],
    content: [
      'Friday',
      '25 September 2026',
      'Not completed',
      'Total daily choices: 240',
    ],
  ),
};

/// Названия команд раскрытого календаря на каждом языке.
final _calendarCommands = {
  Locale('ru'): ['Предыдущий месяц', 'Следующий месяц', 'Свернуть календарь'],
  Locale('en'): ['Previous month', 'Next month', 'Collapse calendar'],
};

/// Тексты элемента [finder] в порядке дерева; при [skipOffstage] — только
/// видимые.
List<String?> _texts(Finder finder, {bool skipOffstage = true}) => [
  for (final element
      in find
          .descendant(
            of: finder,
            matching: find.byType(Text),
            skipOffstage: skipOffstage,
          )
          .evaluate())
    (element.widget as Text).data,
];

/// Подписи выбранных условий по тегам каталога намерений.
List<String?> _conditions(WidgetTester tester) => [
  for (final label
      in find
          .descendant(
            of: find.byType(catalog_page.IntentionCatalogPage),
            matching: find.byKey(
              const ValueKey('intention-tag-condition-label'),
            ),
          )
          .evaluate())
    textIgnoringInlineWidgets(label.widget as Text),
];

ScrollPosition _positionOf(WidgetTester tester, Finder scrollView) => tester
    .state<ScrollableState>(
      find.descendant(of: scrollView, matching: find.byType(Scrollable)).first,
    )
    .position;

ScrollPosition _catalogPosition(WidgetTester tester) => _positionOf(
  tester,
  find.byKey(const PageStorageKey<String>('intention-catalog-list')),
);

/// Позиция прокрутки страницы каталога намерений: параметры поиска и выдача
/// прокручиваются вместе.
ScrollPosition _catalogPagePosition(WidgetTester tester) => _positionOf(
  tester,
  find.descendant(
    of: find.byType(catalog_page.IntentionCatalogPage),
    matching: find.byType(CustomScrollView),
  ),
);

/// Общая прокрутка страницы каталога дневных выборов: календарь, фильтры и
/// выдача прокручиваются вместе.
final _dailyChoiceScrollView = find.descendant(
  of: find.byType(daily_page.DailyChoiceCatalogPage),
  matching: find.byType(CustomScrollView),
);

/// Владелец общей прокрутки каталога дневных выборов.
///
/// Позицию прокрутки владелец создаёт заново при смене зависимостей, например
/// языка, и переносит в неё смещение; сам он живёт столько же, сколько
/// страница.
ScrollableState _dailyChoiceScrollable(WidgetTester tester) => tester.state(
  find
      .descendant(of: _dailyChoiceScrollView, matching: find.byType(Scrollable))
      .first,
);

ScrollPosition _dailyChoicePosition(WidgetTester tester) =>
    _dailyChoiceScrollable(tester).position;

/// Идентификаторы загруженных записей каталога дневных выборов в порядке
/// выдачи.
List<String> _dailyChoiceIds(_App app) => [
  for (final item in app.dailyChoiceCatalog.items) item.id.toCanonicalString(),
];

/// Строки выдачи каталога дневных выборов.
final _dailyChoiceRows = find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) => value.startsWith('daily-choice-row-'),
    _ => false,
  },
);

/// Строка выдачи каталога намерений с названием [title].
Finder _catalogRow(String title) => find.descendant(
  of: find.byType(catalog_page.IntentionCatalogPage),
  matching: find.widgetWithText(IntentionSummaryView, title),
);

String _completion(AppLocalizations l10n, bool completed) =>
    '${l10n.dailyChoiceDetailsDate(_choiceDate.toCanonicalString())} · '
    '${completed ? l10n.dailyChoiceDetailsCompleted : l10n.dailyChoiceDetailsNotCompleted}';

/// Сообщения общей поверхности в дереве, включая невыбранные вкладки.
final _builtMessages = find.byKey(_message, skipOffstage: false);

AppDestination _selected(WidgetTester tester) =>
    tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected;

Future<void> _selectScope(WidgetTester tester, String label) async {
  await _tap(tester, find.byKey(const ValueKey('catalog-scope-control')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _selectOrder(WidgetTester tester, String label) async {
  await _tap(tester, find.byKey(const ValueKey('catalog-order-control')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await _settle(tester);
}

/// Вводит фильтр названия каталога намерений и ждёт выдачу с [total]
/// совпадениями.
Future<void> _enterTitleFilter(
  WidgetTester tester,
  _App app,
  String filter, {
  required int total,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('catalog-filter-field')),
    filter,
  );
  await _until(tester, find.text(app.l10n.catalogTotalCount(total)));
  await tester.pumpAndSettle();
}

/// Выбирает [date] днём каталога дневных выборов, когда выдача начального
/// дня уже получена, и ждёт выдачу выбранного дня с [total] записями.
Future<void> _selectDay(
  WidgetTester tester,
  _App app,
  CalendarDate date, {
  required int total,
}) async {
  await _waitFor(tester, () => app.hasDailyChoiceCatalogResult);
  await selectDailyChoiceCatalogDate(tester, date, tap: _tap);
  await _until(tester, find.text(app.l10n.dailyChoiceCatalogTotalCount(total)));
  await tester.pumpAndSettle();
}

/// Выбирает пункт панели и ждёт его корневую страницу.
Future<void> _select(WidgetTester tester, AppDestination destination) async {
  await tester.tap(appNavigationDestination(destination));
  await _until(tester, find.byType(_rootPages[destination]!));
  await _settle(tester);
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
final class _ObservedRepository implements PersonalGraphRepository {
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

  /// Обращения к выдаче каталога дневных выборов.
  var dailyChoiceCatalogReads = 0;

  void holdNextCommand() => _gate = Completer<void>();

  void releaseCommand() {
    final gate = _gate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

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
  Future<DailyChoiceDayStatusesReadResult> getDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  ) => _delegate.getDailyChoiceDayStatuses(query);

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
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) {
    dailyChoiceCatalogReads++;
    return _delegate.getDailyChoiceCatalogPage(query);
  }

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => _delegate.watchIntention(id);

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => _delegate.getRelationGroupPage(query);

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      _delegate.watchRelation(id);

  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => _delegate.getChoicePathContinuations(query);

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      _delegate.getDailyChoice(id);

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      _delegate.watchDailyChoice(id);

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) =>
      _delegate.getTagCatalog(mode);

  @override
  Future<TagAssignmentsResult> getTagAssignments(IntentionId intentionId) =>
      _delegate.getTagAssignments(intentionId);

  @override
  Stream<TagReadResult> watchTag(TagId id) => _delegate.watchTag(id);
}
