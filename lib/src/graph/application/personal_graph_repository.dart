import '../../daily_choice/application/daily_choice_details.dart';
import '../../daily_choice/application/daily_choice_catalog.dart';
import '../../daily_choice/application/daily_choice_day_statuses.dart';
import '../../daily_choice/domain/daily_choice_id.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_details.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/relation_group_page.dart';
import '../../long_term_relation/application/long_term_relation_projection.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import '../../statistics/application/statistics_read_contract.dart';
import '../../tag/application/tag_read_result.dart';
import 'graph_command_result.dart';
import 'graph_revision.dart';

abstract interface class GraphCommandRepository {
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command);
}

abstract interface class PersonalGraphRepository
    implements GraphCommandRepository, TagReadContract, StatisticsReadContract {
  /// Возвращает null в снимке, если выбор отсутствует на момент чтения.
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id);

  /// Наблюдает выбор вместе с текущими данными участников и связей его пути.
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id);

  /// Возвращает ограниченную порцию проверенных дневных выборов и точное
  /// количество на одной ревизии для первой порции. По умолчанию доступны все
  /// даты и оба состояния. Порядок: дата по убыванию, затем порядок создания
  /// по убыванию; технический ключ остаётся внутри adapter.
  /// Смена ревизии продолжения — конфликт.
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  );

  /// Читает состояния дней на одной ревизии по контракту
  /// [DailyChoiceDayStatusesReadResult] в ограниченном диапазоне [query].
  Future<DailyChoiceDayStatusesReadResult> getDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  );

  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  );

  /// Читает одну прямую группу намерения: долговременную либо дневную.
  /// Первая порция и полная сводка получены на одной ревизии; продолжение
  /// относится к снимку графа первой порции.
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  );

  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id);

  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  );

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command);
}
