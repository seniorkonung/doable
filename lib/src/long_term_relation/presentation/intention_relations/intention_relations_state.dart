import '../../../graph/application/graph_revision.dart';
import '../../application/intention_relation_group.dart';
import '../../application/long_term_relation_projection.dart';
import '../../application/relation_counts.dart';
import '../../application/relation_group_page.dart';
import '../../domain/long_term_relation_id.dart';
import '../relation_group_paging.dart';
import '../relation_list_reconciliation.dart';

/// Активные связи выбранной группы на вкладке «Связи» страницы намерения.
sealed class IntentionRelationsState {
  const IntentionRelationsState({required this.group});

  final IntentionRelationGroup group;
}

/// Первое чтение группы: подтверждённых строк ещё нет.
final class IntentionRelationsInitialLoad extends IntentionRelationsState {
  const IntentionRelationsInitialLoad({required super.group});
}

/// Первое чтение группы завершилось отказом; это не пустая группа.
final class IntentionRelationsInitialFailure extends IntentionRelationsState {
  const IntentionRelationsInitialFailure({
    required super.group,
    required this.failure,
  });

  final RelationGroupReadFailure failure;

  /// Обычный повтор предоставляется только при устранимой недоступности.
  bool get canRetry => failure is RelationGroupUnavailableFailure;
}

/// Намерение подтверждённо отсутствует, его связи больше не читаются.
final class IntentionRelationsIntentionNotFound
    extends IntentionRelationsState {
  const IntentionRelationsIntentionNotFound({required super.group});
}

/// Подтверждённая загруженная часть группы и сводка на одной ревизии графа.
sealed class IntentionRelationsConfirmed extends IntentionRelationsState {
  const IntentionRelationsConfirmed({
    required super.group,
    required this.counts,
    required this.revision,
    required this.summaryStatus,
  });

  /// Полная сводка, полученная вместе с первой порцией.
  final RelationCounts counts;
  final GraphRevision revision;
  final RelationListSummaryStatus summaryStatus;
}

/// Успешное получение группы без активных связей.
final class IntentionRelationsEmpty extends IntentionRelationsConfirmed {
  const IntentionRelationsEmpty({
    required super.group,
    required super.counts,
    required super.revision,
    super.summaryStatus = const RelationListSummaryCurrent(),
  });
}

final class IntentionRelationsLoaded extends IntentionRelationsConfirmed {
  IntentionRelationsLoaded({
    required super.group,
    required super.counts,
    required super.revision,
    super.summaryStatus = const RelationListSummaryCurrent(),
    required List<RelationGroupEntry> items,
    required this.nextCursor,
    this.progress = const RelationListIdle(),
    this.scrollAnchor,
  }) : items = List.unmodifiable(items);

  /// Последовательная загруженная часть группы в порядке приоритета.
  final List<RelationGroupEntry> items;
  final RelationGroupCursor? nextCursor;
  final RelationListProgress progress;

  /// Строка, к которой вид возвращает прокрутку после замены загруженной
  /// части на новой ревизии.
  final RelationPagingAnchor<LongTermRelationId>? scrollAnchor;

  /// Конец подтверждает только успешное получение актуального снимка.
  bool get hasConfirmedEnd =>
      nextCursor == null && summaryStatus is RelationListSummaryCurrent;
}
