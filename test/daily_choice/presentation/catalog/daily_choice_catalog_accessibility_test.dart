import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';
import 'daily_choice_catalog_page_test_support.dart';

/// Экран телефона: при обычном тексте страница с календарём, секциями и
/// двумя строками выдачи помещается целиком.
const _phone = Size(360, 780);

/// Локальное сегодня проверок — воскресенье, последний день своей недели.
final _today = date(2026, 10, 4);

/// Доступные названия заголовка дня и дней календаря на обоих языках.
final _texts = [
  (
    locale: const Locale('ru'),
    selectedToday: '4 октября 2026',
    weekday: 'Воскресенье',
    badge: 'Сегодня',
    today: 'воскресенье, 4 октября 2026\u202Fг., Сегодня',
  ),
  (
    locale: const Locale('en'),
    selectedToday: '4 October 2026',
    weekday: 'Sunday',
    badge: 'Today',
    today: 'Sunday, October 4, 2026, Today',
  ),
];

void main() {
  for (final texts in _texts) {
    final language = texts.locale.languageCode;

    group('экранный диктор на странице каталога ($language)', () {
      testWidgets('читает дни календаря, заголовок дня, секции, количество, '
          'строки и подгрузку по порядку, затем общую панель, '
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
          for (final day in weeksFrom(date(2026, 9, 28), 1).single)
            day == _today ? texts.today : _fullDate(tester, day),
          l10n.dailyChoiceCalendarExpand,
          '${texts.weekday}\n${texts.badge}',
          texts.selectedToday,
          l10n.dailyChoiceCatalogTotalCount(3),
          l10n.dailyChoiceCatalogIncomplete,
          _rowLabel(l10n, 1),
          _rowLabel(l10n, 2),
          l10n.dailyChoiceCatalogLoadMore,
          l10n.dailyChoiceCatalogCompleted,
        ];
        final announced = _announced(tester);
        expect(announced.take(page.length), page);
        expect(announced.skip(page.length), [
          startsWith(l10n.appDestinationHome),
          startsWith(l10n.appDestinationDailyChoices),
          startsWith(l10n.appDestinationIntentionGraph),
          '${l10n.quickCreationLabel}, ${l10n.quickCreationModeIntention}',
        ]);
        expect(
          find.semantics
              .byLabel(texts.selectedToday)
              .evaluate()
              .single
              .flagsCollection
              .isHeader,
          isTrue,
        );
        _expectEveryActionNamed(tester);
        semantics.dispose();
      });

      // Порядок чтения отказов не зависит от языка: подписи
      // страницы по языкам проверяет тест выше.
      if (texts != _texts.first) return;

      testWidgets('читает отказы с повтором на месте выдачи и выполняет '
          'повтор, подгрузку, раскрытие секций доступной '
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
          l10n.dailyChoiceCatalogIncomplete,
          l10n.dailyChoiceCatalogCompleted,
        ];

        repository.failUnavailable(0);
        await tester.pumpAndSettle();
        expect(_afterDayHeading(tester), [
          ...filters,
          l10n.dailyChoiceCatalogUnavailable,
          l10n.commonRetry,
        ]);
        _expectLiveRegion(tester, l10n.dailyChoiceCatalogUnavailable);

        tester.semantics.tap(find.semantics.byLabel(l10n.commonRetry));
        await tester.pump();
        expect(repository.queries, hasLength(2));
        expect(repository.queries[1].date, _today);
        expect(repository.queries[1].isCompleted, isFalse);
        expect(repository.queries[1].cursor, isNull);
        repository.completeFirst(
          1,
          [catalogPageItem(1, date: _today)],
          total: 2,
          cursor: const CatalogPageCursor(),
        );
        await tester.pumpAndSettle();
        expect(_afterDayHeading(tester), [
          l10n.dailyChoiceCatalogTotalCount(2),
          l10n.dailyChoiceCatalogIncomplete,
          _rowLabel(l10n, 1),
          l10n.dailyChoiceCatalogLoadMore,
          l10n.dailyChoiceCatalogCompleted,
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
        expect(_afterDayHeading(tester), [
          l10n.dailyChoiceCatalogTotalCount(2),
          l10n.dailyChoiceCatalogIncomplete,
          _rowLabel(l10n, 1),
          l10n.dailyChoiceCatalogUnavailable,
          l10n.commonRetry,
          l10n.dailyChoiceCatalogCompleted,
        ]);
        _expectLiveRegion(tester, l10n.dailyChoiceCatalogUnavailable);

        tester.semantics.tap(find.semantics.byLabel(l10n.commonRetry));
        await tester.pump();
        expect(repository.queries, hasLength(4));
        expect(repository.queries[3].date, _today);
        expect(repository.queries[3].cursor, isA<CatalogPageCursor>());
        repository.completeMore(3, [catalogPageItem(2, date: _today)]);
        await tester.pumpAndSettle();
        expect(_afterDayHeading(tester), [
          l10n.dailyChoiceCatalogTotalCount(2),
          l10n.dailyChoiceCatalogIncomplete,
          _rowLabel(l10n, 1),
          _rowLabel(l10n, 2),
          l10n.dailyChoiceCatalogCompleted,
        ]);

        tester.semantics.tap(
          find.semantics.byLabel(l10n.dailyChoiceCatalogIncomplete),
        );
        await tester.pumpAndSettle();
        tester.semantics.tap(
          find.semantics.byLabel(l10n.dailyChoiceCatalogCompleted),
        );
        await tester.pumpAndSettle();
        expect(repository.queries, hasLength(4));
        expect(_afterDayHeading(tester), [
          l10n.dailyChoiceCatalogTotalCount(2),
          l10n.dailyChoiceCatalogIncomplete,
          l10n.dailyChoiceCatalogCompleted,
        ]);
        expect(_announced(tester), contains(texts.selectedToday));
        semantics.dispose();
      });

      testWidgets('прокрутка страницы диктором '
          'проходит заголовок дня, секции, строки и подгрузку по порядку, '
          'и подгрузка выполняется', (tester) async {
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
          [
            for (var number = 1; number <= 20; number++)
              catalogPageItem(number, date: _today),
          ],
          total: 21,
          cursor: const CatalogPageCursor(),
        );
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);
        // Системный размер текста доходит до календаря без ограничения.

        final page = [
          '${texts.weekday}\n${texts.badge}',
          texts.selectedToday,
          l10n.dailyChoiceCatalogTotalCount(21),
          l10n.dailyChoiceCatalogIncomplete,
          for (var number = 1; number <= 20; number++) _rowLabel(l10n, number),
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

        final start = visited.indexOf(page.first);
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

/// Названия узлов общей прокрутки страницы в порядке обхода: без заголовка
/// и общей панели, которые стоят вне прокрутки.
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

/// Названия после заголовка дня: секции, выдача и сообщения,
/// без панели основной навигации.
List<String> _afterDayHeading(WidgetTester tester) {
  final nodes = tester.semantics.simulatedAccessibilityTraversal().toList();
  final heading = nodes.lastIndexWhere((node) => node.flagsCollection.isHeader);
  final navigation = nodes.indexWhere(
    (node) => node.getSemanticsData().role == SemanticsRole.tab,
  );
  return [
    for (final node in nodes.sublist(heading + 1, navigation)) ?_name(node),
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

/// Полная дата с днём недели по текущей локали.
String _fullDate(WidgetTester tester, CalendarDate value) =>
    MaterialLocalizations.of(tester.element(find.byType(DailyChoiceCalendar)))
        .formatFullDate(DateTime.utc(value.year, value.month, value.day));

/// Доступное название строки выдачи [number] за [day], по умолчанию — за
/// сегодняшний день.
String _rowLabel(AppLocalizations l10n, int number, [CalendarDate? day]) => [
  l10n.dailyChoiceCatalogRowLabel(
    number,
    l10n.dailyChoiceDetailsPhrase('Основание', 'Действие'),
    (day ?? _today).toCanonicalString(),
    l10n.dailyChoiceDetailsNotCompleted,
  ),
  l10n.dailyChoiceAllDay,
  l10n.dailyChoicePriorityOption('P4'),
  l10n.dailyChoiceCatalogPathIntentionCount(2),
].join('\n');
