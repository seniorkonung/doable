import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar.dart';
import 'package:doable/src/design_system/components/calendar_handle.dart';
import 'package:doable/src/design_system/components/day_heading.dart';
import 'package:doable/src/design_system/components/month_grid_day.dart';
import 'package:doable/src/design_system/components/notice.dart';
import 'package:doable/src/design_system/components/period_picker.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/controlled_local_date.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import 'action_day_calendar_test_support.dart';
import 'action_day_page_test_support.dart';

void main() {
  for (final onDate in [false, true]) {
    for (final locale in const [Locale('ru'), Locale('en')]) {
      final name = onDate ? 'экран дня на дату' : 'корневой экран дня';
      testWidgets('$name на границе 360×720 сохраняет доступность '
          'дней, выбора периода, сообщения и выдачи при переходах и отказе отметок '
          '(${locale.languageCode})', (tester) async {
        await _setSupportBoundary(tester);
        final repository = ActionDayRepository();
        final selected = date(2026, 10, 8);
        await _open(tester, repository, selected, locale, onDate: onDate);
        if (onDate) {
          expect(tester.getSize(find.byType(AppBar)).height, 56 + 24);
        } else {
          expect(find.byType(AppBar), findsNothing);
        }
        await _expectUsableCatalog(tester, repository, initialDate: selected);
      });
    }
  }

  // Отметка «Сегодня» может стоять на второй строке, поэтому высота заголовка
  // не годится: проверяется, что символы дня недели занимают одну строку
  // абзаца. Место строки обновления при крупном шрифте сужено до кольца.
  for (final (locale, selected, weekday) in [
    (const Locale('ru'), date(2026, 10, 5), 'Понедельник'),
    (const Locale('ru'), date(2026, 10, 4), 'Воскресенье'),
    (const Locale('en'), date(2026, 10, 7), 'Wednesday'),
  ]) {
    testWidgets('при масштабе 200% в окне 360 день недели «$weekday» не '
        'разрывается внутри слова', (tester) async {
      await _loadInter();
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = ActionDayRepository();
      await pumpActionDay(
        tester,
        repository,
        today: selected,
        locale: locale,
        size: const Size(360, 2000),
      );
      repository.completeFirst(0, [actionDayItem(1, date: selected)], total: 1);
      await tester.pumpAndSettle();

      final paragraph = tester.renderObject<RenderParagraph>(
        find.textContaining(weekday),
      );
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: weekday.length),
      );
      expect({for (final box in boxes) box.top}, hasLength(1));
    });
  }
}

Future<void> _open(
  WidgetTester tester,
  ActionDayRepository repository,
  CalendarDate selected,
  Locale locale, {
  required bool onDate,
}) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
        ControlledLocalDate(selected).override,
      ],
      retry: (count, error) => null,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (onDate) {
    unawaited(router.push(ActionDayDateRoute(date: selected)));
  } else {
    openActionsOn(router);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Нижняя граница поддержки с системными панелями и стандартным масштабом.
Future<void> _setSupportBoundary(WidgetTester tester) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(360, 720)
    ..padding = const FakeViewPadding(top: 24, bottom: 48)
    ..viewPadding = const FakeViewPadding(top: 24, bottom: 48);
  addTearDown(tester.view.reset);
  // Реальный шрифт нужен для проверки переносов сообщения в обеих локалях.
  await _loadInter();
}

Future<void> _loadInter() =>
    (FontLoader('Inter')..addFont(
          rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
        ))
        .load();

/// Общий сценарий доступности закреплённого блока на обоих экранах дня.
/// Начальное чтение выдачи и отметок ещё не завершено; выбран октябрь 2026.
Future<void> _expectUsableCatalog(
  WidgetTester tester,
  ActionDayRepository repository, {
  required CalendarDate initialDate,
}) async {
  repository.completeFirst(0, [
    for (var number = 1; number <= 20; number++)
      actionDayItem(number, date: initialDate),
  ], total: 20);
  await tester.pumpAndSettle();
  final calendar = find.byType(ActionDayCalendar);
  final l10n = AppLocalizations.of(tester.element(calendar));
  _expectCalendarSpacing(tester);
  repository.failDayStatuses(0);
  await tester.pumpAndSettle();

  final body = _catalogContent;
  final media = MediaQuery.of(tester.element(body));
  expect(media.size, const Size(360, 720));
  expect(media.devicePixelRatio, 1);
  expect(media.textScaler.scale(14), 14);
  final bodyRect = tester.getRect(body);
  final usableBody = Rect.fromLTRB(
    bodyRect.left,
    bodyRect.top + media.padding.top,
    bodyRect.right,
    bodyRect.bottom,
  );
  final list = find.descendant(
    of: body,
    matching: find.byType(CustomScrollView),
  );
  final weekHeight = tester.getSize(calendar).height;
  await tester.tap(find.bySemanticsLabel(l10n.actionCalendarExpand));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  final movingHeight = tester.getSize(calendar).height;
  expect(movingHeight, greaterThan(weekHeight));
  _expectTransitionLayout(tester, usableBody, list);
  await tester.pumpAndSettle();
  expect(tester.getSize(calendar).height, greaterThan(movingHeight));
  final listRect = tester.getRect(list);
  expect(
    find.descendant(
      of: body,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    ),
    findsOneWidget,
  );
  expect(usableBody.height, greaterThanOrEqualTo(528));
  expect(
    usableBody.bottom,
    tester.getTopLeft(find.byType(AppNavigationBar)).dy,
  );
  expect(listRect.top - usableBody.top, lessThanOrEqualTo(480));
  expect(listRect.height, greaterThanOrEqualTo(48));
  expect(listRect.bottom, usableBody.bottom);

  final calendarRect = tester.getRect(calendar);
  _expectCalendarSpacing(tester);
  expect(calendarRect.intersect(usableBody.inflate(0.01)), calendarRect);
  final weeks = weeksFrom(date(2026, 9, 28), 6);
  expect(visibleWeeks(tester), weeks);
  for (final day in weeks.expand((week) => week)) {
    final cell = calendarDay(day);
    final cellRect = tester.getRect(cell);
    expect(cellRect.intersect(calendarRect.inflate(0.01)), cellRect);
    expect(cell.hitTestable(), findsOneWidget);
  }
  final collapse = find.bySemanticsLabel(l10n.actionCalendarCollapse);
  final collapseRect = tester.getRect(collapse);
  expect(collapseRect.intersect(calendarRect.inflate(0.01)), collapseRect);
  expect(collapse.hitTestable(), findsOneWidget);
  expect(find.text(l10n.actionCalendarDayMarksUnavailable), findsOneWidget);
  final notice = find.byType(Notice);
  final noticeRect = tester.getRect(notice);
  expect(noticeRect.intersect(calendarRect.inflate(0.01)), noticeRect);
  expect(noticeRect.bottom, lessThanOrEqualTo(listRect.top));
  _expectCalendarTextsWhole(tester, calendar, usableBody);

  await _scrollToLastRow(tester, list);
  expect(tester.getRect(calendar), calendarRect);
  expect(tester.getRect(notice), noticeRect);
  await _expectUnclippedReturn(
    tester,
    usableBody,
    list,
    find.byType(MonthGridDay),
  );

  await tester.tap(
    find.bySemanticsLabel(l10n.actionCalendarChooseYearAndMonth),
  );
  await tester.pumpAndSettle();
  await tester.drag(find.text('2025'), const Offset(-280, 0));
  await tester.pumpAndSettle();
  expect(find.text('2032–2043'), findsOneWidget);
  for (final fromMonths in [false, true]) {
    if (fromMonths) {
      await tester.tap(find.text('2035'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(l10n.actionCalendarNextYear));
      await tester.pumpAndSettle();
      expect(find.text('2036'), findsOneWidget);
    }
    final periodRect = tester.getRect(calendar);
    _expectCalendarSpacing(tester);
    final periodListRect = tester.getRect(list);
    expect(periodRect.intersect(usableBody.inflate(0.01)), periodRect);
    expect(periodListRect.height, greaterThanOrEqualTo(48));
    expect(periodListRect.bottom, usableBody.bottom);
    final cells = find.descendant(
      of: find.byType(PeriodPicker),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.button == true,
      ),
    );
    expect(cells, findsNWidgets(12));
    for (final cell in cells.evaluate()) {
      expect(find.byWidget(cell.widget).hitTestable(), findsOneWidget);
    }
    for (final label in [
      fromMonths
          ? l10n.actionCalendarPreviousYear
          : l10n.actionCalendarPreviousYears,
      fromMonths ? l10n.actionCalendarNextYear : l10n.actionCalendarNextYears,
      l10n.actionCalendarBackToMonthDays,
      l10n.actionCalendarCollapse,
    ]) {
      expect(find.bySemanticsLabel(label).hitTestable(), findsOneWidget);
    }
    final periodNoticeRect = tester.getRect(notice);
    expect(periodNoticeRect.bottom, lessThanOrEqualTo(periodListRect.top));
    _expectCalendarTextsWhole(tester, calendar, usableBody);
    await tester.drag(list, const Offset(0, 10000));
    await tester.pumpAndSettle();
    await _scrollToLastRow(tester, list);
    expect(tester.getRect(calendar), periodRect);
    expect(tester.getRect(notice), periodNoticeRect);
    await _expectUnclippedReturn(tester, usableBody, list, cells);
  }
  await tester.tap(find.bySemanticsLabel(l10n.actionCalendarBackToMonthDays));
  await tester.pumpAndSettle();
  expect(visibleWeeks(tester), weeks);

  final selected = date(2026, 10, 31);
  await tester.tap(calendarDay(selected));
  repository.completeFirst(1, [
    for (var number = 1; number <= 20; number++)
      actionDayItem(number, date: selected),
  ], total: 20);
  await tester.pumpAndSettle();
  expect(repository.queries.last.date, selected);
  expect(dayCell(tester, selected).isSelected, isTrue);
  expect(visibleWeeks(tester), weeks);
  expect(collapse.hitTestable(), findsOneWidget);
  expect(listRect.contains(tester.getTopLeft(find.byType(DayHeading))), isTrue);

  await tester.tap(collapse);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  _expectTransitionLayout(tester, usableBody, list);
  await tester.pumpAndSettle();
  expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 26), 1));
  _expectCalendarSpacing(tester);
  expect(
    find.bySemanticsLabel(l10n.actionCalendarExpand).hitTestable(),
    findsOneWidget,
  );
  expect(find.text(l10n.actionCalendarDayMarksUnavailable), findsOneWidget);
  await _scrollToLastRow(tester, list);
  expect(tester.takeException(), isNull);
}

Future<void> _expectUnclippedReturn(
  WidgetTester tester,
  Rect usableBody,
  Finder list,
  Finder cells,
) async {
  final calendar = find.byType(ActionDayCalendar);
  final expanded = tester.getRect(calendar);
  final sizes = [
    for (var i = 0; i < cells.evaluate().length; i++)
      tester.getSize(cells.at(i)),
  ];
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(CalendarHandle)),
  );
  await gesture.moveBy(const Offset(0, -20));
  await gesture.moveBy(const Offset(0, -40));
  await tester.pump();
  final moving = tester.getRect(calendar);
  expect(moving.height, closeTo(expanded.height - 40, 0.01));
  _expectTransitionLayout(tester, usableBody, list);
  expect([
    for (var i = 0; i < cells.evaluate().length; i++)
      tester.getSize(cells.at(i)),
  ], sizes);

  final scroll = tester
      .state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      )
      .position;
  final offset = scroll.pixels;
  await tester.dragFrom(
    tester.getCenter(list),
    const Offset(0, 1000),
    pointer: 2,
  );
  await tester.pumpAndSettle();
  expect(scroll.pixels, lessThan(offset));
  expect(tester.getRect(calendar), moving);

  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 15));
  expect(tester.getSize(calendar).height, greaterThan(moving.height));
  expect(tester.getSize(calendar).height, lessThan(expanded.height));
  _expectTransitionLayout(tester, usableBody, list);
  expect([
    for (var i = 0; i < cells.evaluate().length; i++)
      tester.getSize(cells.at(i)),
  ], sizes);
  await tester.pumpAndSettle();
  expect(tester.getRect(calendar), expanded);
}

void _expectTransitionLayout(
  WidgetTester tester,
  Rect usableBody,
  Finder list,
) {
  final calendar = tester.getRect(find.byType(ActionDayCalendar));
  final listRect = tester.getRect(list);
  expect(calendar.intersect(usableBody.inflate(0.01)), calendar);
  expect(listRect.height, greaterThanOrEqualTo(48));
  expect(listRect.bottom, usableBody.bottom);
  _expectCalendarSpacing(tester);
  for (final finder in [find.byType(CalendarHandle), find.byType(Notice)]) {
    final rect = tester.getRect(finder);
    expect(rect.intersect(calendar.inflate(0.01)), rect);
    expect(rect.bottom, lessThanOrEqualTo(listRect.top));
    RenderObject child = tester.renderObject(finder);
    while (child.parent != null) {
      final parent = child.parent!;
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        final globalClip = MatrixUtils.transformRect(
          parent.getTransformTo(null),
          clip,
        );
        expect(rect.intersect(globalClip.inflate(0.01)), rect);
      }
      child = parent;
    }
  }
  expect(find.byType(CalendarHandle).hitTestable(), findsOneWidget);
  _expectCalendarTextsWhole(tester, find.byType(Notice), usableBody);
  expect(tester.takeException(), isNull);
}

/// Содержимое экрана дня в области тела страницы: под `AppBar` и над панелью.
final _catalogContent = find
    .ancestor(
      of: find.byType(ActionDayCalendar),
      matching: find.byType(SafeArea),
    )
    .first;

/// Отступ и ручка сохраняют прежние 52 dp во всех представлениях экрана дня.
void _expectCalendarSpacing(WidgetTester tester) {
  final safeTop =
      tester.getTopLeft(_catalogContent).dy +
      MediaQuery.paddingOf(tester.element(_catalogContent)).top;
  final calendarTop = tester.getTopLeft(find.byType(ActionDayCalendar)).dy;
  final topPadding = calendarTop - safeTop;
  expect(topPadding, 16);
  expect(topPadding + tester.getSize(find.byType(CalendarHandle)).height, 52);
}

Future<void> _scrollToLastRow(WidgetTester tester, Finder list) async {
  final lastRow = find.byKey(
    const ValueKey('action-day-row-20'),
    skipOffstage: false,
  );
  expect(lastRow.hitTestable(), findsNothing);
  final viewport = tester.getRect(list);
  // Длину ещё не построенных строк список оценивает, поэтому первый жест может
  // остановиться раньше конца.
  for (var drag = 0; drag < 2; drag++) {
    await tester.dragFrom(viewport.center, const Offset(0, -10000));
    await tester.pumpAndSettle();
  }
  final last = tester.getRect(lastRow);
  final completedHeader = tester.getRect(
    find.byKey(const ValueKey('action-day-section-completed')),
  );
  // Второй заголовок стоит на 2 ниже строк первой секции.
  expect(last.bottom, closeTo(completedHeader.top - 2, 0.01));
  expect(completedHeader.bottom, closeTo(viewport.bottom - 72, 0.01));
  // Свободное место и заголовок выше этой области, поэтому строка видна чуть
  // раньше конца выдачи.
  await tester.dragFrom(
    viewport.center,
    Offset(0, viewport.bottom - last.bottom),
  );
  await tester.pumpAndSettle();
  expect(lastRow.hitTestable(), findsOneWidget);
}

void _expectCalendarTextsWhole(
  WidgetTester tester,
  Finder calendar,
  Rect area,
) {
  final texts = find.descendant(of: calendar, matching: find.byType(Text));
  final paragraphs = find.descendant(
    of: texts,
    matching: find.byType(RichText),
  );
  for (final element in paragraphs.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final text = paragraph.text.toPlainText();
    expect(paragraph.didExceedMaxLines, isFalse, reason: text);
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
        paragraph.getMaxIntrinsicHeight(paragraph.size.width),
      ),
      reason: text,
    );
    final rect = MatrixUtils.transformRect(
      paragraph.getTransformTo(null),
      Offset.zero & paragraph.size,
    );
    expect(rect.intersect(area.inflate(0.01)), rect, reason: text);
  }
}
