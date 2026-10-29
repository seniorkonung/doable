import '../../../long_term_relation/application/relation_group.dart';
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

/// Страница удерживает ключ, начальную цель и настройки вкладок до закрытия
/// или смены намерения. Равенство по идентичности разделяет состояния страниц
/// одного намерения.
///
/// Настройки переживают освобождение моделей вкладок, поэтому строк, курсоров
/// и якорей списков в них нет.
final class IntentionPageInstance {
  IntentionPageInstance({required this.target});

  final IntentionPageTarget target;

  /// Роль вкладки «Выборы»; до первой смены — «исходное».
  DailyChoiceRelationRole choicesRole = DailyChoiceRelationRole.source;
}
