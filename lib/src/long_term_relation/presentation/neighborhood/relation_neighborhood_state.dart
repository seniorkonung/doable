import '../../../graph/application/graph_revision.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/long_term_relation_projection.dart';
import '../../application/relation_counts.dart';
import '../../application/relation_group_page.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_id.dart';

/// Выбранная пользователем группа связей одного намерения.
///
/// Переключение одного параметра сохраняет остальные: тип, направление и
/// архивное состояние выбираются независимо друг от друга.
final class RelationGroupSelection {
  const RelationGroupSelection({
    required this.type,
    required this.direction,
    required this.scope,
  });

  /// Страница намерения открывает активные исходящие связи «нужно».
  static const initial = RelationGroupSelection(
    type: LongTermRelationType.need,
    direction: RelationDirection.outgoing,
    scope: RelationScope.active,
  );

  final LongTermRelationType type;
  final RelationDirection direction;
  final RelationScope scope;

  RelationGroupSelection withType(LongTermRelationType value) =>
      RelationGroupSelection(type: value, direction: direction, scope: scope);

  RelationGroupSelection withDirection(RelationDirection value) =>
      RelationGroupSelection(type: type, direction: value, scope: scope);

  RelationGroupSelection withScope(RelationScope value) =>
      RelationGroupSelection(type: type, direction: direction, scope: value);

  @override
  bool operator ==(Object other) =>
      other is RelationGroupSelection &&
      other.type == type &&
      other.direction == direction &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(type, direction, scope);
}

sealed class RelationNeighborhoodState {
  const RelationNeighborhoodState({
    required this.intentionId,
    required this.selection,
  });

  final IntentionId intentionId;
  final RelationGroupSelection selection;
}

/// Актуальность сохранённой сводки, предъявляемой вместе с её числами.
enum RelationSummaryFreshness {
  /// Числа относятся к опубликованной согласованной паре и не обновляются.
  current,

  /// Прежняя согласованная пара показана, пока собирается её замена.
  refreshing,

  /// Обновление не удалось, поэтому сохранённые числа устарели.
  stale,
}

/// Независимое состояние актуализации опубликованной сводки.
///
/// Оно хранится отдельно от подгрузки продолжения: поздний ответ порции не
/// может выдать прежние числа за актуальные или скрыть ошибку обновления.
sealed class RelationSummaryStatus {
  const RelationSummaryStatus();

  RelationSummaryFreshness get freshness;
}

/// Опубликованные числа относятся к текущему согласованному снимку.
final class RelationSummaryCurrent extends RelationSummaryStatus {
  const RelationSummaryCurrent();

  @override
  RelationSummaryFreshness get freshness => RelationSummaryFreshness.current;
}

/// Прежняя согласованная пара доступна, пока собирается новая основа.
final class RelationSummaryRefreshing extends RelationSummaryStatus {
  const RelationSummaryRefreshing();

  @override
  RelationSummaryFreshness get freshness => RelationSummaryFreshness.refreshing;
}

/// Новую основу получить не удалось, поэтому сохранённые числа устарели.
final class RelationSummaryRefreshFailure extends RelationSummaryStatus {
  const RelationSummaryRefreshFailure(this.failure);

  final RelationGroupReadFailure failure;

  /// Обычный повтор предоставляется только при устранимой недоступности.
  bool get canRetry => failure is RelationGroupUnavailableFailure;

  @override
  RelationSummaryFreshness get freshness => RelationSummaryFreshness.stale;
}

/// Первое чтение выбранной группы: подтверждённых строк ещё нет.
final class RelationGroupInitialLoad extends RelationNeighborhoodState {
  const RelationGroupInitialLoad({
    required super.intentionId,
    required super.selection,
  });
}

/// Первое чтение выбранной группы завершилось отказом.
///
/// Это не пустая группа и не данные прежнего выбора.
final class RelationGroupInitialFailure extends RelationNeighborhoodState {
  const RelationGroupInitialFailure({
    required super.intentionId,
    required super.selection,
    required this.failure,
  });

  final RelationGroupReadFailure failure;

  bool get canRetry => failure is RelationGroupUnavailableFailure;
}

/// Намерение-владелец подтверждённо отсутствует, его соседство завершено.
final class RelationNeighborhoodIntentionNotFound
    extends RelationNeighborhoodState {
  const RelationNeighborhoodIntentionNotFound({
    required super.intentionId,
    required super.selection,
  });
}

/// Строка, к которой представление возвращает viewport после замены списка.
///
/// Идентификатор служит стабильным ключом строки, а индекс позволяет выбрать
/// ближайшую сохранившуюся позицию, если прежняя видимая связь исчезла.
final class RelationGroupScrollAnchor {
  const RelationGroupScrollAnchor({
    required this.relationId,
    required this.index,
  });

  final LongTermRelationId relationId;
  final int index;
}

/// Подтверждённое состояние выбранной группы на одной ревизии графа.
sealed class RelationGroupConfirmedState extends RelationNeighborhoodState {
  const RelationGroupConfirmedState({
    required super.intentionId,
    required super.selection,
    required this.counts,
    required this.revision,
    this.summaryStatus = const RelationSummaryCurrent(),
  });

  /// Полная сводка восьми групп, полученная вместе с первой порцией.
  final RelationCounts counts;
  final GraphRevision revision;
  final RelationSummaryStatus summaryStatus;
  RelationGroupProgress get progress;
  RelationGroupScrollAnchor? get scrollAnchor;

  /// Подгрузка продолжения не меняет актуальность полной сводки.
  RelationSummaryFreshness get summaryFreshness => summaryStatus.freshness;

  /// Полное количество связей выбранной группы.
  int get totalCount => counts.forGroup(
    scope: selection.scope,
    type: selection.type,
    direction: selection.direction,
  );
}

/// Успешное получение выбранной группы без связей.
final class RelationGroupEmpty extends RelationGroupConfirmedState {
  const RelationGroupEmpty({
    required super.intentionId,
    required super.selection,
    required super.counts,
    required super.revision,
    super.summaryStatus,
    this.progress = const RelationGroupIdle(),
    this.scrollAnchor,
  });

  @override
  final RelationGroupProgress progress;

  @override
  final RelationGroupScrollAnchor? scrollAnchor;

  RelationGroupEmpty withProgress(RelationGroupProgress value) =>
      RelationGroupEmpty(
        intentionId: intentionId,
        selection: selection,
        counts: counts,
        revision: revision,
        summaryStatus: summaryStatus,
        progress: value,
        scrollAnchor: scrollAnchor,
      );

  RelationGroupEmpty withSummaryStatus(RelationSummaryStatus value) =>
      RelationGroupEmpty(
        intentionId: intentionId,
        selection: selection,
        counts: counts,
        revision: revision,
        summaryStatus: value,
        progress: progress,
        scrollAnchor: scrollAnchor,
      );
}

final class RelationGroupLoaded extends RelationGroupConfirmedState {
  RelationGroupLoaded({
    required super.intentionId,
    required super.selection,
    required super.counts,
    required super.revision,
    super.summaryStatus,
    required List<LongTermRelationSummary> items,
    required this.nextCursor,
    this.progress = const RelationGroupIdle(),
    this.scrollAnchor,
  }) : items = List.unmodifiable(items);

  /// Последовательная загруженная часть группы в порядке приоритета и
  /// последовательности создания.
  final List<LongTermRelationSummary> items;
  final RelationGroupCursor? nextCursor;
  @override
  final RelationGroupProgress progress;
  @override
  final RelationGroupScrollAnchor? scrollAnchor;

  /// Подтверждённый конец списка: продолжения больше нет.
  ///
  /// Конец определяется успешным результатом получения актуального снимка,
  /// а не ошибкой или завершением порции уже устаревшей сводки.
  bool get hasConfirmedEnd =>
      nextCursor == null &&
      summaryFreshness == RelationSummaryFreshness.current;

  RelationGroupLoaded withProgress(RelationGroupProgress value) =>
      RelationGroupLoaded(
        intentionId: intentionId,
        selection: selection,
        counts: counts,
        revision: revision,
        summaryStatus: summaryStatus,
        items: items,
        nextCursor: nextCursor,
        progress: value,
        scrollAnchor: scrollAnchor,
      );

  RelationGroupLoaded withSummaryStatus(RelationSummaryStatus value) =>
      RelationGroupLoaded(
        intentionId: intentionId,
        selection: selection,
        counts: counts,
        revision: revision,
        summaryStatus: value,
        items: items,
        nextCursor: nextCursor,
        progress: progress,
        scrollAnchor: scrollAnchor,
      );
}

/// Выполняющееся или неудавшееся чтение поверх подтверждённой части группы.
sealed class RelationGroupProgress {
  const RelationGroupProgress();
}

/// Чтение выбранной группы не выполняется.
final class RelationGroupIdle extends RelationGroupProgress {
  const RelationGroupIdle();
}

/// Выполняется подгрузка следующей порции выбранной группы.
final class RelationGroupLoadingMore extends RelationGroupProgress {
  const RelationGroupLoadingMore();
}

/// Отказ подгрузки: прежние строки, продолжение и количества сохранены.
final class RelationGroupLoadMoreFailure extends RelationGroupProgress {
  const RelationGroupLoadMoreFailure(this.failure);

  final RelationGroupReadFailure failure;

  /// Обычный повтор предоставляется только при устранимой недоступности.
  bool get canRetry => failure is RelationGroupUnavailableFailure;
}
