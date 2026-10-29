import 'dart:async';

import '../../graph/application/graph_command_coordinator.dart';
import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_details.dart'
    as intention_application;
import '../../intention/application/intention_result.dart' as intention_result;
import '../../intention/domain/intention_id.dart';
import '../../tag/application/tag_change.dart';
import '../application/relation_group_page.dart';
import 'relation_group_paging.dart';
import 'relation_group_paging_policy.dart';

typedef RelationListIntentionObservation =
    intention_result.Result<
      GraphSnapshot<intention_application.IntentionDetails?>
    >;

/// Согласует порционный список страницы намерения с подтверждёнными
/// изменениями графа.
///
/// Слой владеет подписками на наблюдение намерения и завершения координатора,
/// сравнением ревизий, пересборкой, первым чтением, подгрузкой, повторами и
/// завершением контекста при удалении намерения. Вкладка задаёт запрос
/// порции, принадлежность строки и признак значимого изменения, а
/// опубликованное состояние слоя переводит в свою форму.
///
/// Подписки и первое чтение [query] начинаются при создании; [dispose]
/// отбрасывает ответы и подписки.
final class RelationListReconciliation<Row, Id extends Object> {
  RelationListReconciliation({
    required this._intentionId,
    required Stream<RelationListIntentionObservation> Function(IntentionId)
    watchIntention,
    required Stream<GraphCommandCompletion> completions,
    required this._policy,
    required RelationListQuery<Row, Id> query,
    required this._publish,
  }) : _query = query {
    _subscribe(watchIntention, completions);
    unawaited(_loadFirstPage(_paging.nextGeneration(), query));
  }

  final IntentionId _intentionId;
  final RelationGroupPagingPolicy _policy;
  final void Function(RelationListState<Row>) _publish;
  final _paging = RelationGroupPaging();

  StreamSubscription<RelationListIntentionObservation>? _intentionSubscription;
  StreamSubscription<GraphCommandCompletion>? _completionSubscription;
  RelationListQuery<Row, Id> _query;
  RelationListState<Row> _state = RelationListInitialLoad<Row>();
  var _isTerminated = false;
  var _isDisposed = false;

  /// Намерение подтверждённо отсутствует, список больше не читается.
  bool get isTerminated => _isTerminated;

  /// Начинает список заново с первой порции запроса и отбрасывает ответы
  /// прежнего.
  void restart(RelationListQuery<Row, Id> query) {
    final generation = _paging.nextGeneration();
    _query = query;
    _update(RelationListInitialLoad<Row>());
    unawaited(_loadFirstPage(generation, query));
  }

  /// Повторяет первое чтение после устранимого отказа.
  Future<void> retryFirstPage() {
    final current = _state;
    if (current is! RelationListInitialFailure<Row> || !current.canRetry) {
      return Future.value();
    }
    final generation = _paging.nextGeneration();
    _update(RelationListInitialLoad<Row>());
    return _loadFirstPage(generation, _query);
  }

  /// Подгружает следующую порцию при приближении к концу загруженной части.
  ///
  /// Пока порция ожидается, повторная прокрутка не отправляет её второй раз.
  Future<void> loadMoreIfNeeded({required int visibleIndex}) {
    final current = _state;
    if (current is! RelationListConfirmed<Row> ||
        current.data.nextCursor == null ||
        current.summaryStatus is! RelationListSummaryCurrent ||
        current.progress is! RelationListIdle ||
        visibleIndex < 0 ||
        current.data.items.length - visibleIndex - 1 >
            _policy.prefetchRemaining) {
      return Future.value();
    }
    return _loadMore(current);
  }

  Future<void> retryLoadMore() {
    final current = _state;
    if (current is! RelationListConfirmed<Row> ||
        current.summaryStatus is! RelationListSummaryCurrent) {
      return Future.value();
    }
    final progress = current.progress;
    if (progress is! RelationListLoadMoreFailure || !progress.canRetry) {
      return Future.value();
    }
    return _loadMore(current);
  }

  Future<void> retryRefresh() {
    final current = _state;
    if (current is! RelationListConfirmed<Row>) return Future.value();
    final summaryStatus = current.summaryStatus;
    if (summaryStatus is! RelationListSummaryRefreshFailure ||
        !summaryStatus.canRetry) {
      return Future.value();
    }
    return _refresh(current, includeRequestedPage: false);
  }

  void dispose() {
    _isDisposed = true;
    _paging.nextGeneration();
    unawaited(_intentionSubscription?.cancel());
    unawaited(_completionSubscription?.cancel());
  }

  void _update(RelationListState<Row> value) {
    _state = value;
    _publish(value);
  }

  Future<void> _loadFirstPage(
    int generation,
    RelationListQuery<Row, Id> query,
  ) async {
    final request = _paging.startRequest(generation);
    final result = await _paging.readFirst(_source(query), request);
    if (_isDisposed || !_paging.owns(request)) return;
    _paging.finishRequest(request);
    switch (result) {
      case GraphResultSuccess(:final value):
        if (_paging.precedesRequiredRevision(value.revision)) {
          unawaited(_loadFirstPage(generation, query));
          return;
        }
        _update(RelationListConfirmed(value));
      case GraphResultFailure(failure: RelationGroupIntentionNotFoundFailure()):
        _finishIntentionContext();
      case GraphResultFailure(:final failure):
        _update(RelationListInitialFailure(failure));
      case null:
        break;
    }
  }

  Future<void> _loadMore(RelationListConfirmed<Row> confirmed) async {
    if (_paging.hasActiveRequest || confirmed.data.nextCursor == null) return;
    if (_paging.precedesRequiredRevision(confirmed.data.revision)) {
      return _refresh(confirmed, includeRequestedPage: true);
    }
    final request = _paging.startRequest(_paging.generation);
    _update(confirmed.withProgress(const RelationListLoadingMore()));
    final result = await _paging.loadMore(
      _source(_query),
      confirmed.data,
      request,
    );
    if (_isDisposed || !_paging.owns(request)) return;
    _paging.finishRequest(request);
    final current = _state;
    if (current is! RelationListConfirmed<Row>) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        if (_paging.precedesRequiredRevision(value.revision)) {
          unawaited(_refresh(current, includeRequestedPage: true));
          return;
        }
        _update(
          RelationListConfirmed(value, summaryStatus: current.summaryStatus),
        );
      case GraphResultFailure(failure: RelationGroupIntentionNotFoundFailure()):
        _finishIntentionContext();
      case GraphResultFailure(:final failure):
        _update(current.withProgress(RelationListLoadMoreFailure(failure)));
      case null:
        unawaited(_refresh(current, includeRequestedPage: true));
    }
  }

  /// Прежняя подтверждённая часть остаётся видимой, пока ядро собирает замену.
  Future<void> _refresh(
    RelationListConfirmed<Row> confirmed, {
    required bool includeRequestedPage,
  }) async {
    if (_paging.hasActiveRequest) return;
    final request = _paging.startRequest(_paging.generation);
    final source = _source(_query);
    final refreshBase = confirmed.withProgress(const RelationListIdle());
    _update(
      refreshBase.withSummaryStatus(const RelationListSummaryRefreshing()),
    );
    try {
      while (_paging.owns(request)) {
        final result = await _paging.refresh(
          source,
          request,
          loadedCount: confirmed.data.items.length,
          includeRequestedPage: includeRequestedPage,
        );
        if (_isDisposed || !_paging.owns(request)) return;
        switch (result) {
          case GraphResultSuccess(:final value):
            if (_paging.precedesRequiredRevision(value.revision)) continue;
            _update(RelationListConfirmed(value));
            return;
          case GraphResultFailure(
            failure: RelationGroupIntentionNotFoundFailure(),
          ):
            _finishIntentionContext();
            return;
          case GraphResultFailure(:final failure):
            _update(
              refreshBase.withSummaryStatus(
                RelationListSummaryRefreshFailure(failure),
              ),
            );
            return;
          case null:
            return;
        }
      }
    } finally {
      _paging.finishRequest(request);
    }
  }

  RelationPagingSource<Row, Id> _source(RelationListQuery<Row, Id> query) =>
      RelationPagingSource(
        pageSize: _policy.pageSize,
        identify: query.identify,
        readPage: (cursor) async {
          try {
            return await query.readPage(cursor, _policy.pageSize);
          } on Object {
            // Неизвестная причина отказа не выдаётся за отсутствие данных.
            return const GraphResultFailure(RelationGroupUnexpectedFailure());
          }
        },
      );

  void _subscribe(
    Stream<RelationListIntentionObservation> Function(IntentionId)
    watchIntention,
    Stream<GraphCommandCompletion> completions,
  ) {
    try {
      _intentionSubscription = watchIntention(_intentionId).listen(
        (result) =>
            scheduleMicrotask(() => _handleIntentionObservation(result)),
        onError: (Object _, StackTrace _) => scheduleMicrotask(
          () => _handleIntentionObservation(
            const intention_result.ResultFailure(
              intention_result.IntentionUnexpectedFailure(),
            ),
          ),
        ),
      );
    } on Object {
      scheduleMicrotask(
        () => _handleIntentionObservation(
          const intention_result.ResultFailure(
            intention_result.IntentionUnexpectedFailure(),
          ),
        ),
      );
    }
    _completionSubscription = completions.listen(
      (completion) => scheduleMicrotask(() => _handleCompletion(completion)),
    );
  }

  void _handleIntentionObservation(RelationListIntentionObservation result) {
    if (_isDisposed || _isTerminated) return;
    switch (result) {
      case GraphResultSuccess(
        value: GraphSnapshot(value: null, :final revision),
      ):
        if (_observationPrecedesKnownRevision(revision)) return;
        _paging.requireRevision(revision);
        _finishIntentionContext();
      case GraphResultSuccess(
        value: GraphSnapshot(
          value: intention_application.IntentionDetails(),
          :final revision,
        ),
      ):
        _requestReconciliation(revision);
      case GraphResultFailure(:final failure):
        final mapped = _relationFailureForIntention(failure);
        final current = _state;
        _update(switch (current) {
          RelationListConfirmed() => current.withSummaryStatus(
            RelationListSummaryRefreshFailure(mapped),
          ),
          RelationListInitialLoad() ||
          RelationListInitialFailure() => RelationListInitialFailure(mapped),
          RelationListIntentionNotFound() => current,
        });
    }
  }

  void _handleCompletion(GraphCommandCompletion completion) {
    if (_isDisposed || _isTerminated) return;
    final confirmedChange = completion.confirmedChange;
    if (confirmedChange == null) return;
    if (confirmedChange.changes.whereType<IntentionCatalogDeleted>().any(
      (change) => change.before.summary.id == _intentionId,
    )) {
      _paging.requireRevision(confirmedChange.revision);
      _finishIntentionContext();
      return;
    }
    final current = _state;
    final confirmed = current is RelationListConfirmed<Row>
        ? current.data
        : null;
    if (confirmedChange.changes.any(
      (change) => _query.isSignificant(change, confirmed),
    )) {
      _requestReconciliation(confirmedChange.revision);
    } else if (confirmedChange.changes.any((change) => change is TagChange)) {
      _noteUnrelatedRevision(confirmedChange.revision);
    }
  }

  /// Чужая ревизия не меняет строк, но делает непригодным продолжение
  /// прежнего снимка.
  void _noteUnrelatedRevision(GraphRevision revision) {
    if (!_isNewerThanKnown(revision)) return;
    _paging.requireRevision(revision);
    final current = _state;
    if (current is RelationListConfirmed<Row> &&
        current.progress is RelationListLoadingMore) {
      _paging.cancelRequest();
      unawaited(_refresh(current, includeRequestedPage: true));
    }
  }

  void _requestReconciliation(GraphRevision revision) {
    if (!_isNewerThanKnown(revision)) return;
    _paging.requireRevision(revision);
    final current = _state;
    if (current is RelationListConfirmed<Row> &&
        current.progress is RelationListLoadingMore) {
      // Продолжение прежней ревизии может задержаться или не завершиться.
      // Новую основу читаем сразу, сохраняя предел запрошенной порции.
      _paging.cancelRequest();
      unawaited(_refresh(current, includeRequestedPage: true));
    } else if (current is RelationListConfirmed<Row> &&
        !_paging.hasActiveRequest) {
      unawaited(_refresh(current, includeRequestedPage: false));
    }
  }

  /// Ревизия новее опубликованной части и уже затребованной основы.
  bool _isNewerThanKnown(GraphRevision revision) {
    bool isNotNewer(GraphRevision known) => switch (revision.compareTo(known)) {
      GraphRevisionOrder.older || GraphRevisionOrder.same => true,
      GraphRevisionOrder.newer || GraphRevisionOrder.differentEpoch => false,
    };
    final current = _state;
    if (current is RelationListConfirmed<Row> &&
        isNotNewer(current.data.revision)) {
      return false;
    }
    final required = _paging.requiredRevision;
    return required == null || !isNotNewer(required);
  }

  bool _observationPrecedesKnownRevision(GraphRevision revision) {
    final current = _state;
    if (current is RelationListConfirmed<Row> &&
        _paging.precedes(revision, current.data.revision)) {
      return true;
    }
    return _paging.precedesRequiredRevision(revision);
  }

  RelationGroupReadFailure _relationFailureForIntention(
    intention_result.IntentionFailure failure,
  ) => switch (failure) {
    intention_result.IntentionUnavailableFailure() =>
      const RelationGroupUnavailableFailure(),
    intention_result.IntentionCorruptionFailure() =>
      const RelationGroupCorruptionFailure(),
    intention_result.IntentionNotFoundFailure() =>
      RelationGroupIntentionNotFoundFailure(_intentionId),
    intention_result.IntentionValidationFailure() ||
    intention_result.IntentionConflictFailure() ||
    intention_result.IntentionHasBlockingRelationsFailure() ||
    intention_result.IntentionUnexpectedFailure() =>
      const RelationGroupUnexpectedFailure(),
  };

  void _finishIntentionContext() {
    if (_isTerminated) return;
    _isTerminated = true;
    _paging.nextGeneration();
    _update(RelationListIntentionNotFound<Row>());
    unawaited(_intentionSubscription?.cancel());
    unawaited(_completionSubscription?.cancel());
  }
}

/// Предметная часть списка, которую задаёт вкладка.
final class RelationListQuery<Row, Id extends Object> {
  const RelationListQuery({
    required this.readPage,
    required this.identify,
    required this.isSignificant,
  });

  /// Первая порция при `null`, иначе продолжение по курсору.
  final Future<RelationPagingPageResult<Row>> Function(
    RelationGroupCursor? cursor,
    int pageSize,
  )
  readPage;

  /// Идентификатор строки своего списка или `null` для чужой строки.
  final Id? Function(Row) identify;

  /// Требует ли подтверждённое изменение новой основы списка. Опубликованная
  /// часть передаётся, когда она есть.
  final bool Function(GraphChange change, RelationPagingData<Row>? confirmed)
  isSignificant;
}

/// Опубликованное состояние списка, которое вкладка переводит в свою форму.
sealed class RelationListState<Row> {
  const RelationListState();
}

/// Первое чтение: подтверждённых строк ещё нет.
final class RelationListInitialLoad<Row> extends RelationListState<Row> {
  const RelationListInitialLoad();
}

/// Первое чтение завершилось отказом; это не пустой список.
final class RelationListInitialFailure<Row> extends RelationListState<Row> {
  const RelationListInitialFailure(this.failure);

  final RelationGroupReadFailure failure;

  /// Обычный повтор предоставляется только при устранимой недоступности.
  bool get canRetry => failure is RelationGroupUnavailableFailure;
}

/// Намерение подтверждённо отсутствует, список больше не читается.
final class RelationListIntentionNotFound<Row> extends RelationListState<Row> {
  const RelationListIntentionNotFound();
}

/// Подтверждённая загруженная часть и сводка на одной ревизии графа.
final class RelationListConfirmed<Row> extends RelationListState<Row> {
  const RelationListConfirmed(
    this.data, {
    this.summaryStatus = const RelationListSummaryCurrent(),
    this.progress = const RelationListIdle(),
  });

  final RelationPagingData<Row> data;
  final RelationListSummaryStatus summaryStatus;
  final RelationListProgress progress;

  RelationListConfirmed<Row> withSummaryStatus(
    RelationListSummaryStatus value,
  ) => RelationListConfirmed(data, summaryStatus: value, progress: progress);

  RelationListConfirmed<Row> withProgress(RelationListProgress value) =>
      RelationListConfirmed(
        data,
        summaryStatus: summaryStatus,
        progress: value,
      );
}

/// Актуальность опубликованной пары строк и сводки.
///
/// Она хранится отдельно от подгрузки: поздний ответ порции не может выдать
/// прежние числа за актуальные или скрыть ошибку обновления.
sealed class RelationListSummaryStatus {
  const RelationListSummaryStatus();
}

/// Опубликованная пара относится к текущему согласованному снимку.
final class RelationListSummaryCurrent extends RelationListSummaryStatus {
  const RelationListSummaryCurrent();
}

/// Прежняя пара показана, пока собирается её замена.
final class RelationListSummaryRefreshing extends RelationListSummaryStatus {
  const RelationListSummaryRefreshing();
}

/// Замену получить не удалось, поэтому показанная пара устарела.
final class RelationListSummaryRefreshFailure
    extends RelationListSummaryStatus {
  const RelationListSummaryRefreshFailure(this.failure);

  final RelationGroupReadFailure failure;

  /// Обычный повтор предоставляется только при устранимой недоступности.
  bool get canRetry => failure is RelationGroupUnavailableFailure;
}

/// Подгрузка продолжения поверх подтверждённой части.
sealed class RelationListProgress {
  const RelationListProgress();
}

final class RelationListIdle extends RelationListProgress {
  const RelationListIdle();
}

final class RelationListLoadingMore extends RelationListProgress {
  const RelationListLoadingMore();
}

/// Отказ подгрузки: прежние строки, продолжение и сводка сохранены.
final class RelationListLoadMoreFailure extends RelationListProgress {
  const RelationListLoadMoreFailure(this.failure);

  final RelationGroupReadFailure failure;

  /// Обычный повтор предоставляется только при устранимой недоступности.
  bool get canRetry => failure is RelationGroupUnavailableFailure;
}
