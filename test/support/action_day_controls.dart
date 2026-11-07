/// Общие шаги управления экраном дня в сценариях приложения.
///
/// Сценарий называет только намерение человека — «выбрать день на экране дня»,
/// «какой день экран дня показывает выбранным», «где выбирается день»,
/// «перелистать или раскрыть календарь», «какой период он показывает» — и не
/// знает, каким элементом страница позволяет выбрать дату. Шаги действуют и
/// наблюдают через интерфейс экрана дня и не обращаются к его модели.
///
/// Экран дня показывает день встроенным календарём: шаги, как человек,
/// перелистывают недели свайпом, месяцы командами шапки и нажимают день.
/// Смена способа выбора дня меняет только этот файл, а не сценарии.
library;

import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar.dart';
import 'package:doable/src/action/presentation/day/action_day_body.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar_day.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar_viewport.dart';
import 'package:doable/src/design_system/components/action_check.dart';
import 'package:doable/src/design_system/components/action_row.dart';
import 'package:doable/src/design_system/components/day_heading.dart';
import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/design_system/components/notice.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'app_root_pages.dart';

/// Элемент открытого экрана дня, которым человек выбирает день.
///
/// Для проверок его размещения на странице: видимости, доступности нажатия и
/// соседства с другими элементами.
final actionDayDateControl = find.byType(ActionDayCalendar);

/// День [date] в календаре открытого экрана дня.
///
/// Находится, только пока календарь показывает период с этим днём.
Finder actionDayDay(CalendarDate date) =>
    find.byKey(ValueKey('action-day-calendar-day-${date.toCanonicalString()}'));

/// Отметка показанного дня. У дня без действий отметки нет.
Finder actionDayDayMark(CalendarDate date, {DayMark? mark}) => find.descendant(
  of: actionDayDay(date),
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

/// Выбирает [date] днём открытого экрана дня.
///
/// Если день не виден, шаг перелистывает календарь к нему командами шапки:
/// далёкий день он находит по месяцам в раскрытом календаре, а свёрнутый
/// календарь сворачивает обратно до нажатия дня. Поэтому представление
/// календаря шаг не меняет, а последним действием остаётся нажатие дня.
///
/// Шаг выполняет выбор и не ждёт выдачи этого дня: её дожидается сам
/// сценарий. [tap] — нажатие сценария для команд календаря; по умолчанию
/// [tapWhenFound].
Future<void> selectActionDayDate(
  WidgetTester tester,
  CalendarDate date, {
  RootPageTap tap = tapWhenFound,
}) async {
  await pumpUntilFound(tester, actionDayDateControl);
  final day = actionDayDay(date);
  if (day.evaluate().isEmpty) {
    final texts = AppLocalizations.of(tester.element(actionDayDateControl));
    final expand = find.bySemanticsLabel(texts.actionCalendarExpand);
    final collapsed = expand.evaluate().isNotEmpty;
    if (collapsed) {
      await _runCommand(tester, tap, expand);
    }
    await _turnUntilShown(
      tester,
      date,
      tap,
      previous: texts.actionCalendarPreviousMonth,
      next: texts.actionCalendarNextMonth,
    );
    if (collapsed) {
      await _runCommand(
        tester,
        tap,
        find.bySemanticsLabel(texts.actionCalendarCollapse),
      );
      await _turnUntilShown(tester, date, tap, previous: null, next: null);
    }
  }
  await tester.tap(day);
  await tester.pump();
}

/// День, который открытый экран дня показывает выбранным.
///
/// Заголовок называет выбранный день полной датой и тогда, когда календарь
/// просматривает другой период. Заголовок прокручивается вместе с выдачей,
/// поэтому шаг читает его и за краем видимой части страницы. Экран дня, который
/// не называет выбранный день, проваливает проверку.
CalendarDate shownActionDayDate(WidgetTester tester) {
  final calendar = find.byType(ActionDayCalendar, skipOffstage: false);
  final selected = tester.widget<ActionDayCalendar>(calendar).selectedDate;
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
    fail('Экран дня не называет выбранный день $selected.');
  }
  return selected;
}

/// Перелистывает календарь открытого экрана дня: недели свайпом, месяцы
/// командами шапки, пока он не покажет [date], и день не выбирает.
///
/// Календарь закреплён над выдачей. [tap] — нажатие сценария для команд;
/// по умолчанию [tapWhenFound].
Future<void> showActionDayPeriod(
  WidgetTester tester,
  CalendarDate date, {
  RootPageTap tap = tapWhenFound,
}) async {
  await pumpUntilFound(tester, actionDayDateControl);
  final texts = AppLocalizations.of(tester.element(actionDayDateControl));
  final collapsed = find
      .bySemanticsLabel(texts.actionCalendarExpand)
      .evaluate()
      .isNotEmpty;
  await _turnUntilShown(
    tester,
    date,
    tap,
    previous: collapsed ? null : texts.actionCalendarPreviousMonth,
    next: collapsed ? null : texts.actionCalendarNextMonth,
  );
}

/// Раскрывает свёрнутый календарь открытого экрана дня в месяц
/// просматриваемой даты.
///
/// Календарь закреплён над выдачей. [tap] — нажатие сценария для команды;
/// по умолчанию [tapWhenFound].
Future<void> expandActionDayCalendar(
  WidgetTester tester, {
  RootPageTap tap = tapWhenFound,
}) async {
  await pumpUntilFound(tester, actionDayDateControl);
  final texts = AppLocalizations.of(tester.element(actionDayDateControl));
  await _runCommand(
    tester,
    tap,
    find.bySemanticsLabel(texts.actionCalendarExpand),
  );
}

/// Период, который показывает календарь открытого экрана дня:
/// дата просмотра и представление.
///
/// В месяце шапка называет месяц и год даты просмотра; в неделе шапки нет.
/// Видны неделя или весь месяц с этой датой, а команда представления
/// предлагает обратное: раскрыть неделю или свернуть месяц. Календарь, который показывает другой
/// период, проваливает проверку. Как и выбранный день, период читается и за
/// краем видимой части страницы.
ActionDayCalendarViewport shownActionDayViewport(WidgetTester tester) {
  final calendar = find.byType(ActionDayCalendar, skipOffstage: false);
  final viewport = tester.widget<ActionDayCalendar>(calendar).viewport;
  final context = tester.element(calendar);
  final texts = AppLocalizations.of(context);
  final focused = viewport.focusedDate;
  final monthLabel = DateFormat(
    'LLLL y',
    Localizations.localeOf(context).toLanguageTag(),
  ).format(DateTime.utc(focused.year, focused.month, focused.day));
  final title = monthLabel[0].toUpperCase() + monthLabel.substring(1);
  final toggle = switch (viewport.mode) {
    ActionDayCalendarMode.week => texts.actionCalendarExpand,
    ActionDayCalendarMode.month => texts.actionCalendarCollapse,
  };
  final days = {
    for (final element
        in find
            .descendant(
              of: calendar,
              matching: find.byType(ActionDayCalendarDay, skipOffstage: false),
            )
            .evaluate())
      (element.widget as ActionDayCalendarDay).date,
  };
  final periodShown = switch (viewport.mode) {
    ActionDayCalendarMode.week =>
      days.length == DateTime.daysPerWeek && days.contains(focused),
    ActionDayCalendarMode.month => [
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
  final expectedTitle = viewport.mode == ActionDayCalendarMode.month;
  if (!periodShown || titleShown != expectedTitle || !toggleShown) {
    fail(
      'Календарь экрана дня не показывает период $viewport: '
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
  await pumpUntilFound(tester, actionDayDateControl);
  for (var turn = 0; turn < _maxTurns; turn++) {
    final shown = [
      for (final element in find.byType(ActionDayCalendarDay).evaluate())
        (element.widget as ActionDayCalendarDay).date,
    ];
    if (shown.contains(date)) return;
    final isEarlier = shown.every((day) => _isBefore(date, day));
    final command = isEarlier ? previous : next;
    if (command != null) {
      await _runCommand(tester, tap, find.bySemanticsLabel(command));
    } else {
      await tester.drag(
        find.byType(ActionDayCalendarDay).first,
        Offset(
          tester.getSize(actionDayDateControl).width * (isEarlier ? 0.8 : -0.8),
          0,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
  }
  fail('Календарь экрана дня не показал день $date.');
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

/// Флажок выполнения на строке экрана дня, когда строка одна.
///
/// Строку из нескольких шаг находит по её ключу выполнения.
final actionCompletionControl = find.byType(ActionCheck);

/// Что показывает флажок выполнения [control]: выполнено ли действие и можно ли
/// сейчас изменить выполнение.
///
/// Шаг читает строку вокруг флажка, поэтому сценарии не знают, каким
/// виджетом экран дня рисует флажок.
({bool completed, bool enabled}) actionCompletionState(
  WidgetTester tester,
  Finder control,
) {
  final row = tester.widget<ActionRow>(
    find.ancestor(of: control, matching: find.byType(ActionRow)),
  );
  return (completed: row.done, enabled: row.onToggle != null);
}

/// Действие уведомления об отказе записи выполнения с подписью [label].
///
/// Уведомление стоит у строки и несёт одно действие: повтор или
/// актуализацию действия.
Finder actionCompletionNoticeAction(String label) =>
    find.descendant(of: find.byType(Notice), matching: find.text(label));

/// Вертикальная прокрутка выдачи открытого экрана дня.
Finder _actionDayScroll() => find.descendant(
  of: find.byType(ActionDayBody).last,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

/// Подвал секции с ещё не полученными порциями: подгрузка или её отказ.
///
/// Лениво построенный подвал находится, только когда конец загруженной части
/// секции подошёл к видимой области.
Finder actionDayPageFooter({
  required ActionDaySection section,
  bool skipOffstage = true,
}) => find.descendant(
  of: find.byType(ActionDayBody).last,
  matching: find.byKey(
    ValueKey('action-day-page-footer-${section.name}'),
    skipOffstage: skipOffstage,
  ),
  skipOffstage: skipOffstage,
);

/// Наибольшее число жестов прокрутки до конца загруженной части секции.
const _maxScrolls = 60;

/// Прокручивает выдачу жестами, пока конец загруженной части секции не
/// подойдёт к видимой области: тогда экран дня сам запрашивает следующую порцию.
///
/// Шаг останавливается на подвале, который увидел первым, и ответа на запрос
/// не ждёт: его завершает сам сценарий.
Future<void> scrollToActionDayEnd(
  WidgetTester tester,
  ActionDaySection section,
) async {
  final footer = actionDayPageFooter(section: section, skipOffstage: false);
  for (var scroll = 0; footer.evaluate().isEmpty; scroll++) {
    if (scroll == _maxScrolls) {
      fail('Экран дня не показал конец загруженной части секции.');
    }
    await tester.drag(_actionDayScroll(), const Offset(0, -300));
    await tester.pump();
  }
  await tester.pump();
}

/// Показывает только выбранную секцию, сохраняя дату и загруженные порции.
Future<void> showActionDaySection(
  WidgetTester tester,
  ActionDaySection shown,
) async {
  final body = find.byType(ActionDayBody).last;
  final scroll = _actionDayScroll();
  Finder header(ActionDaySection section) => find.descendant(
    of: body,
    matching: find.byKey(ValueKey('action-day-section-${section.name}')),
  );
  double direction(ActionDaySection section) =>
      section == ActionDaySection.completed ? 500 : -500;
  final semantics = tester.ensureSemantics();
  // Невыполненные сворачиваются первыми: иначе прокрутка к заголовку
  // выполненных дошла бы до конца их порции и получила бы следующую.
  for (final (section, expand) in [
    (ActionDaySection.incomplete, false),
    (ActionDaySection.completed, shown == ActionDaySection.completed),
    (ActionDaySection.incomplete, shown == ActionDaySection.incomplete),
  ]) {
    await tester.scrollUntilVisible(
      header(section),
      direction(section),
      scrollable: scroll,
    );
    await tester.pump();
    final expanded = tester
        .getSemantics(header(section))
        .flagsCollection
        .isExpanded;
    if ((expanded == Tristate.isTrue) != expand) {
      await tester.tap(header(section));
      await tester.pump();
    }
  }
  await tester.scrollUntilVisible(
    header(shown),
    direction(shown),
    scrollable: scroll,
  );
  semantics.dispose();
}

/// Заголовок секции со счётчиком [count].
Finder actionDaySectionWithCount({
  required ActionDaySection section,
  required int count,
  bool skipOffstage = true,
}) => find.descendant(
  of: find.byKey(
    ValueKey('action-day-section-${section.name}'),
    skipOffstage: skipOffstage,
  ),
  matching: find.text('$count', skipOffstage: skipOffstage),
);

/// Число в счётчике заголовка секции; заголовок должен быть построен.
String actionDaySectionCount(
  WidgetTester tester, {
  required ActionDaySection section,
}) {
  final header = find.byKey(ValueKey('action-day-section-${section.name}'));
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
