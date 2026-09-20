import '../../../graph/application/graph_revision.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/long_term_relation_projection.dart';
import '../../application/relation_counts.dart';
import '../../application/relation_group_page.dart';
import '../../domain/long_term_relation.dart';

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

/// Подтверждённое состояние выбранной группы на одной ревизии графа.
sealed class RelationGroupConfirmedState extends RelationNeighborhoodState {
  const RelationGroupConfirmedState({
    required super.intentionId,
    required super.selection,
    required this.counts,
    required this.revision,
  });

  /// Полная сводка восьми групп, полученная вместе с первой порцией.
  final RelationCounts counts;
  final GraphRevision revision;

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
  });
}

final class RelationGroupLoaded extends RelationGroupConfirmedState {
  RelationGroupLoaded({
    required super.intentionId,
    required super.selection,
    required super.counts,
    required super.revision,
    required List<LongTermRelationSummary> items,
    required this.nextCursor,
    this.progress = const RelationGroupIdle(),
  }) : items = List.unmodifiable(items);

  /// Последовательная загруженная часть группы в порядке приоритета и
  /// последовательности создания.
  final List<LongTermRelationSummary> items;
  final RelationGroupCursor? nextCursor;
  final RelationGroupProgress progress;

  /// Подтверждённый конец списка: продолжения больше нет.
  ///
  /// Конец определяется успешным результатом получения, а не ошибкой.
  bool get hasConfirmedEnd => nextCursor == null;

  RelationGroupLoaded withProgress(RelationGroupProgress value) =>
      RelationGroupLoaded(
        intentionId: intentionId,
        selection: selection,
        counts: counts,
        revision: revision,
        items: items,
        nextCursor: nextCursor,
        progress: value,
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

/// Выполняется получение новой основы уже загруженной части группы.
final class RelationGroupRefreshing extends RelationGroupProgress {
  const RelationGroupRefreshing();
}

/// Отказ подгрузки: прежние строки, продолжение и количества сохранены.
final class RelationGroupLoadMoreFailure extends RelationGroupProgress {
  const RelationGroupLoadMoreFailure(this.failure);

  final RelationGroupReadFailure failure;

  /// Обычный повтор предоставляется только при устранимой недоступности.
  bool get canRetry => failure is RelationGroupUnavailableFailure;
}

/// Отказ обновления: прежняя подтверждённая пара сохранена целиком.
final class RelationGroupRefreshFailure extends RelationGroupProgress {
  const RelationGroupRefreshFailure(this.failure);

  final RelationGroupReadFailure failure;

  /// Обычный повтор предоставляется только при устранимой недоступности.
  bool get canRetry => failure is RelationGroupUnavailableFailure;
}
