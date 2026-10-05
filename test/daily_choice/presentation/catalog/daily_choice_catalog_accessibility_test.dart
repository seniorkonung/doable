import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';
import 'daily_choice_catalog_page_test_support.dart';

/// Экран телефона: при обычном тексте страница с календарём, фильтрами и
/// двумя строками выдачи помещается целиком.
const _phone = Size(360, 780);

/// Локальное сегодня проверок — воскресенье, последний день своей недели.
final _today = date(2026, 10, 4);

/// Следующий за сегодняшним день — первый день следующей недели.
final _tomorrow = date(2026, 10, 5);

/// Полные даты, которые экранный диктор читает на каждом языке. Русские даты
/// Flutter форматирует с узким неразрывным пробелом перед «г.».
final _texts = [
  (
    locale: const Locale('ru'),
    selectedToday: 'Выбранная дата: воскресенье, 4 октября 2026\u202Fг.',
    selectedTomorrow: 'Выбранная дата: понедельник, 5 октября 2026\u202Fг.',
    today: 'воскресенье, 4 октября 2026\u202Fг., Сегодня',
    tomorrow: 'понедельник, 5 октября 2026\u202Fг.',
  ),
  (
    locale: const Locale('en'),
    selectedToday: 'Selected date: Sunday, October 4, 2026',
    selectedTomorrow: 'Selected date: Monday, October 5, 2026',
    today: 'Sunday, October 4, 2026, Today',
    tomorrow: 'Monday, October 5, 2026',
  ),
];

void main() {
  for (final texts in _texts) {
    final language = texts.locale.languageCode;

    group('экранный диктор на странице каталога ($language)', () {
      testWidgets('читает шапку календаря, дни недели, фильтры, количество, '
          'строки и подгрузку по порядку, затем основное действие и панель, '
          'без отдельных чисел дней', (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = CatalogPageRepository();
        await pumpCatalogPage(
          tester,
          repository,
          today: _today,
          locale: texts.locale,
          size: _phone,
        );
        repository.completeFirst(
          0,
          [catalogPageItem(1, date: _today), catalogPageItem(2, date: _today)],
          total: 3,
          cursor: const CatalogPageCursor(),
        );
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        final page = [
          l10n.appDestinationDailyChoices,
          texts.selectedToday,
          l10n.dailyChoiceCalendarPreviousWeek,
          _monthTitle(tester, _today),
          l10n.dailyChoiceCalendarNextWeek,
          l10n.dailyChoiceCalendarExpand,
          for (final day in weeksFrom(date(2026, 9, 28), 1).single)
            day == _today ? texts.today : _fullDate(tester, day),
          _completionFilter(l10n, l10n.dailyChoiceCatalogAllStates),
          l10n.dailyChoiceCatalogClearFilters,
          l10n.dailyChoiceCatalogTotalCount(3),
          _rowLabel(l10n, 1),
          _rowLabel(l10n, 2),
          l10n.dailyChoiceCatalogLoadMore,
          l10n.dailyChoiceCreateFromAction,
        ];
        final announced = _announced(tester);
        expect(announced.take(page.length), page);
        expect(announced.skip(page.length), [
          startsWith(l10n.appDestinationHome),
          startsWith(l10n.appDestinationDailyChoices),
          startsWith(l10n.appDestinationIntentionGraph),
        ]);
        _expectEveryActionNamed(tester);
        semantics.dispose();
      });

      testWidgets('различает выбранный и сегодняшний день по отдельности и при '
          'совпадении, а выбор дня, соседние периоды, раскрытие и '
          'сворачивание выполняются доступной активацией без свайпа', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final repository = CatalogPageRepository();
        await pumpCatalogPage(
          tester,
          repository,
          today: _today,
          locale: texts.locale,
          size: _phone,
        );
        repository.completeFirst(0, [], total: 0);
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        // Сегодняшний день выбран: оба признака у одного дня.
        _expectDay(tester, texts.today, isSelected: true);
        expect(find.semantics.byLabel(_fullDate(tester, _today)), findsNothing);

        await _activateCommand(tester, l10n.dailyChoiceCalendarNextWeek);
        expect(visibleWeeks(tester), weeksFrom(_tomorrow, 1));
        expect(repository.queries, hasLength(1));

        tester.semantics.tap(find.semantics.byLabel(texts.tomorrow));
        // Выбор применён до следующего кадра.
        expect(repository.queries, hasLength(2));
        expect(repository.queries[1].date, _tomorrow);
        expect(repository.queries[1].isCompleted, isNull);
        expect(repository.queries[1].cursor, isNull);
        await _settle(tester);
        expect(_announced(tester), contains(texts.selectedTomorrow));

        await _activateCommand(tester, l10n.dailyChoiceCalendarExpand);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 5));
        // Диктор читает сегодняшний и следующий за ним выбранный день подряд.
        final announced = _announced(tester);
        final today = announced.indexOf(texts.today);
        expect(today, isNonNegative);
        expect(announced[today + 1], texts.tomorrow);
        _expectDay(tester, texts.today, isSelected: false);
        _expectDay(tester, texts.tomorrow, isSelected: true);
        expect(
          _dayNodes(
            tester,
          ).where((node) => node.flagsCollection.isSelected == Tristate.isTrue),
          hasLength(1),
        );

        await _activateCommand(tester, l10n.dailyChoiceCalendarNextMonth);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
        // Выбранный день вне просматриваемого месяца остаётся названным.
        expect(_announced(tester), contains(texts.selectedTomorrow));
        await _activateCommand(tester, l10n.dailyChoiceCalendarPreviousMonth);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 5));
        // Перелистывание месяца переносит дату просмотра в его первый день,
        // поэтому сворачивается неделя 1 октября.
        await _activateCommand(tester, l10n.dailyChoiceCalendarCollapse);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));
        _expectDay(tester, texts.today, isSelected: false);
        await _activateCommand(tester, l10n.dailyChoiceCalendarNextWeek);
        expect(visibleWeeks(tester), weeksFrom(_tomorrow, 1));
        _expectDay(tester, texts.tomorrow, isSelected: true);
        await _activateCommand(tester, l10n.dailyChoiceCalendarPreviousWeek);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));

        // Просмотр периодов и смена представления ничего не читают.
        expect(repository.queries, hasLength(2));
        repository.completeFirst(1, [
          catalogPageItem(1, date: _tomorrow),
        ], total: 1);
        await _settle(tester);
        expect(_announced(tester), contains(_rowLabel(l10n, 1, _tomorrow)));
        semantics.dispose();
      });

      testWidgets('читает отказы с повтором на месте выдачи и выполняет '
          'повтор, подгрузку, фильтр выполнения и сброс доступной '
          'активацией для выбранного дня', (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = CatalogPageRepository();
        await pumpCatalogPage(
          tester,
          repository,
          today: _today,
          locale: texts.locale,
          size: _phone,
        );
        final l10n = _l10n(tester);
        final filters = [
          _completionFilter(l10n, l10n.dailyChoiceCatalogAllStates),
          l10n.dailyChoiceCatalogClearFilters,
        ];

        repository.failUnavailable(0);
        await tester.pumpAndSettle();
        expect(_afterCalendar(tester), [
          ...filters,
          l10n.dailyChoiceCatalogUnavailable,
          l10n.commonRetry,
          l10n.dailyChoiceCreateFromAction,
        ]);
        _expectLiveRegion(tester, l10n.dailyChoiceCatalogUnavailable);

        tester.semantics.tap(find.semantics.byLabel(l10n.commonRetry));
        await tester.pump();
        expect(repository.queries, hasLength(2));
        expect(repository.queries[1].date, _today);
        expect(repository.queries[1].isCompleted, isNull);
        expect(repository.queries[1].cursor, isNull);
        repository.completeFirst(
          1,
          [catalogPageItem(1, date: _today)],
          total: 2,
          cursor: const CatalogPageCursor(),
        );
        await tester.pumpAndSettle();
        expect(_afterCalendar(tester), [
          ...filters,
          l10n.dailyChoiceCatalogTotalCount(2),
          _rowLabel(l10n, 1),
          l10n.dailyChoiceCatalogLoadMore,
          l10n.dailyChoiceCreateFromAction,
        ]);

        tester.semantics.tap(
          find.semantics.byLabel(l10n.dailyChoiceCatalogLoadMore),
        );
        await tester.pump();
        expect(repository.queries, hasLength(3));
        expect(repository.queries[2].date, _today);
        expect(repository.queries[2].cursor, isA<CatalogPageCursor>());
        repository.failUnavailable(2);
        await tester.pumpAndSettle();
        // Отказ подгрузки читается после загруженной строки.
        expect(_afterCalendar(tester), [
          ...filters,
          l10n.dailyChoiceCatalogTotalCount(2),
          _rowLabel(l10n, 1),
          l10n.dailyChoiceCatalogUnavailable,
          l10n.commonRetry,
          l10n.dailyChoiceCreateFromAction,
        ]);
        _expectLiveRegion(tester, l10n.dailyChoiceCatalogUnavailable);

        tester.semantics.tap(find.semantics.byLabel(l10n.commonRetry));
        await tester.pump();
        expect(repository.queries, hasLength(4));
        expect(repository.queries[3].date, _today);
        expect(repository.queries[3].cursor, isA<CatalogPageCursor>());
        repository.completeMore(3, [catalogPageItem(2, date: _today)]);
        await tester.pumpAndSettle();
        expect(_afterCalendar(tester), [
          ...filters,
          l10n.dailyChoiceCatalogTotalCount(2),
          _rowLabel(l10n, 1),
          _rowLabel(l10n, 2),
          l10n.dailyChoiceCreateFromAction,
        ]);

        tester.semantics.tap(find.semantics.byLabel(filters.first));
        await tester.pumpAndSettle();
        tester.semantics.tap(
          find.semantics.byLabel(l10n.dailyChoiceCatalogIncomplete),
        );
        await tester.pump();
        expect(repository.queries, hasLength(5));
        expect(repository.queries[4].date, _today);
        expect(repository.queries[4].isCompleted, isFalse);
        expect(repository.queries[4].cursor, isNull);
        repository.completeFirst(4, [], total: 0);
        await tester.pumpAndSettle();
        expect(_afterCalendar(tester), [
          _completionFilter(l10n, l10n.dailyChoiceCatalogIncomplete),
          l10n.dailyChoiceCatalogClearFilters,
          l10n.dailyChoiceCatalogTotalCount(0),
          l10n.dailyChoiceCatalogEmpty,
          l10n.dailyChoiceCreateFromAction,
        ]);

        tester.semantics.tap(
          find.semantics.byLabel(l10n.dailyChoiceCatalogClearFilters),
        );
        await tester.pump();
        expect(repository.queries, hasLength(6));
        expect(repository.queries[5].date, _today);
        expect(repository.queries[5].isCompleted, isNull);
        expect(repository.queries[5].cursor, isNull);
        expect(_announced(tester), contains(texts.selectedToday));
        semantics.dispose();
      });

      testWidgets('при масштабе текста 2.5 прокрутка страницы диктором '
          'проходит календарь, фильтры, строки и подгрузку в том же порядке, '
          'и подгрузка выполняется', (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = CatalogPageRepository();
        await pumpCatalogPage(
          tester,
          repository,
          today: _today,
          locale: texts.locale,
          size: _phone,
          textScale: 2.5,
        );
        repository.completeFirst(
          0,
          [catalogPageItem(1, date: _today), catalogPageItem(2, date: _today)],
          total: 3,
          cursor: const CatalogPageCursor(),
        );
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);
        // Системный размер текста доходит до календаря без ограничения.
        expect(
          MediaQuery.textScalerOf(
            tester.element(find.byType(DailyChoiceCalendar)),
          ).scale(10),
          25,
        );

        final page = [
          texts.selectedToday,
          l10n.dailyChoiceCalendarPreviousWeek,
          _monthTitle(tester, _today),
          l10n.dailyChoiceCalendarNextWeek,
          l10n.dailyChoiceCalendarExpand,
          for (final day in weeksFrom(date(2026, 9, 28), 1).single)
            day == _today ? texts.today : _fullDate(tester, day),
          _completionFilter(l10n, l10n.dailyChoiceCatalogAllStates),
          l10n.dailyChoiceCatalogClearFilters,
          l10n.dailyChoiceCatalogTotalCount(3),
          _rowLabel(l10n, 1),
          _rowLabel(l10n, 2),
          l10n.dailyChoiceCatalogLoadMore,
        ];

        // Диктор продвигается по странице командой прокрутки, как при
        // переходе за край видимой части.
        final visited = <String>[];
        for (var step = 0; step < 30; step++) {
          for (final name in _announcedInScroll(tester)) {
            if (!visited.contains(name)) visited.add(name);
          }
          if (visited.contains(l10n.dailyChoiceCatalogLoadMore)) break;
          tester.semantics.scrollUp(
            scrollable: find.semantics.scrollable(axis: Axis.vertical),
          );
          await tester.pumpAndSettle();
        }

        final start = visited.indexOf(texts.selectedToday);
        final end = visited.indexOf(l10n.dailyChoiceCatalogLoadMore);
        expect(start, isNonNegative);
        expect(end, greaterThan(start));
        expect(visited.sublist(start, end + 1), page);

        tester.semantics.tap(
          find.semantics.byLabel(l10n.dailyChoiceCatalogLoadMore),
        );
        await tester.pump();
        expect(repository.queries, hasLength(2));
        expect(repository.queries[1].date, _today);
        expect(repository.queries[1].cursor, isA<CatalogPageCursor>());
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    });
  }
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(DailyChoiceCalendar)));

/// Названия узлов в порядке обхода экранным диктором: доступное название
/// вместе с объединёнными потомками или, у кнопок со всплывающей подсказкой,
/// её текст.
List<String> _announced(WidgetTester tester) => [
  for (final node in tester.semantics.simulatedAccessibilityTraversal())
    ?_name(node),
];

/// Названия узлов общей прокрутки страницы в порядке обхода: без заголовка,
/// основного действия и панели, которые стоят вне прокрутки.
List<String> _announcedInScroll(WidgetTester tester) {
  final scroll = find.semantics
      .scrollable(axis: Axis.vertical)
      .evaluate()
      .single;
  bool inScroll(SemanticsNode node) {
    for (var parent = node.parent; parent != null; parent = parent.parent) {
      if (identical(parent, scroll)) return true;
    }
    return false;
  }

  return [
    for (final node in tester.semantics.simulatedAccessibilityTraversal())
      if (inScroll(node)) ?_name(node),
  ];
}

/// Названия после последнего дня календаря: фильтры, выдача, сообщения и
/// основное действие страницы, без панели основной навигации.
List<String> _afterCalendar(WidgetTester tester) {
  final nodes = tester.semantics.simulatedAccessibilityTraversal().toList();
  final lastDay = nodes.lastIndexWhere(
    (node) =>
        node.flagsCollection.isSelected != Tristate.none &&
        node.getSemanticsData().role != SemanticsRole.tab,
  );
  final navigation = nodes.indexWhere(
    (node) => node.getSemanticsData().role == SemanticsRole.tab,
  );
  return [
    for (final node in nodes.sublist(lastDay + 1, navigation)) ?_name(node),
  ];
}

String? _name(SemanticsNode node) {
  final data = node.getSemanticsData();
  return data.label.isNotEmpty
      ? data.label
      : data.tooltip.isNotEmpty
      ? data.tooltip
      : null;
}

/// Каждый узел, предлагающий касание, назван.
void _expectEveryActionNamed(WidgetTester tester) {
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    if (node.getSemanticsData().hasAction(SemanticsAction.tap)) {
      expect(_name(node), isNotNull, reason: '$node');
    }
  }
}

/// Дни календаря в порядке обхода: только у них и пунктов панели есть
/// состояние выбранности.
List<SemanticsNode> _dayNodes(WidgetTester tester) => [
  for (final node in tester.semantics.simulatedAccessibilityTraversal())
    if (node.flagsCollection.isSelected != Tristate.none &&
        node.getSemanticsData().role != SemanticsRole.tab)
      node,
];

/// День объявляется одной кнопкой выбора с явным состоянием выбранности.
void _expectDay(WidgetTester tester, String label, {required bool isSelected}) {
  final node = find.semantics.byLabel(label).evaluate().single;
  expect(node.flagsCollection.isButton, isTrue, reason: label);
  expect(
    node.getSemanticsData().actions,
    SemanticsAction.tap.index,
    reason: '$label: доступно только действие выбора',
  );
  expect(
    node.flagsCollection.isSelected,
    isSelected ? Tristate.isTrue : Tristate.isFalse,
    reason: label,
  );
}

/// Сообщение объявляется при появлении без перехода к нему.
void _expectLiveRegion(WidgetTester tester, String message) {
  expect(
    find.semantics
        .byLabel(message)
        .evaluate()
        .single
        .flagsCollection
        .isLiveRegion,
    isTrue,
    reason: message,
  );
}

/// Выполняет команду шапки календаря доступной активацией по её названию.
Future<void> _activateCommand(WidgetTester tester, String name) async {
  tester.semantics.tap(
    find.semantics.byPredicate((node) => node.tooltip == name),
  );
  await _settle(tester);
}

/// Доводит до конца перелистывание календаря. Индикатор загрузки выдачи не
/// даёт дождаться покоя всех анимаций, поэтому время продвигается явно.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Полная дата с днём недели по текущей локали.
String _fullDate(WidgetTester tester, CalendarDate value) =>
    MaterialLocalizations.of(tester.element(find.byType(DailyChoiceCalendar)))
        .formatFullDate(DateTime.utc(value.year, value.month, value.day));

/// Месяц и год по текущей локали.
String _monthTitle(WidgetTester tester, CalendarDate value) =>
    MaterialLocalizations.of(tester.element(find.byType(DailyChoiceCalendar)))
        .formatMonthYear(DateTime.utc(value.year, value.month));

/// Фильтр выполнения читается своим названием и выбранным состоянием.
String _completionFilter(AppLocalizations l10n, String state) =>
    '${l10n.dailyChoiceCatalogCompletionFilter}\n$state';

/// Доступное название строки выдачи [number] за [day], по умолчанию — за
/// сегодняшний день.
String _rowLabel(AppLocalizations l10n, int number, [CalendarDate? day]) =>
    l10n.dailyChoiceCatalogRowLabel(
      number,
      l10n.dailyChoiceDetailsPhrase('Основание', 'Действие'),
      (day ?? _today).toCanonicalString(),
      l10n.dailyChoiceDetailsNotCompleted,
    );
