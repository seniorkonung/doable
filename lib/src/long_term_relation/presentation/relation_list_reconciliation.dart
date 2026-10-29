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
import '../application/relation_counts.dart';
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
/// завершением контекста при удалении намерения. Вкладка задаёт части
/// списка с запросом порции и принадлежностью строки, признак значимого
/// изменения, а опубликованное состояние слоя переводит в свою форму.
///
/// Все части публикуются вместе на одной ревизии: строка, которая переходит
/// между частями, видна ровно в одной из них.
///
/// Подписки и первое чтение [query] начинаются при создании; [dispose]
/// отбрасывает ответы и подписки.
final class RelationListReconciliation<
  Part extends Object,
  Row,
  Id extends Object
> {
  RelationListReconciliation({
    required this._intentionId,
    required Stream<RelationListIntentionObservation> Function(IntentionId)
    watchIntention,
    required Stream<GraphCommandCompletion> completions,
    required this._policy,
    required RelationListQuery<Part, Row, Id> query,
    required this._publish,
  }) : _query = query {
    _subscribe(watchIntention, completions);
    unawaited(_loadFirstPage(_paging.nextGeneration(), query));
  }

  final IntentionId _intentionId;
  final RelationGroupPagingPolicy _policy;
  final void Function(RelationListState<Part, Row>) _publish;
  final _paging = RelationGroupPaging();

  StreamSubscription<RelationListIntentionObservation>? _intentionSubscription;
  StreamSubscription<GraphCommandCompletion>? _completionSubscription;
  RelationListQuery<Part, Row, Id> _query;
  RelationListState<Part, Row> _state = RelationListInitialLoad<Part, Row>();
  var _isTerminated = false;
  var _isDisposed = false;

  /// Намерение подтверждённо отсутствует, список больше не читается.
  bool get isTerminated => _isTerminated;

  /// Начинает список заново с первых порций запроса и отбрасывает ответы
  /// прежнего.
  void restart(RelationListQuery<Part, Row, Id> query) {
    final generation = _paging.nextGeneration();
    _query = query;
    _update(RelationListInitialLoad<Part, Row>());
    unawaited(_loadFirstPage(generation, query));
  }

  /// Меняет состав частей, сохраняя хотя бы одну из прежних.
  ///
  /// Убранные части отбрасываются сразу. Добавленные получают первую порцию
  /// на ревизии опубликованных, а до готовности новой пары видна прежняя.
  void reshape(RelationListQuery<Part, Row, Id> query) {
    if (_isTerminated) return;
    final current = _state;
    _query = query;
    switch (current) {
      case RelationListInitialLoad():
        restart(query);
      case RelationListInitialFailure() || RelationListIntentionNotFound():
        break;
      case RelationListConfirmed():
        final retained = current.retaining(query.parts.keys);
        final added = [
          for (final entry in query.parts.entries)
            if (!retained.parts.containsKey(entry.key)) entry,
        ];
        if (_paging.hasActiveRequest) {
          // Ответ прежнего состава не подходит новой паре.
          _paging.cancelRequest();
          unawaited(_refresh(retained, requestedPart: retained.loadingPart));
        } else if (added.isEmpty) {
          _update(retained);
        } else {
          unawaited(_extend(retained, added));
        }
    }
  }

  /// Повторяет первое чтение после устранимого отказа.
  Future<void> retryFirstPage() {
    final current = _state;
    if (current is! RelationListInitialFailure<Part, Row> ||
        !current.canRetry) {
      return Future.value();
    }
    final generation = _paging.nextGeneration();
    _update(RelationListInitialLoad<Part, Row>());
    return _loadFirstPage(generation, _query);
  }

  /// Подгружает следующую порцию [part] при приближении к концу её
  /// загруженной части.
  ///
  /// Пока порция ожидается, повторная прокрутка не отправляет её второй раз.
  Future<void> loadMoreIfNeeded({
    required Part part,
    required int visibleIndex,
  }) {
    final current = _state;
    if (current is! RelationListConfirmed<Part, Row> ||
        current.summaryStatus is! RelationListSummaryCurrent) {
      return Future.value();
    }
    final loaded = current.parts[part];
    if (loaded == null ||
        loaded.data.nextCursor == null ||
        loaded.progress is! RelationListIdle ||
        visibleIndex < 0 ||
        loaded.data.items.length - visibleIndex - 1 >
            _policy.prefetchRemaining) {
      return Future.value();
    }
    return _loadMore(current, part, loaded);
  }

  Future<void> retryLoadMore({required Part part}) {
    final current = _state;
    if (current is! RelationListConfirmed<Part, Row> ||
        current.summaryStatus is! RelationListSummaryCurrent) {
      return Future.value();
    }
    final loaded = current.parts[part];
    final progress = loaded?.progress;
    if (loaded == null ||
        progress is! RelationListLoadMoreFailure ||
        !progress.canRetry) {
      return Future.value();
    }
    return _loadMore(current, part, loaded);
  }

  Future<void> retryRefresh() {
    final current = _state;
    if (current is! RelationListConfirmed<Part, Row>) return Future.value();
    final summaryStatus = current.summaryStatus;
    if (summaryStatus is! RelationListSummaryRefreshFailure ||
        !summaryStatus.canRetry) {
      return Future.value();
    }
    return _refresh(current, requestedPart: null);
  }

  void dispose() {
    _isDisposed = true;
    _paging.nextGeneration();
    unawaited(_intentionSubscription?.cancel());
    unawaited(_completionSubscription?.cancel());
  }

  void _update(RelationListState<Part, Row> value) {
    _state = value;
    _publish(value);
  }

  Future<void> _loadFirstPage(
    int generation,
    RelationListQuery<Part, Row, Id> query,
  ) async {
    final request = _paging.startRequest(generation);
    final parts = query.parts.entries.toList();
    final results = await Future.wait([
      for (final MapEntry(value: part) in parts)
        _paging.readFirst(_source(part), request),
    ]);
    if (_isDisposed || !_paging.owns(request)) return;
    _paging.finishRequest(request);
    switch (_collect(parts, results)) {
      case GraphResultSuccess(:final value):
        if (!_isConsistent(value)) {
          unawaited(_loadFirstPage(generation, query));
          return;
        }
        _update(RelationListConfirmed(_freshParts(value)));
      case GraphResultFailure(failure: RelationGroupIntentionNotFoundFailure()):
        _finishIntentionContext();
      case GraphResultFailure(:final failure):
        _update(RelationListInitialFailure(failure));
      case null:
        break;
    }
  }

  Future<void> _loadMore(
    RelationListConfirmed<Part, Row> confirmed,
    Part part,
    RelationListPart<Row> loaded,
  ) async {
    if (_paging.hasActiveRequest || loaded.data.nextCursor == null) return;
    if (_paging.precedesRequiredRevision(confirmed.revision)) {
      return _refresh(confirmed, requestedPart: part);
    }
    final request = _paging.startRequest(_paging.generation);
    _update(confirmed.withProgress(part, const RelationListLoadingMore()));
    final result = await _paging.loadMore(
      _source(_query.parts[part]!),
      loaded.data,
      request,
    );
    if (_isDisposed || !_paging.owns(request)) return;
    _paging.finishRequest(request);
    final current = _state;
    if (current is! RelationListConfirmed<Part, Row>) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        if (_paging.precedesRequiredRevision(value.revision)) {
          unawaited(_refresh(current, requestedPart: part));
          return;
        }
        _update(current.withPart(part, RelationListPart(value)));
      case GraphResultFailure(failure: RelationGroupIntentionNotFoundFailure()):
        _finishIntentionContext();
      case GraphResultFailure(:final failure):
        _update(
          current.withProgress(part, RelationListLoadMoreFailure(failure)),
        );
      case null:
        unawaited(_refresh(current, requestedPart: part));
    }
  }

  /// Добавленные части читают первую порцию и присоединяются к
  /// опубликованным, только если ревизия общая; иначе пара пересобирается
  /// целиком.
  Future<void> _extend(
    RelationListConfirmed<Part, Row> confirmed,
    List<MapEntry<Part, RelationListPartQuery<Row, Id>>> added,
  ) async {
    if (_paging.precedesRequiredRevision(confirmed.revision)) {
      return _refresh(confirmed, requestedPart: null);
    }
    final request = _paging.startRequest(_paging.generation);
    _update(confirmed);
    final results = await Future.wait([
      for (final MapEntry(value: part) in added)
        _paging.readFirst(_source(part), request),
    ]);
    if (_isDisposed || !_paging.owns(request)) return;
    _paging.finishRequest(request);
    final current = _state;
    if (current is! RelationListConfirmed<Part, Row>) return;
    switch (_collect(added, results)) {
      case GraphResultSuccess(:final value):
        if (!_isConsistent({
          for (final MapEntry(:key, :value) in current.parts.entries)
            key: value.data,
          ...value,
        })) {
          unawaited(_refresh(current, requestedPart: null));
          return;
        }
        final fresh = _freshParts(value);
        _update(
          RelationListConfirmed({
            for (final key in _query.parts.keys)
              key: ?(fresh[key] ?? current.parts[key]),
          }, summaryStatus: current.summaryStatus),
        );
      case GraphResultFailure(failure: RelationGroupIntentionNotFoundFailure()):
        _finishIntentionContext();
      case GraphResultFailure(:final failure):
        _update(
          current.withSummaryStatus(RelationListSummaryRefreshFailure(failure)),
        );
      case null:
        break;
    }
  }

  /// Прежняя подтверждённая пара остаётся видимой, пока ядро собирает
  /// замену. Каждая часть повторяет своё загруженное, а [requestedPart] —
  /// ещё и запрошенное продолжение; новая часть получает первую порцию.
  Future<void> _refresh(
    RelationListConfirmed<Part, Row> confirmed, {
    required Part? requestedPart,
  }) async {
    if (_paging.hasActiveRequest) return;
    final request = _paging.startRequest(_paging.generation);
    final parts = _query.parts.entries.toList();
    final refreshBase = confirmed.withIdleProgress();
    _update(
      refreshBase.withSummaryStatus(const RelationListSummaryRefreshing()),
    );
    try {
      while (_paging.owns(request)) {
        final results = await Future.wait([
          for (final MapEntry(key: key, value: part) in parts)
            _paging.refresh(
              _source(part),
              request,
              loadedCount: confirmed.parts[key]?.data.items.length ?? 0,
              includeRequestedPage: key == requestedPart,
            ),
        ]);
        if (_isDisposed || !_paging.owns(request)) return;
        switch (_collect(parts, results)) {
          case GraphResultSuccess(:final value):
            if (!_isConsistent(value)) continue;
            _update(RelationListConfirmed(_freshParts(value)));
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

  /// Отсутствие намерения важнее прочих отказов частей; `null` означает
  /// ответ прежнего запроса.
  GraphResult<Map<Part, RelationPagingData<Row>>, RelationGroupReadFailure>?
  _collect(
    List<MapEntry<Part, RelationListPartQuery<Row, Id>>> parts,
    List<RelationPagingResult<Row>?> results,
  ) {
    final collected = <Part, RelationPagingData<Row>>{};
    RelationGroupReadFailure? failure;
    for (final (index, result) in results.indexed) {
      switch (result) {
        case GraphResultSuccess(:final value):
          collected[parts[index].key] = value;
        case GraphResultFailure(failure: final partFailure):
          if (failure == null ||
              partFailure is RelationGroupIntentionNotFoundFailure) {
            failure = partFailure;
          }
        case null:
          return null;
      }
    }
    return failure == null
        ? GraphResultSuccess(collected)
        : GraphResultFailure(failure);
  }

  /// Части публикуются только на одной ревизии не старше затребованной.
  bool _isConsistent(Map<Part, RelationPagingData<Row>> parts) {
    final revision = parts.values.first.revision;
    return parts.values.every(
      (part) =>
          !_paging.precedesRequiredRevision(part.revision) &&
          part.revision.compareTo(revision) == GraphRevisionOrder.same,
    );
  }

  Map<Part, RelationListPart<Row>> _freshParts(
    Map<Part, RelationPagingData<Row>> parts,
  ) => {
    for (final MapEntry(:key, :value) in parts.entries)
      key: RelationListPart(value),
  };

  RelationPagingSource<Row, Id> _source(RelationListPartQuery<Row, Id> part) =>
      RelationPagingSource(
        pageSize: _policy.pageSize,
        identify: part.identify,
        readPage: (cursor) async {
          try {
            return await part.readPage(cursor, _policy.pageSize);
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
    final confirmed = current is RelationListConfirmed<Part, Row>
        ? current
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
    if (current is! RelationListConfirmed<Part, Row>) return;
    final loadingPart = current.loadingPart;
    if (loadingPart != null) {
      _paging.cancelRequest();
      unawaited(_refresh(current, requestedPart: loadingPart));
    }
  }

  void _requestReconciliation(GraphRevision revision) {
    if (!_isNewerThanKnown(revision)) return;
    _paging.requireRevision(revision);
    final current = _state;
    if (current is! RelationListConfirmed<Part, Row>) return;
    final loadingPart = current.loadingPart;
    if (loadingPart != null) {
      // Продолжение прежней ревизии может задержаться или не завершиться.
      // Новую основу читаем сразу, сохраняя предел запрошенной порции.
      _paging.cancelRequest();
      unawaited(_refresh(current, requestedPart: loadingPart));
    } else if (!_paging.hasActiveRequest) {
      unawaited(_refresh(current, requestedPart: null));
    }
  }

  /// Ревизия новее опубликованной пары и уже затребованной основы.
  bool _isNewerThanKnown(GraphRevision revision) {
    bool isNotNewer(GraphRevision known) => switch (revision.compareTo(known)) {
      GraphRevisionOrder.older || GraphRevisionOrder.same => true,
      GraphRevisionOrder.newer || GraphRevisionOrder.differentEpoch => false,
    };
    final current = _state;
    if (current is RelationListConfirmed<Part, Row> &&
        isNotNewer(current.revision)) {
      return false;
    }
    final required = _paging.requiredRevision;
    return required == null || !isNotNewer(required);
  }

  bool _observationPrecedesKnownRevision(GraphRevision revision) {
    final current = _state;
    if (current is RelationListConfirmed<Part, Row> &&
        _paging.precedes(revision, current.revision)) {
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
    _update(RelationListIntentionNotFound<Part, Row>());
    unawaited(_intentionSubscription?.cancel());
    unawaited(_completionSubscription?.cancel());
  }
}

/// Предметная часть списка, которую задаёт вкладка.
final class RelationListQuery<Part extends Object, Row, Id extends Object> {
  RelationListQuery({
    required Map<Part, RelationListPartQuery<Row, Id>> parts,
    required this.isSignificant,
  }) : assert(parts.isNotEmpty, 'У списка есть хотя бы одна часть.'),
       parts = Map.unmodifiable(parts);

  /// Читаемые части в порядке показа.
  final Map<Part, RelationListPartQuery<Row, Id>> parts;

  /// Требует ли подтверждённое изменение новой основы списка. Опубликованная
  /// пара передаётся, когда она есть.
  final bool Function(
    GraphChange change,
    RelationListConfirmed<Part, Row>? confirmed,
  )
  isSignificant;
}

/// Чтение одной части списка.
final class RelationListPartQuery<Row, Id extends Object> {
  const RelationListPartQuery({required this.readPage, required this.identify});

  /// Первая порция при `null`, иначе продолжение по курсору.
  final Future<RelationPagingPageResult<Row>> Function(
    RelationGroupCursor? cursor,
    int pageSize,
  )
  readPage;

  /// Идентификатор строки своей части или `null` для чужой строки.
  final Id? Function(Row) identify;
}

/// Опубликованное состояние списка, которое вкладка переводит в свою форму.
sealed class RelationListState<Part extends Object, Row> {
  const RelationListState();
}

/// Первое чтение: подтверждённых строк ещё нет.
final class RelationListInitialLoad<Part extends Object, Row>
    extends RelationListState<Part, Row> {
  const RelationListInitialLoad();
}

/// Первое чтение завершилось отказом; это не пустой список.
final class RelationListInitialFailure<Part extends Object, Row>
    extends RelationListState<Part, Row> {
  const RelationListInitialFailure(this.failure);

  final RelationGroupReadFailure failure;

  /// Обычный повтор предоставляется только при устранимой недоступности.
  bool get canRetry => failure is RelationGroupUnavailableFailure;
}

/// Намерение подтверждённо отсутствует, список больше не читается.
final class RelationListIntentionNotFound<Part extends Object, Row>
    extends RelationListState<Part, Row> {
  const RelationListIntentionNotFound();
}

/// Подтверждённые загруженные части и сводка на одной ревизии графа.
///
/// Части идут в порядке запроса. Добавленная часть появляется здесь только
/// вместе с остальными на общей ревизии.
final class RelationListConfirmed<Part extends Object, Row>
    extends RelationListState<Part, Row> {
  RelationListConfirmed(
    Map<Part, RelationListPart<Row>> parts, {
    this.summaryStatus = const RelationListSummaryCurrent(),
  }) : assert(parts.isNotEmpty, 'У списка есть хотя бы одна часть.'),
       parts = Map.unmodifiable(parts);

  final Map<Part, RelationListPart<Row>> parts;
  final RelationListSummaryStatus summaryStatus;

  /// Полная сводка, полученная вместе с первыми порциями частей.
  RelationCounts get counts => parts.values.first.data.counts;

  GraphRevision get revision => parts.values.first.data.revision;

  /// Строки всех частей в порядке показа.
  Iterable<Row> get items => parts.values.expand((part) => part.data.items);

  /// Часть, продолжение которой сейчас ожидается.
  Part? get loadingPart {
    for (final MapEntry(:key, :value) in parts.entries) {
      if (value.progress is RelationListLoadingMore) return key;
    }
    return null;
  }

  RelationListConfirmed<Part, Row> withSummaryStatus(
    RelationListSummaryStatus value,
  ) => RelationListConfirmed(parts, summaryStatus: value);

  RelationListConfirmed<Part, Row> withPart(
    Part key,
    RelationListPart<Row> value,
  ) => RelationListConfirmed({
    for (final MapEntry(key: partKey, value: part) in parts.entries)
      partKey: partKey == key ? value : part,
  }, summaryStatus: summaryStatus);

  RelationListConfirmed<Part, Row> withProgress(
    Part key,
    RelationListProgress value,
  ) => RelationListConfirmed({
    for (final MapEntry(key: partKey, value: part) in parts.entries)
      partKey: partKey == key ? part.withProgress(value) : part,
  }, summaryStatus: summaryStatus);

  RelationListConfirmed<Part, Row> withIdleProgress() => RelationListConfirmed({
    for (final MapEntry(:key, :value) in parts.entries)
      key: value.withProgress(const RelationListIdle()),
  }, summaryStatus: summaryStatus);

  RelationListConfirmed<Part, Row> retaining(Iterable<Part> keys) {
    final retained = keys.toSet();
    return RelationListConfirmed({
      for (final MapEntry(:key, :value) in parts.entries)
        if (retained.contains(key)) key: value,
    }, summaryStatus: summaryStatus);
  }
}

/// Загруженная часть списка и подгрузка её продолжения.
final class RelationListPart<Row> {
  const RelationListPart(this.data, {this.progress = const RelationListIdle()});

  final RelationPagingData<Row> data;
  final RelationListProgress progress;

  RelationListPart<Row> withProgress(RelationListProgress value) =>
      RelationListPart(data, progress: value);
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
