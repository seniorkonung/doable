import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';

/// Узкий экран телефона.
const _screen = Size(360, 780);

/// Русский проверяется целиком. Английские подписи дней недели длиннее
/// русских, поэтому дополнительно проверяется свёрнутая неделя на английском.
final _configurations = [
  (locale: const Locale('ru'), full: true),
  (locale: const Locale('en'), full: false),
];

/// Короткие подписи дней с понедельника по воскресенье.
const _weekdays = {
  'ru': ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'],
  'en': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
};

/// Раскрытые месяцы с четырьмя, пятью и шестью неделями.
final _months = [
  (
    name: 'февраль 2027 года из четырёх недель',
    focusedDate: date(2027, 2, 15),
    weeks: weeksFrom(date(2027, 2, 1), 4),
  ),
  (
    name: 'апрель 2026 года из пяти недель',
    focusedDate: date(2026, 4, 15),
    weeks: weeksFrom(date(2026, 3, 30), 5),
  ),
  (
    name: 'март 2026 года из шести недель',
    focusedDate: date(2026, 3, 15),
    weeks: weeksFrom(date(2026, 2, 23), 6),
  ),
];

const _message = ValueKey('сообщение под календарём');
const _lastRow = ValueKey('последняя строка под календарём');
const _rowCount = 40;

/// Содержимое каталога под календарём в той же прокрутке: сообщение и список,
/// который не помещается на экран.
final _contentBelow = <Widget>[
  const SliverToBoxAdapter(
    child: Padding(
      key: _message,
      padding: EdgeInsets.all(16),
      child: Text('Сообщение каталога под календарём'),
    ),
  ),
  SliverList.builder(
    itemCount: _rowCount,
    itemBuilder: (context, index) => ListTile(
      key: index == _rowCount - 1 ? _lastRow : null,
      title: Text('Строка ${index + 1}'),
    ),
  ),
];

/// Общая вертикальная прокрутка страницы. Перелистывание периодов календаря —
/// горизонтальная прокрутка внутри неё.
final _pageScroll = find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

void main() {
  testWidgets('отметки помещаются под числами '
      'без изменения высоты строк недели и месяца', (tester) async {
    final consumer = await _pumpOnPhone(
      tester,
      locale: const Locale('ru'),
      viewport: week(date(2026, 10, 4)),
    );
    final statuses = {
      date(2026, 9, 30): DailyChoiceDayStatus.allCompleted,
      date(2026, 10, 4): DailyChoiceDayStatus.hasIncomplete,
    };
    for (final viewport in [
      week(date(2026, 10, 4)),
      month(date(2026, 10, 4)),
    ]) {
      consumer.replaceInputs(
        viewport: viewport,
        dayStatuses: {},
        hasDayMarksReadFailure: false,
      );
      await tester.pumpAndSettle();
      final before = await _calendarLayout(tester);
      final number = find.descendant(
        of: calendarDay(date(2026, 10, 4)),
        matching: find.text('4'),
      );
      final numberOffset =
          _rect(tester, number).top -
          _rect(tester, calendarDay(date(2026, 10, 4))).top;

      consumer.replaceInputs(dayStatuses: statuses);
      await tester.pumpAndSettle();
      final marked = await _calendarLayout(tester);
      expect(marked.rowHeight, moreOrLessEquals(before.rowHeight));
      expect(marked.gridHeight, moreOrLessEquals(before.gridHeight));
      expect(marked.calendar.height, moreOrLessEquals(before.calendar.height));
      expect(marked.messageTop, moreOrLessEquals(before.messageTop));
      expect(
        _rect(tester, number).top -
            _rect(tester, calendarDay(date(2026, 10, 4))).top,
        moreOrLessEquals(numberOffset),
      );
      for (final day in statuses.keys) {
        final cell = calendarDay(day);
        final mark = find.descendant(
          of: cell,
          matching: viewport.mode == DailyChoiceCalendarMode.week
              ? find.byType(DayMarkIndicator)
              : find.byType(Icon),
        );
        final number = find.descendant(
          of: cell,
          matching: find.text('${day.day}'),
        );
        final markRect = _rect(tester, mark);
        expect(_contains(_rect(tester, cell), markRect), isTrue);
        expect(markRect.top, greaterThan(_rect(tester, number).bottom));
      }

      consumer.replaceInputs(hasDayMarksReadFailure: true);
      await tester.pumpAndSettle();
      final failed = await _calendarLayout(tester);
      expect(failed.rowHeight, moreOrLessEquals(before.rowHeight));
      final failure = find.text('Отметки дней не загружены.');
      _expectFullyShown(tester, failure, within: failed.calendar);
      expect(
        _rect(tester, failure).bottom,
        lessThan(_rect(tester, calendarDay(date(2026, 9, 28))).top),
      );
      expect(tester.takeException(), isNull);
    }
    expect(consumer.events, isEmpty);
  });

  for (final (:locale, :full) in _configurations) {
    final language = locale.languageCode;

    group('экран 360×780, $language', () {
      testWidgets(
        'свёрнутая неделя показывает семь колонок, числа, подписи дней '
        'недели, выбранную дату и команды целиком, и всё нажимается',
        (tester) async {
          final consumer = await _pumpOnPhone(
            tester,
            locale: locale,
            viewport: week(date(2026, 10, 4)),
          );
          final weeks = weeksFrom(date(2026, 9, 28), 1);

          _expectLaidOut(
            tester,
            weeks: weeks,
            weekdays: _weekdays[language]!,
            selectedDate: date(2026, 10, 4),
          );
          await _tapEveryDay(tester, consumer, weeks);
          final localizations = _localizations(tester);
          await _tapEveryCommand(tester, consumer, {
            localizations.dailyChoiceCalendarPreviousWeek: week(
              date(2026, 9, 27),
            ),
            localizations.dailyChoiceCalendarNextWeek: week(date(2026, 10, 11)),
            localizations.dailyChoiceCalendarExpand: month(date(2026, 10, 4)),
          });
        },
      );

      if (!full) return;

      // Крайние месяцы: строки сетки не ветвят раскладку, пять недель
      // лежат между ними и проверяются вместе с высотами ниже.
      for (final (shown, nextFocusedDate) in [
        (_months.first, date(2027, 3, 1)),
        (_months.last, date(2026, 4, 5)),
      ]) {
        testWidgets(
          'раскрытый ${shown.name} размещается целиком, а все его дни и '
          'команды нажимаются',
          (tester) async {
            final consumer = await _pumpOnPhone(
              tester,
              locale: locale,
              viewport: month(shown.focusedDate),
            );
            final focused = shown.focusedDate;

            _expectLaidOut(
              tester,
              weeks: shown.weeks,
              weekdays: _weekdays[language]!,
              selectedDate: focused,
            );
            await _tapEveryDay(tester, consumer, shown.weeks);
            final localizations = _localizations(tester);
            await _tapEveryCommand(tester, consumer, {
              localizations.dailyChoiceCalendarPreviousMonth: month(
                date(focused.year, focused.month - 1, 1),
              ),
              localizations.dailyChoiceCalendarNextMonth: month(
                nextFocusedDate,
              ),
              localizations.dailyChoiceCalendarCollapse: week(focused),
            });
          },
        );
      }

      testWidgets('раскрытие увеличивает высоту на строки месяца и сдвигает '
          'содержимое ниже, которое остаётся достижимым общей прокруткой', (
        tester,
      ) async {
        final consumer = await _pumpOnPhone(
          tester,
          locale: locale,
          viewport: week(date(2027, 2, 15)),
        );
        final weekLayout = await _calendarLayout(tester);
        expect(weekLayout.rows, 1);

        final expand = find.byTooltip(
          _localizations(tester).dailyChoiceCalendarExpand,
        );
        await _reveal(tester, expand);
        await tester.tap(expand);
        await tester.pumpAndSettle();
        expect(consumer.viewport, month(date(2027, 2, 15)));
        // Месяц раскрывается внутри страницы: у календаря нет своей
        // вертикальной прокрутки, окна или маршрута.
        expect(_pageScroll, findsOneWidget);
        expect(find.byType(DailyChoiceCalendar), findsOneWidget);
        expect(tester.takeException(), isNull);

        final layouts = [weekLayout, await _calendarLayout(tester)];
        for (final shown in _months.skip(1)) {
          consumer.replaceInputs(viewport: month(shown.focusedDate));
          await tester.pumpAndSettle();
          layouts.add(await _calendarLayout(tester));
        }

        expect(layouts.map((layout) => layout.rows), [1, 4, 5, 6]);
        final rowHeight = weekLayout.rowHeight;
        expect(rowHeight, greaterThanOrEqualTo(54));
        final monthRowHeight = layouts[1].rowHeight;
        for (final layout in layouts) {
          // Сетка занимает ровно свои строки одинаковой высоты, а каталог
          // начинается сразу под календарём: ничего не обрезано и не
          // перекрыто.
          if (layout.rows > 1) {
            expect(layout.rowHeight, moreOrLessEquals(monthRowHeight));
          }
          expect(
            layout.gridHeight,
            moreOrLessEquals(layout.rows * layout.rowHeight),
            reason: '${layout.rows} строк',
          );
          expect(
            layout.messageTop,
            moreOrLessEquals(layout.calendar.bottom),
            reason: '${layout.rows} строк',
          );
        }
        expect(
          layouts[1].calendar.height,
          greaterThan(weekLayout.calendar.height),
        );

        await tester.scrollUntilVisible(
          find.byKey(_lastRow),
          200,
          scrollable: _pageScroll,
        );
        await tester.pumpAndSettle();
        _expectTappable(tester, find.byKey(_lastRow));
        await tester.scrollUntilVisible(
          find.byKey(_message),
          -200,
          scrollable: _pageScroll,
        );
        await tester.pumpAndSettle();
        _expectTappable(tester, find.byKey(_message));
        expect(consumer.viewport, month(date(2026, 3, 15)));
        expect(consumer.selectedDate, date(2027, 2, 15));
      });

      testWidgets(
        'вертикальный жест по дням прокручивает страницу, а горизонтальный '
        'перелистывает месяц',
        (tester) async {
          final consumer = await _pumpOnPhone(
            tester,
            locale: locale,
            viewport: month(date(2026, 10, 4)),
          );
          final day = calendarDay(date(2026, 10, 14));
          await _reveal(tester, day);
          final scroll = tester.state<ScrollableState>(_pageScroll).position;
          final before = scroll.pixels;

          await tester.drag(day, const Offset(0, -150));
          await tester.pumpAndSettle();

          expect(scroll.pixels, greaterThan(before + 100));
          expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 5));
          expect(consumer.events, isEmpty);

          final scrolled = scroll.pixels;
          // Больше половины, но меньше ширины страницы периода.
          await tester.drag(day, const Offset(-300, 0));
          await tester.pumpAndSettle();

          expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 6));
          expect(consumer.events, [ViewportChanged(month(date(2026, 11, 1)))]);
          expect(consumer.selectedDate, date(2026, 10, 4));
          expect(scroll.pixels, scrolled);
        },
      );
    });
  }
}

/// Допуск сравнения координат.
const _epsilon = 0.01;

/// Показывает календарь в общей прокрутке с содержимым под ним на узком
/// телефоне.
Future<CalendarConsumer> _pumpOnPhone(
  WidgetTester tester, {
  required Locale locale,

  required DailyChoiceCalendarViewport viewport,
}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  return pumpCalendarConsumer(
    tester,
    selectedDate: viewport.focusedDate,
    viewport: viewport,
    today: date(2026, 10, 4),
    locale: locale,
    contentBelow: _contentBelow,
  );
}

AppLocalizations _localizations(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(DailyChoiceCalendar)));

/// Проверяет, что календарь с видимыми неделями [weeks] целиком размещён в
/// ширине экрана: семь колонок дней, подписи внутри недели или над месяцем,
/// все тексты показаны полностью.
void _expectLaidOut(
  WidgetTester tester, {
  required List<List<CalendarDate>> weeks,
  required List<String> weekdays,
  required CalendarDate selectedDate,
}) {
  expect(visibleWeeks(tester), weeks);
  final isWeek =
      tester
          .widget<DailyChoiceCalendar>(find.byType(DailyChoiceCalendar))
          .viewport
          .mode ==
      DailyChoiceCalendarMode.week;
  final screen = Offset.zero & _screen;
  final calendar = _rect(tester, find.byType(DailyChoiceCalendar));
  expect(calendar.left, moreOrLessEquals(screen.left));
  expect(calendar.right, moreOrLessEquals(screen.right));

  // Дни: семь смежных колонок на всю ширину, строки одна под другой, каждая
  // ячейка не меньше области нажатия и показывает своё число целиком.
  final rows = [
    for (final week in weeks)
      [for (final day in week) _rect(tester, calendarDay(day))],
  ];
  for (final (index, row) in rows.indexed) {
    expect(row.first.left, moreOrLessEquals(calendar.left));
    expect(row.last.right, moreOrLessEquals(calendar.right));
    for (final (column, cell) in row.indexed) {
      expect(cell.width, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(cell.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      if (isWeek) expect(cell.height, greaterThanOrEqualTo(54));
      expect(cell.top, moreOrLessEquals(row.first.top));
      expect(cell.height, moreOrLessEquals(row.first.height));
      if (column > 0) {
        expect(cell.left, moreOrLessEquals(row[column - 1].right));
      }
    }
    if (index > 0) {
      expect(row.first.top, moreOrLessEquals(rows[index - 1].first.bottom));
    }
  }
  expect(rows.last.last.bottom, lessThanOrEqualTo(calendar.bottom + _epsilon));
  for (final (index, week) in weeks.indexed) {
    for (final (column, day) in week.indexed) {
      final number = find.descendant(
        of: calendarDay(day),
        matching: find.text('${day.day}'),
      );
      expect(_textOf(tester, number), '${day.day}');
      _expectFullyShown(tester, number, within: rows[index][column]);
    }
  }

  // В неделе подписи находятся в ячейках дней, в месяце — над колонками.
  final labels = [
    for (final weekday in weekdays)
      find.descendant(
        of: find.byType(DailyChoiceCalendar),
        matching: find.text(
          isWeek ? weekday[0].toUpperCase() + weekday.substring(1) : weekday,
        ),
      ),
  ];
  for (final (column, label) in labels.indexed) {
    final columnRect = isWeek
        ? rows.first[column]
        : Rect.fromLTRB(
            rows.first[column].left,
            calendar.top,
            rows.first[column].right,
            rows.first[column].top,
          );
    _expectFullyShown(tester, label, within: columnRect);
  }
  final gridTop = isWeek
      ? rows.first.first.top
      : [for (final label in labels) _rect(tester, label).top]
            .reduce((a, b) => a < b ? a : b);

  // Шапка над подписями: выбранная дата, месяц просмотра и команды.
  final header = Rect.fromLTRB(
    calendar.left,
    calendar.top,
    calendar.right,
    gridTop,
  );
  final context = tester.element(find.byType(DailyChoiceCalendar));
  final dates = MaterialLocalizations.of(context);
  final selected = DateTime.utc(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );
  _expectFullyShown(
    tester,
    find.text(
      AppLocalizations.of(context)
          .dailyChoiceCalendarSelectedDate(dates.formatFullDate(selected)),
    ),
    within: header,
  );
  final focused = tester
      .widget<DailyChoiceCalendar>(find.byType(DailyChoiceCalendar))
      .viewport
      .focusedDate;
  _expectFullyShown(
    tester,
    find.text(dates.formatMonthYear(DateTime.utc(focused.year, focused.month))),
    within: header,
  );
  final commands = find.descendant(
    of: find.byType(DailyChoiceCalendar),
    matching: find.byType(IconButton),
  );
  expect(commands, findsNWidgets(3));
  for (final command in commands.evaluate()) {
    final rect = _rect(tester, find.byWidget(command.widget));
    expect(_contains(header, rect), isTrue, reason: '$rect вне $header');
    expect(rect.width, greaterThanOrEqualTo(kMinInteractiveDimension));
    expect(rect.height, greaterThanOrEqualTo(kMinInteractiveDimension));
  }

  // Других текстов у календаря нет, и ни один не обрезан.
  final texts = find.descendant(
    of: find.byType(DailyChoiceCalendar),
    matching: find.byType(Text),
  );
  expect(
    texts,
    findsNWidgets(weeks.expand((week) => week).length + weekdays.length + 2),
  );
  expect(tester.takeException(), isNull);
}

/// Текст [finder] показан целиком внутри [within]: без ограничения строк и
/// многоточия, со всей высотой строк при доступной ширине.
void _expectFullyShown(
  WidgetTester tester,
  Finder finder, {
  required Rect within,
}) {
  expect(finder, findsOneWidget);
  final text = tester.widget<Text>(finder);
  expect(text.maxLines, isNull, reason: text.data);
  expect(text.overflow, isNull, reason: text.data);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  );
  expect(paragraph.maxLines, isNull, reason: text.data);

  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(
      paragraph.getMaxIntrinsicHeight(paragraph.constraints.maxWidth) -
          _epsilon,
    ),
    reason: '${text.data}: часть строк не помещается',
  );
  final rect = _globalRect(paragraph);
  expect(rect.width, moreOrLessEquals(paragraph.size.width));
  expect(rect.height, moreOrLessEquals(paragraph.size.height));
  expect(
    _contains(within, rect),
    isTrue,
    reason: '${text.data}: $rect вне $within',
  );
}

String? _textOf(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).data;

bool _contains(Rect outer, Rect inner) =>
    inner.left >= outer.left - _epsilon &&
    inner.top >= outer.top - _epsilon &&
    inner.right <= outer.right + _epsilon &&
    inner.bottom <= outer.bottom + _epsilon;

Rect _rect(WidgetTester tester, Finder finder) =>
    _globalRect(tester.renderObject<RenderBox>(finder));

Rect _globalRect(RenderBox box) =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

/// Положение календаря и содержимого под ним в общей прокрутке.
///
/// [gridHeight] — высота от верха первой строки дней до низа календаря.
typedef _CalendarLayout = ({
  Rect calendar,
  int rows,
  double rowHeight,
  double gridHeight,
  double messageTop,
});

/// Прокручивает страницу к сообщению под календарём, чтобы низ календаря и
/// сообщение были на экране, и измеряет их положение.
Future<_CalendarLayout> _calendarLayout(WidgetTester tester) async {
  // После раскрытия сообщение может быть далеко за
  // пределами экрана.
  await tester
      .state<ScrollableState>(_pageScroll)
      .position
      .ensureVisible(
        tester.renderObject(find.byKey(_message, skipOffstage: false)),
        alignment: 0.5,
      );
  await tester.pump();
  final weeks = visibleWeeks(tester);
  final firstDay = _rect(
    tester,
    calendarDay(weeks.first.firstWhere((day) => day != null)!),
  );
  final calendar = _rect(tester, find.byType(DailyChoiceCalendar));
  return (
    calendar: calendar,
    rows: weeks.length,
    rowHeight: firstDay.height,
    gridHeight: calendar.bottom - firstDay.top,
    messageTop: _rect(tester, find.byKey(_message)).top,
  );
}

/// Прокручивает страницу так, чтобы элемент календаря [finder] оказался
/// посередине экрана. Перелистывание календаря при этом не меняется.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  // Ближайшая прокрутка дня — горизонтальная страница периода, поэтому
  // положение в общей прокрутке определяется через календарь целиком.
  await tester
      .state<ScrollableState>(_pageScroll)
      .position
      .ensureVisible(
        tester.renderObject(find.byType(DailyChoiceCalendar)),
        alignment: 0.5,
        targetRenderObject: tester.renderObject(finder),
      );
  await tester.pump();
}

/// Касание середины [finder] на экране достигает его, а не другого элемента.
void _expectTappable(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  final center = _globalRect(box).center;
  expect(
    (Offset.zero & _screen).contains(center),
    isTrue,
    reason: 'Середина $finder вне экрана: $center',
  );
  expect(
    tester
        .hitTestOnBinding(center)
        .path
        .any((entry) => identical(entry.target, box)),
    isTrue,
    reason: 'Касание не достигает $finder',
  );
}

/// Нажимает каждый день [weeks] после прокрутки к нему. Каждое нажатие
/// выбирает свой день; день соседнего месяца переносит просмотр в свой месяц,
/// после чего потребитель возвращает прежний период.
Future<void> _tapEveryDay(
  WidgetTester tester,
  CalendarConsumer consumer,
  List<List<CalendarDate>> weeks,
) async {
  final viewport = consumer.viewport;
  final days = weeks.expand((week) => week).toList();
  for (final day in days) {
    await _reveal(tester, calendarDay(day));
    _expectTappable(tester, calendarDay(day));
    await tester.tap(calendarDay(day));
    await tester.pumpAndSettle();
    expect(consumer.selectedDate, day);
    if (consumer.viewport != viewport) {
      consumer.replaceInputs(viewport: viewport);
      await tester.pumpAndSettle();
    }
  }
  expect(consumer.events, [for (final day in days) DateSelected(day)]);
  consumer.events.clear();
  expect(visibleWeeks(tester), weeks);
}

/// Нажимает каждую команду шапки по названию из [expected] после прокрутки к
/// ней и проверяет единственное изменение просмотра; затем потребитель
/// возвращает прежний просмотр.
Future<void> _tapEveryCommand(
  WidgetTester tester,
  CalendarConsumer consumer,
  Map<String, DailyChoiceCalendarViewport> expected,
) async {
  final viewport = consumer.viewport;
  for (final MapEntry(key: name, value: changed) in expected.entries) {
    final command = find.byTooltip(name);
    await _reveal(tester, command);
    _expectTappable(tester, command);
    await tester.tap(command);
    await tester.pumpAndSettle();
    expect(consumer.events, [ViewportChanged(changed)], reason: name);
    consumer.events.clear();
    consumer.replaceInputs(viewport: viewport);
    await tester.pumpAndSettle();
    expect(consumer.events, isEmpty, reason: name);
  }
}
