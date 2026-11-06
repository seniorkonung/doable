import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/application/action_read_contract.dart';

/// Подставляет явный отказ в тестовые графы, не читающие действия.
mixin ActionReadContractTestFallback implements ActionReadContract {
  @override
  Future<ActionDayPageResult> getActionDayPage(ActionDayQuery query) async =>
      const ActionDayPageError(ActionDayUnexpectedFailure());

  @override
  Future<ActionDayStatusesReadResult> getActionDayStatuses(
    ActionDayStatusQuery query,
  ) async =>
      const ActionDayStatusesReadError(ActionDayStatusesUnexpectedFailure());
}
