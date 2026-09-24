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
import '../../application/long_term_relation_projection.dart';
import '../../application/relation_group_page.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_id.dart';
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
  /// Непрерывно меняющийся граф не удерживает список в обновлении навсегда.
  static const _maxRefreshAttempts = 8;

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
  var _generation = 0;
  var _invalidation = 0;
  Object? _activeRequest;
  GraphRevision? _requiredRevision;
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
      unawaited(_intentionSubscription?.cancel());
      unawaited(_completionSubscription?.cancel());
    });
    final generation = _nextGeneration();
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

  /// Открывает актуальный просмотр связей, блокирующих удаление намерения.
  ///
  /// Полная сводка десяти групп и первая порция читаются заново. Переход
  /// начинает с первой непустой долговременной группы; незагруженные связи
  /// всех групп остаются учтёнными в полной сводке.
  void showBlockingRelations() => _restart(_firstNonEmptyGroup());

  /// Открывает архив связей намерения, сохранённый после каскада.
  ///
  /// Архивные связи остаются архивированными сами по себе, поэтому просмотр
  /// начинается с первой непустой архивной группы.
  void showArchivedRelations() =>
      _restart(_firstNonEmptyGroup(scope: RelationScope.archived));

  /// Повторяет первое чтение выбранной группы после устранимого отказа.
  Future<void> retryFirstPage() {
    final current = state;
    if (current is! RelationGroupInitialFailure || !current.canRetry) {
      return Future.value();
    }
    final generation = _nextGeneration();
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
  /// Пока сводка не подтверждена, выбор остаётся прежним: пустая группа не
  /// объявляет остальные группы пустыми.
  RelationGroupSelection _firstNonEmptyGroup({RelationScope? scope}) {
    final fallback = scope == null ? _selection : _selection.withScope(scope);
    final current = state;
    if (current is! RelationGroupConfirmedState) {
      return fallback;
    }
    final counts = current.counts;
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
    final generation = _nextGeneration();
    state = RelationGroupInitialLoad(
      intentionId: _intentionId,
      selection: _selection,
      group: group,
    );
    unawaited(_loadFirstPage(generation));
  }

  Future<void> _loadFirstPage(int generation) async {
    final request = Object();
    _activeRequest = request;
    final selection = _selection;
    final group = _group;

    final result = await _readPage(group);
    if (!_owns(request, generation)) {
      return;
    }
    _activeRequest = null;
    switch (result) {
      case GraphResultSuccess(:final value):
        if (_pagePrecedesRequiredRevision(value.revision)) {
          unawaited(_loadFirstPage(generation));
          return;
        }
        state = _stateFromFirstPage(group, value);
      case GraphResultFailure(failure: RelationGroupIntentionNotFoundFailure()):
        _finishIntentionContext();
      // Первая порция запрашивается без продолжения: устаревший снимок здесь
      // не является ответом на заданный вопрос.
      case GraphResultFailure(failure: RelationGroupSnapshotExpired()):
        state = _initialFailure(
          selection,
          group,
          const RelationGroupUnexpectedFailure(),
        );
      case GraphResultFailure(:final failure):
        state = _initialFailure(selection, group, failure);
    }
  }

  Future<void> _loadMore(RelationGroupConfirmedState confirmed) async {
    final cursor = _cursorOf(confirmed);
    if (_activeRequest != null || cursor == null) {
      return;
    }
    final request = Object();
    final generation = _generation;
    final invalidation = _invalidation;
    _activeRequest = request;
    state = _withProgress(confirmed, const RelationGroupLoadingMore());

    final result = await _readPage(confirmed.group, cursor: cursor);
    if (!_owns(request, generation)) {
      return;
    }
    _activeRequest = null;
    if (invalidation != _invalidation) {
      unawaited(_refresh(confirmed, includeRequestedPage: true));
      return;
    }
    final current = state;
    if (current is! RelationGroupLoaded && current is! DailyChoiceGroupLoaded) {
      return;
    }

    switch (result) {
      case GraphResultSuccess(:final value):
        final appended = _appendContinuation(
          current as RelationGroupConfirmedState,
          value,
        );
        if (appended == null) {
          unawaited(_refresh(current, includeRequestedPage: true));
          return;
        }
        state = appended;
      // Продолжение относится к недоступному снимку: нужна новая основа.
      case GraphResultFailure(failure: RelationGroupSnapshotExpired()):
        unawaited(
          _refresh(
            current as RelationGroupConfirmedState,
            includeRequestedPage: true,
          ),
        );
      case GraphResultFailure(failure: RelationGroupIntentionNotFoundFailure()):
        _finishIntentionContext();
      case GraphResultFailure(:final failure):
        state = _withProgress(
          current as RelationGroupConfirmedState,
          RelationGroupLoadMoreFailure(failure),
        );
    }
  }

  /// Получает новую основу вместо непригодного продолжения.
  ///
  /// Прежняя подтверждённая часть группы и её количества остаются доступными
  /// с состоянием обновления до атомарной публикации согласованной замены.
  Future<void> _refresh(
    RelationGroupConfirmedState confirmed, {
    required bool includeRequestedPage,
  }) async {
    if (_activeRequest != null) {
      return;
    }
    final request = Object();
    final generation = _generation;
    final refreshBase = _withProgress(confirmed, const RelationGroupIdle());
    _activeRequest = request;
    state = _withSummaryStatus(refreshBase, const RelationSummaryRefreshing());

    try {
      for (var attempt = 0; attempt < _maxRefreshAttempts; attempt += 1) {
        final invalidation = _invalidation;
        final assembly = await _assembleGroup(
          refreshBase,
          request,
          generation,
          invalidation,
          includeRequestedPage: includeRequestedPage,
        );
        if (!_owns(request, generation)) {
          return;
        }
        switch (assembly) {
          case _AssembledGroup(:final replacement):
            if (invalidation != _invalidation) {
              continue;
            }
            state = _withScrollAnchor(
              previous: refreshBase,
              replacement: replacement,
            );
            return;
          case _AssemblyFailed(:final failure):
            if (failure is RelationGroupIntentionNotFoundFailure) {
              _finishIntentionContext();
              return;
            }
            state = _withSummaryStatus(
              refreshBase,
              RelationSummaryRefreshFailure(failure),
            );
            return;
          case _AssemblyInterrupted():
            continue;
        }
      }
      state = _withSummaryStatus(
        refreshBase,
        const RelationSummaryRefreshFailure(RelationGroupUnavailableFailure()),
      );
    } finally {
      if (identical(_activeRequest, request)) {
        _activeRequest = null;
      }
    }
  }

  /// Собирает замену с первой порции на одной ревизии.
  ///
  /// Предел сборки — прежняя загруженная часть и одна запрошенная порция:
  /// незагруженный остаток группы и другие группы не читаются.
  Future<_GroupAssembly> _assembleGroup(
    RelationGroupConfirmedState confirmed,
    Object request,
    int generation,
    int invalidation, {
    required bool includeRequestedPage,
  }) async {
    if (confirmed.group case final DailyChoiceRelationGroup dailyGroup) {
      return _assembleDailyGroup(
        confirmed,
        dailyGroup,
        request,
        generation,
        invalidation,
        includeRequestedPage: includeRequestedPage,
      );
    }
    final selection = confirmed.selection;
    final limit =
        _itemsOf(confirmed).length +
        (includeRequestedPage ? _policy.pageSize : 0);

    final firstResult = await _readPage(confirmed.group);
    if (!_assemblyIsCurrent(request, generation, invalidation)) {
      return const _AssemblyInterrupted();
    }
    final RelationGroupFirstPage firstPage;
    switch (firstResult) {
      case GraphResultSuccess(value: final RelationGroupFirstPage page):
        firstPage = page;
      case GraphResultSuccess():
        return const _AssemblyFailed(RelationGroupUnexpectedFailure());
      case GraphResultFailure(failure: RelationGroupSnapshotExpired()):
        return const _AssemblyFailed(RelationGroupUnexpectedFailure());
      case GraphResultFailure(:final failure):
        return _AssemblyFailed(failure);
    }

    final counts = firstPage.counts;
    final revision = firstPage.revision;
    if (_pagePrecedesRequiredRevision(revision)) {
      return const _AssemblyInterrupted();
    }
    final totalCount = counts.forSelection(confirmed.group);
    final firstItems = _combine(const [], firstPage.items, selection);
    var cursor = firstPage.nextCursor;
    if (firstItems == null ||
        !_hasConsistentTotal(firstItems.length, cursor, totalCount)) {
      return const _AssemblyFailed(RelationGroupUnexpectedFailure());
    }
    var items = firstItems;

    while (cursor != null && items.length < limit) {
      final result = await _readPage(confirmed.group, cursor: cursor);
      if (!_assemblyIsCurrent(request, generation, invalidation)) {
        return const _AssemblyInterrupted();
      }
      switch (result) {
        case GraphResultSuccess(
          value: final RelationGroupContinuationPage page,
        ):
          if (page.revision.compareTo(revision) != GraphRevisionOrder.same) {
            return const _AssemblyInterrupted();
          }
          final combined = _combine(items, page.items, selection);
          cursor = page.nextCursor;
          if (combined == null ||
              !_hasConsistentTotal(combined.length, cursor, totalCount)) {
            return const _AssemblyFailed(RelationGroupUnexpectedFailure());
          }
          items = combined;
        case GraphResultSuccess():
          return const _AssemblyFailed(RelationGroupUnexpectedFailure());
        case GraphResultFailure(failure: RelationGroupSnapshotExpired()):
          return const _AssemblyInterrupted();
        case GraphResultFailure(:final failure):
          return _AssemblyFailed(failure);
      }
    }

    if (items.isEmpty) {
      return _AssembledGroup(
        RelationGroupEmpty(
          intentionId: _intentionId,
          selection: selection,
          group: confirmed.group,
          counts: counts,
          revision: revision,
        ),
      );
    }
    return _AssembledGroup(
      RelationGroupLoaded(
        intentionId: _intentionId,
        selection: selection,
        group: confirmed.group,
        counts: counts,
        revision: revision,
        items: items,
        nextCursor: cursor,
      ),
    );
  }

  Future<_GroupAssembly> _assembleDailyGroup(
    RelationGroupConfirmedState confirmed,
    DailyChoiceRelationGroup group,
    Object request,
    int generation,
    int invalidation, {
    required bool includeRequestedPage,
  }) async {
    final limit =
        _dailyItemsOf(confirmed).length +
        (includeRequestedPage ? _policy.pageSize : 0);
    final firstResult = await _readPage(group);
    if (!_assemblyIsCurrent(request, generation, invalidation)) {
      return const _AssemblyInterrupted();
    }
    final DailyChoiceGroupFirstPage firstPage;
    switch (firstResult) {
      case GraphResultSuccess(value: final DailyChoiceGroupFirstPage page):
        firstPage = page;
      case GraphResultSuccess() ||
          GraphResultFailure(failure: RelationGroupSnapshotExpired()):
        return const _AssemblyFailed(RelationGroupUnexpectedFailure());
      case GraphResultFailure(:final failure):
        return _AssemblyFailed(failure);
    }
    final counts = firstPage.counts;
    final revision = firstPage.revision;
    if (_pagePrecedesRequiredRevision(revision)) {
      return const _AssemblyInterrupted();
    }
    final totalCount = counts.forSelection(group);
    final firstItems = _combineDaily(const [], firstPage.items, group);
    var cursor = firstPage.nextCursor;
    if (firstItems == null ||
        !_hasConsistentTotal(firstItems.length, cursor, totalCount)) {
      return const _AssemblyFailed(RelationGroupUnexpectedFailure());
    }
    var items = firstItems;
    while (cursor != null && items.length < limit) {
      final result = await _readPage(group, cursor: cursor);
      if (!_assemblyIsCurrent(request, generation, invalidation)) {
        return const _AssemblyInterrupted();
      }
      switch (result) {
        case GraphResultSuccess(
          value: final DailyChoiceGroupContinuationPage page,
        ):
          if (page.revision.compareTo(revision) != GraphRevisionOrder.same) {
            return const _AssemblyInterrupted();
          }
          final combined = _combineDaily(items, page.items, group);
          cursor = page.nextCursor;
          if (combined == null ||
              !_hasConsistentTotal(combined.length, cursor, totalCount)) {
            return const _AssemblyFailed(RelationGroupUnexpectedFailure());
          }
          items = combined;
        case GraphResultSuccess():
          return const _AssemblyFailed(RelationGroupUnexpectedFailure());
        case GraphResultFailure(failure: RelationGroupSnapshotExpired()):
          return const _AssemblyInterrupted();
        case GraphResultFailure(:final failure):
          return _AssemblyFailed(failure);
      }
    }
    if (items.isEmpty) {
      return _AssembledGroup(
        RelationGroupEmpty(
          intentionId: _intentionId,
          selection: confirmed.selection,
          group: group,
          counts: counts,
          revision: revision,
        ),
      );
    }
    return _AssembledGroup(
      DailyChoiceGroupLoaded(
        intentionId: _intentionId,
        selection: confirmed.selection,
        group: group,
        counts: counts,
        revision: revision,
        items: items,
        nextCursor: cursor,
      ),
    );
  }

  /// Присоединяет порцию продолжения к подтверждённой части группы.
  ///
  /// `null` означает порцию несовместимого состояния графа: её строки не
  /// смешиваются с загруженной частью, а список получает новую основу.
  RelationGroupConfirmedState? _appendContinuation(
    RelationGroupConfirmedState confirmed,
    RelationGroupPage page,
  ) {
    if (confirmed is DailyChoiceGroupLoaded) {
      if (page is! DailyChoiceGroupContinuationPage) {
        return confirmed.withProgress(
          const RelationGroupLoadMoreFailure(RelationGroupUnexpectedFailure()),
        );
      }
      if (page.revision.compareTo(confirmed.revision) !=
          GraphRevisionOrder.same) {
        return null;
      }
      final combined = _combineDaily(
        confirmed.items,
        page.items,
        confirmed.group as DailyChoiceRelationGroup,
      );
      if (combined == null ||
          !_hasConsistentTotal(
            combined.length,
            page.nextCursor,
            confirmed.totalCount,
          )) {
        return confirmed.withProgress(
          const RelationGroupLoadMoreFailure(RelationGroupUnexpectedFailure()),
        );
      }
      return DailyChoiceGroupLoaded(
        intentionId: confirmed.intentionId,
        selection: confirmed.selection,
        group: confirmed.group as DailyChoiceRelationGroup,
        counts: confirmed.counts,
        revision: confirmed.revision,
        summaryStatus: confirmed.summaryStatus,
        items: combined,
        nextCursor: page.nextCursor,
      );
    }
    if (confirmed is! RelationGroupLoaded) {
      return null;
    }
    if (page is! RelationGroupContinuationPage) {
      return confirmed.withProgress(
        const RelationGroupLoadMoreFailure(RelationGroupUnexpectedFailure()),
      );
    }
    if (page.revision.compareTo(confirmed.revision) !=
        GraphRevisionOrder.same) {
      return null;
    }

    final combined = _combine(confirmed.items, page.items, confirmed.selection);
    if (combined == null ||
        !_hasConsistentTotal(
          combined.length,
          page.nextCursor,
          confirmed.totalCount,
        )) {
      return confirmed.withProgress(
        const RelationGroupLoadMoreFailure(RelationGroupUnexpectedFailure()),
      );
    }
    return RelationGroupLoaded(
      intentionId: confirmed.intentionId,
      selection: confirmed.selection,
      group: confirmed.group,
      counts: confirmed.counts,
      revision: confirmed.revision,
      summaryStatus: confirmed.summaryStatus,
      items: combined,
      nextCursor: page.nextCursor,
      scrollAnchor: confirmed.scrollAnchor,
    );
  }

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
        _requiredRevision = revision;
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
      _requiredRevision = confirmedChange.revision;
      _finishIntentionContext();
      return;
    }
    if (_changesAffectObservedState(confirmedChange.changes)) {
      _requestReconciliation(confirmedChange.revision);
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
    final activeCounts = <IntentionId, int>{
      if (current case RelationGroupConfirmedState(:final counts))
        _intentionId: counts.active,
      for (final item in items) ...{
        item.source.id: item.source.activeRelationCount,
        item.related.id: item.related.activeRelationCount,
      },
    };
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
        case IntentionRelationCountsChanged(:final intentionId, :final counts):
          if (intentionId == _intentionId) {
            if (current is! RelationGroupConfirmedState ||
                counts != current.counts) {
              return true;
            }
          } else if (activeCounts[intentionId] case final int activeCount) {
            if (activeCount != counts.active) {
              return true;
            }
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
              _relationChangeAffectsSelection(before: before, after: after) ||
              _relationChangeAffectsParticipantCounts(
                before: before,
                after: after,
                observedIntentionIds: activeCounts.keys,
              )) {
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

  bool _relationChangeAffectsParticipantCounts({
    required LongTermRelation? before,
    required LongTermRelation? after,
    required Iterable<IntentionId> observedIntentionIds,
  }) {
    final beforeParticipants = _activeParticipants(before);
    final afterParticipants = _activeParticipants(after);
    for (final intentionId in observedIntentionIds) {
      if (beforeParticipants.contains(intentionId) !=
          afterParticipants.contains(intentionId)) {
        return true;
      }
    }
    return false;
  }

  Set<IntentionId> _activeParticipants(LongTermRelation? relation) =>
      relation == null || relation.scope != RelationScope.active
      ? const {}
      : {relation.sourceIntentionId, relation.relatedIntentionId};

  void _requestReconciliation(GraphRevision revision) {
    final current = state;
    if (current is RelationGroupConfirmedState) {
      final order = revision.compareTo(current.revision);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    final required = _requiredRevision;
    if (required != null) {
      final order = revision.compareTo(required);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    _requiredRevision = revision;
    _invalidation += 1;
    if (current is RelationGroupConfirmedState) {
      if ((current is RelationGroupLoaded ||
              current is DailyChoiceGroupLoaded) &&
          current.progress is RelationGroupLoadingMore) {
        // Продолжение прежней ревизии может задержаться или не завершиться.
        // Новую основу читаем сразу, сохраняя предел запрошенной порции.
        _activeRequest = null;
        unawaited(_refresh(current, includeRequestedPage: true));
      } else if (_activeRequest == null) {
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
    _nextGeneration();
    state = RelationNeighborhoodIntentionNotFound(
      intentionId: _intentionId,
      selection: _selection,
      group: _group,
    );
    unawaited(_intentionSubscription?.cancel());
    unawaited(_completionSubscription?.cancel());
  }

  RelationNeighborhoodState _stateFromFirstPage(
    RelationGroup group,
    RelationGroupPage page,
  ) {
    final selection = _selection;
    if (group case final DailyChoiceRelationGroup dailyGroup) {
      if (page is! DailyChoiceGroupFirstPage) {
        return _initialFailure(
          selection,
          group,
          const RelationGroupUnexpectedFailure(),
        );
      }
      final items = _combineDaily(const [], page.items, dailyGroup);
      if (items == null ||
          !_hasConsistentTotal(
            items.length,
            page.nextCursor,
            page.counts.forSelection(group),
          )) {
        return _initialFailure(
          selection,
          group,
          const RelationGroupUnexpectedFailure(),
        );
      }
      if (items.isEmpty) {
        return RelationGroupEmpty(
          intentionId: _intentionId,
          selection: selection,
          group: group,
          counts: page.counts,
          revision: page.revision,
        );
      }
      return DailyChoiceGroupLoaded(
        intentionId: _intentionId,
        selection: selection,
        group: dailyGroup,
        counts: page.counts,
        revision: page.revision,
        items: items,
        nextCursor: page.nextCursor,
      );
    }
    if (page is! RelationGroupFirstPage) {
      return _initialFailure(
        selection,
        group,
        const RelationGroupUnexpectedFailure(),
      );
    }
    final totalCount = page.counts.forSelection(group);
    final items = _combine(const [], page.items, selection);
    if (items == null ||
        !_hasConsistentTotal(items.length, page.nextCursor, totalCount)) {
      return _initialFailure(
        selection,
        group,
        const RelationGroupUnexpectedFailure(),
      );
    }
    if (items.isEmpty) {
      return RelationGroupEmpty(
        intentionId: _intentionId,
        selection: selection,
        group: group,
        counts: page.counts,
        revision: page.revision,
      );
    }
    return RelationGroupLoaded(
      intentionId: _intentionId,
      selection: selection,
      group: group,
      counts: page.counts,
      revision: page.revision,
      items: items,
      nextCursor: page.nextCursor,
    );
  }

  /// Проверяет строки порции и присоединяет их без повторов.
  ///
  /// `null` означает строку вне выбранной группы или порцию сверх
  /// запрошенного размера: частичный успех такой порции не публикуется.
  List<LongTermRelationSummary>? _combine(
    List<LongTermRelationSummary> loaded,
    List<LongTermRelationSummary> page,
    RelationGroupSelection selection,
  ) {
    if (page.length > _policy.pageSize) {
      return null;
    }
    final knownIds = <LongTermRelationId>{
      for (final item in loaded) item.relation.id,
    };
    final combined = [...loaded];
    for (final item in page) {
      if (!_belongsToGroup(item, selection)) {
        return null;
      }
      if (knownIds.add(item.relation.id)) {
        combined.add(item);
      }
    }
    return combined;
  }

  List<DailyChoiceCatalogItem>? _combineDaily(
    List<DailyChoiceCatalogItem> loaded,
    List<DailyChoiceCatalogItem> page,
    DailyChoiceRelationGroup group,
  ) {
    if (page.length > _policy.pageSize) return null;
    final knownIds = <DailyChoiceId>{for (final item in loaded) item.id};
    final combined = [...loaded];
    for (final item in page) {
      final owner = switch (group.role) {
        DailyChoiceRelationRole.source => item.source.id,
        DailyChoiceRelationRole.selected => item.selected.id,
      };
      if (owner != _intentionId) return null;
      if (knownIds.add(item.id)) combined.add(item);
    }
    return combined;
  }

  bool _belongsToGroup(
    LongTermRelationSummary item,
    RelationGroupSelection selection,
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

  /// Проверяет полноту выдачи: конец списка объявляет только полная группа.
  bool _hasConsistentTotal(
    int loadedCount,
    RelationGroupCursor? nextCursor,
    int totalCount,
  ) =>
      nextCursor == null ? loadedCount == totalCount : loadedCount < totalCount;

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
    final visibleId = _visibleRelationId;
    final previousItems = _itemsOf(previous);
    final replacementItems = _itemsOf(replacement);
    if (visibleId == null ||
        previousItems.isEmpty ||
        replacementItems.isEmpty) {
      _visibleRelationId = null;
      return replacement;
    }

    final previousIndex = previousItems.indexWhere(
      (item) => item.relation.id == visibleId,
    );
    if (previousIndex < 0) {
      _visibleRelationId = null;
      return replacement;
    }
    final replacementIndexes = <LongTermRelationId, int>{
      for (var index = 0; index < replacementItems.length; index += 1)
        replacementItems[index].relation.id: index,
    };
    var targetId = visibleId;
    var targetIndex = replacementIndexes[visibleId];
    for (
      var distance = 1;
      targetIndex == null && distance < previousItems.length;
      distance += 1
    ) {
      final after = previousIndex + distance;
      final before = previousIndex - distance;
      if (after < previousItems.length) {
        final candidate = previousItems[after].relation.id;
        final candidateIndex = replacementIndexes[candidate];
        if (candidateIndex != null) {
          targetId = candidate;
          targetIndex = candidateIndex;
          break;
        }
      }
      if (before >= 0) {
        final candidate = previousItems[before].relation.id;
        final candidateIndex = replacementIndexes[candidate];
        if (candidateIndex != null) {
          targetId = candidate;
          targetIndex = candidateIndex;
        }
      }
    }
    if (targetIndex == null) {
      targetIndex = previousIndex.clamp(0, replacementItems.length - 1);
      targetId = replacementItems[targetIndex].relation.id;
    }
    final anchor = RelationGroupScrollAnchor(
      relationId: targetId,
      index: targetIndex,
    );
    _visibleRelationId = targetId;
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
        scrollAnchor: anchor,
      ),
      DailyChoiceGroupLoaded() => replacement,
    };
  }

  bool _assemblyIsCurrent(Object request, int generation, int invalidation) =>
      _owns(request, generation) && invalidation == _invalidation;

  bool _pagePrecedesRequiredRevision(GraphRevision revision) {
    final required = _requiredRevision;
    return required != null && _precedes(revision, required);
  }

  bool _observationPrecedesKnownRevision(GraphRevision revision) {
    final current = state;
    if (current is RelationGroupConfirmedState &&
        _precedes(revision, current.revision)) {
      return true;
    }
    final required = _requiredRevision;
    return required != null && _precedes(revision, required);
  }

  bool _precedes(GraphRevision revision, GraphRevision known) =>
      switch (revision.compareTo(known)) {
        GraphRevisionOrder.older || GraphRevisionOrder.differentEpoch => true,
        GraphRevisionOrder.same || GraphRevisionOrder.newer => false,
      };

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

  bool _owns(Object request, int generation) =>
      ref.mounted &&
      _generation == generation &&
      identical(_activeRequest, request);

  int _nextGeneration() {
    _generation += 1;
    _activeRequest = null;
    return _generation;
  }
}

/// Результат сборки новой основы выбранной группы.
sealed class _GroupAssembly {
  const _GroupAssembly();
}

/// Согласованная замена собрана целиком и готова к публикации.
final class _AssembledGroup extends _GroupAssembly {
  const _AssembledGroup(this.replacement);

  final RelationGroupConfirmedState replacement;
}

/// Граф изменился во время сборки: нужна новая попытка с первой порции.
final class _AssemblyInterrupted extends _GroupAssembly {
  const _AssemblyInterrupted();
}

/// Сборка остановлена отказом чтения: прежняя пара остаётся подтверждённой.
final class _AssemblyFailed extends _GroupAssembly {
  const _AssemblyFailed(this.failure);

  final RelationGroupReadFailure failure;
}
