import '../../../long_term_relation/application/intention_relation_group.dart';
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
  const RelationsTarget([this.group]);

  /// Группа, которую вкладка «Связи» выбирает при первом показе.
  final IntentionRelationGroup? group;
}

final class ChoicesTarget extends IntentionPageTarget {
  const ChoicesTarget();
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

  /// Настройки вкладки «Связи»; их задаёт первая модель вкладки этого
  /// экземпляра.
  IntentionRelationsSettings? relations;
}

/// Выбранная группа и раскрытые архивы групп вкладки «Связи».
final class IntentionRelationsSettings {
  IntentionRelationsSettings({
    required this.group,
    required Set<IntentionRelationGroup> expandedArchives,
  }) : expandedArchives = {...expandedArchives};

  IntentionRelationGroup group;

  /// Группы, архив которых раскрыт; флаг каждой группы меняется отдельно.
  final Set<IntentionRelationGroup> expandedArchives;
}
