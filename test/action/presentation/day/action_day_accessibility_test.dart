import 'dart:ui' show Tristate, CheckedState;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/action_panel_controls.dart';
import 'action_day_calendar_test_support.dart';
import 'action_day_page_test_support.dart';
import 'action_day_panel_repository.dart';

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

    group('экранный диктор на экране дня ($language)', () {
      testWidgets('независимо переключает выполнение и открывает действие, '
          'читает сохранённое состояние и недоступность при записи', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final repository = ActionDayRepository();
        final panels = ActionDayPanelRepository(repository);
        final completed = language == 'en';
        final item = actionDayItem(1, date: _today, isCompleted: completed);
        final router = await pumpActionDay(
          tester,
          panels,
          today: _today,
          locale: texts.locale,
          size: _phone,
        );
        repository.completeFirst(0, [item], total: 1);
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);
        final checkbox = find.semantics.byLabel(_completionLabel(l10n, 1));
        final initial = checkbox.evaluate().single;
        expect(
          initial.flagsCollection.isChecked,
          completed ? CheckedState.isTrue : CheckedState.isFalse,
        );
        expect(initial.flagsCollection.isEnabled, Tristate.isTrue);
        expect(
          initial.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        final route = router.current.name;
        tester.semantics.tap(checkbox);
        await tester.pump();
        expect(router.current.name, route);
        expect(repository.completionCommands.single.actionId, item.id);
        final pending = checkbox.evaluate().single;
        expect(
          pending.flagsCollection.isChecked,
          completed ? CheckedState.isTrue : CheckedState.isFalse,
        );
        expect(pending.flagsCollection.isEnabled, Tristate.isFalse);
        expect(
          pending.getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
        );
        repository.failCompletion(0, const ActionUnavailableFailure());
        await tester.pumpAndSettle();
        _expectLiveRegion(tester, l10n.actionOperationUnavailable);
        final opening = find.semantics.byLabel(_rowLabel(l10n, 1, completed));
        expect(opening.evaluate().single.flagsCollection.isButton, isTrue);
        tester.semantics.tap(opening);
        await tester.pump();
        expect(shownActionId(tester), item.id);
        expect(repository.completionCommands, hasLength(1));
        semantics.dispose();
      });

      testWidgets('обе секции доступны при переходе по заголовкам; '
          'читает дни календаря, заголовок дня, секции, '
          'строки и подгрузку по порядку, затем общую панель, '
          'без отдельных чисел дней', (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = ActionDayRepository();
        await pumpActionDay(
          tester,
          repository,
          today: _today,
          locale: texts.locale,
          size: _phone,
        );
        repository.completeFirst(0, [
          actionDayItem(1, date: _today),
          actionDayItem(2, date: _today),
        ], total: 2);
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        final page = [
          for (final day in weeksFrom(date(2026, 9, 28), 1).single)
            day == _today ? texts.today : _fullDate(tester, day),
          l10n.actionCalendarExpand,
          '${texts.weekday}\n${texts.badge}',
          texts.selectedToday,
          _sectionLabel(l10n, ActionDaySection.incomplete, count: 2),
          _completionLabel(l10n, 1),
          _rowLabel(l10n, 1),
          _completionLabel(l10n, 2),
          _rowLabel(l10n, 2),
          _sectionLabel(l10n, ActionDaySection.completed, count: 0),
        ];
        final announced = _announced(tester);
        expect(announced.take(page.length), page);
        expect(announced.skip(page.length), [
          startsWith(l10n.appDestinationHome),
          startsWith(l10n.appDestinationActions),
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

        for (final section in [
          (
            label: _sectionLabel(l10n, ActionDaySection.incomplete, count: 2),
            expanded: true,
          ),
          (
            label: _sectionLabel(l10n, ActionDaySection.completed, count: 0),
            expanded: true,
          ),
        ]) {
          final command = find.semantics.byLabel(section.label);
          for (final expanded in [section.expanded, !section.expanded]) {
            final node = command.evaluate().single;
            expect(
              node.flagsCollection.isHeader,
              isTrue,
              reason: section.label,
            );
            expect(
              node.flagsCollection.isExpanded,
              expanded ? Tristate.isTrue : Tristate.isFalse,
              reason: section.label,
            );
            expect(
              node.getSemanticsData().hasAction(SemanticsAction.tap),
              isTrue,
              reason: section.label,
            );
            tester.semantics.tap(command);
            await tester.pumpAndSettle();
          }
        }
        expect(_announced(tester), announced);
        semantics.dispose();
      });

      // Порядок чтения отказов не зависит от языка: подписи
      // страницы по языкам проверяет тест выше.
      if (texts != _texts.first) return;

      testWidgets('читает подгрузку и отказы с повтором на месте выдачи и '
          'выполняет повтор и раскрытие секций доступной активацией для '
          'выбранного дня', (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = ActionDayRepository();
        await pumpActionDay(
          tester,
          repository,
          today: _today,
          locale: texts.locale,
          size: _phone,
        );
        final l10n = _l10n(tester);

        repository.failUnavailable(0);
        await tester.pumpAndSettle();
        expect(_afterDayHeading(tester), [
          l10n.actionDayUnavailable,
          l10n.commonRetry,
        ]);
        _expectLiveRegion(tester, l10n.actionDayUnavailable);

        tester.semantics.tap(find.semantics.byLabel(l10n.commonRetry));
        await tester.pump();
        expect(repository.queries, hasLength(2));
        expect(repository.queries[1].date, _today);
        expect(repository.queries[1].section, ActionDaySection.incomplete);
        expect(repository.queries[1].cursor, isNull);
        repository.completeFirst(
          1,
          [actionDayItem(1, date: _today)],
          total: 2,
          cursor: const ActionDayTestCursor(),
        );
        await tester.pump();
        await tester.pump();
        expect(_afterDayHeading(tester), [
          _sectionLabel(l10n, ActionDaySection.incomplete, count: 2),
          _completionLabel(l10n, 1),
          _rowLabel(l10n, 1),
          l10n.actionDayLoadingMore,
          _sectionLabel(l10n, ActionDaySection.completed, count: 0),
        ]);
        _expectLiveRegion(tester, l10n.actionDayLoadingMore);

        expect(repository.queries, hasLength(3));
        expect(repository.queries[2].date, _today);
        expect(repository.queries[2].cursor, isA<ActionDayTestCursor>());
        repository.failUnavailable(2);
        await tester.pumpAndSettle();
        // Отказ подгрузки читается после загруженной строки.
        expect(_afterDayHeading(tester), [
          _sectionLabel(l10n, ActionDaySection.incomplete, count: 2),
          _completionLabel(l10n, 1),
          _rowLabel(l10n, 1),
          l10n.actionDayUnavailable,
          l10n.commonRetry,
          _sectionLabel(l10n, ActionDaySection.completed, count: 0),
        ]);
        _expectLiveRegion(tester, l10n.actionDayUnavailable);

        tester.semantics.tap(find.semantics.byLabel(l10n.commonRetry));
        await tester.pump();
        expect(repository.queries, hasLength(4));
        expect(repository.queries[3].date, _today);
        expect(repository.queries[3].cursor, isA<ActionDayTestCursor>());
        repository.completeMore(3, [actionDayItem(2, date: _today)]);
        await tester.pumpAndSettle();
        expect(_afterDayHeading(tester), [
          _sectionLabel(l10n, ActionDaySection.incomplete, count: 2),
          _completionLabel(l10n, 1),
          _rowLabel(l10n, 1),
          _completionLabel(l10n, 2),
          _rowLabel(l10n, 2),
          _sectionLabel(l10n, ActionDaySection.completed, count: 0),
        ]);

        tester.semantics.tap(
          find.semantics.byLabel(
            _sectionLabel(l10n, ActionDaySection.incomplete, count: 2),
          ),
        );
        await tester.pumpAndSettle();
        tester.semantics.tap(
          find.semantics.byLabel(
            _sectionLabel(l10n, ActionDaySection.completed, count: 0),
          ),
        );
        await tester.pumpAndSettle();
        expect(repository.queries, hasLength(4));
        expect(_afterDayHeading(tester), [
          _sectionLabel(l10n, ActionDaySection.incomplete, count: 2),
          _sectionLabel(l10n, ActionDaySection.completed, count: 0),
        ]);
        expect(_announced(tester), contains(texts.selectedToday));
        semantics.dispose();
      });

      testWidgets('прокрутка страницы диктором '
          'проходит заголовок дня, секции, строки и подгрузку по порядку '
          'и сама запрашивает порцию', (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = ActionDayRepository();
        await pumpActionDay(
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
              actionDayItem(number, date: _today),
          ],
          total: 21,
          cursor: const ActionDayTestCursor(),
        );
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);
        // Системный размер текста доходит до календаря без ограничения.

        final page = [
          '${texts.weekday}\n${texts.badge}',
          texts.selectedToday,
          _sectionLabel(l10n, ActionDaySection.incomplete, count: 21),
          for (var number = 1; number <= 20; number++) ...[
            _completionLabel(l10n, number),
            _rowLabel(l10n, number),
          ],
          l10n.actionDayLoadingMore,
        ];

        // Диктор продвигается по странице командой прокрутки, как при
        // переходе за край видимой части.
        final visited = <String>[];
        for (var step = 0; step < 30; step++) {
          for (final name in _announcedInScroll(tester)) {
            if (!visited.contains(name)) visited.add(name);
          }
          if (visited.contains(l10n.actionDayLoadingMore)) break;
          tester.semantics.scrollUp(
            scrollable: find.semantics.scrollable(axis: Axis.vertical),
          );
          // Кольцо подгрузки не даёт дождаться покоя всех анимаций.
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
        }

        final start = visited.indexOf(page.first);
        final end = visited.indexOf(l10n.actionDayLoadingMore);
        expect(start, isNonNegative);
        expect(end, greaterThan(start));
        expect(visited.sublist(start, end + 1), page);

        expect(repository.queries, hasLength(2));
        expect(repository.queries[1].date, _today);
        expect(repository.queries[1].cursor, isA<ActionDayTestCursor>());
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    });
  }
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ActionDayCalendar)));

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
  final heading = nodes.indexWhere((node) => node.flagsCollection.isHeader);
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
    MaterialLocalizations.of(tester.element(find.byType(ActionDayCalendar)))
        .formatFullDate(DateTime.utc(value.year, value.month, value.day));

/// Доступное название строки выдачи [number].
String _rowLabel(AppLocalizations l10n, int number, [bool completed = false]) =>
    [
      l10n.actionDayRowLabel(number, 'Действие'),
      l10n.actionDayRowRoot('Основание'),
      l10n.actionDayPathIntentionCount(2),
      l10n.actionAllDay,
      completed ? l10n.actionCompleted : l10n.actionNotCompleted,
    ].join('\n');

/// Доступное название заголовка секции: название и число действий.
String _sectionLabel(
  AppLocalizations l10n,
  ActionDaySection section, {
  required int count,
}) =>
    '${switch (section) {
      ActionDaySection.incomplete => l10n.actionDaySectionIncomplete,
      ActionDaySection.completed => l10n.actionDaySectionCompleted,
    }}\n$count';

String _completionLabel(AppLocalizations l10n, int number) =>
    l10n.localeName == 'ru'
    ? 'Выполнение действия № $number. Действие. Приоритет P4'
    : 'Completion of action #$number. Действие. Priority P4';
