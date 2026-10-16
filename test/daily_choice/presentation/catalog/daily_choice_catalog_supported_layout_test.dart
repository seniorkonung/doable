import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart';
import 'package:doable/src/design_system/components/calendar_handle.dart';
import 'package:doable/src/design_system/components/day_heading.dart';
import 'package:doable/src/design_system/components/month_grid_day.dart';
import 'package:doable/src/design_system/components/notice.dart';
import 'package:doable/src/design_system/components/period_picker.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/daily_choice_local_date.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import 'daily_choice_calendar_test_support.dart';
import 'daily_choice_catalog_page_test_support.dart';

void main() {
  for (final onDate in [false, true]) {
    for (final locale in const [Locale('ru'), Locale('en')]) {
      final name = onDate ? 'каталог на дату' : 'корневой каталог';
      testWidgets('$name на границе 360×720 сохраняет доступность '
          'дней, выбора периода, сообщения и выдачи при переходах и отказе отметок '
          '(${locale.languageCode})', (tester) async {
        await _setSupportBoundary(tester);
        final repository = CatalogPageRepository();
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
}

Future<void> _open(
  WidgetTester tester,
  CatalogPageRepository repository,
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
        ControlledDailyChoiceLocalDate(selected).override,
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
    unawaited(router.push(DailyChoiceDateCatalogRoute(date: selected)));
  } else {
    openDailyChoicesOn(router);
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
  await (FontLoader('Inter')..addFont(
        rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
      ))
      .load();
}

/// Общий сценарий доступности закреплённого блока в обоих каталогах.
/// Начальное чтение выдачи и отметок ещё не завершено; выбран октябрь 2026.
Future<void> _expectUsableCatalog(
  WidgetTester tester,
  CatalogPageRepository repository, {
  required CalendarDate initialDate,
}) async {
  repository.completeFirst(0, [
    for (var number = 1; number <= 20; number++)
      catalogPageItem(number, date: initialDate),
  ], total: 20);
  await tester.pumpAndSettle();
  final calendar = find.byType(DailyChoiceCalendar);
  final l10n = AppLocalizations.of(tester.element(calendar));
  _expectCalendarSpacing(tester);
  repository.failDayStatuses(0);
  await tester.pumpAndSettle();

  final body = find.byType(DailyChoiceCatalogBody);
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
  await tester.tap(find.bySemanticsLabel(l10n.dailyChoiceCalendarExpand));
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
  final collapse = find.bySemanticsLabel(l10n.dailyChoiceCalendarCollapse);
  final collapseRect = tester.getRect(collapse);
  expect(collapseRect.intersect(calendarRect.inflate(0.01)), collapseRect);
  expect(collapse.hitTestable(), findsOneWidget);
  expect(
    find.text(l10n.dailyChoiceCalendarDayMarksUnavailable),
    findsOneWidget,
  );
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
    find.bySemanticsLabel(l10n.dailyChoiceCalendarChooseYearAndMonth),
  );
  await tester.pumpAndSettle();
  await tester.drag(find.text('2025'), const Offset(-280, 0));
  await tester.pumpAndSettle();
  expect(find.text('2032–2043'), findsOneWidget);
  for (final fromMonths in [false, true]) {
    if (fromMonths) {
      await tester.tap(find.text('2035'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(l10n.dailyChoiceCalendarNextYear));
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
          ? l10n.dailyChoiceCalendarPreviousYear
          : l10n.dailyChoiceCalendarPreviousYears,
      fromMonths
          ? l10n.dailyChoiceCalendarNextYear
          : l10n.dailyChoiceCalendarNextYears,
      l10n.dailyChoiceCalendarBackToMonthDays,
      l10n.dailyChoiceCalendarCollapse,
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
  await tester.tap(
    find.bySemanticsLabel(l10n.dailyChoiceCalendarBackToMonthDays),
  );
  await tester.pumpAndSettle();
  expect(visibleWeeks(tester), weeks);

  final selected = date(2026, 10, 31);
  await tester.tap(calendarDay(selected));
  repository.completeFirst(1, [
    for (var number = 1; number <= 20; number++)
      catalogPageItem(number, date: selected),
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
    find.bySemanticsLabel(l10n.dailyChoiceCalendarExpand).hitTestable(),
    findsOneWidget,
  );
  expect(
    find.text(l10n.dailyChoiceCalendarDayMarksUnavailable),
    findsOneWidget,
  );
  await _scrollToLastRow(tester, list);
  expect(tester.takeException(), isNull);
}

Future<void> _expectUnclippedReturn(
  WidgetTester tester,
  Rect usableBody,
  Finder list,
  Finder cells,
) async {
  final calendar = find.byType(DailyChoiceCalendar);
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
  final calendar = tester.getRect(find.byType(DailyChoiceCalendar));
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

/// Отступ и ручка сохраняют прежние 52 dp во всех представлениях каталогов.
void _expectCalendarSpacing(WidgetTester tester) {
  final body = find.byType(DailyChoiceCatalogBody);
  final safeTop =
      tester.getTopLeft(body).dy +
      MediaQuery.paddingOf(tester.element(body)).top;
  final calendarTop = tester.getTopLeft(find.byType(DailyChoiceCalendar)).dy;
  final topPadding = calendarTop - safeTop;
  expect(topPadding, 16);
  expect(topPadding + tester.getSize(find.byType(CalendarHandle)).height, 52);
}

Future<void> _scrollToLastRow(WidgetTester tester, Finder list) async {
  final lastRow = find.byKey(const ValueKey('daily-choice-row-20'));
  expect(lastRow.hitTestable(), findsNothing);
  final viewport = tester.getRect(list);
  await tester.dragFrom(viewport.center, const Offset(0, -10000));
  await tester.pumpAndSettle();
  final last = tester.getRect(lastRow);
  expect(last.intersect(viewport).height, greaterThan(0));
  expect(last.bottom, closeTo(viewport.bottom, 0.01));
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
