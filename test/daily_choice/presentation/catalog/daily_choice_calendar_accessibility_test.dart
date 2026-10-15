import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';

/// Ожидаемые доступные названия на обоих языках. Русские даты Flutter
/// форматирует с узким неразрывным пробелом перед «г.».
final _localizedTexts = [
  (
    locale: const Locale('ru'),
    selectedDate: 'Выбранная дата: воскресенье, 4 октября 2026 г.',
    october: 'Октябрь 2026',
    todayOctober4: 'воскресенье, 4 октября 2026 г., Сегодня',
    october5: 'понедельник, 5 октября 2026 г.',
    september28: 'понедельник, 28 сентября 2026 г.',
    weekdays: ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'],
    previousWeek: 'Предыдущая неделя',
    nextWeek: 'Следующая неделя',
    previousMonth: 'Предыдущий месяц',
    nextMonth: 'Следующий месяц',
    expand: 'Развернуть календарь',
    collapse: 'Свернуть календарь',
    allCompleted: 'Все дневные выборы выполнены',
    hasIncomplete: 'Есть невыполненный дневной выбор',
    marksUnavailable: 'Отметки дней не загружены.',
  ),
  (
    locale: const Locale('en'),
    selectedDate: 'Selected date: Sunday, October 4, 2026',
    october: 'October 2026',
    todayOctober4: 'Sunday, October 4, 2026, Today',
    october5: 'Monday, October 5, 2026',
    september28: 'Monday, September 28, 2026',
    weekdays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    previousWeek: 'Previous week',
    nextWeek: 'Next week',
    previousMonth: 'Previous month',
    nextMonth: 'Next month',
    expand: 'Expand calendar',
    collapse: 'Collapse calendar',
    allCompleted: 'All daily choices are completed',
    hasIncomplete: 'There is an incomplete daily choice',
    marksUnavailable: 'Day marks could not be loaded.',
  ),
];

void main() {
  for (final texts in _localizedTexts) {
    final language = texts.locale.languageCode;

    group('экранный диктор ($language)', () {
      testWidgets(
        'читает шапку и затем каждый день месяца в календарном порядке '
        'полной датой с днём недели, без отдельного числа',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await pumpCalendarConsumer(
            tester,
            selectedDate: date(2026, 10, 4),
            viewport: month(date(2026, 10, 4)),
            today: date(2026, 10, 4),
            locale: texts.locale,
          );

          final days = weeksFrom(date(2026, 9, 28), 6).expand((row) => row);
          expect(_announced(tester), [
            texts.selectedDate,
            texts.previousMonth,
            texts.october,
            texts.nextMonth,
            for (final day in days)
              _dayLabel(tester, day, isToday: day == date(2026, 10, 4)),
            texts.collapse,
          ]);
          final title = find.semantics.byLabel(texts.october).evaluate().single;
          expect(title.flagsCollection.isButton, isFalse);
          expect(title.getSemanticsData().actions, 0);
          // День соседнего месяца назван своей полной датой.
          expect(_announced(tester), contains(texts.september28));
          expect(_announced(tester), contains(texts.todayOctober4));
          semantics.dispose();
        },
      );

      testWidgets('состояние дня дополняет дату и «сегодня», сохраняя '
          'выбранность; строка отказа читается под шапкой без действий', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 5),
          viewport: month(date(2026, 10, 4)),
          today: date(2026, 10, 4),
          locale: texts.locale,
          dayStatuses: {
            date(2026, 10, 4): DailyChoiceDayStatus.allCompleted,
            date(2026, 10, 5): DailyChoiceDayStatus.hasIncomplete,
          },
          hasDayMarksReadFailure: true,
        );
        final completed = '${texts.todayOctober4}, ${texts.allCompleted}';
        final incomplete = '${texts.october5}, ${texts.hasIncomplete}';
        _expectDay(tester, completed, isSelected: false);
        _expectDay(tester, incomplete, isSelected: true);
        _expectDay(
          tester,
          _dayLabel(tester, date(2026, 10, 7)),
          isSelected: false,
        );
        expect(
          _announced(tester),
          containsAllInOrder([
            texts.marksUnavailable,
            texts.september28,
            completed,
            incomplete,
            texts.collapse,
          ]),
        );
        final failure = find.semantics.byLabel(texts.marksUnavailable);
        expect(failure, findsOne);
        expect(failure.evaluate().single.getSemanticsData().actions, 0);
        expect(find.byType(SnackBar), findsNothing);

        tester.semantics.tap(find.semantics.byLabel(completed));
        await tester.pumpAndSettle();
        _expectDay(tester, completed, isSelected: true);
        expect(consumer.events, [DateSelected(date(2026, 10, 4))]);

        consumer.replaceInputs(dayStatuses: {});
        await tester.pumpAndSettle();
        _expectDay(tester, texts.todayOctober4, isSelected: true);
        expect(find.semantics.byLabel(completed), findsNothing);
        expect(failure, findsOne);
        semantics.dispose();
      });

      // Остальные проверки не зависят от языка: подписи по языкам читает тест
      // выше.
      if (texts != _localizedTexts.first) return;

      testWidgets('различает сегодняшний 2026-10-04 и выбранный 2026-10-05 при '
          'последовательном чтении', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 5),
          viewport: month(date(2026, 10, 5)),
          today: date(2026, 10, 4),
          locale: texts.locale,
        );

        final announced = _announced(tester);
        final today = announced.indexOf(texts.todayOctober4);
        expect(today, isNonNegative);
        expect(announced[today + 1], texts.october5);

        _expectDay(tester, texts.todayOctober4, isSelected: false);
        _expectDay(tester, texts.october5, isSelected: true);
        _expectDay(tester, texts.september28, isSelected: false);
        // Каждый показанный день — одна кнопка выбора с состоянием
        // выбранности; выбран ровно один.
        final dayNodes = _dayNodes(tester);
        expect(dayNodes, hasLength(42));
        for (final node in dayNodes) {
          _expectSingleSelectAction(node);
        }
        expect(
          dayNodes.where(
            (node) => node.flagsCollection.isSelected == Tristate.isTrue,
          ),
          hasLength(1),
        );
        semantics.dispose();
      });

      testWidgets('выбранный сегодняшний день сохраняет оба признака', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: week(date(2026, 10, 4)),
          today: date(2026, 10, 4),
          locale: texts.locale,
        );

        _expectDay(tester, texts.todayOctober4, isSelected: true);
        expect(_dayNodes(tester), hasLength(7));
        for (final node in _dayNodes(tester)) {
          _expectSingleSelectAction(node);
        }
        expect(
          find.semantics.byLabel(_dayLabel(tester, date(2026, 10, 4))),
          findsNothing,
        );
        semantics.dispose();
      });

      testWidgets(
        'команды сообщают назначение и доступность, а у пределов диапазона '
        'переход недоступен, недопустимые позиции молчат',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final consumer = await pumpCalendarConsumer(
            tester,
            selectedDate: date(9999, 12, 31),
            viewport: week(date(9999, 12, 31)),
            today: date(2026, 10, 4),
            locale: texts.locale,
          );

          _expectNoWeekCommands(tester, texts.previousWeek, texts.nextWeek);

          expect(
            _command(texts.expand).evaluate().single.flagsCollection.isExpanded,
            Tristate.isFalse,
          );
          // Суббота и воскресенье за 9999-12-31 сохраняют место в строке, но
          // не объявляются и не предлагают выбор.
          expect(unavailableCalendarDays, findsNWidgets(2));
          final lastDays = [
            for (var day = 27; day <= 31; day++) date(9999, 12, day),
          ];
          expect(_dayNodes(tester).map((node) => node.label), [
            for (final day in lastDays) _dayLabel(tester, day),
          ]);
          expect(_actionable(tester), [
            for (final day in lastDays) _dayLabel(tester, day),
            texts.expand,
          ]);
          _expectDay(
            tester,
            _dayLabel(tester, date(9999, 12, 31)),
            isSelected: true,
          );

          consumer.replaceInputs(viewport: month(date(9999, 12, 31)));
          await tester.pumpAndSettle();
          _expectCommand(tester, texts.previousMonth, isEnabled: true);
          _expectCommand(tester, texts.nextMonth, isEnabled: false);
          expect(
            _command(texts.collapse)
                .evaluate()
                .single
                .flagsCollection
                .isExpanded,
            Tristate.isTrue,
          );
          expect(unavailableCalendarDays, findsNWidgets(9));
          expect(_dayNodes(tester), hasLength(33));

          consumer.replaceInputs(
            selectedDate: date(1, 1, 1),
            viewport: week(date(1, 1, 1)),
          );
          await tester.pumpAndSettle();
          _expectNoWeekCommands(tester, texts.previousWeek, texts.nextWeek);

          final firstDays = weeksFrom(date(1, 1, 1), 1).single;
          expect(_dayNodes(tester).map((node) => node.label), [
            for (final day in firstDays) _dayLabel(tester, day),
          ]);
          _expectDay(
            tester,
            _dayLabel(tester, date(1, 1, 1)),
            isSelected: true,
          );

          consumer.replaceInputs(viewport: month(date(1, 1, 1)));
          await tester.pumpAndSettle();
          _expectCommand(tester, texts.previousMonth, isEnabled: false);
          _expectCommand(tester, texts.nextMonth, isEnabled: true);
          expect(_dayNodes(tester), hasLength(42));
          expect(consumer.events, isEmpty);
          semantics.dispose();
        },
      );

      testWidgets(
        'доступная активация команд и дня без свайпа даёт те же события, '
        'что нажатие',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final byTouch = await _controlWithoutSwipes(
            tester,
            texts.locale,
            activateCommand: (name) => tester.tap(find.bySemanticsLabel(name)),
            activateDay: (value) => tester.tap(calendarDay(value)),
          );
          final byScreenReader = await _controlWithoutSwipes(
            tester,
            texts.locale,
            activateCommand: (name) async =>
                tester.semantics.tap(_command(name)),
            activateDay: (value) async => tester.semantics.tap(
              find.semantics.byLabel(_dayLabel(tester, value)),
            ),
          );

          expect(byScreenReader, byTouch);
          expect(byScreenReader, [
            ViewportChanged(month(date(2026, 10, 4))),
            DateSelected(date(2026, 10, 7)),
            ViewportChanged(month(date(2026, 11, 1))),
            ViewportChanged(week(date(2026, 11, 1))),
          ]);
          semantics.dispose();
        },
      );
    });
  }

  testWidgets('неподдерживаемый язык устройства даёт английские названия', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final english = _localizedTexts.last;
    await pumpCalendarConsumer(
      tester,
      selectedDate: date(2026, 10, 5),
      viewport: week(date(2026, 10, 4)),
      today: date(2026, 10, 4),
      locale: const Locale('de', 'DE'),
    );

    expect(_announced(tester), [
      'Selected date: Monday, October 5, 2026',
      for (final day in weeksFrom(date(2026, 9, 28), 1).single)
        _dayLabel(tester, day, isToday: day == date(2026, 10, 4)),
      english.expand,
    ]);
    expect(_announced(tester), contains(english.todayOctober4));
    for (final weekday in english.weekdays) {
      expect(find.text(weekday), findsOneWidget, reason: weekday);
    }
    semantics.dispose();
  });

  testWidgets(
    'новый сегодняшний день переносит обозначение без событий и без смены '
    'выбора и просмотра',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 5),
        viewport: week(date(2026, 10, 5)),
        today: date(2026, 10, 6),
      );
      expect(
        find.semantics.byLabel(
          _dayLabel(tester, date(2026, 10, 6), isToday: true),
        ),
        findsOne,
      );

      consumer.replaceInputs(today: date(2026, 10, 7));
      await tester.pumpAndSettle();

      expect(_dayNodes(tester).map((node) => node.label), [
        for (final day in weeksFrom(date(2026, 10, 5), 1).single)
          _dayLabel(tester, day, isToday: day == date(2026, 10, 7)),
      ]);
      expect(dayCell(tester, date(2026, 10, 6)).isToday, isFalse);
      expect(dayCell(tester, date(2026, 10, 7)).isToday, isTrue);
      _expectDay(
        tester,
        _dayLabel(tester, date(2026, 10, 5)),
        isSelected: true,
      );
      expect(consumer.selectedDate, date(2026, 10, 5));
      expect(consumer.viewport, week(date(2026, 10, 5)));
      expect(consumer.events, isEmpty);
      semantics.dispose();
    },
  );
}

/// Узлы, которые экранный диктор читает в порядке обхода: доступное название
/// или, у кнопок со всплывающей подсказкой, её текст.
List<String> _announced(WidgetTester tester) => [
  for (final node in tester.semantics.simulatedAccessibilityTraversal())
    ?_name(node),
];

/// Узлы, предлагающие касание, в порядке обхода.
List<String> _actionable(WidgetTester tester) => [
  for (final node in tester.semantics.simulatedAccessibilityTraversal())
    if (node.getSemanticsData().hasAction(SemanticsAction.tap))
      _name(node) ?? '<без названия>',
];

String? _name(SemanticsNode node) => node.label.isNotEmpty
    ? node.label
    : node.tooltip.isNotEmpty
    ? node.tooltip
    : null;

/// Дни в порядке обхода: только у них есть состояние выбранности.
List<SemanticsNode> _dayNodes(WidgetTester tester) => [
  for (final node in tester.semantics.simulatedAccessibilityTraversal())
    if (node.flagsCollection.isSelected != Tristate.none) node,
];

/// Доступное название дня: полная дата с днём недели в форме Flutter для
/// текущей локали и, у сегодняшнего дня, отметка «сегодня».
String _dayLabel(
  WidgetTester tester,
  CalendarDate value, {
  bool isToday = false,
}) {
  final context = tester.element(find.byType(DailyChoiceCalendar));
  final fullDate = MaterialLocalizations.of(context)
      .formatFullDate(DateTime.utc(value.year, value.month, value.day));
  return isToday
      ? '$fullDate, ${AppLocalizations.of(context).dailyChoiceCalendarToday}'
      : fullDate;
}

/// День объявляется одной кнопкой выбора с явным состоянием выбранности.
void _expectDay(WidgetTester tester, String label, {required bool isSelected}) {
  final node = find.semantics.byLabel(label).evaluate().single;
  _expectSingleSelectAction(node);
  expect(
    node.flagsCollection.isSelected,
    isSelected ? Tristate.isTrue : Tristate.isFalse,
    reason: label,
  );
}

void _expectSingleSelectAction(SemanticsNode node) {
  expect(node.flagsCollection.isButton, isTrue, reason: node.label);
  expect(
    node.getSemanticsData().actions,
    SemanticsAction.tap.index,
    reason: '${node.label}: доступно только действие выбора',
  );
}

SemanticsFinder _command(String name) => find.semantics.byLabel(name);

/// Команда шапки — кнопка с названием, сообщающая доступность; недоступная
/// команда не предлагает касания.
void _expectCommand(
  WidgetTester tester,
  String name, {
  required bool isEnabled,
}) {
  final node = _command(name).evaluate().single;
  expect(node.flagsCollection.isButton, isTrue, reason: name);
  expect(
    node.flagsCollection.isEnabled,
    isEnabled ? Tristate.isTrue : Tristate.isFalse,
    reason: name,
  );
  expect(
    node.getSemanticsData().hasAction(SemanticsAction.tap),
    isEnabled,
    reason: name,
  );
}

/// Управляет календарём без свайпа: раскрытие, выбор дня,
/// следующий месяц и сворачивание. Возвращает журнал событий потребителя.
Future<List<CalendarEvent>> _controlWithoutSwipes(
  WidgetTester tester,
  Locale locale, {
  required Future<void> Function(String name) activateCommand,
  required Future<void> Function(CalendarDate value) activateDay,
}) async {
  final texts = _localizedTexts.firstWhere((texts) => texts.locale == locale);
  final consumer = await pumpCalendarConsumer(
    tester,
    selectedDate: date(2026, 10, 4),
    viewport: week(date(2026, 10, 4)),
    today: date(2026, 10, 4),
    locale: locale,
  );

  await activateCommand(texts.expand);
  await tester.pumpAndSettle();
  expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 6));

  await activateDay(date(2026, 10, 7));
  await tester.pumpAndSettle();
  expect(consumer.selectedDate, date(2026, 10, 7));

  await activateCommand(texts.nextMonth);
  await tester.pumpAndSettle();
  expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));

  await activateCommand(texts.collapse);
  await tester.pumpAndSettle();
  expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 1));
  expect(consumer.selectedDate, date(2026, 10, 7));

  final events = List.of(consumer.events);
  await tester.pumpWidget(const SizedBox.shrink());
  return events;
}

void _expectNoWeekCommands(WidgetTester tester, String previous, String next) {
  expect(_command(previous), findsNothing);
  expect(_command(next), findsNothing);
  expect(find.byType(IconButton), findsNothing);
}
