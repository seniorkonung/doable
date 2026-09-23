import '../../daily_choice/application/daily_choice_details.dart';
import '../../daily_choice/application/daily_choice_catalog.dart';
import '../../daily_choice/application/choice_path_continuations.dart';
import '../../daily_choice/domain/daily_choice_id.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_details.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/relation_counts.dart';
import '../../long_term_relation/application/relation_group_page.dart';
import '../../long_term_relation/application/long_term_relation_projection.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import 'graph_command_result.dart';
import 'graph_revision.dart';
import 'selected_relations.dart';

abstract interface class GraphCommandRepository {
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command);
}

abstract interface class PersonalGraphRepository
    implements GraphCommandRepository {
  /// Проверяет весь префикс и вычисляет продолжения на одном снимке графа.
  /// Активное исходное намерение без шагов допустимо. Изменённый, архивный или
  /// утративший связность префикс возвращает конфликт, а отсутствующее текущее
  /// намерение — отдельный отказ. Результат содержит актуальные данные конца,
  /// возможность его подтвердить и порцию активных достижимых переходов.
  /// Порядок: «нужно», затем «можно»; внутри группы P1–P4 и порядок создания.
  /// Чужой курсор или курсор другого запроса — ошибка ввода; смена ревизии или
  /// эпохи курсора — конфликт с требованием начать чтение с новой основы.
  /// Ошибка чтения не заменяется пустым набором. SQL остаётся внутри модуля.
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  );

  /// Возвращает null в снимке, если выбор отсутствует на момент чтения.
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id);

  /// Наблюдает выбор вместе с текущими данными участников и связей его пути.
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id);

  /// Возвращает ограниченную порцию проверенных дневных выборов и точное
  /// количество на одной ревизии для первой порции. По умолчанию доступны все
  /// даты и оба состояния. Порядок: дата по убыванию, затем порядок создания
  /// по убыванию; технический ключ остаётся внутри adapter.
  /// Чужое продолжение даёт отказ ввода, смена эпохи или ревизии — конфликт.
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  );

  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  );

  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  );

  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  );

  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id);

  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  );

  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  );

  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  );

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command);
}
