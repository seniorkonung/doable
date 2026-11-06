import '../../application/action_day_statuses.dart';

/// Последние полученные отметки сохраняются при обновлении и отказе.
/// До первого успеха дни остаются без отметок; загрузка не видна календарю.
final class ActionDayMarksState {
  const ActionDayMarksState({this.dayStatuses, this.hasReadFailure = false});

  final ActionDayStatuses? dayStatuses;
  final bool hasReadFailure;
}
