import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';

import '../../../support/tag_read_contract_test_fallback.dart';
import 'action_day_page_test_support.dart';
import '../../../support/intention_holding_read_contract_test_fallback.dart';

/// Хранилище экрана дня, которое умеет открыть панель действия.
///
/// Чтения выдачи, отметок и команды выполнения отдаёт [day], а наблюдение
/// действия, нужное панели, молчит: страничным проверкам важно только, что
/// нажатие на строку открыло панель именно этого действия.
final class ActionDayPanelRepository
    with IntentionHoldingReadContractTestFallback, TagReadContractTestFallback
    implements PersonalGraphRepository {
  ActionDayPanelRepository(this.day);

  final ActionDayRepository day;

  @override
  Future<ActionDayPageResult> getActionDayPage(ActionDayQuery query) =>
      day.getActionDayPage(query);

  @override
  Future<ActionDayStatusesReadResult> getActionDayStatuses(
    ActionDayStatusQuery query,
  ) => day.getActionDayStatuses(query);

  @override
  Stream<ActionReadResult> watchAction(ActionId id) => const Stream.empty();

  @override
  Future<GraphCommandResult<T, F>> execute<
    T extends GraphCommandOutcome,
    F extends GraphCommandFailure
  >(GraphCommand<T, F> command) => day.execute(command);

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => day.getCatalogPage(query);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
