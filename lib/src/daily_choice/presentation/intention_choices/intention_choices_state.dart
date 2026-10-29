import '../../../graph/application/graph_revision.dart';
import '../../../long_term_relation/application/relation_counts.dart';
import '../../../long_term_relation/application/relation_group_page.dart';
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
  final IntentionChoicesSummaryStatus summaryStatus;

  List<DailyChoiceCatalogItem> get items;

  /// Полное количество выборов выбранной роли.
  int get totalCount =>
      counts.forSelection(DailyChoiceRelationGroup(role: role));

  IntentionChoicesConfirmed withSummaryStatus(
    IntentionChoicesSummaryStatus value,
  );
}

/// Успешное получение роли без выборов.
final class IntentionChoicesEmpty extends IntentionChoicesConfirmed {
  const IntentionChoicesEmpty({
    required super.role,
    required super.counts,
    required super.revision,
    super.summaryStatus = const IntentionChoicesSummaryCurrent(),
  });

  @override
  List<DailyChoiceCatalogItem> get items => const [];

  @override
  IntentionChoicesEmpty withSummaryStatus(
    IntentionChoicesSummaryStatus value,
  ) => IntentionChoicesEmpty(
    role: role,
    counts: counts,
    revision: revision,
    summaryStatus: value,
  );
}

final class IntentionChoicesLoaded extends IntentionChoicesConfirmed {
  IntentionChoicesLoaded({
    required super.role,
    required super.counts,
    required super.revision,
    super.summaryStatus = const IntentionChoicesSummaryCurrent(),
    required List<DailyChoiceCatalogItem> items,
    required this.nextCursor,
    this.progress = const IntentionChoicesIdle(),
  }) : items = List.unmodifiable(items);

  /// Последовательная загруженная часть роли в порядке каталога.
  @override
  final List<DailyChoiceCatalogItem> items;
  final RelationGroupCursor? nextCursor;
  final IntentionChoicesProgress progress;

  /// Конец подтверждает только успешное получение актуального снимка.
  bool get hasConfirmedEnd =>
      nextCursor == null && summaryStatus is IntentionChoicesSummaryCurrent;

  IntentionChoicesLoaded withProgress(IntentionChoicesProgress value) =>
      IntentionChoicesLoaded(
        role: role,
        counts: counts,
        revision: revision,
        summaryStatus: summaryStatus,
        items: items,
        nextCursor: nextCursor,
        progress: value,
      );

  @override
  IntentionChoicesLoaded withSummaryStatus(
    IntentionChoicesSummaryStatus value,
  ) => IntentionChoicesLoaded(
    role: role,
    counts: counts,
    revision: revision,
    summaryStatus: value,
    items: items,
    nextCursor: nextCursor,
    progress: progress,
  );
}

/// Актуальность опубликованной пары строк и сводки.
///
/// Она хранится отдельно от подгрузки: поздний ответ порции не может выдать
/// прежние числа за актуальные или скрыть ошибку обновления.
sealed class IntentionChoicesSummaryStatus {
  const IntentionChoicesSummaryStatus();
}

/// Опубликованная пара относится к текущему согласованному снимку.
final class IntentionChoicesSummaryCurrent
    extends IntentionChoicesSummaryStatus {
  const IntentionChoicesSummaryCurrent();
}

/// Прежняя пара показана, пока собирается её замена.
final class IntentionChoicesSummaryRefreshing
    extends IntentionChoicesSummaryStatus {
  const IntentionChoicesSummaryRefreshing();
}

/// Замену получить не удалось, поэтому показанная пара устарела.
final class IntentionChoicesSummaryRefreshFailure
    extends IntentionChoicesSummaryStatus {
  const IntentionChoicesSummaryRefreshFailure(this.failure);

  final RelationGroupReadFailure failure;

  /// Обычный повтор предоставляется только при устранимой недоступности.
  bool get canRetry => failure is RelationGroupUnavailableFailure;
}

/// Подгрузка продолжения поверх подтверждённой части роли.
sealed class IntentionChoicesProgress {
  const IntentionChoicesProgress();
}

final class IntentionChoicesIdle extends IntentionChoicesProgress {
  const IntentionChoicesIdle();
}

final class IntentionChoicesLoadingMore extends IntentionChoicesProgress {
  const IntentionChoicesLoadingMore();
}

/// Отказ подгрузки: прежние строки, продолжение и сводка сохранены.
final class IntentionChoicesLoadMoreFailure extends IntentionChoicesProgress {
  const IntentionChoicesLoadMoreFailure(this.failure);

  final RelationGroupReadFailure failure;

  /// Обычный повтор предоставляется только при устранимой недоступности.
  bool get canRetry => failure is RelationGroupUnavailableFailure;
}
