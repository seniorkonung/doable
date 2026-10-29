import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

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
import '../../../intention/presentation/details/intention_page_target.dart';
import '../../../long_term_relation/application/relation_group_page.dart';
import '../../../long_term_relation/presentation/neighborhood/relation_neighborhood_paging_policy.dart';
import '../../../long_term_relation/presentation/relation_group_paging.dart';
import '../../../tag/application/tag_change.dart';
import '../../application/daily_choice_catalog.dart';
import '../../domain/daily_choice_id.dart';
import 'intention_choices_state.dart';

part 'intention_choices_view_model.g.dart';

/// Порциями получает прямые дневные выборы намерения в роли, сохранённой
/// экземпляром страницы.
///
/// Модель живёт, пока её слушают: освобождение отбрасывает строки,
/// продолжения и подписки, а роль остаётся в экземпляре страницы. Ответ
/// принимается только для текущего поколения запроса.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose
@riverpod
final class IntentionChoicesViewModel extends _$IntentionChoicesViewModel {
  final _paging = RelationGroupPaging();

  late IntentionId _intentionId;
  late IntentionPageInstance _pageInstance;
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
  var _isTerminated = false;

  @override
  IntentionChoicesState build(
    IntentionId intentionId,
    IntentionPageInstance pageInstance,
  ) {
    _intentionId = intentionId;
    _pageInstance = pageInstance;
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
    final role = pageInstance.choicesRole;
    final generation = _paging.nextGeneration();
    unawaited(_loadFirstPage(generation, role));
    return IntentionChoicesInitialLoad(role: role);
  }

  /// Отбрасывает строки прежней роли и запоминает новую в экземпляре.
  void selectRole(DailyChoiceRelationRole role) {
    if (_isTerminated || state.role == role) return;
    _pageInstance.choicesRole = role;
    final generation = _paging.nextGeneration();
    state = IntentionChoicesInitialLoad(role: role);
    unawaited(_loadFirstPage(generation, role));
  }

  /// Повторяет первое чтение роли после устранимого отказа.
  Future<void> retryFirstPage() {
    final current = state;
    if (current is! IntentionChoicesInitialFailure || !current.canRetry) {
      return Future.value();
    }
    final generation = _paging.nextGeneration();
    state = IntentionChoicesInitialLoad(role: current.role);
    return _loadFirstPage(generation, current.role);
  }

  /// Подгружает следующую порцию при приближении к концу загруженной части.
  ///
  /// Пока порция ожидается, повторная прокрутка не отправляет её второй раз.
  Future<void> loadMoreIfNeeded({required int visibleIndex}) {
    final current = state;
    if (current is! IntentionChoicesLoaded ||
        current.nextCursor == null ||
        current.summaryStatus is! IntentionChoicesSummaryCurrent ||
        current.progress is! IntentionChoicesIdle ||
        visibleIndex < 0 ||
        current.items.length - visibleIndex - 1 > _policy.prefetchRemaining) {
      return Future.value();
    }
    return _loadMore(current);
  }

  Future<void> retryLoadMore() {
    final current = state;
    if (current is! IntentionChoicesLoaded ||
        current.summaryStatus is! IntentionChoicesSummaryCurrent) {
      return Future.value();
    }
    final progress = current.progress;
    if (progress is! IntentionChoicesLoadMoreFailure || !progress.canRetry) {
      return Future.value();
    }
    return _loadMore(current);
  }

  Future<void> retryRefresh() {
    final current = state;
    if (current is! IntentionChoicesConfirmed) return Future.value();
    final summaryStatus = current.summaryStatus;
    if (summaryStatus is! IntentionChoicesSummaryRefreshFailure ||
        !summaryStatus.canRetry) {
      return Future.value();
    }
    return _refresh(current, includeRequestedPage: false);
  }

  Future<void> _loadFirstPage(
    int generation,
    DailyChoiceRelationRole role,
  ) async {
    final request = _paging.startRequest(generation);
    final result = await _paging.readFirst(_source(role), request);
    if (!ref.mounted || !_paging.owns(request)) return;
    _paging.finishRequest(request);
    switch (result) {
      case GraphResultSuccess(:final value):
        if (_paging.precedesRequiredRevision(value.revision)) {
          unawaited(_loadFirstPage(generation, role));
          return;
        }
        state = _confirmed(role, value);
      case GraphResultFailure(failure: RelationGroupIntentionNotFoundFailure()):
        _finishIntentionContext();
      case GraphResultFailure(:final failure):
        state = IntentionChoicesInitialFailure(role: role, failure: failure);
      case null:
        break;
    }
  }

  Future<void> _loadMore(IntentionChoicesLoaded confirmed) async {
    if (_paging.hasActiveRequest || confirmed.nextCursor == null) return;
    if (_paging.precedesRequiredRevision(confirmed.revision)) {
      return _refresh(confirmed, includeRequestedPage: true);
    }
    final request = _paging.startRequest(_paging.generation);
    state = confirmed.withProgress(const IntentionChoicesLoadingMore());
    final result = await _paging.loadMore(
      _source(confirmed.role),
      RelationPagingData(
        items: confirmed.items,
        counts: confirmed.counts,
        totalCount: confirmed.totalCount,
        revision: confirmed.revision,
        nextCursor: confirmed.nextCursor,
      ),
      request,
    );
    if (!ref.mounted || !_paging.owns(request)) return;
    _paging.finishRequest(request);
    final current = state;
    if (current is! IntentionChoicesLoaded) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        if (_paging.precedesRequiredRevision(value.revision)) {
          unawaited(_refresh(current, includeRequestedPage: true));
          return;
        }
        state = _confirmed(
          current.role,
          value,
        ).withSummaryStatus(current.summaryStatus);
      case GraphResultFailure(failure: RelationGroupIntentionNotFoundFailure()):
        _finishIntentionContext();
      case GraphResultFailure(:final failure):
        state = current.withProgress(IntentionChoicesLoadMoreFailure(failure));
      case null:
        unawaited(_refresh(current, includeRequestedPage: true));
    }
  }

  /// Прежняя подтверждённая пара остаётся видимой, пока ядро собирает замену.
  Future<void> _refresh(
    IntentionChoicesConfirmed confirmed, {
    required bool includeRequestedPage,
  }) async {
    if (_paging.hasActiveRequest) return;
    final request = _paging.startRequest(_paging.generation);
    final refreshBase = switch (confirmed) {
      final IntentionChoicesLoaded loaded => loaded.withProgress(
        const IntentionChoicesIdle(),
      ),
      IntentionChoicesEmpty() => confirmed,
    };
    state = refreshBase.withSummaryStatus(
      const IntentionChoicesSummaryRefreshing(),
    );
    try {
      while (_paging.owns(request)) {
        final result = await _paging.refresh(
          _source(confirmed.role),
          request,
          loadedCount: confirmed.items.length,
          includeRequestedPage: includeRequestedPage,
        );
        if (!ref.mounted || !_paging.owns(request)) return;
        switch (result) {
          case GraphResultSuccess(:final value):
            if (_paging.precedesRequiredRevision(value.revision)) continue;
            state = _confirmed(confirmed.role, value);
            return;
          case GraphResultFailure(
            failure: RelationGroupIntentionNotFoundFailure(),
          ):
            _finishIntentionContext();
            return;
          case GraphResultFailure(:final failure):
            state = refreshBase.withSummaryStatus(
              IntentionChoicesSummaryRefreshFailure(failure),
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

  IntentionChoicesConfirmed _confirmed(
    DailyChoiceRelationRole role,
    RelationPagingData<DailyChoiceCatalogItem> data,
  ) => data.items.isEmpty
      ? IntentionChoicesEmpty(
          role: role,
          counts: data.counts,
          revision: data.revision,
        )
      : IntentionChoicesLoaded(
          role: role,
          counts: data.counts,
          revision: data.revision,
          items: data.items,
          nextCursor: data.nextCursor,
        );

  RelationPagingSource<DailyChoiceCatalogItem, DailyChoiceId> _source(
    DailyChoiceRelationRole role,
  ) => RelationPagingSource(
    pageSize: _policy.pageSize,
    identify: (item) => _belongsToRole(item, role) ? item.id : null,
    readPage: (cursor) async => switch (await _readPage(role, cursor)) {
      GraphResultSuccess(value: final DailyChoiceGroupFirstPage page) =>
        GraphResultSuccess(
          RelationPagingFirstPage(
            items: page.items,
            counts: page.counts,
            totalCount: page.counts.forSelection(
              DailyChoiceRelationGroup(role: role),
            ),
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

  bool _belongsToRole(
    DailyChoiceCatalogItem item,
    DailyChoiceRelationRole role,
  ) => switch (role) {
    DailyChoiceRelationRole.source => item.source.id == _intentionId,
    DailyChoiceRelationRole.selected => item.selected.id == _intentionId,
  };

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
    if (!ref.mounted || _isTerminated) return;
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
        final current = state;
        state = switch (current) {
          IntentionChoicesConfirmed() => current.withSummaryStatus(
            IntentionChoicesSummaryRefreshFailure(mapped),
          ),
          IntentionChoicesInitialLoad() || IntentionChoicesInitialFailure() =>
            IntentionChoicesInitialFailure(role: current.role, failure: mapped),
          IntentionChoicesIntentionNotFound() => current,
        };
    }
  }

  void _handleCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted || _isTerminated) return;
    final confirmedChange = completion.confirmedChange;
    if (confirmedChange == null) return;
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
      _noteUnrelatedRevision(confirmedChange.revision);
    }
  }

  bool _changesAffectObservedState(Iterable<GraphChange> changes) {
    final current = state;
    final items = switch (current) {
      IntentionChoicesConfirmed(:final items) => items,
      IntentionChoicesInitialLoad() ||
      IntentionChoicesInitialFailure() ||
      IntentionChoicesIntentionNotFound() => const <DailyChoiceCatalogItem>[],
    };
    final loadedChoiceIds = {for (final item in items) item.id};
    final observedIntentionIds = {
      _intentionId,
      for (final item in items) ...[item.source.id, item.selected.id],
    };
    for (final change in changes) {
      switch (change) {
        case IntentionCatalogMutation(:final before, :final after):
          if (observedIntentionIds.contains(before?.summary.id) ||
              observedIntentionIds.contains(after?.summary.id)) {
            return true;
          }
        case IntentionRelationCountsChanged(:final intentionId, :final counts)
            when intentionId == _intentionId:
          if (current is! IntentionChoicesConfirmed ||
              counts != current.counts) {
            return true;
          }
        case DailyChoiceChange(
          :final intentionCounts,
          :final before,
          :final after,
        ):
          final counts = intentionCounts[_intentionId];
          final affectsRole = switch (current.role) {
            DailyChoiceRelationRole.source =>
              before?.sourceIntentionId == _intentionId ||
                  after?.sourceIntentionId == _intentionId,
            DailyChoiceRelationRole.selected =>
              before?.selectedIntentionId == _intentionId ||
                  after?.selectedIntentionId == _intentionId,
          };
          if (affectsRole ||
              loadedChoiceIds.contains(after?.id ?? before?.id) ||
              (counts != null &&
                  (current is! IntentionChoicesConfirmed ||
                      counts != current.counts))) {
            return true;
          }
        case GraphChange():
          break;
      }
    }
    return false;
  }

  /// Чужая ревизия не меняет строк, но делает непригодным продолжение
  /// прежнего снимка.
  void _noteUnrelatedRevision(GraphRevision revision) {
    if (!_isNewerThanKnown(revision)) return;
    _paging.requireRevision(revision);
    final current = state;
    if (current is IntentionChoicesLoaded &&
        current.progress is IntentionChoicesLoadingMore) {
      _paging.cancelRequest();
      unawaited(_refresh(current, includeRequestedPage: true));
    }
  }

  void _requestReconciliation(GraphRevision revision) {
    if (!_isNewerThanKnown(revision)) return;
    _paging.requireRevision(revision);
    final current = state;
    if (current is IntentionChoicesLoaded &&
        current.progress is IntentionChoicesLoadingMore) {
      // Продолжение прежней ревизии может задержаться или не завершиться.
      // Новую основу читаем сразу, сохраняя предел запрошенной порции.
      _paging.cancelRequest();
      unawaited(_refresh(current, includeRequestedPage: true));
    } else if (current is IntentionChoicesConfirmed &&
        !_paging.hasActiveRequest) {
      unawaited(_refresh(current, includeRequestedPage: false));
    }
  }

  /// Ревизия новее опубликованной пары и уже затребованной основы.
  bool _isNewerThanKnown(GraphRevision revision) {
    bool isNotNewer(GraphRevision known) => switch (revision.compareTo(known)) {
      GraphRevisionOrder.older || GraphRevisionOrder.same => true,
      GraphRevisionOrder.newer || GraphRevisionOrder.differentEpoch => false,
    };
    final current = state;
    if (current is IntentionChoicesConfirmed && isNotNewer(current.revision)) {
      return false;
    }
    final required = _paging.requiredRevision;
    return required == null || !isNotNewer(required);
  }

  bool _observationPrecedesKnownRevision(GraphRevision revision) {
    final current = state;
    if (current is IntentionChoicesConfirmed &&
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
    state = IntentionChoicesIntentionNotFound(role: state.role);
    unawaited(_intentionSubscription?.cancel());
    unawaited(_completionSubscription?.cancel());
  }

  Future<RelationGroupPageResult> _readPage(
    DailyChoiceRelationRole role,
    RelationGroupCursor? cursor,
  ) async {
    try {
      return await _repository.getRelationGroupPage(
        DailyChoiceGroupQuery(
          intentionId: _intentionId,
          role: role,
          pageSize: _policy.pageSize,
          cursor: cursor,
        ),
      );
    } on Object {
      // Неизвестная причина отказа не выдаётся за отсутствие данных.
      return const GraphResultFailure(RelationGroupUnexpectedFailure());
    }
  }
}
