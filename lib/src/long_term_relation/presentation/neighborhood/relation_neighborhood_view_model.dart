import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../daily_choice/application/daily_choice_catalog.dart';
import '../../../daily_choice/domain/daily_choice_id.dart';
import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/application/intention_details.dart'
    as intention_application;
import '../../../intention/application/intention_result.dart'
    as intention_result;
import '../../../intention/domain/intention_id.dart';
import '../../../tag/application/tag_change.dart';
import '../../application/long_term_relation_projection.dart';
import '../../application/relation_counts.dart';
import '../../application/relation_group_page.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_id.dart';
import '../relation_group_paging.dart';
import 'relation_neighborhood_paging_policy.dart';
import 'relation_neighborhood_state.dart';

part 'relation_neighborhood_view_model.g.dart';

/// Управляет первым чтением и подгрузкой одной выбранной группы связей.
///
/// Одновременно выполняется не более одного чтения группы. Ответ принимается
/// только для текущего поколения запроса: смена группы, повторное первое
/// чтение и обновление делают прежние ответы непригодными.
@riverpod
final class RelationNeighborhoodViewModel
    extends _$RelationNeighborhoodViewModel {
  final _paging = RelationGroupPaging();

  late IntentionId _intentionId;
  late PersonalGraphRepository _repository;
  late GraphCommandCoordinator _coordinator;
  late RelationNeighborhoodPagingPolicy _policy;
  StreamSubscription<
    intention_result.Result<
      GraphSnapshot<intention_application.IntentionDetails?>
    >
  >?
  _intentionSubscription;
  StreamSubscription<GraphCommandCompletion>? _completionSubscription;
  var _selection = RelationGroupSelection.initial;
  RelationGroup _group = const LongTermRelationGroup(
    type: LongTermRelationType.need,
    direction: RelationDirection.outgoing,
    scope: RelationScope.active,
  );
  LongTermRelationId? _visibleRelationId;
  var _isTerminated = false;

  @override
  RelationNeighborhoodState build(IntentionId intentionId) {
    _intentionId = intentionId;
    _repository = ref.watch(personalGraphRepositoryProvider);
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _policy = ref.watch(relationNeighborhoodPagingPolicyProvider);
    _isTerminated = false;
    _subscribeToGraphChanges();
    ref.onDispose(() {
      _paging.nextGeneration();
      unawaited(_intentionSubscription?.cancel());
      unawaited(_completionSubscription?.cancel());
    });
    final generation = _paging.nextGeneration();
    unawaited(_loadFirstPage(generation));
    return RelationGroupInitialLoad(
      intentionId: intentionId,
      selection: _selection,
      group: _group,
    );
  }

  void selectType(LongTermRelationType type) {
    if (_group is LongTermRelationGroup && _selection.type == type) {
      return;
    }
    _restart(_selection.withType(type));
  }

  void selectDirection(RelationDirection direction) {
    if (_group is LongTermRelationGroup && _selection.direction == direction) {
      return;
    }
    _restart(_selection.withDirection(direction));
  }

  void selectScope(RelationScope scope) {
    if (_group is LongTermRelationGroup && _selection.scope == scope) {
      return;
    }
    _restart(_selection.withScope(scope));
  }

  /// Открывает один из восьми точных переходов полной сводки.
  void selectGroup(RelationGroupSelection selection) {
    if (_group is LongTermRelationGroup && _selection == selection) {
      return;
    }
    _restart(selection);
  }

  /// Выбирает одну прямую роль дневных выборов без чтения других групп.
  void selectDailyGroup(DailyChoiceRelationRole role) {
    final group = DailyChoiceRelationGroup(role: role);
    if (_group == group) {
      return;
    }
    _restartGroup(group);
  }

  /// Открывает архив связей намерения, сохранённый после каскада.
  ///
  /// Архивные связи остаются архивированными сами по себе, поэтому просмотр
  /// начинается с первой непустой архивной группы.
  void showArchivedRelations(RelationCounts counts) =>
      _restart(_firstNonEmptyGroup(counts, scope: RelationScope.archived));

  /// Повторяет первое чтение выбранной группы после устранимого отказа.
  Future<void> retryFirstPage() {
    final current = state;
    if (current is! RelationGroupInitialFailure || !current.canRetry) {
      return Future.value();
    }
    final generation = _paging.nextGeneration();
    state = RelationGroupInitialLoad(
      intentionId: _intentionId,
      selection: current.selection,
      group: current.group,
    );
    return _loadFirstPage(generation);
  }

  /// Подгружает следующую порцию при приближении к концу загруженной части.
  ///
  /// Пока порция ожидается, повторная прокрутка не отправляет её второй раз.
  Future<void> loadMoreIfNeeded({required int visibleIndex}) {
    final current = state;
    if (current is! RelationGroupConfirmedState) return Future.value();
    final length = switch (current) {
      RelationGroupLoaded(:final items) => items.length,
      DailyChoiceGroupLoaded(:final items) => items.length,
      RelationGroupEmpty() => null,
    };
    if (length == null ||
        _cursorOf(current) == null ||
        current.summaryFreshness != RelationSummaryFreshness.current ||
        current.progress is! RelationGroupIdle ||
        visibleIndex < 0 ||
        length - visibleIndex - 1 > _policy.prefetchRemaining) {
      return Future.value();
    }
    return _loadMore(current);
  }

  Future<void> retryLoadMore() {
    final current = state;
    if (current is! RelationGroupConfirmedState ||
        current is RelationGroupEmpty) {
      return Future.value();
    }
    if (current.summaryFreshness != RelationSummaryFreshness.current) {
      return Future.value();
    }
    final progress = current.progress;
    if (progress is! RelationGroupLoadMoreFailure || !progress.canRetry) {
      return Future.value();
    }
    return _loadMore(current);
  }

  Future<void> retryRefresh() {
    final current = state;
    if (current is! RelationGroupConfirmedState) {
      return Future.value();
    }
    final summaryStatus = current.summaryStatus;
    if (summaryStatus is! RelationSummaryRefreshFailure ||
        !summaryStatus.canRetry) {
      return Future.value();
    }
    return _refresh(current, includeRequestedPage: false);
  }

  /// Запоминает первую видимую строку для восстановления viewport после
  /// атомарной замены загруженной части.
  void rememberVisibleRelation(LongTermRelationId relationId) {
    final current = state;
    if (current is RelationGroupLoaded &&
        current.items.any((item) => item.relation.id == relationId)) {
      _visibleRelationId = relationId;
    }
  }

  /// Выбирает группу с подтверждённым содержимым в границах охвата.
  ///
  /// Сводка страницы доступна и до первого чтения соседства.
  RelationGroupSelection _firstNonEmptyGroup(
    RelationCounts counts, {
    RelationScope? scope,
  }) {
    final fallback = scope == null ? _selection : _selection.withScope(scope);
    for (final candidate in _groupOrder(scope)) {
      if (counts.forGroup(
            scope: candidate.scope,
            type: candidate.type,
            direction: candidate.direction,
          ) >
          0) {
        return candidate;
      }
    }
    return fallback;
  }

  /// Перебирает группы в порядке полной сводки на странице намерения.
  Iterable<RelationGroupSelection> _groupOrder(RelationScope? scope) sync* {
    const scopeOrder = [RelationScope.active, RelationScope.archived];
    const typeOrder = [LongTermRelationType.need, LongTermRelationType.can];
    const directionOrder = [
      RelationDirection.outgoing,
      RelationDirection.incoming,
    ];
    for (final groupScope in scope == null ? scopeOrder : [scope]) {
      for (final type in typeOrder) {
        for (final direction in directionOrder) {
          yield RelationGroupSelection(
            type: type,
            direction: direction,
            scope: groupScope,
          );
        }
      }
    }
  }

  void _restart(RelationGroupSelection selection) {
    _selection = selection;
    _restartGroup(
      LongTermRelationGroup(
        type: selection.type,
        direction: selection.direction,
        scope: selection.scope,
      ),
    );
  }

  void _restartGroup(RelationGroup group) {
    _group = group;
    _visibleRelationId = null;
    final generation = _paging.nextGeneration();
    state = RelationGroupInitialLoad(
      intentionId: _intentionId,
      selection: _selection,
      group: group,
    );
    unawaited(_loadFirstPage(generation));
  }

  Future<void> _loadFirstPage(int generation) async {
    final request = _paging.startRequest(generation);
    final selection = _selection;
    final group = _group;
    final result = await switch (group) {
      final LongTermRelationGroup longTerm => _mapPagingResult(
        _paging.readFirst(_longTermSource(longTerm), request),
        (data) => _longTermState(longTerm, data),
      ),
      final DailyChoiceRelationGroup daily => _mapPagingResult(
        _paging.readFirst(_dailySource(daily), request),
        (data) => _dailyState(daily, data),
      ),
    };
    if (!ref.mounted || !_paging.owns(request)) return;
    _paging.finishRequest(request);
    switch (result) {
      case GraphResultSuccess(:final value):
        if (_paging.precedesRequiredRevision(value.revision)) {
          unawaited(_loadFirstPage(generation));
          return;
        }
        state = value;
      case GraphResultFailure(failure: RelationGroupIntentionNotFoundFailure()):
        _finishIntentionContext();
      case GraphResultFailure(:final failure):
        state = _initialFailure(selection, group, failure);
      case null:
        break;
    }
  }

  Future<void> _loadMore(RelationGroupConfirmedState confirmed) async {
    if (_paging.hasActiveRequest || _cursorOf(confirmed) == null) return;
    if (_paging.precedesRequiredRevision(confirmed.revision)) {
      return _refresh(confirmed, includeRequestedPage: true);
    }
    final request = _paging.startRequest(_paging.generation);
    state = _withProgress(confirmed, const RelationGroupLoadingMore());
    final result = await switch (confirmed) {
      RelationGroupLoaded() => _mapPagingResult(
        _paging.loadMore(
          _longTermSource(confirmed.group as LongTermRelationGroup),
          _pagingData(confirmed, confirmed.items),
          request,
        ),
        (data) => _longTermState(
          confirmed.group as LongTermRelationGroup,
          data,
          scrollAnchor: confirmed.scrollAnchor,
        ),
      ),
      DailyChoiceGroupLoaded() => _mapPagingResult(
        _paging.loadMore(
          _dailySource(confirmed.group as DailyChoiceRelationGroup),
          _pagingData(confirmed, confirmed.items),
          request,
        ),
        (data) =>
            _dailyState(confirmed.group as DailyChoiceRelationGroup, data),
      ),
      RelationGroupEmpty() => null,
    };
    if (!ref.mounted || !_paging.owns(request)) return;
    _paging.finishRequest(request);
    final current = state;
    if (current is! RelationGroupConfirmedState ||
        current is RelationGroupEmpty) {
      return;
    }
    switch (result) {
      case GraphResultSuccess(:final value):
        if (_paging.precedesRequiredRevision(value.revision)) {
          unawaited(_refresh(current, includeRequestedPage: true));
          return;
        }
        state = _withSummaryStatus(value, current.summaryStatus);
      case GraphResultFailure(failure: RelationGroupIntentionNotFoundFailure()):
        _finishIntentionContext();
      case GraphResultFailure(:final failure):
        state = _withProgress(current, RelationGroupLoadMoreFailure(failure));
      case null:
        unawaited(_refresh(current, includeRequestedPage: true));
    }
  }

  /// Прежняя подтверждённая пара остаётся видимой, пока ядро собирает замену.
  Future<void> _refresh(
    RelationGroupConfirmedState confirmed, {
    required bool includeRequestedPage,
  }) async {
    if (_paging.hasActiveRequest) return;
    final request = _paging.startRequest(_paging.generation);
    final refreshBase = _withProgress(confirmed, const RelationGroupIdle());
    state = _withSummaryStatus(refreshBase, const RelationSummaryRefreshing());
    try {
      while (_paging.owns(request)) {
        final result = await switch (confirmed.group) {
          final LongTermRelationGroup group => _mapPagingResult(
            _paging.refresh(
              _longTermSource(group),
              request,
              loadedCount: _itemsOf(confirmed).length,
              includeRequestedPage: includeRequestedPage,
            ),
            (data) => _longTermState(group, data),
          ),
          final DailyChoiceRelationGroup group => _mapPagingResult(
            _paging.refresh(
              _dailySource(group),
              request,
              loadedCount: _dailyItemsOf(confirmed).length,
              includeRequestedPage: includeRequestedPage,
            ),
            (data) => _dailyState(group, data),
          ),
        };
        if (!ref.mounted || !_paging.owns(request)) return;
        switch (result) {
          case GraphResultSuccess(:final value):
            if (_paging.precedesRequiredRevision(value.revision)) continue;
            state = _withScrollAnchor(
              previous: refreshBase,
              replacement: value,
            );
            return;
          case GraphResultFailure(
            failure: RelationGroupIntentionNotFoundFailure(),
          ):
            _finishIntentionContext();
            return;
          case GraphResultFailure(:final failure):
            state = _withSummaryStatus(
              refreshBase,
              RelationSummaryRefreshFailure(failure),
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

  Future<GraphResult<RelationGroupConfirmedState, RelationGroupReadFailure>?>
  _mapPagingResult<Row>(
    Future<RelationPagingResult<Row>?> result,
    RelationGroupConfirmedState Function(RelationPagingData<Row>) toState,
  ) async => switch (await result) {
    GraphResultSuccess(:final value) => GraphResultSuccess(toState(value)),
    GraphResultFailure(:final failure) => GraphResultFailure(failure),
    null => null,
  };

  RelationPagingData<Row> _pagingData<Row>(
    RelationGroupConfirmedState confirmed,
    List<Row> items,
  ) => RelationPagingData(
    items: items,
    counts: confirmed.counts,
    totalCount: confirmed.totalCount,
    revision: confirmed.revision,
    nextCursor: _cursorOf(confirmed),
  );

  RelationPagingSource<LongTermRelationSummary, LongTermRelationId>
  _longTermSource(LongTermRelationGroup group) => RelationPagingSource(
    pageSize: _policy.pageSize,
    identify: (item) => _belongsToGroup(item, group) ? item.relation.id : null,
    readPage: (cursor) async =>
        switch (await _readPage(group, cursor: cursor)) {
          GraphResultSuccess(value: final RelationGroupFirstPage page) =>
            GraphResultSuccess(
              RelationPagingFirstPage(
                items: page.items,
                counts: page.counts,
                totalCount: page.counts.forSelection(group),
                revision: page.revision,
                nextCursor: page.nextCursor,
              ),
            ),
          GraphResultSuccess(value: final RelationGroupContinuationPage page) =>
            GraphResultSuccess(
              RelationPagingContinuationPage(
                items: page.items,
                revision: page.revision,
                nextCursor: page.nextCursor,
              ),
            ),
          GraphResultSuccess() => const GraphResultFailure(
            RelationGroupUnexpectedFailure(),
          ),
          GraphResultFailure(:final failure) => GraphResultFailure(failure),
        },
  );

  RelationPagingSource<DailyChoiceCatalogItem, DailyChoiceId> _dailySource(
    DailyChoiceRelationGroup group,
  ) => RelationPagingSource(
    pageSize: _policy.pageSize,
    identify: (item) => _dailyItemBelongsToGroup(item, group) ? item.id : null,
    readPage: (cursor) async => switch (await _readPage(
      group,
      cursor: cursor,
    )) {
      GraphResultSuccess(value: final DailyChoiceGroupFirstPage page) =>
        GraphResultSuccess(
          RelationPagingFirstPage(
            items: page.items,
            counts: page.counts,
            totalCount: page.counts.forSelection(group),
            revision: page.revision,
            nextCursor: page.nextCursor,
          ),
        ),
      GraphResultSuccess(value: final DailyChoiceGroupContinuationPage page) =>
        GraphResultSuccess(
          RelationPagingContinuationPage(
            items: page.items,
            revision: page.revision,
            nextCursor: page.nextCursor,
          ),
        ),
      GraphResultSuccess() => const GraphResultFailure(
        RelationGroupUnexpectedFailure(),
      ),
      GraphResultFailure(:final failure) => GraphResultFailure(failure),
    },
  );

  RelationGroupConfirmedState _longTermState(
    LongTermRelationGroup group,
    RelationPagingData<LongTermRelationSummary> data, {
    RelationGroupScrollAnchor? scrollAnchor,
  }) => data.items.isEmpty
      ? _emptyState(group, data)
      : RelationGroupLoaded(
          intentionId: _intentionId,
          selection: _selection,
          group: group,
          counts: data.counts,
          revision: data.revision,
          items: data.items,
          nextCursor: data.nextCursor,
          scrollAnchor: scrollAnchor,
        );

  RelationGroupConfirmedState _dailyState(
    DailyChoiceRelationGroup group,
    RelationPagingData<DailyChoiceCatalogItem> data,
  ) => data.items.isEmpty
      ? _emptyState(group, data)
      : DailyChoiceGroupLoaded(
          intentionId: _intentionId,
          selection: _selection,
          group: group,
          counts: data.counts,
          revision: data.revision,
          items: data.items,
          nextCursor: data.nextCursor,
        );

  RelationGroupEmpty _emptyState<Row>(
    RelationGroup group,
    RelationPagingData<Row> data,
  ) => RelationGroupEmpty(
    intentionId: _intentionId,
    selection: _selection,
    group: group,
    counts: data.counts,
    revision: data.revision,
  );

  void _subscribeToGraphChanges() {
    try {
      _intentionSubscription = _repository
          .watchIntention(_intentionId)
          .listen(
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
    _completionSubscription = _coordinator.completions.listen(
      (completion) => scheduleMicrotask(() => _handleCompletion(completion)),
    );
  }

  void _handleIntentionObservation(
    intention_result.Result<
      GraphSnapshot<intention_application.IntentionDetails?>
    >
    result,
  ) {
    if (!ref.mounted || _isTerminated) {
      return;
    }
    switch (result) {
      case GraphResultSuccess(
        value: GraphSnapshot(value: null, :final revision),
      ):
        if (_observationPrecedesKnownRevision(revision)) {
          return;
        }
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
        final current = state;
        state = switch (current) {
          RelationGroupConfirmedState() => _withSummaryStatus(
            current,
            RelationSummaryRefreshFailure(mapped),
          ),
          RelationGroupInitialLoad() || RelationGroupInitialFailure() =>
            _initialFailure(current.selection, current.group, mapped),
          RelationNeighborhoodIntentionNotFound() => current,
        };
    }
  }

  void _handleCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted || _isTerminated) {
      return;
    }
    final confirmedChange = completion.confirmedChange;
    if (confirmedChange == null) {
      return;
    }
    if (confirmedChange.changes.whereType<IntentionCatalogDeleted>().any(
      (change) => change.before.summary.id == _intentionId,
    )) {
      _paging.requireRevision(confirmedChange.revision);
      _finishIntentionContext();
      return;
    }
    if (_changesAffectObservedState(confirmedChange.changes)) {
      _requestReconciliation(confirmedChange.revision);
    } else if (confirmedChange.changes.any((change) => change is TagChange)) {
      _noteUnrelatedTagRevision(confirmedChange.revision);
    }
  }

  void _noteUnrelatedTagRevision(GraphRevision revision) {
    final current = state;
    if (current is RelationGroupConfirmedState) {
      final order = revision.compareTo(current.revision);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    final required = _paging.requiredRevision;
    if (required != null) {
      final order = revision.compareTo(required);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    _paging.requireRevision(revision);
    if (current is RelationGroupConfirmedState &&
        current.progress is RelationGroupLoadingMore) {
      _paging.cancelRequest();
      unawaited(_refresh(current, includeRequestedPage: true));
    }
  }

  Set<IntentionId> get _observedIntentionIds => {
    _intentionId,
    for (final item in _itemsOfState(state)) ...[
      item.relation.sourceIntentionId,
      item.relation.relatedIntentionId,
    ],
    if (state case DailyChoiceGroupLoaded(:final items))
      for (final item in items) ...[item.source.id, item.selected.id],
  };

  bool _changesAffectObservedState(Iterable<GraphChange> changes) {
    final current = state;
    final items = _itemsOfState(current);
    final loadedRelationIds = {for (final item in items) item.relation.id};
    final loadedDailyChoiceIds = <DailyChoiceId>{
      if (current case DailyChoiceGroupLoaded(:final items))
        for (final item in items) item.id,
    };
    final observedIntentionIds = _observedIntentionIds;
    for (final change in changes) {
      switch (change) {
        case IntentionCatalogMutation(:final before, :final after):
          if (observedIntentionIds.contains(before?.summary.id) ||
              observedIntentionIds.contains(after?.summary.id)) {
            return true;
          }
        case IntentionRelationCountsChanged(:final intentionId, :final counts)
            when intentionId == _intentionId:
          if (current is! RelationGroupConfirmedState ||
              counts != current.counts) {
            return true;
          }
        case DailyChoiceChange(
          :final intentionCounts,
          :final before,
          :final after,
        ):
          final counts = intentionCounts[_intentionId];
          final choiceId = after?.id ?? before?.id;
          final selectedDailyRole = switch (_group) {
            DailyChoiceRelationGroup(:final role) => role,
            LongTermRelationGroup() => null,
          };
          final affectsSelectedRole = switch (selectedDailyRole) {
            DailyChoiceRelationRole.source =>
              before?.sourceIntentionId == _intentionId ||
                  after?.sourceIntentionId == _intentionId,
            DailyChoiceRelationRole.selected =>
              before?.selectedIntentionId == _intentionId ||
                  after?.selectedIntentionId == _intentionId,
            null => false,
          };
          if (affectsSelectedRole ||
              loadedDailyChoiceIds.contains(choiceId) ||
              (counts != null &&
                  (current is! RelationGroupConfirmedState ||
                      counts != current.counts))) {
            return true;
          }
        case LongTermRelationChange(:final id, :final before, :final after):
          if (loadedRelationIds.contains(id) ||
              _relationChangeAffectsSelection(before: before, after: after)) {
            return true;
          }
        case GraphChange():
          break;
      }
    }
    return false;
  }

  bool _relationChangeAffectsSelection({
    required LongTermRelation? before,
    required LongTermRelation? after,
  }) {
    final beforeGroup = _relationGroupForOwner(before);
    final afterGroup = _relationGroupForOwner(after);
    if (beforeGroup != afterGroup) {
      return true;
    }
    return beforeGroup == _selection &&
        before != null &&
        after != null &&
        before.priority != after.priority;
  }

  RelationGroupSelection? _relationGroupForOwner(LongTermRelation? relation) {
    if (relation == null) {
      return null;
    }
    final RelationDirection direction;
    if (relation.sourceIntentionId == _intentionId) {
      direction = RelationDirection.outgoing;
    } else if (relation.relatedIntentionId == _intentionId) {
      direction = RelationDirection.incoming;
    } else {
      return null;
    }
    return RelationGroupSelection(
      type: relation.type,
      direction: direction,
      scope: relation.scope,
    );
  }

  void _requestReconciliation(GraphRevision revision) {
    final current = state;
    if (current is RelationGroupConfirmedState) {
      final order = revision.compareTo(current.revision);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    final required = _paging.requiredRevision;
    if (required != null) {
      final order = revision.compareTo(required);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    _paging.requireRevision(revision);
    if (current is RelationGroupConfirmedState) {
      if ((current is RelationGroupLoaded ||
              current is DailyChoiceGroupLoaded) &&
          current.progress is RelationGroupLoadingMore) {
        // Продолжение прежней ревизии может задержаться или не завершиться.
        // Новую основу читаем сразу, сохраняя предел запрошенной порции.
        _paging.cancelRequest();
        unawaited(_refresh(current, includeRequestedPage: true));
      } else if (!_paging.hasActiveRequest) {
        unawaited(_refresh(current, includeRequestedPage: false));
      }
    }
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
    if (_isTerminated) {
      return;
    }
    _isTerminated = true;
    _paging.nextGeneration();
    state = RelationNeighborhoodIntentionNotFound(
      intentionId: _intentionId,
      selection: _selection,
      group: _group,
    );
    unawaited(_intentionSubscription?.cancel());
    unawaited(_completionSubscription?.cancel());
  }

  bool _dailyItemBelongsToGroup(
    DailyChoiceCatalogItem item,
    DailyChoiceRelationGroup group,
  ) => switch (group.role) {
    DailyChoiceRelationRole.source => item.source.id == _intentionId,
    DailyChoiceRelationRole.selected => item.selected.id == _intentionId,
  };

  bool _belongsToGroup(
    LongTermRelationSummary item,
    LongTermRelationGroup selection,
  ) {
    final relation = item.relation;
    if (relation.type != selection.type || relation.scope != selection.scope) {
      return false;
    }
    return switch (selection.direction) {
      RelationDirection.outgoing => relation.sourceIntentionId == _intentionId,
      RelationDirection.incoming => relation.relatedIntentionId == _intentionId,
    };
  }

  List<LongTermRelationSummary> _itemsOf(
    RelationGroupConfirmedState confirmed,
  ) => switch (confirmed) {
    RelationGroupEmpty() => const [],
    RelationGroupLoaded(:final items) => items,
    DailyChoiceGroupLoaded() => const [],
  };

  List<DailyChoiceCatalogItem> _dailyItemsOf(
    RelationGroupConfirmedState confirmed,
  ) => switch (confirmed) {
    DailyChoiceGroupLoaded(:final items) => items,
    RelationGroupEmpty() || RelationGroupLoaded() => const [],
  };

  RelationGroupCursor? _cursorOf(RelationGroupConfirmedState confirmed) =>
      switch (confirmed) {
        RelationGroupLoaded(:final nextCursor) ||
        DailyChoiceGroupLoaded(:final nextCursor) => nextCursor,
        RelationGroupEmpty() => null,
      };

  List<LongTermRelationSummary> _itemsOfState(
    RelationNeighborhoodState current,
  ) => switch (current) {
    RelationGroupLoaded(:final items) => items,
    DailyChoiceGroupLoaded() => const [],
    RelationGroupInitialLoad() ||
    RelationGroupInitialFailure() ||
    RelationNeighborhoodIntentionNotFound() ||
    RelationGroupEmpty() => const [],
  };

  RelationGroupConfirmedState _withSummaryStatus(
    RelationGroupConfirmedState confirmed,
    RelationSummaryStatus summaryStatus,
  ) => switch (confirmed) {
    final RelationGroupEmpty empty => empty.withSummaryStatus(summaryStatus),
    final RelationGroupLoaded loaded => loaded.withSummaryStatus(summaryStatus),
    final DailyChoiceGroupLoaded loaded => loaded.withSummaryStatus(
      summaryStatus,
    ),
  };

  RelationGroupConfirmedState _withProgress(
    RelationGroupConfirmedState confirmed,
    RelationGroupProgress progress,
  ) => switch (confirmed) {
    final RelationGroupEmpty empty => empty.withProgress(progress),
    final RelationGroupLoaded loaded => loaded.withProgress(progress),
    final DailyChoiceGroupLoaded loaded => loaded.withProgress(progress),
  };

  RelationGroupConfirmedState _withScrollAnchor({
    required RelationGroupConfirmedState previous,
    required RelationGroupConfirmedState replacement,
  }) {
    if (replacement is DailyChoiceGroupLoaded ||
        previous is DailyChoiceGroupLoaded) {
      return replacement;
    }
    final anchor = _paging.chooseAnchor(
      previous: _itemsOf(previous),
      replacement: _itemsOf(replacement),
      visibleId: _visibleRelationId,
      identify: (item) => item.relation.id,
    );
    _visibleRelationId = anchor?.id;
    if (anchor == null) return replacement;
    return switch (replacement) {
      RelationGroupEmpty() => replacement,
      RelationGroupLoaded() => RelationGroupLoaded(
        intentionId: replacement.intentionId,
        selection: replacement.selection,
        group: replacement.group,
        counts: replacement.counts,
        revision: replacement.revision,
        summaryStatus: replacement.summaryStatus,
        items: replacement.items,
        nextCursor: replacement.nextCursor,
        progress: replacement.progress,
        scrollAnchor: RelationGroupScrollAnchor(
          relationId: anchor.id,
          index: anchor.index,
        ),
      ),
      DailyChoiceGroupLoaded() => replacement,
    };
  }

  bool _observationPrecedesKnownRevision(GraphRevision revision) {
    final current = state;
    if (current is RelationGroupConfirmedState &&
        _paging.precedes(revision, current.revision)) {
      return true;
    }
    final required = _paging.requiredRevision;
    return required != null && _paging.precedes(revision, required);
  }

  RelationGroupInitialFailure _initialFailure(
    RelationGroupSelection selection,
    RelationGroup group,
    RelationGroupReadFailure failure,
  ) => RelationGroupInitialFailure(
    intentionId: _intentionId,
    selection: selection,
    group: group,
    failure: failure,
  );

  Future<RelationGroupPageResult> _readPage(
    RelationGroup group, {
    RelationGroupCursor? cursor,
  }) async {
    try {
      return await _repository.getRelationGroupPage(switch (group) {
        LongTermRelationGroup(:final type, :final direction, :final scope) =>
          RelationGroupQuery(
            intentionId: _intentionId,
            type: type,
            direction: direction,
            scope: scope,
            pageSize: _policy.pageSize,
            cursor: cursor,
          ),
        DailyChoiceRelationGroup(:final role) => DailyChoiceGroupQuery(
          intentionId: _intentionId,
          role: role,
          pageSize: _policy.pageSize,
          cursor: cursor,
        ),
      });
    } on Object {
      // Неизвестная причина отказа не выдаётся за отсутствие данных.
      return const GraphResultFailure(RelationGroupUnexpectedFailure());
    }
  }
}
