import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../daily_choice/application/daily_choice_day_statuses.dart';
import '../../daily_choice/domain/calendar_date.dart';
import '../application/contribution_counts.dart';
import '../application/intention_statistics_calendar.dart';

/// Собственное представление готового календаря, без состояния каталога.
final class IntentionStatisticsCalendarView extends StatelessWidget {
  const IntentionStatisticsCalendarView({
    required this.calendar,
    required this.localDate,
    required this.onMonthSelected,
    required this.onDaySelected,
    super.key,
  });

  final IntentionStatisticsCalendar calendar;
  final CalendarDate localDate;
  final ValueChanged<int> onMonthSelected;
  final ValueChanged<CalendarDate> onDaySelected;

  @override
  Widget build(BuildContext context) => switch (calendar) {
    final IntentionStatisticsMonthCalendar month => _MonthGrid(
      calendar: month,
      onDaySelected: onDaySelected,
    ),
    final IntentionStatisticsYearCalendar year => _YearBars(
      calendar: year,
      localDate: localDate,
      onMonthSelected: onMonthSelected,
    ),
  };
}

final class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.calendar, required this.onDaySelected});
  final IntentionStatisticsMonthCalendar calendar;
  final ValueChanged<CalendarDate> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final period = calendar.period;
    // Индекс локализованной недели начинается с воскресенья:
    // https://api.flutter.dev/flutter/material/MaterialLocalizations/firstDayOfWeekIndex.html
    final firstWeekday = material.firstDayOfWeekIndex;
    final offset =
        (DateTime.utc(period.year, period.month).weekday % 7 -
            firstWeekday +
            7) %
        7;
    final days = period.lastDate.day;
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            for (var i = 0; i < 7; i++)
              ExcludeSemantics(
                child: Text(
                  material.narrowWeekdays[(firstWeekday + i) % 7],
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
        for (var row = 0; row < (offset + days + 6) ~/ 7; row++)
          TableRow(
            children: [
              for (var column = 0; column < 7; column++)
                if (row * 7 + column - offset + 1 case final day
                    when day >= 1 && day <= days)
                  _Day(
                    onDaySelected: onDaySelected,
                    date: CalendarDate.fromParts(
                      period.year,
                      period.month,
                      day,
                    ),
                    status:
                        calendar.statuses[CalendarDate.fromParts(
                          period.year,
                          period.month,
                          day,
                        )],
                  )
                else
                  const SizedBox.shrink(),
            ],
          ),
      ],
    );
  }
}

final class _Day extends StatelessWidget {
  const _Day({
    required this.date,
    required this.status,
    required this.onDaySelected,
  });
  final CalendarDate date;
  final DailyChoiceDayStatus? status;
  final ValueChanged<CalendarDate> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    // Одна кнопка для касания, клавиатуры и экранного диктора:
    // https://api.flutter.dev/flutter/material/TextButton-class.html
    return TextButton(
      onPressed: () => onDaySelected(date),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        minimumSize: const Size(48, 48),
      ),
      child: Semantics(
        excludeSemantics: true,
        label: texts.statisticsCalendarDaySemantics(
          DateTime.utc(date.year, date.month, date.day),
          switch (status) {
            DailyChoiceDayStatus.allCompleted =>
              texts.statisticsCalendarDayAllCompleted,
            DailyChoiceDayStatus.hasIncomplete =>
              texts.statisticsCalendarDayHasIncomplete,
            null => texts.statisticsCalendarDayNoChoices,
          },
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${date.day}', textAlign: TextAlign.center),
            SizedBox(
              height: MediaQuery.textScalerOf(context).scale(16),
              child: switch (status) {
                null => null,
                final status => Icon(
                  switch (status) {
                    DailyChoiceDayStatus.allCompleted => Icons.check,
                    DailyChoiceDayStatus.hasIncomplete => Icons.circle_outlined,
                  },
                  size: 16,
                  applyTextScaling: true,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

final class _YearBars extends StatelessWidget {
  const _YearBars({
    required this.calendar,
    required this.localDate,
    required this.onMonthSelected,
  });
  final IntentionStatisticsYearCalendar calendar;
  final CalendarDate localDate;
  final ValueChanged<int> onMonthSelected;

  @override
  Widget build(BuildContext context) {
    final texts = AppLocalizations.of(context);
    final maxPlanned = calendar.months.fold(
      0,
      (max, counts) => math.max(max, counts.planned),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var month = 1; month <= 12; month++)
            SizedBox(
              width: math.max(96, MediaQuery.textScalerOf(context).scale(80)),
              child: TextButton(
                onPressed: () => onMonthSelected(month),
                child: Semantics(
                  excludeSemantics: true,
                  label: [
                    texts.statisticsMonthBarSemantics(
                      DateTime.utc(calendar.period.year, month),
                      texts.statisticsContributionCountsSemantics(
                        calendar.months[month - 1].contribution,
                        calendar.months[month - 1].planned,
                      ),
                    ),
                    if (calendar.period.year == localDate.year &&
                        month == localDate.month)
                      texts.statisticsCurrentPeriod,
                  ].join('. '),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Bar(
                        counts: calendar.months[month - 1],
                        maxPlanned: maxPlanned,
                      ),
                      Text(
                        texts.statisticsMonthName(
                          DateTime.utc(calendar.period.year, month),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        texts.statisticsContributionCounts(
                          calendar.months[month - 1].contribution,
                          calendar.months[month - 1].planned,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (calendar.period.year == localDate.year &&
                          month == localDate.month)
                        Text(
                          texts.statisticsCurrentPeriod,
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final class _Bar extends StatelessWidget {
  const _Bar({required this.counts, required this.maxPlanned});
  final ContributionCounts counts;
  final int maxPlanned;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 96,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: 24,
          height: maxPlanned == 0
              ? 1
              : math.max(1, 96 * counts.planned / maxPlanned),
          decoration: BoxDecoration(
            border: Border.all(color: colors.onSurface),
          ),
          // Контур показывает запланированный вклад, заполнение — вклад;
          // обе меры дополнительно названы в доступной подписи столбика.
          child: FractionallySizedBox(
            alignment: Alignment.bottomCenter,
            heightFactor: counts.planned == 0
                ? 0
                : counts.contribution / counts.planned,
            child: ColoredBox(color: colors.primary),
          ),
        ),
      ),
    );
  }
}
