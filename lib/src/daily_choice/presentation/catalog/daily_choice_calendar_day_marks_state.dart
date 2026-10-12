import '../../application/daily_choice_day_statuses.dart';

/// Последние полученные отметки сохраняются при обновлении и отказе.
/// До первого успеха дни остаются без отметок; загрузка не видна календарю.
final class DailyChoiceCalendarDayMarksState {
  const DailyChoiceCalendarDayMarksState({
    this.dayStatuses,
    this.hasReadFailure = false,
  });

  final DailyChoiceDayStatuses? dayStatuses;
  final bool hasReadFailure;
}
