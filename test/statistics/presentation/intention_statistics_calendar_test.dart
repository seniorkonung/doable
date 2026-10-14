import 'dart:ui' show SemanticsAction, Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/intention_statistics_calendar.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'месяц отмечает только засчитанные дни и предоставляет действие дня',
    (tester) async {
      final opened = <CalendarDate>[];
      await _pump(tester, _month(), onDaySelected: opened.add);
      final texts = AppLocalizations.of(
        tester.element(find.byType(IntentionStatisticsCalendarView)),
      );
      for (final (day, status, icon) in [
        (5, texts.statisticsCalendarDayAllCompleted, Icons.check),
        (7, texts.statisticsCalendarDayHasIncomplete, Icons.circle_outlined),
        (9, texts.statisticsCalendarDayNoChoices, null),
      ]) {
        final label = texts.statisticsCalendarDaySemantics(
          DateTime.utc(2026, 10, day),
          status,
        );
        final cell = find.bySemanticsLabel(label);
        expect(cell, findsOneWidget);
        final node = tester.getSemantics(cell);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(node.flagsCollection.isButton, isTrue);
        expect(node.flagsCollection.isSelected, Tristate.none);
        expect(
          find.descendant(of: cell, matching: find.byType(Icon)),
          icon == null ? findsNothing : findsOneWidget,
        );
        if (icon != null) {
          expect(
            find.descendant(of: cell, matching: find.byIcon(icon)),
            findsOneWidget,
          );
        }
      }
      expect(
        tester.semantics.simulatedAccessibilityTraversal().where(
          (node) => node.getSemanticsData().hasAction(SemanticsAction.tap),
        ),
        hasLength(31),
      );
      for (var i = 0; i < 7; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, [CalendarDate.fromParts(2026, 10, 7)]);
      for (final day in [5, 7, 9]) {
        await tester.tap(find.text('$day'));
        await tester.pumpAndSettle();
        expect(opened.last, CalendarDate.fromParts(2026, 10, day));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('31'), findsOneWidget);
    },
  );

  testWidgets(
    'год содержит все 12 месяцев с мерами и позволяет выбрать месяц клавиатурой',
    (tester) async {
      int? selected;
      final calendar = IntentionStatisticsYearCalendar(
        period: StatisticsYear(2026),
        months: List.generate(
          12,
          (i) => ContributionCounts(
            planned: i == 2 ? 7 : 0,
            contribution: i == 2 ? 3 : 0,
          ),
        ),
      );
      await _pump(
        tester,
        calendar,
        onMonthSelected: (month) => selected = month,
      );
      final texts = AppLocalizations.of(
        tester.element(find.byType(IntentionStatisticsCalendarView)),
      );
      expect(find.text('0 из 0'), findsNWidgets(11));
      expect(find.text('3 из 7'), findsOneWidget);
      for (var month = 1; month <= 12; month++) {
        expect(
          find.text(texts.statisticsMonthName(DateTime.utc(2026, month))),
          findsOneWidget,
        );
      }
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, 3);
      final label = texts.statisticsMonthBarSemantics(
        DateTime.utc(2026, 3),
        texts.statisticsContributionCountsSemantics(3, 7),
      );
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(label))), findsWidgets);
    },
  );

  testWidgets(
    'календарь локализован, начало недели следует локали, текст 3× не скрывает дни и месяцы',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final locale in ['ru', 'en']) {
        CalendarDate? opened;
        await _pump(
          tester,
          _month(),
          locale: locale,
          scale: 3,
          onDaySelected: (date) => opened = date,
        );
        final context = tester.element(
          find.byType(IntentionStatisticsCalendarView),
        );
        final texts = AppLocalizations.of(context);
        final material = MaterialLocalizations.of(context);
        final weekdays = tester
            .widgetList<Text>(find.byType(Text))
            .take(7)
            .map((text) => text.data);
        expect(
          weekdays,
          List.generate(
            7,
            (i) =>
                material.narrowWeekdays[(material.firstDayOfWeekIndex + i) % 7],
          ),
        );
        await tester.ensureVisible(find.text('31'));
        await tester.pumpAndSettle();
        expect(find.text('31').hitTestable(), findsOneWidget);
        await tester.tap(find.text('31'));
        await tester.pumpAndSettle();
        expect(opened, CalendarDate.fromParts(2026, 10, 31));
        expect(tester.takeException(), isNull);
        final year = IntentionStatisticsYearCalendar(
          period: StatisticsYear(2026),
          months: List.generate(
            12,
            (_) => ContributionCounts(planned: 0, contribution: 0),
          ),
        );
        await _pump(tester, year, locale: locale, scale: 3);
        final december = find.text(
          texts.statisticsMonthName(DateTime.utc(2026, 12)),
        );
        await tester.ensureVisible(december);
        await tester.pumpAndSettle();
        expect(december.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

IntentionStatisticsMonthCalendar _month() => IntentionStatisticsMonthCalendar(
  period: StatisticsMonth(2026, 10),
  statuses: {
    CalendarDate.fromParts(2026, 10, 5): DailyChoiceDayStatus.allCompleted,
    CalendarDate.fromParts(2026, 10, 7): DailyChoiceDayStatus.hasIncomplete,
  },
);

Future<void> _pump(
  WidgetTester tester,
  IntentionStatisticsCalendar calendar, {
  String locale = 'ru',
  double scale = 1,
  ValueChanged<int>? onMonthSelected,
  ValueChanged<CalendarDate>? onDaySelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: SingleChildScrollView(
            child: IntentionStatisticsCalendarView(
              calendar: calendar,
              localDate: CalendarDate.fromParts(2026, 10, 12),
              onMonthSelected: onMonthSelected ?? (_) {},
              onDaySelected: onDaySelected ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
