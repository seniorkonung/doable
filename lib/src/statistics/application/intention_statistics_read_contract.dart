import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention_id.dart';
import 'contribution_counts.dart';
import 'intention_statistics_breakdown.dart';
import 'intention_statistics_calendar.dart';
import 'statistics_period.dart';
import 'statistics_read_contract.dart';

typedef IntentionStatisticsSectionResult =
    GraphResult<IntentionStatisticsSection, StatisticsReadFailure>;
typedef IntentionStatisticsSectionSuccess =
    GraphResultSuccess<IntentionStatisticsSection, StatisticsReadFailure>;
typedef IntentionStatisticsSectionError =
    GraphResultFailure<IntentionStatisticsSection, StatisticsReadFailure>;

typedef IntentionStatisticsBreakdownResult<T> =
    GraphResult<StatisticsBreakdownContinuationPage<T>, StatisticsReadFailure>;
typedef IntentionStatisticsBreakdownSuccess<T> =
    GraphResultSuccess<
      StatisticsBreakdownContinuationPage<T>,
      StatisticsReadFailure
    >;
typedef IntentionStatisticsBreakdownError<T> =
    GraphResultFailure<
      StatisticsBreakdownContinuationPage<T>,
      StatisticsReadFailure
    >;

/// Условия одного чтения раздела. Размер порции проверяется теми же
/// пределами, что у Главной. Каждая допустимая разбивка получает свою порцию.
final class IntentionStatisticsQuery {
  factory IntentionStatisticsQuery({
    required IntentionId intentionId,
    required StatisticsPeriod period,
    required StatisticsView? view,
    required int pageSize,
  }) {
    if (pageSize < StatisticsQuery.minPageSize ||
        pageSize > StatisticsQuery.maxPageSize) {
      throw const StatisticsQueryValidationException(
        StatisticsQueryValidationFailure.pageSizeOutOfRange,
      );
    }
    return IntentionStatisticsQuery._(intentionId, period, view, pageSize);
  }

  const IntentionStatisticsQuery._(
    this.intentionId,
    this.period,
    this.view,
    this.pageSize,
  );

  final IntentionId intentionId;
  final StatisticsPeriod period;

  /// null поручает выбор вида чтению: роль в пути, в которой у намерения
  /// за всё время больше всего действий, при равенстве — первая в порядке
  /// видов; без них — «Через связи», если до намерения по активным связям
  /// доходят действия, иначе «Корневые намерения».
  final StatisticsView? view;
  final int pageSize;
}

/// Четыре обязательные карточки; нулевой вклад не исключает карточку.
final class IntentionStatisticsCards {
  const IntentionStatisticsCards({
    required this.rootIntentions,
    required this.intermediateIntentions,
    required this.terminalIntentions,
    required this.throughRelations,
  });

  final ContributionCounts rootIntentions;
  final ContributionCounts intermediateIntentions;
  final ContributionCounts terminalIntentions;
  final ContributionCounts throughRelations;

  ContributionCounts operator [](StatisticsView view) => switch (view) {
    StatisticsView.rootIntentions => rootIntentions,
    StatisticsView.intermediateIntentions => intermediateIntentions,
    StatisticsView.terminalIntentions => terminalIntentions,
    StatisticsView.throughRelations => throughRelations,
  };
}

/// Первые порции выбранного вида. Варианты требуют все допустимые
/// разбивки и не позволяют добавить неподдерживаемую. Число действий
/// с намерением на пути есть только у
/// [IntentionStatisticsThroughRelationsDetails].
sealed class IntentionStatisticsViewDetails {
  const IntentionStatisticsViewDetails();

  StatisticsView get view;

  List<StatisticsBreakdownFirstPage<Object>> get _pages;
}

/// Действия, где намерение корневое, по их конечным намерениям.
final class IntentionStatisticsRootDetails
    extends IntentionStatisticsViewDetails {
  const IntentionStatisticsRootDetails({required this.terminalIntentions});

  final StatisticsBreakdownFirstPage<StatisticsItem> terminalIntentions;

  @override
  StatisticsView get view => StatisticsView.rootIntentions;

  @override
  List<StatisticsBreakdownFirstPage<Object>> get _pages => [terminalIntentions];
}

final class IntentionStatisticsIntermediateDetails
    extends IntentionStatisticsViewDetails {
  const IntentionStatisticsIntermediateDetails({
    required this.rootIntentions,
    required this.terminalIntentions,
  });

  final StatisticsBreakdownFirstPage<StatisticsItem> rootIntentions;
  final StatisticsBreakdownFirstPage<StatisticsItem> terminalIntentions;

  @override
  StatisticsView get view => StatisticsView.intermediateIntentions;

  @override
  List<StatisticsBreakdownFirstPage<Object>> get _pages => [
    rootIntentions,
    terminalIntentions,
  ];
}

/// Действия, где намерение конечное, по их корневым намерениям.
final class IntentionStatisticsTerminalDetails
    extends IntentionStatisticsViewDetails {
  const IntentionStatisticsTerminalDetails({required this.rootIntentions});

  final StatisticsBreakdownFirstPage<StatisticsItem> rootIntentions;

  @override
  StatisticsView get view => StatisticsView.terminalIntentions;

  @override
  List<StatisticsBreakdownFirstPage<Object>> get _pages => [rootIntentions];
}

final class IntentionStatisticsThroughRelationsDetails
    extends IntentionStatisticsViewDetails {
  IntentionStatisticsThroughRelationsDetails({
    required this.explicitPathActions,
    required this.relations,
    required this.terminalIntentions,
  }) {
    if (explicitPathActions < 0) {
      throw const StatisticsDataValidationException();
    }
  }

  /// Сколько действий вида содержат намерение на сохранённом пути.
  final int explicitPathActions;
  final StatisticsBreakdownFirstPage<StatisticsRelationItem> relations;
  final StatisticsBreakdownFirstPage<StatisticsItem> terminalIntentions;

  @override
  StatisticsView get view => StatisticsView.throughRelations;

  @override
  List<StatisticsBreakdownFirstPage<Object>> get _pages => [
    relations,
    terminalIntentions,
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
    if ((query.view != null && details.view != query.view) ||
        calendar.period != query.period) {
      throw const StatisticsDataValidationException();
    }
    if (selectedCounts.planned > periodCounts.planned) {
      throw const StatisticsDataValidationException();
    }
    if (details case IntentionStatisticsThroughRelationsDetails(
      :final explicitPathActions,
    )) {
      if (explicitPathActions > selectedCounts.planned) {
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

  /// Все действия периода, каждое один раз. Знаменатель доли сводки
  /// раздела — [ContributionCounts.planned] этих мер.
  final ContributionCounts periodCounts;
  final IntentionStatisticsViewDetails details;
  final IntentionStatisticsCalendar calendar;

  /// Заданный запросом вид либо выбранный чтением, если запрос его не задал.
  StatisticsView get view => details.view;

  /// Меры сводки берутся из выбранной карточки, а запланированный вклад
  /// служит знаменателем долей всех её разбивок.
  ContributionCounts get selectedCounts => cards[view];
}
