import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';
import 'daily_choice_catalog_page_test_support.dart';

/// Узкий экран телефона.
const _screen = Size(360, 780);

/// Обычный и увеличенный системный размер текста.
const _textScales = [1.0, 2.5];

/// Локальное сегодня проверок свёрнутой недели и прокрутки.
final _today = date(2026, 10, 4);

/// Раскрытые месяцы с четырьмя, пятью и шестью неделями: сегодня и выбранный
/// день — середина месяца.
final _months = [
  (
    name: 'февраль 2027 года из четырёх недель',
    today: date(2027, 2, 15),
    weeks: weeksFrom(date(2027, 2, 1), 4),
  ),
  (
    name: 'апрель 2026 года из пяти недель',
    today: date(2026, 4, 15),
    weeks: weeksFrom(date(2026, 3, 30), 5),
  ),
  (
    name: 'март 2026 года из шести недель',
    today: date(2026, 3, 15),
    weeks: weeksFrom(date(2026, 2, 23), 6),
  ),
];

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    for (final textScale in _textScales) {
      final language = locale.languageCode;

      group('экран 360×780, $language, масштаб текста $textScale', () {
        testWidgets('свёрнутая неделя занимает семь колонок во всю ширину, '
            'тексты страницы показаны целиком, а дни и команды нажимаются', (
          tester,
        ) async {
          final repository = CatalogPageRepository();
          await _open(tester, repository, locale, textScale, today: _today);
          repository.completeFirst(0, [
            catalogPageItem(1, date: _today),
          ], total: 1);
          await tester.pumpAndSettle();
          final l10n = _l10n(tester);

          _expectColumns(tester, weeksFrom(date(2026, 9, 28), 1));
          _expectCommands(tester);
          expect(
            find.descendant(
              of: find.byType(DailyChoiceCalendar),
              matching: find.text(_selectedDateLabel(tester, _today)),
            ),
            findsOneWidget,
          );
          await _expectWholeTexts(tester, textScale);

          await _tapCommand(tester, l10n.dailyChoiceCalendarNextWeek);
          expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
          await _tapCommand(tester, l10n.dailyChoiceCalendarPreviousWeek);
          expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));
          expect(repository.queries, hasLength(1));

          final day = date(2026, 10, 1);
          await _reveal(tester, calendarDay(day));
          _expectTappable(tester, calendarDay(day));
          await tester.tap(calendarDay(day));
          await tester.pump();
          expect(repository.queries, hasLength(2));
          expect(repository.queries[1].date, day);
          expect(tester.takeException(), isNull);
        });

        for (final shown in _months) {
          testWidgets('раскрытый ${shown.name} увеличивает высоту календаря '
              'на свои строки и сдвигает выдачу, все дни нажимаются, а '
              'сворачивание возвращает прежнюю высоту', (tester) async {
            final repository = CatalogPageRepository();
            await _open(
              tester,
              repository,
              locale,
              textScale,
              today: shown.today,
            );
            repository.completeFirst(0, [
              catalogPageItem(1, date: shown.today),
            ], total: 1);
            await tester.pumpAndSettle();
            final l10n = _l10n(tester);
            final week = _measure(tester);
            expect(week.rows, 1);

            await _tapCommand(tester, l10n.dailyChoiceCalendarExpand);
            final month = _measure(tester);
            expect(visibleWeeks(tester, skipOffstage: false), shown.weeks);
            expect(month.rows, shown.weeks.length);
            expect(month.rowHeight, moreOrLessEquals(week.rowHeight));
            // Шапка прежняя, поэтому календарь вырастает ровно на строки
            // месяца, и выдача сдвигается вниз на столько же.
            final grown = (shown.weeks.length - 1) * week.rowHeight;
            expect(
              month.calendar.height - week.calendar.height,
              moreOrLessEquals(grown),
            );
            expect(
              month.countOffset - week.countOffset,
              moreOrLessEquals(grown),
            );
            // Месяц раскрывается внутри страницы: прокрутка остаётся одной.
            expect(_pageScroll, findsOneWidget);
            _expectColumns(tester, shown.weeks);
            _expectCommands(tester);
            await _expectWholeTexts(tester, textScale);

            for (final row in shown.weeks) {
              await _reveal(
                tester,
                calendarDay(row.first, skipOffstage: false),
              );
              for (final day in row) {
                _expectTappable(tester, calendarDay(day));
              }
            }
            // Последний день самого месяца: день соседнего месяца перенёс бы
            // просмотр в свой месяц.
            final lastDay = shown.weeks
                .expand((week) => week)
                .lastWhere((day) => day.month == shown.today.month);
            await _reveal(tester, calendarDay(lastDay, skipOffstage: false));
            await tester.tap(calendarDay(lastDay));
            await tester.pump();
            expect(repository.queries, hasLength(2));
            expect(repository.queries[1].date, lastDay);
            repository.completeFirst(1, [
              catalogPageItem(2, date: lastDay),
            ], total: 1);
            await _settle(tester);
            expect(visibleWeeks(tester, skipOffstage: false), shown.weeks);
            expect(
              find.byTooltip(l10n.dailyChoiceCalendarCollapse),
              findsOneWidget,
            );

            // Подпись нового выбранного дня может занять другое число строк,
            // поэтому сворачивание сравнивается с раскрытым после выбора.
            final selected = _measure(tester);
            await _tapCommand(tester, l10n.dailyChoiceCalendarCollapse);
            final collapsed = _measure(tester);
            expect(collapsed.rows, 1);
            expect(
              selected.calendar.height - collapsed.calendar.height,
              moreOrLessEquals(grown),
            );
            expect(
              selected.countOffset - collapsed.countOffset,
              moreOrLessEquals(grown),
            );
            expect(tester.takeException(), isNull);
          });
        }

        testWidgets('у страницы одна вертикальная прокрутка: жест из '
            'календаря прокручивает страницу, горизонтальный листает неделю, '
            'а фильтры, подгрузка и последняя строка достижимы жестами над '
            'основным действием и панелью', (tester) async {
          final repository = CatalogPageRepository();
          await _open(tester, repository, locale, textScale, today: _today);
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
          expect(_pageScroll, findsOneWidget);
          final scroll = tester.state<ScrollableState>(_pageScroll).position;

          final day = calendarDay(date(2026, 10, 1));
          await _reveal(tester, day);
          final before = scroll.pixels;
          await tester.drag(day, const Offset(0, -150));
          await tester.pumpAndSettle();
          expect(scroll.pixels, greaterThan(before + 100));
          expect(visibleWeeks(tester), weeksFrom(date(2026, 9, 28), 1));

          await _reveal(tester, day);
          final scrolled = scroll.pixels;
          // Больше половины, но меньше ширины недели.
          await tester.drag(day, const Offset(-200, 0));
          await tester.pumpAndSettle();
          expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
          expect(scroll.pixels, scrolled);
          expect(repository.queries, hasLength(1));

          for (final key in _filterKeys) {
            await _dragUntilReachable(
              tester,
              find.byKey(ValueKey(key), skipOffstage: false),
            );
          }
          final loadMore = find.byKey(
            const ValueKey('daily-choice-load-more'),
            skipOffstage: false,
          );
          await _dragUntilReachable(tester, loadMore);
          await tester.tap(loadMore);
          await tester.pump();
          expect(repository.queries, hasLength(2));
          expect(repository.queries[1].date, _today);
          expect(repository.queries[1].cursor, isA<CatalogPageCursor>());
          repository.completeMore(1, [catalogPageItem(21, date: _today)]);
          await tester.pumpAndSettle();

          final lastRow = find.byKey(
            const ValueKey('daily-choice-row-21'),
            skipOffstage: false,
          );
          await _dragToEnd(tester);
          _expectAtEnd(tester, lastRow);
          await _expectWholeTexts(tester, textScale);
          await _dragUntilReachable(
            tester,
            find.byTooltip(l10n.dailyChoiceCalendarExpand, skipOffstage: false),
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('начальные загрузка и отказ, отказ повтора и пустая '
            'выдача показаны целиком и достижимы жестами над основным '
            'действием и панелью', (tester) async {
          final repository = CatalogPageRepository();
          await _open(tester, repository, locale, textScale, today: _today);
          final l10n = _l10n(tester);
          final retry = find.widgetWithText(
            TextButton,
            l10n.commonRetry,
            skipOffstage: false,
          );

          await _dragUntilReachable(
            tester,
            find.text(l10n.dailyChoiceCatalogLoading, skipOffstage: false),
          );
          await _expectWholeTexts(tester, textScale);

          for (final attempt in [0, 1]) {
            repository.failUnavailable(attempt);
            await tester.pumpAndSettle();
            await _dragUntilReachable(
              tester,
              find.text(
                l10n.dailyChoiceCatalogUnavailable,
                skipOffstage: false,
              ),
            );
            await _dragUntilReachable(tester, retry);
            await _expectWholeTexts(tester, textScale);
            await tester.tap(retry);
            await tester.pump();
            expect(repository.queries, hasLength(attempt + 2));
            expect(repository.queries[attempt + 1].date, _today);
            expect(repository.queries[attempt + 1].cursor, isNull);
          }

          repository.completeFirst(2, [], total: 0);
          await tester.pumpAndSettle();
          await _dragUntilReachable(
            tester,
            find.text(
              l10n.dailyChoiceCatalogTotalCount(0),
              skipOffstage: false,
            ),
          );
          await _dragUntilReachable(
            tester,
            find.text(l10n.dailyChoiceCatalogEmpty, skipOffstage: false),
          );
          await _expectWholeTexts(tester, textScale);
          await _dragUntilReachable(
            tester,
            calendarDay(date(2026, 10, 1), skipOffstage: false),
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('фильтр выполнения показывает название и каждое '
            'состояние целиком, а меню выбирает состояние для выбранного дня', (
          tester,
        ) async {
          final repository = CatalogPageRepository();
          await _open(tester, repository, locale, textScale, today: _today);
          repository.completeFirst(0, [], total: 0);
          await tester.pumpAndSettle();
          final l10n = _l10n(tester);
          final filter = find.byKey(
            const ValueKey('daily-choice-completion-filter'),
            skipOffstage: false,
          );

          for (final (index, (value, state)) in [
            (false, l10n.dailyChoiceCatalogIncomplete),
            (true, l10n.dailyChoiceCatalogCompleted),
            (null, l10n.dailyChoiceCatalogAllStates),
          ].indexed) {
            await _dragUntilReachable(tester, filter);
            await tester.tap(filter);
            await tester.pumpAndSettle();
            final item = find
                .byWidgetPredicate(
                  (widget) =>
                      widget is DropdownMenuItem<bool?> &&
                      widget.value == value,
                )
                .last;
            _expectTappable(tester, item);
            _expectWholeTextsIn(tester, item, textScale);
            await tester.tap(item);
            await tester.pump();
            expect(repository.queries, hasLength(index + 2));
            expect(repository.queries[index + 1].date, _today);
            expect(repository.queries[index + 1].isCompleted, value);
            repository.completeFirst(index + 1, [], total: 0);
            await tester.pumpAndSettle();

            await _dragUntilReachable(tester, filter);
            expect(
              find.descendant(of: filter, matching: find.text(state)),
              findsOneWidget,
            );
            await _expectWholeTexts(tester, textScale);
          }
          expect(tester.takeException(), isNull);
        });
      });
    }
  }
}

/// Допуск сравнения координат.
const _epsilon = 0.01;

/// Фильтры каталога под календарём: выполнение и сброс.
const _filterKeys = [
  'daily-choice-completion-filter',
  'daily-choice-clear-filters',
];

/// Общая вертикальная прокрутка страницы каталога. Перелистывание периодов
/// календаря — горизонтальная прокрутка внутри неё.
final _pageScroll = find.descendant(
  of: find.byType(DailyChoiceCatalogPage),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable &&
        axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
  ),
);

final _createAction = find.byKey(
  const ValueKey('daily-choice-create-from-action'),
);

/// Открывает каталог на узком телефоне с системным размером текста
/// [textScale]; первое чтение остаётся незавершённым.
Future<void> _open(
  WidgetTester tester,
  CatalogPageRepository repository,
  Locale locale,
  double textScale, {
  required CalendarDate today,
}) => pumpCatalogPage(
  tester,
  repository,
  today: today,
  locale: locale,
  size: _screen,
  textScale: textScale,
);

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(DailyChoiceCalendar, skipOffstage: false)),
);

/// Подпись полной выбранной даты в шапке календаря по текущей локали.
String _selectedDateLabel(WidgetTester tester, CalendarDate value) {
  final context = tester.element(find.byType(DailyChoiceCalendar));
  return AppLocalizations.of(context).dailyChoiceCalendarSelectedDate(
    MaterialLocalizations.of(context)
        .formatFullDate(DateTime.utc(value.year, value.month, value.day)),
  );
}

/// Видимая часть страницы: под шапкой и над основным действием, которое
/// само стоит над панелью основной навигации.
Rect _visibleArea(WidgetTester tester) {
  final appBar = tester.getRect(find.byType(AppBar));
  final action = tester.getRect(_createAction);
  final bar = tester.getRect(find.byType(AppNavigationBar));
  expect(action.bottom, lessThanOrEqualTo(bar.top));
  return Rect.fromLTRB(0, appBar.bottom, _screen.width, action.top);
}

/// Элемент [finder] целиком лежит в видимой части страницы, над основным
/// действием и панелью, и касание его середины достигает его.
void _expectReachable(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  expect(
    _contains(_visibleArea(tester), rect),
    isTrue,
    reason: '$finder: $rect вне видимой части ${_visibleArea(tester)}',
  );
  _expectTappable(tester, finder);
}

/// Последний элемент выдачи [finder] на прокрученной до конца странице
/// заканчивается над основным действием и панелью, и касание его видимой
/// части достигает его. При крупном тексте строка выше видимой части
/// страницы, поэтому целиком она видна только по частям при прокрутке.
void _expectAtEnd(WidgetTester tester, Finder finder) {
  final area = _visibleArea(tester);
  final rect = tester.getRect(finder);
  expect(rect.bottom, lessThanOrEqualTo(area.bottom + _epsilon));
  expect(rect.bottom, greaterThan(area.top));
  _expectHit(tester, finder, rect.intersect(area).center);
}

/// Прокручивает страницу жестами по видимой части, пока [finder] не окажется
/// в ней целиком, и проверяет его достижимость.
///
/// [finder] находит элемент и за краем видимой части; ещё не построенная
/// строка выдачи лежит ниже построенных и далеко, поэтому к ней страница
/// листается крупнее.
Future<void> _dragUntilReachable(WidgetTester tester, Finder finder) async {
  for (var step = 0; step < 200; step++) {
    final area = _visibleArea(tester);
    final isBuilt = finder.evaluate().isNotEmpty;
    if (isBuilt && _contains(area, tester.getRect(finder))) {
      _expectReachable(tester, finder);
      return;
    }
    final double shift = !isBuilt
        ? -300
        : tester.getRect(finder).bottom > area.bottom
        ? -120
        : 120;
    await tester.dragFrom(
      Offset(area.left + 24, area.center.dy),
      Offset(0, shift),
    );
    await _settle(tester);
  }
  fail('Жестами не удалось целиком показать $finder.');
}

/// Прокручивает страницу жестами до конца выдачи.
Future<void> _dragToEnd(WidgetTester tester) async {
  final scroll = tester.state<ScrollableState>(_pageScroll).position;
  for (var step = 0; step < 200; step++) {
    if (scroll.pixels >= scroll.maxScrollExtent - _epsilon) return;
    final area = _visibleArea(tester);
    await tester.dragFrom(
      Offset(area.left + 24, area.center.dy),
      const Offset(0, -300),
    );
    await _settle(tester);
  }
  fail('Жестами не удалось дойти до конца выдачи.');
}

/// Доводит до конца прокрутку и перелистывание календаря. Индикатор загрузки
/// выдачи не даёт дождаться покоя всех анимаций, поэтому время продвигается
/// явно.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
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
        tester.renderObject(
          find.byType(DailyChoiceCalendar, skipOffstage: false),
        ),
        alignment: 0.5,
        targetRenderObject: tester.renderObject(finder),
      );
  await tester.pump();
}

/// Выполняет команду шапки календаря касанием после прокрутки к ней.
Future<void> _tapCommand(WidgetTester tester, String name) async {
  await _reveal(tester, find.byTooltip(name, skipOffstage: false));
  final command = find.byTooltip(name);
  _expectTappable(tester, command);
  await tester.tap(command);
  await _settle(tester);
}

/// Касание середины [finder] на экране достигает его, а не другого элемента.
void _expectTappable(WidgetTester tester, Finder finder) => _expectHit(
  tester,
  finder,
  _globalRect(tester.renderObject<RenderBox>(finder)).center,
);

/// Касание экрана в точке [position] достигает [finder], а не другого
/// элемента.
void _expectHit(WidgetTester tester, Finder finder, Offset position) {
  final box = tester.renderObject<RenderBox>(finder);
  expect(
    (Offset.zero & _screen).contains(position),
    isTrue,
    reason: 'Точка касания $finder вне экрана: $position',
  );
  expect(
    tester
        .hitTestOnBinding(position)
        .path
        .any((entry) => identical(entry.target, box)),
    isTrue,
    reason: 'Касание в $position не достигает $finder',
  );
}

/// Положение календаря и выдачи под ним в общей прокрутке.
///
/// [countOffset] — расстояние от верха календаря до количества выдачи; оно не
/// зависит от прокрутки страницы.
typedef _Layout = ({
  Rect calendar,
  int rows,
  double rowHeight,
  double countOffset,
});

_Layout _measure(WidgetTester tester) {
  final calendar = _rect(
    tester,
    find.byType(DailyChoiceCalendar, skipOffstage: false),
  );
  final weeks = visibleWeeks(tester, skipOffstage: false);
  final firstDay = _rect(
    tester,
    calendarDay(
      weeks.first.firstWhere((day) => day != null)!,
      skipOffstage: false,
    ),
  );
  final count = _rect(
    tester,
    find.text(
      _l10n(tester).dailyChoiceCatalogTotalCount(1),
      skipOffstage: false,
    ),
  );
  return (
    calendar: calendar,
    rows: weeks.length,
    rowHeight: firstDay.height,
    countOffset: count.top - calendar.top,
  );
}

/// Видимые недели календаря — семь смежных колонок во всю ширину экрана;
/// строки одна под другой, каждая ячейка не меньше области нажатия.
void _expectColumns(WidgetTester tester, List<List<CalendarDate>> weeks) {
  expect(visibleWeeks(tester, skipOffstage: false), weeks);
  final calendar = _rect(
    tester,
    find.byType(DailyChoiceCalendar, skipOffstage: false),
  );
  expect(calendar.left, moreOrLessEquals(0));
  expect(calendar.right, moreOrLessEquals(_screen.width));
  final rows = [
    for (final week in weeks)
      [
        for (final day in week)
          _rect(tester, calendarDay(day, skipOffstage: false)),
      ],
  ];
  for (final (index, row) in rows.indexed) {
    expect(row, hasLength(DateTime.daysPerWeek));
    expect(row.first.left, moreOrLessEquals(calendar.left));
    expect(row.last.right, moreOrLessEquals(calendar.right));
    for (final (column, cell) in row.indexed) {
      expect(cell.width, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(cell.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(cell.top, moreOrLessEquals(row.first.top));
      if (column > 0) {
        expect(cell.left, moreOrLessEquals(row[column - 1].right));
      }
    }
    if (index > 0) {
      expect(row.first.top, moreOrLessEquals(rows[index - 1].first.bottom));
    }
  }
  expect(rows.last.last.bottom, lessThanOrEqualTo(calendar.bottom + _epsilon));
}

/// Команды шапки календаря лежат в ширине экрана и не меньше области нажатия.
void _expectCommands(WidgetTester tester) {
  final commands = find.descendant(
    of: find.byType(DailyChoiceCalendar, skipOffstage: false),
    matching: find.byType(IconButton, skipOffstage: false),
  );
  expect(commands, findsNWidgets(3));
  for (final command in commands.evaluate()) {
    final rect = _globalRect(command.renderObject! as RenderBox);
    expect(rect.left, greaterThanOrEqualTo(-_epsilon));
    expect(rect.right, lessThanOrEqualTo(_screen.width + _epsilon));
    expect(rect.width, greaterThanOrEqualTo(kMinInteractiveDimension));
    expect(rect.height, greaterThanOrEqualTo(kMinInteractiveDimension));
  }
}

/// Проходит общую прокрутку страницы от начала до конца и проверяет каждый
/// построенный текст календаря, фильтров и выдачи: он показан целиком в
/// системном масштабе [textScale] и лежит в ширине экрана. Затем возвращает
/// прежнее положение прокрутки.
Future<void> _expectWholeTexts(WidgetTester tester, double textScale) async {
  final scroll = tester.state<ScrollableState>(_pageScroll).position;
  final initial = scroll.pixels;
  var offset = scroll.minScrollExtent;
  while (true) {
    scroll.jumpTo(offset);
    await tester.pump();
    _expectWholeTextsIn(
      tester,
      find.byType(CustomScrollView, skipOffstage: false),
      textScale,
    );
    if (offset >= scroll.maxScrollExtent) break;
    offset = (offset + 200).clamp(
      scroll.minScrollExtent,
      scroll.maxScrollExtent,
    );
  }
  scroll.jumpTo(initial);
  await tester.pump();
}

/// Каждый текст внутри [scope] показан целиком: без многоточия и потери
/// строк, со всей высотой строк при своей ширине, в системном масштабе
/// [textScale] без уменьшения и в ширине экрана.
void _expectWholeTextsIn(WidgetTester tester, Finder scope, double textScale) {
  // Значки рисуются глифом шрифта без масштаба текста, поэтому проверяются
  // только тексты.
  final paragraphs = find.descendant(
    of: find.descendant(
      of: scope,
      matching: find.byType(Text, skipOffstage: false),
    ),
    matching: find.byType(RichText, skipOffstage: false),
  );
  for (final element in paragraphs.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    if (!paragraph.attached || !paragraph.hasSize) continue;
    final text = paragraph.text.toPlainText();
    expect(paragraph.didExceedMaxLines, isFalse, reason: '«$text» обрезан');
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
        paragraph.getMaxIntrinsicHeight(paragraph.size.width) - _epsilon,
      ),
      reason: '«$text»: часть строк не помещается',
    );
    if (!paragraph.softWrap) {
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(
          paragraph.getMaxIntrinsicWidth(double.infinity) - _epsilon,
        ),
        reason: '«$text» не помещается в строку',
      );
    }
    expect(
      paragraph.textScaler.scale(10),
      moreOrLessEquals(10 * textScale),
      reason: '«$text»: масштаб текста ограничен',
    );
    final rect = _globalRect(paragraph);
    expect(rect.left, greaterThanOrEqualTo(-_epsilon), reason: '«$text»');
    expect(
      rect.right,
      lessThanOrEqualTo(_screen.width + _epsilon),
      reason: '«$text»',
    );
  }
}

bool _contains(Rect outer, Rect inner) =>
    inner.left >= outer.left - _epsilon &&
    inner.top >= outer.top - _epsilon &&
    inner.right <= outer.right + _epsilon &&
    inner.bottom <= outer.bottom + _epsilon;

Rect _rect(WidgetTester tester, Finder finder) =>
    _globalRect(tester.renderObject<RenderBox>(finder));

Rect _globalRect(RenderBox box) =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
