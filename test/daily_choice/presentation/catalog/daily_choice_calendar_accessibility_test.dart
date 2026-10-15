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
    choosePeriod: 'Выбрать год и месяц',
    backToDays: 'Вернуться к дням месяца',
    previousYears: 'Предыдущие годы',
    nextYears: 'Следующие годы',
    previousYear: 'Предыдущий год',
    nextYear: 'Следующий год',
    currentPeriod: 'Текущий период',
    months: [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь',
    ],
  ),
  (
    locale: const Locale('en'),
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
    choosePeriod: 'Choose year and month',
    backToDays: 'Back to the days of the month',
    previousYears: 'Previous years',
    nextYears: 'Next years',
    previousYear: 'Previous year',
    nextYear: 'Next year',
    currentPeriod: 'Current period',
    months: [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ],
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

          final command = lookupAppLocalizations(texts.locale)
              .dailyChoiceCalendarChooseYearAndMonth;
          final days = weeksFrom(date(2026, 9, 28), 6).expand((row) => row);
          expect(_announced(tester), [
            texts.previousMonth,
            command,
            texts.nextMonth,
            for (final day in days)
              _dayLabel(tester, day, isToday: day == date(2026, 10, 4)),
            texts.collapse,
          ]);
          final title = find.semantics.byLabel(command).evaluate().single;
          expect(title.value, texts.october);
          expect(title.flagsCollection.isButton, isTrue);
          expect(
            title.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          // День соседнего месяца назван своей полной датой.
          expect(_announced(tester), contains(texts.september28));
          expect(_announced(tester), contains(texts.todayOctober4));
          semantics.dispose();
        },
      );

      testWidgets('состояние дня дополняет дату и «сегодня», сохраняя '
          'выбранность; Notice читается после ручки без действий', (
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
        _expectSelection(tester, completed, isSelected: false);
        _expectSelection(tester, incomplete, isSelected: true);
        _expectSelection(
          tester,
          _dayLabel(tester, date(2026, 10, 7)),
          isSelected: false,
        );
        expect(
          _announced(tester),
          containsAllInOrder([
            texts.september28,
            completed,
            incomplete,
            texts.collapse,
            texts.marksUnavailable,
          ]),
        );
        final failure = find.semantics.byLabel(texts.marksUnavailable);
        expect(failure, findsOne);
        expect(failure.evaluate().single.getSemanticsData().actions, 0);
        expect(failure.evaluate().single.flagsCollection.isLiveRegion, isTrue);
        expect(find.byType(SnackBar), findsNothing);

        tester.semantics.tap(find.semantics.byLabel(completed));
        await tester.pumpAndSettle();
        _expectSelection(tester, completed, isSelected: true);
        expect(consumer.events, [DateSelected(date(2026, 10, 4))]);

        consumer.replaceInputs(dayStatuses: {});
        await tester.pumpAndSettle();
        _expectSelection(tester, texts.todayOctober4, isSelected: true);
        expect(find.semantics.byLabel(completed), findsNothing);
        expect(failure, findsOne);
        semantics.dispose();
      });

      testWidgets('доступная активация открывает выбор, листает годы, '
          'выбирает месяц, возвращает дни и сворачивает без свайпа', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2026, 10, 4),
          viewport: week(date(2026, 10, 4)),
          today: date(2026, 10, 4),
          locale: texts.locale,
        );

        await _activate(tester, texts.expand);
        _expectPickerTitle(
          tester,
          texts.choosePeriod,
          texts.october,
          isExpanded: false,
        );
        await _activate(tester, texts.choosePeriod);
        _expectPickerTitle(tester, texts.backToDays, '2020–2031');
        expect(_announced(tester), [
          texts.previousYears,
          texts.backToDays,
          texts.nextYears,
          for (var year = 2020; year <= 2031; year++)
            year == 2026 ? '$year, ${texts.currentPeriod}' : '$year',
          texts.collapse,
        ]);
        _expectSelection(
          tester,
          '2026, ${texts.currentPeriod}',
          isSelected: true,
        );

        await _activate(tester, texts.previousYears);
        _expectPickerTitle(tester, texts.backToDays, '2008–2019');
        await _activate(tester, texts.nextYears);
        await _activate(tester, texts.nextYears);
        _expectPickerTitle(tester, texts.backToDays, '2032–2043');
        await _activate(tester, texts.previousYears);
        await _activate(tester, '2026, ${texts.currentPeriod}');
        _expectPickerTitle(tester, texts.backToDays, '2026');
        expect(_announced(tester), [
          texts.previousYear,
          texts.backToDays,
          texts.nextYear,
          for (var index = 0; index < 12; index++)
            '${texts.months[index]} 2026'
                '${index == 9 ? ', ${texts.currentPeriod}' : ''}',
          texts.collapse,
        ]);
        _expectSelection(
          tester,
          '${texts.october}, ${texts.currentPeriod}',
          isSelected: true,
        );

        await _activate(tester, texts.previousYear);
        _expectPickerTitle(tester, texts.backToDays, '2025');
        await _activate(tester, texts.nextYear);
        await _activate(tester, texts.nextYear);
        _expectPickerTitle(tester, texts.backToDays, '2027');
        await _activate(tester, texts.backToDays);
        expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 6));
        expect(consumer.events, [ViewportChanged(month(date(2026, 10, 4)))]);

        await _activate(tester, texts.choosePeriod);
        await _activate(tester, '2028');
        await _activate(tester, '${texts.months[2]} 2028');
        _expectPickerTitle(
          tester,
          texts.choosePeriod,
          '${texts.months[2]} 2028',
          isExpanded: false,
        );
        expect(visibleWeeks(tester), weeksFrom(date(2028, 2, 28), 6));
        await _activate(tester, texts.collapse);
        expect(visibleWeeks(tester), weeksFrom(date(2028, 2, 28), 1));
        expect(consumer.selectedDate, date(2026, 10, 4));
        expect(consumer.events, [
          ViewportChanged(month(date(2026, 10, 4))),
          MonthSelectionCompleted(month(date(2028, 3, 1))),
          ViewportChanged(week(date(2028, 3, 1))),
        ]);
        semantics.dispose();
      });

      testWidgets('показанный и текущий периоды читаются независимо '
          'от выбранной даты', (tester) async {
        final semantics = tester.ensureSemantics();
        final consumer = await pumpCalendarConsumer(
          tester,
          selectedDate: date(2035, 1, 15),
          viewport: month(date(2028, 3, 1)),
          today: date(2026, 10, 4),
          locale: texts.locale,
        );

        await _activate(tester, texts.choosePeriod);
        _expectSelection(tester, '2028', isSelected: true);
        _expectSelection(
          tester,
          '2026, ${texts.currentPeriod}',
          isSelected: false,
        );
        _expectSelection(tester, '2027', isSelected: false);
        await _activate(tester, '2026, ${texts.currentPeriod}');
        for (var index = 0; index < 12; index++) {
          _expectSelection(
            tester,
            '${texts.months[index]} 2026'
            '${index == 9 ? ', ${texts.currentPeriod}' : ''}',
            isSelected: false,
          );
        }

        await _activate(tester, texts.backToDays);
        await _activate(tester, texts.choosePeriod);
        await _activate(tester, '2028');
        for (var index = 0; index < 12; index++) {
          _expectSelection(
            tester,
            '${texts.months[index]} 2028',
            isSelected: index == 2,
          );
        }
        await _activate(tester, texts.collapse);
        expect(visibleWeeks(tester), weeksFrom(date(2028, 2, 28), 1));
        expect(consumer.selectedDate, date(2035, 1, 15));
        expect(consumer.events, [ViewportChanged(week(date(2028, 3, 1)))]);
        semantics.dispose();
      });

      // Остальные проверки не зависят от языка: подписи по языкам читает тест
      // выше.
      if (texts != _localizedTexts.first) return;

      for (final (boundary, years, disabledYears, disabledYear) in [
        (1, [1, 2, 3], texts.previousYears, texts.previousYear),
        (
          9999,
          [for (var year = 9988; year <= 9999; year++) year],
          texts.nextYears,
          texts.nextYear,
        ),
      ]) {
        testWidgets(
          'выбор у границы $boundary объявляет только допустимые годы '
          'и сообщает недоступность стрелок',
          (tester) async {
            final semantics = tester.ensureSemantics();
            final consumer = await pumpCalendarConsumer(
              tester,
              selectedDate: date(2026, 10, 4),
              viewport: month(date(boundary, 6, 15)),
              today: date(2026, 10, 4),
            );
            await _activate(tester, texts.choosePeriod);
            _expectPickerTitle(
              tester,
              texts.backToDays,
              '${years.first}–${years.last}',
            );
            _expectCommand(
              tester,
              texts.previousYears,
              isEnabled: boundary != 1,
            );
            _expectCommand(
              tester,
              texts.nextYears,
              isEnabled: boundary != 9999,
            );
            final yearLabels = [
              texts.previousYears,
              texts.backToDays,
              texts.nextYears,
              for (final year in years) '$year',
              texts.collapse,
            ];
            expect(_announced(tester), yearLabels);
            expect(
              _actionable(tester),
              yearLabels.where((label) => label != disabledYears),
            );
            for (final year in years) {
              _expectSelection(tester, '$year', isSelected: year == boundary);
            }

            await _activate(tester, '$boundary');
            _expectCommand(
              tester,
              texts.previousYear,
              isEnabled: boundary != 1,
            );
            _expectCommand(tester, texts.nextYear, isEnabled: boundary != 9999);
            final monthLabels = [
              texts.previousYear,
              texts.backToDays,
              texts.nextYear,
              for (final month in texts.months) '$month $boundary',
              texts.collapse,
            ];
            expect(_announced(tester), monthLabels);
            expect(
              _actionable(tester),
              monthLabels.where((label) => label != disabledYear),
            );
            await _activate(tester, '${texts.months[5]} $boundary');
            expect(consumer.events, [
              MonthSelectionCompleted(month(date(boundary, 6, 1))),
            ]);
            semantics.dispose();
          },
        );
      }

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

        _expectSelection(tester, texts.todayOctober4, isSelected: false);
        _expectSelection(tester, texts.october5, isSelected: true);
        _expectSelection(tester, texts.september28, isSelected: false);
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

        _expectSelection(tester, texts.todayOctober4, isSelected: true);
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
          _expectSelection(
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
          _expectSelection(
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
      _expectSelection(
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

/// Ячейка объявляется одной кнопкой выбора с явным состоянием выбранности.
void _expectSelection(
  WidgetTester tester,
  String label, {
  required bool isSelected,
}) {
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

Future<void> _activate(WidgetTester tester, String label) async {
  tester.semantics.tap(find.semantics.byLabel(label));
  await tester.pumpAndSettle();
}

void _expectPickerTitle(
  WidgetTester tester,
  String label,
  String value, {
  bool isExpanded = true,
}) {
  final node = find.semantics.byLabel(label).evaluate().single;
  _expectSingleSelectAction(node);
  expect(node.value, value);
  expect(
    node.flagsCollection.isExpanded,
    isExpanded ? Tristate.isTrue : Tristate.isFalse,
  );
}

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
