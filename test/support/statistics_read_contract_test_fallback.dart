import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';

/// Подставляет явный отказ в тестовые графы, не проверяющие статистику.
mixin StatisticsReadContractTestFallback implements StatisticsReadContract {
  @override
  Future<StatisticsPageResult> getStatisticsPage(StatisticsQuery query) async =>
      const StatisticsPageError(StatisticsReadUnexpectedFailure());

  @override
  Future<IntentionStatisticsSectionResult> getIntentionStatisticsSection(
    IntentionStatisticsQuery query,
  ) async =>
      const IntentionStatisticsSectionError(StatisticsReadUnexpectedFailure());

  @override
  Future<IntentionStatisticsBreakdownResult<T>> getIntentionStatisticsBreakdown<
    T
  >(StatisticsBreakdownCursor<T> cursor) async =>
      IntentionStatisticsBreakdownError<T>(
        const StatisticsReadUnexpectedFailure(),
      );
}
