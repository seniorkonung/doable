import '../../daily_choice/domain/calendar_date.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention_id.dart';
import 'contribution_counts.dart';
import 'intention_statistics_breakdown.dart';
import 'intention_statistics_calendar.dart';
import 'statistics_period.dart';
import 'statistics_read_contract.dart';

/// Условия одного чтения раздела. Размер порции проверяется тем же
/// контрактом, что у Главной. Каждая допустимая разбивка получает свою порцию.
final class IntentionStatisticsQuery {
  IntentionStatisticsQuery({
    required this.intentionId,
    required StatisticsPeriod period,
    required StatisticsView view,
    required CalendarDate localDate,
    required int pageSize,
  }) : _statistics = StatisticsQuery(
         period: period,
         view: view,
         localDate: localDate,
         pageSize: pageSize,
       );

  final IntentionId intentionId;
  final StatisticsQuery _statistics;

  StatisticsPeriod get period => _statistics.period;
  StatisticsView get view => _statistics.view;
  CalendarDate get localDate => _statistics.localDate;
  int get pageSize => _statistics.pageSize;
}

/// Четыре обязательные карточки; нулевой вклад не исключает карточку.
final class IntentionStatisticsCards {
  const IntentionStatisticsCards({
    required this.sourceIntentions,
    required this.intermediateIntentions,
    required this.selectedActions,
    required this.throughRelations,
  });

  final ContributionCounts sourceIntentions;
  final ContributionCounts intermediateIntentions;
  final ContributionCounts selectedActions;
  final ContributionCounts throughRelations;

  ContributionCounts operator [](StatisticsView view) => switch (view) {
    StatisticsView.sourceIntentions => sourceIntentions,
    StatisticsView.intermediateIntentions => intermediateIntentions,
    StatisticsView.selectedActions => selectedActions,
    StatisticsView.throughRelations => throughRelations,
  };
}

/// Сводка и первые порции выбранного вида. Варианты требуют все допустимые
/// разбивки и не позволяют добавить неподдерживаемую. Число явных оснований
/// присутствует только у [IntentionStatisticsThroughRelationsDetails].
sealed class IntentionStatisticsViewDetails {
  const IntentionStatisticsViewDetails({required this.uncompleted});

  StatisticsView get view;
  final UncompletedSplit uncompleted;

  List<StatisticsBreakdownFirstPage<Object>> get _pages;
}

final class IntentionStatisticsSourceDetails
    extends IntentionStatisticsViewDetails {
  const IntentionStatisticsSourceDetails({
    required super.uncompleted,
    required this.selectedActions,
  });

  final StatisticsBreakdownFirstPage<StatisticsItem> selectedActions;

  @override
  StatisticsView get view => StatisticsView.sourceIntentions;

  @override
  List<StatisticsBreakdownFirstPage<Object>> get _pages => [selectedActions];
}

final class IntentionStatisticsIntermediateDetails
    extends IntentionStatisticsViewDetails {
  const IntentionStatisticsIntermediateDetails({
    required super.uncompleted,
    required this.sourceIntentions,
    required this.selectedActions,
  });

  final StatisticsBreakdownFirstPage<StatisticsItem> sourceIntentions;
  final StatisticsBreakdownFirstPage<StatisticsItem> selectedActions;

  @override
  StatisticsView get view => StatisticsView.intermediateIntentions;

  @override
  List<StatisticsBreakdownFirstPage<Object>> get _pages => [
    sourceIntentions,
    selectedActions,
  ];
}

final class IntentionStatisticsSelectedDetails
    extends IntentionStatisticsViewDetails {
  const IntentionStatisticsSelectedDetails({
    required super.uncompleted,
    required this.sourceIntentions,
  });

  final StatisticsBreakdownFirstPage<StatisticsItem> sourceIntentions;

  @override
  StatisticsView get view => StatisticsView.selectedActions;

  @override
  List<StatisticsBreakdownFirstPage<Object>> get _pages => [sourceIntentions];
}

final class IntentionStatisticsThroughRelationsDetails
    extends IntentionStatisticsViewDetails {
  IntentionStatisticsThroughRelationsDetails({
    required super.uncompleted,
    required this.explicitPathChoices,
    required this.relations,
    required this.selectedActions,
  }) {
    if (explicitPathChoices < 0) {
      throw const StatisticsDataValidationException();
    }
  }

  /// Сколько запланированных выборов содержат намерение на сохранённом пути.
  final int explicitPathChoices;
  final StatisticsBreakdownFirstPage<StatisticsRelationItem> relations;
  final StatisticsBreakdownFirstPage<StatisticsItem> selectedActions;

  @override
  StatisticsView get view => StatisticsView.throughRelations;

  @override
  List<StatisticsBreakdownFirstPage<Object>> get _pages => [
    relations,
    selectedActions,
  ];
}

/// Составной результат одной согласованной попытки чтения раздела.
/// Карточки, сводка выбранного вида, календарь, названия, архивные отметки
/// и первые порции разбивок принадлежат одной [revision]. Вложенные данные
/// не имеют отдельных ревизий; адаптер проверяет снимок перед публикацией.
///
/// Чтение не возвращает частичных чисел: нарушение инварианта прочитанных
/// данных означает повреждение всего результата. Устаревание снимка требует
/// нового чтения раздела только актуальным видимым потребителем.
/// Отсутствующее намерение не считается разделом с нулевыми числами.
final class IntentionStatisticsSection {
  IntentionStatisticsSection({
    required this.query,
    required this.revision,
    required this.cards,
    required this.periodCounts,
    required this.details,
    required this.calendar,
  }) {
    if (details.view != query.view || calendar.period != query.period) {
      throw const StatisticsDataValidationException();
    }
    if (details.uncompleted.missed + details.uncompleted.upcoming !=
        selectedCounts.uncompleted) {
      throw const StatisticsDataValidationException();
    }
    if (details case IntentionStatisticsThroughRelationsDetails(
      :final explicitPathChoices,
    )) {
      if (explicitPathChoices > selectedCounts.planned) {
        throw const StatisticsDataValidationException();
      }
    }
    if (details._pages.any((page) => page.items.length > query.pageSize)) {
      throw const StatisticsDataValidationException();
    }
  }

  final IntentionStatisticsQuery query;
  final GraphRevision revision;
  final IntentionStatisticsCards cards;

  /// Все выборы периода, каждый один раз. Знаменатель доли сводки раздела —
  /// [ContributionCounts.contribution] этих мер; при нуле доли нет.
  final ContributionCounts periodCounts;
  final IntentionStatisticsViewDetails details;
  final IntentionStatisticsCalendar calendar;

  /// Меры сводки берутся из выбранной карточки, а вклад служит знаменателем
  /// долей всех её разбивок. При нуле доли не показываются.
  ContributionCounts get selectedCounts => cards[query.view];
}
