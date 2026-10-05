import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';

/// Узкий экран телефона.
const _screen = Size(360, 780);

/// Обычный и увеличенный системный размер текста.
const _textScales = [1.0, 2.5];

/// Короткие подписи колонок с понедельника по воскресенье.
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
  for (final locale in const [Locale('ru'), Locale('en')]) {
    for (final textScale in _textScales) {
      final language = locale.languageCode;

      group('экран 360×780, $language, масштаб текста $textScale', () {
        testWidgets(
          'свёрнутая неделя показывает семь колонок, числа, подписи дней '
          'недели, выбранную дату и команды целиком, и всё нажимается',
          (tester) async {
            final consumer = await _pumpOnPhone(
              tester,
              locale: locale,
              textScale: textScale,
              viewport: week(date(2026, 10, 4)),
            );
            final weeks = weeksFrom(date(2026, 9, 28), 1);

            _expectLaidOut(
              tester,
              weeks: weeks,
              weekdays: _weekdays[language]!,
              selectedDate: date(2026, 10, 4),
              textScale: textScale,
            );
            await _tapEveryDay(tester, consumer, weeks);
            final localizations = _localizations(tester);
            await _tapEveryCommand(tester, consumer, {
              localizations.dailyChoiceCalendarPreviousWeek: week(
                date(2026, 9, 27),
              ),
              localizations.dailyChoiceCalendarNextWeek: week(
                date(2026, 10, 11),
              ),
              localizations.dailyChoiceCalendarExpand: month(date(2026, 10, 4)),
            });
          },
        );

        for (final shown in _months) {
          testWidgets(
            'раскрытый ${shown.name} размещается целиком, а все его дни и '
            'команды нажимаются',
            (tester) async {
              final consumer = await _pumpOnPhone(
                tester,
                locale: locale,
                textScale: textScale,
                viewport: month(shown.focusedDate),
              );
              final focused = shown.focusedDate;

              _expectLaidOut(
                tester,
                weeks: shown.weeks,
                weekdays: _weekdays[language]!,
                selectedDate: focused,
                textScale: textScale,
              );
              await _tapEveryDay(tester, consumer, shown.weeks);
              final localizations = _localizations(tester);
              await _tapEveryCommand(tester, consumer, {
                localizations.dailyChoiceCalendarPreviousMonth: month(
                  date(focused.year, focused.month - 1, 1),
                ),
                localizations.dailyChoiceCalendarNextMonth: month(
                  date(focused.year, focused.month + 1, 1),
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
            textScale: textScale,
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
          expect(rowHeight, greaterThanOrEqualTo(kMinInteractiveDimension));
          for (final layout in layouts) {
            // Сетка занимает ровно свои строки одинаковой высоты, а каталог
            // начинается сразу под календарём: ничего не обрезано и не
            // перекрыто.
            expect(layout.rowHeight, moreOrLessEquals(rowHeight));
            expect(
              layout.gridHeight,
              moreOrLessEquals(layout.rows * rowHeight),
              reason: '${layout.rows} строк',
            );
            expect(
              layout.messageTop,
              moreOrLessEquals(layout.calendar.bottom),
              reason: '${layout.rows} строк',
            );
          }
          // Высота шапки зависит от длины названия месяца, поэтому
          // раскрытие сравнивается на одном и том же феврале 2027 года.
          expect(
            layouts[1].calendar.height - weekLayout.calendar.height,
            moreOrLessEquals(3 * rowHeight),
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
              textScale: textScale,
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
            expect(consumer.events, [
              ViewportChanged(month(date(2026, 11, 1))),
            ]);
            expect(consumer.selectedDate, date(2026, 10, 4));
            expect(scroll.pixels, scrolled);
          },
        );
      });
    }
  }

  testWidgets(
    'смена системного масштаба текста у открытого календаря меняет высоту '
    'строк, сохраняя выбор и просмотр без событий',
    (tester) async {
      final consumer = await _pumpOnPhone(
        tester,
        locale: const Locale('ru'),
        textScale: 1,
        viewport: month(date(2026, 3, 15)),
      );
      final normal = await _calendarLayout(tester);

      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      await tester.pumpAndSettle();
      final large = await _calendarLayout(tester);

      expect(large.rows, 6);
      expect(large.rowHeight, greaterThan(normal.rowHeight));
      expect(large.gridHeight, moreOrLessEquals(6 * large.rowHeight));
      expect(large.messageTop, moreOrLessEquals(large.calendar.bottom));
      _expectLaidOut(
        tester,
        weeks: weeksFrom(date(2026, 2, 23), 6),
        weekdays: _weekdays['ru']!,
        selectedDate: date(2026, 3, 15),
        textScale: 2.5,
      );

      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await tester.pumpAndSettle();
      final restored = await _calendarLayout(tester);

      expect(restored.rowHeight, moreOrLessEquals(normal.rowHeight));
      expect(
        restored.calendar.height,
        moreOrLessEquals(normal.calendar.height),
      );
      expect(consumer.events, isEmpty);
      expect(consumer.selectedDate, date(2026, 3, 15));
      expect(consumer.viewport, month(date(2026, 3, 15)));
    },
  );
}

/// Допуск сравнения координат.
const _epsilon = 0.01;

/// Показывает календарь в общей прокрутке с содержимым под ним на узком
/// телефоне с системным размером текста [textScale].
Future<CalendarConsumer> _pumpOnPhone(
  WidgetTester tester, {
  required Locale locale,
  required double textScale,
  required DailyChoiceCalendarViewport viewport,
}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
/// ширине экрана: семь колонок дней, подписи колонок над ними, шапка над
/// подписями и все тексты показаны полностью в системном масштабе.
void _expectLaidOut(
  WidgetTester tester, {
  required List<List<CalendarDate>> weeks,
  required List<String> weekdays,
  required CalendarDate selectedDate,
  required double textScale,
}) {
  expect(visibleWeeks(tester), weeks);
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
        matching: find.byType(Text),
      );
      expect(_textOf(tester, number), '${day.day}');
      _expectFullyShown(
        tester,
        number,
        within: rows[index][column],
        textScale: textScale,
      );
    }
  }

  // Подписи дней недели — над своими колонками.
  final labels = [
    for (final weekday in weekdays)
      find.descendant(
        of: find.byType(DailyChoiceCalendar),
        matching: find.text(weekday),
      ),
  ];
  for (final (column, label) in labels.indexed) {
    final columnRect = Rect.fromLTRB(
      rows.first[column].left,
      calendar.top,
      rows.first[column].right,
      rows.first[column].top,
    );
    _expectFullyShown(tester, label, within: columnRect, textScale: textScale);
  }
  final gridTop = [for (final label in labels) _rect(tester, label).top]
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
    textScale: textScale,
  );
  final focused = tester
      .widget<DailyChoiceCalendar>(find.byType(DailyChoiceCalendar))
      .viewport
      .focusedDate;
  _expectFullyShown(
    tester,
    find.text(dates.formatMonthYear(DateTime.utc(focused.year, focused.month))),
    within: header,
    textScale: textScale,
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
/// многоточия, со всей высотой строк при доступной ширине, в системном масштабе
/// [textScale] и без уменьшающего преобразования.
void _expectFullyShown(
  WidgetTester tester,
  Finder finder, {
  required Rect within,
  required double textScale,
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
    paragraph.textScaler.scale(10),
    moreOrLessEquals(10 * textScale),
    reason: text.data,
  );
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
  // После раскрытия при крупном тексте сообщение может быть далеко за
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
