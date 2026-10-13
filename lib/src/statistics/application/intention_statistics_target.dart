import 'intention_statistics_breakdown.dart';
import 'statistics_period.dart';
import 'statistics_read_contract.dart';

/// Цель открытия статистики: не зависит от маршрута, прокрутки или вкладок.
/// Намерение задаёт сама страница, а цель — начальные условия её раздела.
final class IntentionStatisticsTarget {
  const IntentionStatisticsTarget({required this.view, required this.period});

  IntentionStatisticsTarget.forBreakdown({
    required StatisticsBreakdown breakdown,
    required this.period,
  }) : view = switch (breakdown) {
         StatisticsBreakdown.sourceIntentions =>
           StatisticsView.sourceIntentions,
         StatisticsBreakdown.selectedActions => StatisticsView.selectedActions,
         StatisticsBreakdown.relations => StatisticsView.throughRelations,
       };

  final StatisticsView view;
  final StatisticsPeriod period;
}
