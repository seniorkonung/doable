import 'package:doable/src/statistics/application/statistics_read_contract.dart';

/// Подставляет явный отказ в тестовые графы, не проверяющие статистику.
mixin StatisticsReadContractTestFallback implements StatisticsReadContract {
  @override
  Future<StatisticsPageResult> getStatisticsPage(StatisticsQuery query) async =>
      const StatisticsPageError(StatisticsReadUnexpectedFailure());
}
