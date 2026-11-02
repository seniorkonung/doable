/// Общие шаги управления каталогом дневных выборов в сценариях приложения.
///
/// Сценарий называет только намерение человека — «выбрать день каталога»,
/// «какой день каталог показывает выбранным», «где выбирается день»,
/// «перелистать или раскрыть календарь», «какой период он показывает» — и не
/// знает, каким элементом страница позволяет выбрать дату. Шаги действуют и
/// наблюдают через интерфейс каталога и не обращаются к его модели.
///
/// Каталог выбирает день встроенным календарём: шаги, как человек,
/// перелистывают недели свайпом, месяцы командами шапки и нажимают день.
/// Смена способа выбора дня меняет только этот файл, а не сценарии.
library;

import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:doable/src/design_system/components/choice_check.dart';
import 'package:doable/src/design_system/components/choice_row.dart';
import 'package:doable/src/design_system/components/day_heading.dart';
import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'app_root_pages.dart';

/// Элемент открытого каталога дневных выборов, которым человек выбирает день.
///
/// Для проверок его размещения на странице: видимости, доступности нажатия и
/// соседства с другими элементами.
final dailyChoiceCatalogDateControl = find.byType(DailyChoiceCalendar);

/// День [date] в календаре открытого каталога дневных выборов.
///
/// Находится, только пока календарь показывает период с этим днём.
Finder dailyChoiceCatalogDay(CalendarDate date) => find.byKey(
  ValueKey('daily-choice-calendar-day-${date.toCanonicalString()}'),
);

/// Отметка показанного дня. У дня без выборов отметки нет.
Finder dailyChoiceCatalogDayMark(CalendarDate date, {DayMark? mark}) =>
    find.descendant(
      of: dailyChoiceCatalogDay(date),
      matching: find.byWidgetPredicate((widget) {
        final shown = switch (widget) {
          DayMarkIndicator(:final mark) => mark,
          Icon(icon: Icons.check) => DayMark.done,
          Icon(icon: Icons.circle_outlined) => DayMark.todo,
          _ => DayMark.none,
        };
        return shown != DayMark.none && (mark == null || shown == mark);
      }),
    );

/// Выбирает [date] днём открытого каталога дневных выборов.
///
/// Если день не виден, шаг перелистывает календарь к нему командами шапки:
/// далёкий день он находит по месяцам в раскрытом календаре, а свёрнутый
/// календарь сворачивает обратно до нажатия дня. Поэтому представление
/// календаря шаг не меняет, а последним действием остаётся нажатие дня.
///
/// Шаг выполняет выбор и не ждёт выдачи этого дня: её дожидается сам
/// сценарий. [tap] — нажатие сценария для команд календаря; по умолчанию
/// [tapWhenFound].
Future<void> selectDailyChoiceCatalogDate(
  WidgetTester tester,
  CalendarDate date, {
  RootPageTap tap = tapWhenFound,
}) async {
  await pumpUntilFound(tester, dailyChoiceCatalogDateControl);
  final day = dailyChoiceCatalogDay(date);
  if (day.evaluate().isEmpty) {
    final texts = AppLocalizations.of(
      tester.element(dailyChoiceCatalogDateControl),
    );
    final expand = find.bySemanticsLabel(texts.dailyChoiceCalendarExpand);
    final collapsed = expand.evaluate().isNotEmpty;
    if (collapsed) {
      await _runCommand(tester, tap, expand);
    }
    await _turnUntilShown(
      tester,
      date,
      tap,
      previous: texts.dailyChoiceCalendarPreviousMonth,
      next: texts.dailyChoiceCalendarNextMonth,
    );
    if (collapsed) {
      await _runCommand(
        tester,
        tap,
        find.bySemanticsLabel(texts.dailyChoiceCalendarCollapse),
      );
      await _turnUntilShown(tester, date, tap, previous: null, next: null);
    }
  }
  await tester.tap(day);
  await tester.pump();
}

/// День, который открытый каталог дневных выборов показывает выбранным.
///
/// Заголовок называет выбранный день полной датой и тогда, когда календарь
/// просматривает другой период. Заголовок прокручивается вместе с выдачей,
/// поэтому шаг читает его и за краем видимой части страницы. Каталог, который
/// не называет выбранный день, проваливает проверку.
CalendarDate shownDailyChoiceCatalogDate(WidgetTester tester) {
  final calendar = find.byType(DailyChoiceCalendar, skipOffstage: false);
  final selected = tester.widget<DailyChoiceCalendar>(calendar).selectedDate;
  final context = tester.element(calendar);
  final label = DateFormat(
    'd MMMM y',
    Localizations.localeOf(context).toLanguageTag(),
  ).format(DateTime.utc(selected.year, selected.month, selected.day));
  final shown = find.descendant(
    of: find.byType(DayHeading, skipOffstage: false),
    matching: find.text(label, skipOffstage: false),
  );
  if (shown.evaluate().isEmpty) {
    fail('Каталог дневных выборов не называет выбранный день $selected.');
  }
  return selected;
}

/// Перелистывает календарь открытого каталога: недели свайпом, месяцы
/// командами шапки, пока он не покажет [date], и день не выбирает.
///
/// Календарь закреплён над выдачей. [tap] — нажатие сценария для команд;
/// по умолчанию [tapWhenFound].
Future<void> showDailyChoiceCatalogPeriod(
  WidgetTester tester,
  CalendarDate date, {
  RootPageTap tap = tapWhenFound,
}) async {
  await pumpUntilFound(tester, dailyChoiceCatalogDateControl);
  final texts = AppLocalizations.of(
    tester.element(dailyChoiceCatalogDateControl),
  );
  final collapsed = find
      .bySemanticsLabel(texts.dailyChoiceCalendarExpand)
      .evaluate()
      .isNotEmpty;
  await _turnUntilShown(
    tester,
    date,
    tap,
    previous: collapsed ? null : texts.dailyChoiceCalendarPreviousMonth,
    next: collapsed ? null : texts.dailyChoiceCalendarNextMonth,
  );
}

/// Раскрывает свёрнутый календарь открытого каталога дневных выборов в месяц
/// просматриваемой даты.
///
/// Календарь закреплён над выдачей. [tap] — нажатие сценария для команды;
/// по умолчанию [tapWhenFound].
Future<void> expandDailyChoiceCatalogCalendar(
  WidgetTester tester, {
  RootPageTap tap = tapWhenFound,
}) async {
  await pumpUntilFound(tester, dailyChoiceCatalogDateControl);
  final texts = AppLocalizations.of(
    tester.element(dailyChoiceCatalogDateControl),
  );
  await _runCommand(
    tester,
    tap,
    find.bySemanticsLabel(texts.dailyChoiceCalendarExpand),
  );
}

/// Период, который показывает календарь открытого каталога дневных выборов:
/// дата просмотра и представление.
///
/// В месяце шапка называет месяц и год даты просмотра; в неделе шапки нет.
/// Видны неделя или весь месяц с этой датой, а команда представления
/// предлагает обратное: раскрыть неделю или свернуть месяц. Календарь, который показывает другой
/// период, проваливает проверку. Как и выбранный день, период читается и за
/// краем видимой части страницы.
DailyChoiceCalendarViewport shownDailyChoiceCatalogViewport(
  WidgetTester tester,
) {
  final calendar = find.byType(DailyChoiceCalendar, skipOffstage: false);
  final viewport = tester.widget<DailyChoiceCalendar>(calendar).viewport;
  final context = tester.element(calendar);
  final texts = AppLocalizations.of(context);
  final focused = viewport.focusedDate;
  final monthLabel = DateFormat(
    'LLLL y',
    Localizations.localeOf(context).toLanguageTag(),
  ).format(DateTime.utc(focused.year, focused.month, focused.day));
  final title = monthLabel[0].toUpperCase() + monthLabel.substring(1);
  final toggle = switch (viewport.mode) {
    DailyChoiceCalendarMode.week => texts.dailyChoiceCalendarExpand,
    DailyChoiceCalendarMode.month => texts.dailyChoiceCalendarCollapse,
  };
  final days = {
    for (final element
        in find
            .descendant(
              of: calendar,
              matching: find.byType(
                DailyChoiceCalendarDay,
                skipOffstage: false,
              ),
            )
            .evaluate())
      (element.widget as DailyChoiceCalendarDay).date,
  };
  final periodShown = switch (viewport.mode) {
    DailyChoiceCalendarMode.week =>
      days.length == DateTime.daysPerWeek && days.contains(focused),
    DailyChoiceCalendarMode.month => [
      for (
        var day = 1;
        day <= DateTime.utc(focused.year, focused.month + 1, 0).day;
        day++
      )
        CalendarDate.fromParts(focused.year, focused.month, day),
    ].every(days.contains),
  };
  final titleShown = find
      .descendant(of: calendar, matching: find.text(title, skipOffstage: false))
      .evaluate()
      .isNotEmpty;
  final toggleShown = find
      .descendant(
        of: calendar,
        matching: find.bySemanticsLabel(toggle, skipOffstage: false),
      )
      .evaluate()
      .isNotEmpty;
  final expectedTitle = viewport.mode == DailyChoiceCalendarMode.month;
  if (!periodShown || titleShown != expectedTitle || !toggleShown) {
    fail(
      'Календарь каталога дневных выборов не показывает период $viewport: '
      'дни $days, шапка «$title» ${titleShown ? 'видна' : 'не видна'}, '
      'команда «$toggle» ${toggleShown ? 'видна' : 'не видна'}.',
    );
  }
  return viewport;
}

/// Наибольшее число перелистываний к одному дню: далёкий день календарь
/// находит по месяцам.
const _maxTurns = 240;

/// Перелистывает календарь к [date]: месяц — командами [previous] и [next],
/// неделю — свайпом, когда обе команды отсутствуют.
Future<void> _turnUntilShown(
  WidgetTester tester,
  CalendarDate date,
  RootPageTap tap, {
  required String? previous,
  required String? next,
}) async {
  await pumpUntilFound(tester, dailyChoiceCatalogDateControl);
  for (var turn = 0; turn < _maxTurns; turn++) {
    final shown = [
      for (final element in find.byType(DailyChoiceCalendarDay).evaluate())
        (element.widget as DailyChoiceCalendarDay).date,
    ];
    if (shown.contains(date)) return;
    final isEarlier = shown.every((day) => _isBefore(date, day));
    final command = isEarlier ? previous : next;
    if (command != null) {
      await _runCommand(tester, tap, find.bySemanticsLabel(command));
    } else {
      await tester.drag(
        find.byType(DailyChoiceCalendarDay).first,
        Offset(
          tester.getSize(dailyChoiceCatalogDateControl).width *
              (isEarlier ? 0.8 : -0.8),
          0,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
  }
  fail('Календарь каталога не показал день $date.');
}

/// Выполняет команду шапки календаря и доводит смену периода до конца.
///
/// Индикатор загрузки выдачи может не дать дождаться покоя всех анимаций,
/// поэтому шаг продвигает время сам: перелистывание короче секунды.
Future<void> _runCommand(
  WidgetTester tester,
  RootPageTap tap,
  Finder command,
) async {
  await tap(tester, command);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Каноническая запись даты имеет постоянную ширину, поэтому её порядок —
/// календарный.
bool _isBefore(CalendarDate a, CalendarDate b) =>
    a.toCanonicalString().compareTo(b.toCanonicalString()) < 0;

/// Флажок выполнения на карточке каталога, когда карточка одна.
///
/// Карточку из нескольких шаг находит по её ключу выполнения.
final dailyChoiceCompletionControl = find.byType(ChoiceCheck);

/// Что показывает флажок выполнения [control]: выполнен ли выбор и можно ли
/// сейчас изменить выполнение.
///
/// Шаг читает карточку вокруг флажка, поэтому сценарии не знают, каким
/// виджетом каталог рисует флажок.
({bool completed, bool enabled}) dailyChoiceCompletionState(
  WidgetTester tester,
  Finder control,
) {
  final row = tester.widget<ChoiceRow>(
    find.ancestor(of: control, matching: find.byType(ChoiceRow)),
  );
  return (completed: row.done, enabled: row.onToggle != null);
}

/// Вертикальная прокрутка выдачи открытого каталога дневных выборов.
Finder _catalogScroll() => find.descendant(
  of: find.byType(DailyChoiceCatalogBody).last,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

/// Подвал секции с ещё не полученными порциями: подгрузка или её отказ.
///
/// Лениво построенный подвал находится, только когда конец загруженной части
/// секции подошёл к видимой области.
Finder dailyChoiceCatalogPageFooter({
  required bool completed,
  bool skipOffstage = true,
}) => find.descendant(
  of: find.byType(DailyChoiceCatalogBody).last,
  matching: find.byKey(
    ValueKey('daily-choice-page-footer-$completed'),
    skipOffstage: skipOffstage,
  ),
  skipOffstage: skipOffstage,
);

/// Наибольшее число жестов прокрутки до конца загруженной части секции.
const _maxScrolls = 60;

/// Прокручивает выдачу жестами, пока конец загруженной части секции не
/// подойдёт к видимой области: тогда каталог сам запрашивает следующую порцию.
///
/// Шаг останавливается на подвале, который увидел первым, и ответа на запрос
/// не ждёт: его завершает сам сценарий.
Future<void> scrollToDailyChoiceCatalogPageEnd(
  WidgetTester tester,
  bool isCompleted,
) async {
  final footer = dailyChoiceCatalogPageFooter(
    completed: isCompleted,
    skipOffstage: false,
  );
  for (var scroll = 0; footer.evaluate().isEmpty; scroll++) {
    if (scroll == _maxScrolls) {
      fail('Каталог не показал конец загруженной части секции.');
    }
    await tester.drag(_catalogScroll(), const Offset(0, -300));
    await tester.pump();
  }
  await tester.pump();
}

/// Показывает только выбранную секцию, сохраняя дату и загруженные порции.
Future<void> showDailyChoiceCatalogSection(
  WidgetTester tester,
  bool isCompleted,
) async {
  final body = find.byType(DailyChoiceCatalogBody).last;
  final scroll = _catalogScroll();
  Finder header(bool completed) => find.descendant(
    of: body,
    matching: find.byKey(ValueKey('daily-choice-section-$completed')),
  );
  final semantics = tester.ensureSemantics();
  // Невыполненные сворачиваются первыми: иначе прокрутка к заголовку
  // выполненных дошла бы до конца их порции и получила бы следующую.
  for (final (completed, expand) in [
    (false, false),
    (true, isCompleted),
    (false, !isCompleted),
  ]) {
    await tester.scrollUntilVisible(
      header(completed),
      completed ? 500 : -500,
      scrollable: scroll,
    );
    await tester.pump();
    final expanded = tester
        .getSemantics(header(completed))
        .flagsCollection
        .isExpanded;
    if ((expanded == Tristate.isTrue) != expand) {
      await tester.tap(header(completed));
      await tester.pump();
    }
  }
  await tester.scrollUntilVisible(
    header(isCompleted),
    isCompleted ? 500 : -500,
    scrollable: scroll,
  );
  semantics.dispose();
}

/// Заголовок секции со счётчиком [count].
Finder dailyChoiceSectionWithCount({
  required bool completed,
  required int count,
  bool skipOffstage = true,
}) => find.descendant(
  of: find.byKey(
    ValueKey('daily-choice-section-$completed'),
    skipOffstage: skipOffstage,
  ),
  matching: find.text('$count', skipOffstage: skipOffstage),
);

/// Число в счётчике заголовка секции; заголовок должен быть построен.
String dailyChoiceSectionCount(WidgetTester tester, {required bool completed}) {
  final header = find.byKey(ValueKey('daily-choice-section-$completed'));
  return tester
      .widget<Text>(
        find.descendant(
          of: header,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data != null &&
                int.tryParse(widget.data!) != null,
          ),
        ),
      )
      .data!;
}
