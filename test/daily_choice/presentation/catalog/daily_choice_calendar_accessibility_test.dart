import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
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
    october: 'октябрь 2026 г.',
    november: 'ноябрь 2026 г.',
    todayOctober4: 'воскресенье, 4 октября 2026 г., Сегодня',
    october5: 'понедельник, 5 октября 2026 г.',
    september28: 'понедельник, 28 сентября 2026 г.',
    november15: 'воскресенье, 15 ноября 2026 г.',
    weekdays: ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'],
    previousWeek: 'Предыдущая неделя',
    nextWeek: 'Следующая неделя',
    previousMonth: 'Предыдущий месяц',
    nextMonth: 'Следующий месяц',
    expand: 'Развернуть календарь',
    collapse: 'Свернуть календарь',
  ),
  (
    locale: const Locale('en'),
    selectedDate: 'Selected date: Sunday, October 4, 2026',
    october: 'October 2026',
    november: 'November 2026',
    todayOctober4: 'Sunday, October 4, 2026, Today',
    october5: 'Monday, October 5, 2026',
    september28: 'Monday, September 28, 2026',
    november15: 'Sunday, November 15, 2026',
    weekdays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    previousWeek: 'Previous week',
    nextWeek: 'Next week',
    previousMonth: 'Previous month',
    nextMonth: 'Next month',
    expand: 'Expand calendar',
    collapse: 'Collapse calendar',
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

          final days = weeksFrom(date(2026, 9, 28), 5).expand((row) => row);
          expect(_announced(tester), [
            texts.selectedDate,
            texts.previousMonth,
            texts.october,
            texts.nextMonth,
            texts.collapse,
            for (final day in days)
              _dayLabel(tester, day, isToday: day == date(2026, 10, 4)),
          ]);
          // День соседнего месяца назван своей полной датой.
          expect(_announced(tester), contains(texts.september28));
          expect(_announced(tester), contains(texts.todayOctober4));
          semantics.dispose();
        },
      );

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
        expect(dayNodes, hasLength(35));
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

          _expectCommand(tester, texts.previousWeek, isEnabled: true);
          _expectCommand(tester, texts.nextWeek, isEnabled: false);
          _expectCommand(tester, texts.expand, isEnabled: true);
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
            texts.previousWeek,
            texts.expand,
            for (final day in lastDays) _dayLabel(tester, day),
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
          _expectCommand(tester, texts.collapse, isEnabled: true);
          expect(unavailableCalendarDays, findsNWidgets(2));
          expect(_dayNodes(tester), hasLength(33));

          consumer.replaceInputs(
            selectedDate: date(1, 1, 1),
            viewport: week(date(1, 1, 1)),
          );
          await tester.pumpAndSettle();
          _expectCommand(tester, texts.previousWeek, isEnabled: false);
          _expectCommand(tester, texts.nextWeek, isEnabled: true);
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
          expect(_dayNodes(tester), hasLength(35));
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
            activateCommand: (name) => tester.tap(find.byTooltip(name)),
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
            ViewportChanged(week(date(2026, 10, 11))),
            DateSelected(date(2026, 10, 7)),
            ViewportChanged(month(date(2026, 10, 7))),
            ViewportChanged(month(date(2026, 11, 1))),
            ViewportChanged(week(date(2026, 11, 1))),
          ]);
          semantics.dispose();
        },
      );
    });
  }

  testWidgets(
    'смена языка у того же календаря переводит подписи и названия команд, '
    'сохраняя выбор, просмотр и раскрытие без событий',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final consumer = await pumpCalendarConsumer(
        tester,
        selectedDate: date(2026, 10, 4),
        viewport: month(date(2026, 11, 15)),
        today: date(2026, 10, 4),
      );
      final layout = visibleWeeks(tester);

      for (final texts in [..._localizedTexts, _localizedTexts.first]) {
        tester.platformDispatcher.localesTestValue = [texts.locale];
        await tester.pumpAndSettle();

        expect(_announced(tester).take(5), [
          texts.selectedDate,
          texts.previousMonth,
          texts.november,
          texts.nextMonth,
          texts.collapse,
        ], reason: texts.locale.languageCode);
        expect(_announced(tester), contains(texts.november15));
        for (final weekday in texts.weekdays) {
          expect(find.text(weekday), findsOneWidget, reason: weekday);
        }
        expect(visibleWeeks(tester), layout);
        expect(consumer.selectedDate, date(2026, 10, 4));
        expect(consumer.viewport, month(date(2026, 11, 15)));
        expect(consumer.events, isEmpty);
      }
      semantics.dispose();
    },
  );

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
      english.previousWeek,
      english.october,
      english.nextWeek,
      english.expand,
      for (final day in weeksFrom(date(2026, 9, 28), 1).single)
        _dayLabel(tester, day, isToday: day == date(2026, 10, 4)),
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

  group('признаки дня на экране', () {
    testWidgets(
      'выбранный день залит кругом, сегодняшний обведён, и при совпадении '
      'видны оба признака',
      (tester) async {
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 5),
          viewport: week(date(2026, 10, 5)),
          today: date(2026, 10, 6),
        );

        expect(_mark(tester, date(2026, 10, 5)), (disc: true, ring: false));
        expect(_mark(tester, date(2026, 10, 6)), (disc: false, ring: true));
        expect(_mark(tester, date(2026, 10, 7)), (disc: false, ring: false));

        consumer.replaceInputs(selectedDate: date(2026, 10, 6));
        await tester.pumpAndSettle();

        expect(_mark(tester, date(2026, 10, 6)), (disc: true, ring: true));
        expect(_mark(tester, date(2026, 10, 5)), (disc: false, ring: false));
      },
    );
  });
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

SemanticsFinder _command(String name) =>
    find.semantics.byPredicate((node) => node.tooltip == name);

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

/// Управляет календарём без свайпа: следующая неделя, выбор дня, раскрытие,
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

  await activateCommand(texts.nextWeek);
  await tester.pumpAndSettle();
  expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));

  await activateDay(date(2026, 10, 7));
  await tester.pumpAndSettle();
  expect(consumer.selectedDate, date(2026, 10, 7));

  await activateCommand(texts.expand);
  await tester.pumpAndSettle();
  expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 5));

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

/// Признаки выбранности и «сегодня», различимые формой, а не только цветом:
/// заливка круга и его контур.
({bool disc, bool ring}) _mark(WidgetTester tester, CalendarDate value) {
  final decoration =
      tester
              .widget<DecoratedBox>(
                find.descendant(
                  of: calendarDay(value),
                  matching: find.byType(DecoratedBox),
                ),
              )
              .decoration
          as BoxDecoration;
  expect(decoration.shape, BoxShape.circle);
  return (disc: decoration.color != null, ring: decoration.border != null);
}
