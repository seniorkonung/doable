import '../../daily_choice/application/daily_choice_day_statuses.dart';
import '../../daily_choice/domain/calendar_date.dart';
import 'contribution_counts.dart';
import 'statistics_period.dart';

/// Календарное представление только выборов выбранного вида намерения.
sealed class IntentionStatisticsCalendar {
  const IntentionStatisticsCalendar();

  StatisticsPeriod get period;
}

final class IntentionStatisticsMonthCalendar
    extends IntentionStatisticsCalendar {
  IntentionStatisticsMonthCalendar({
    required this.period,
    required Map<CalendarDate, DailyChoiceDayStatus> statuses,
  }) : statuses = Map.unmodifiable(statuses) {
    if (this.statuses.keys.any((date) => !period.contains(date))) {
      throw const StatisticsDataValidationException();
    }
  }

  @override
  final StatisticsMonth period;

  /// Отсутствие даты означает отсутствие засчитанных выборов этого дня.
  final Map<CalendarDate, DailyChoiceDayStatus> statuses;
}

final class IntentionStatisticsYearCalendar
    extends IntentionStatisticsCalendar {
  IntentionStatisticsYearCalendar({
    required this.period,
    required List<ContributionCounts> months,
  }) : months = List.unmodifiable(months) {
    if (this.months.length != 12) {
      throw const StatisticsDataValidationException();
    }
  }

  @override
  final StatisticsYear period;

  /// Ровно 12 месяцев от января (индекс 0) до декабря, включая нулевые.
  final List<ContributionCounts> months;
}
