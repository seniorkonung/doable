import '../../../statistics/application/intention_statistics_target.dart';

/// Начальная вкладка страницы намерения.
sealed class IntentionPageTarget {
  const IntentionPageTarget();
}

final class OverviewTarget extends IntentionPageTarget {
  const OverviewTarget();
}

final class RelationsTarget extends IntentionPageTarget {
  const RelationsTarget();
}

final class StatisticsTarget extends IntentionPageTarget {
  const StatisticsTarget(this.statistics);

  final IntentionStatisticsTarget statistics;
}

/// Страница удерживает ключ и начальную цель до закрытия или смены намерения.
/// Равенство по идентичности разделяет состояния страниц одного намерения.
final class IntentionPageInstance {
  IntentionPageInstance({required this.target});

  final IntentionPageTarget target;
}
