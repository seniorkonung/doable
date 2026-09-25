import '../../daily_choice/application/daily_choice_details.dart';
import '../../daily_choice/application/daily_choice_catalog.dart';
import '../../daily_choice/application/choice_path_continuations.dart';
import '../../daily_choice/application/choice_path_suggestions.dart';
import '../../daily_choice/domain/daily_choice_id.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_details.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/relation_counts.dart';
import '../../long_term_relation/application/relation_group_page.dart';
import '../../long_term_relation/application/long_term_relation_projection.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import '../../tag/application/tag_read_result.dart';
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
    implements GraphCommandRepository, TagReadContract {
  /// Читает подсказки для исходного намерения либо выбранного действия на
  /// одной ревизии. Выборка ограничена последними 20 выборами участника по
  /// порядку создания до устранения повторов; возвращается до пяти разных
  /// текущих маршрутов с наиболее новым представителем каждого. Дата и
  /// выполнение не участвуют в отборе. Пустой успех, отсутствие участника и
  /// отказ чтения различны; повреждение любого кандидата отклоняет всё чтение.
  /// Чтение не меняет граф. Допустимость предложения повторно проверяется
  /// командой сохранения. SQL и технический порядок остаются за репозиторием.
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  );

  /// Проверяет весь направленный черновик на одном снимке графа. Ноль шагов
  /// допустим, но не подтверждаем. Для нижнего обхода начало — фиксированное
  /// активное готовое действие, а текущее намерение — возможное основание
  /// любой готовности. Все участники и связи должны оставаться активными.
  /// Изменённый, архивный или разорванный путь даёт конфликт;
  /// отсутствующее намерение — отдельный отказ. Снимок содержит ревизию,
  /// подтверждаемость и порцию активных продолжений данного направления.
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

  /// Читает одну прямую группу намерения: долговременную либо дневную.
  /// Первая порция и полная сводка получены на одной ревизии; продолжение
  /// относится к той же группе, размеру порции и снимку графа.
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  );

  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id);

  /// Возвращает ровно явно выбранные ссылки обоих видов на одном снимке.
  /// Отсутствие и утрата прямой принадлежности остаются отдельными записями.
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  );

  /// Наблюдает тот же полный набор до отдельного подтверждения удаления.
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
