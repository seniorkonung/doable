import '../../../graph/application/graph_revision.dart';
import '../../../long_term_relation/application/relation_counts.dart';
import '../../../long_term_relation/application/relation_group_page.dart';
import '../../../long_term_relation/presentation/relation_list_reconciliation.dart';
import '../../application/daily_choice_catalog.dart';

/// Прямые дневные выборы намерения в одной роли на вкладке «Выборы».
sealed class IntentionChoicesState {
  const IntentionChoicesState({required this.role});

  final DailyChoiceRelationRole role;
}

/// Первое чтение роли: подтверждённых строк ещё нет.
final class IntentionChoicesInitialLoad extends IntentionChoicesState {
  const IntentionChoicesInitialLoad({required super.role});
}

/// Первое чтение роли завершилось отказом; это не пустая роль.
final class IntentionChoicesInitialFailure extends IntentionChoicesState {
  const IntentionChoicesInitialFailure({
    required super.role,
    required this.failure,
  });

  final RelationGroupReadFailure failure;

  /// Обычный повтор предоставляется только при устранимой недоступности.
  bool get canRetry => failure is RelationGroupUnavailableFailure;
}

/// Намерение подтверждённо отсутствует, его выборы больше не читаются.
final class IntentionChoicesIntentionNotFound extends IntentionChoicesState {
  const IntentionChoicesIntentionNotFound({required super.role});
}

/// Подтверждённая загруженная часть роли и сводка на одной ревизии графа.
sealed class IntentionChoicesConfirmed extends IntentionChoicesState {
  const IntentionChoicesConfirmed({
    required super.role,
    required this.counts,
    required this.revision,
    required this.summaryStatus,
  });

  /// Полная сводка, полученная вместе с первой порцией.
  final RelationCounts counts;
  final GraphRevision revision;
  final RelationListSummaryStatus summaryStatus;
}

/// Успешное получение роли без выборов.
final class IntentionChoicesEmpty extends IntentionChoicesConfirmed {
  const IntentionChoicesEmpty({
    required super.role,
    required super.counts,
    required super.revision,
    super.summaryStatus = const RelationListSummaryCurrent(),
  });
}

final class IntentionChoicesLoaded extends IntentionChoicesConfirmed {
  IntentionChoicesLoaded({
    required super.role,
    required super.counts,
    required super.revision,
    super.summaryStatus = const RelationListSummaryCurrent(),
    required List<DailyChoiceCatalogItem> items,
    required this.nextCursor,
    this.progress = const RelationListIdle(),
  }) : items = List.unmodifiable(items);

  /// Последовательная загруженная часть роли в порядке каталога.
  final List<DailyChoiceCatalogItem> items;
  final RelationGroupCursor? nextCursor;
  final RelationListProgress progress;

  /// Конец подтверждает только успешное получение актуального снимка.
  bool get hasConfirmedEnd =>
      nextCursor == null && summaryStatus is RelationListSummaryCurrent;
}
