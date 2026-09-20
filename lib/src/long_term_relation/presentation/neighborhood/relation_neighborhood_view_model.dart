import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
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
  late RelationNeighborhoodPagingPolicy _policy;
  var _selection = RelationGroupSelection.initial;
  var _generation = 0;
  Object? _activeRequest;

  @override
  RelationNeighborhoodState build(IntentionId intentionId) {
    _intentionId = intentionId;
    _repository = ref.watch(personalGraphRepositoryProvider);
    _policy = ref.watch(relationNeighborhoodPagingPolicyProvider);
    final generation = _nextGeneration();
    unawaited(_loadFirstPage(generation));
    return RelationGroupInitialLoad(
      intentionId: intentionId,
      selection: _selection,
    );
  }

  void selectType(LongTermRelationType type) {
    if (_selection.type == type) {
      return;
    }
    _restart(_selection.withType(type));
  }

  void selectDirection(RelationDirection direction) {
    if (_selection.direction == direction) {
      return;
    }
    _restart(_selection.withDirection(direction));
  }

  void selectScope(RelationScope scope) {
    if (_selection.scope == scope) {
      return;
    }
    _restart(_selection.withScope(scope));
  }

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
    );
    return _loadFirstPage(generation);
  }

  /// Подгружает следующую порцию при приближении к концу загруженной части.
  ///
  /// Пока порция ожидается, повторная прокрутка не отправляет её второй раз.
  Future<void> loadMoreIfNeeded({required int visibleIndex}) {
    final current = state;
    if (current is! RelationGroupLoaded ||
        current.nextCursor == null ||
        current.progress is! RelationGroupIdle ||
        visibleIndex < 0 ||
        current.items.length - visibleIndex - 1 > _policy.prefetchRemaining) {
      return Future.value();
    }
    return _loadMore(current);
  }

  Future<void> retryLoadMore() {
    final current = state;
    if (current is! RelationGroupLoaded) {
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
    if (current is! RelationGroupLoaded) {
      return Future.value();
    }
    final progress = current.progress;
    if (progress is! RelationGroupRefreshFailure || !progress.canRetry) {
      return Future.value();
    }
    return _refresh(current);
  }

  void _restart(RelationGroupSelection selection) {
    _selection = selection;
    final generation = _nextGeneration();
    state = RelationGroupInitialLoad(
      intentionId: _intentionId,
      selection: selection,
    );
    unawaited(_loadFirstPage(generation));
  }

  Future<void> _loadFirstPage(int generation) async {
    final request = Object();
    _activeRequest = request;
    final selection = _selection;

    final result = await _readPage(selection);
    if (!_owns(request, generation)) {
      return;
    }
    _activeRequest = null;
    state = switch (result) {
      GraphResultSuccess(:final value) => _stateFromFirstPage(selection, value),
      // Первая порция запрашивается без продолжения: устаревший снимок здесь
      // не является ответом на заданный вопрос.
      GraphResultFailure(failure: RelationGroupSnapshotExpired()) =>
        _initialFailure(selection, const RelationGroupUnexpectedFailure()),
      GraphResultFailure(:final failure) => _initialFailure(selection, failure),
    };
  }

  Future<void> _loadMore(RelationGroupLoaded confirmed) async {
    final cursor = confirmed.nextCursor;
    if (_activeRequest != null || cursor == null) {
      return;
    }
    final request = Object();
    final generation = _generation;
    _activeRequest = request;
    state = confirmed.withProgress(const RelationGroupLoadingMore());

    final result = await _readPage(confirmed.selection, cursor: cursor);
    if (!_owns(request, generation)) {
      return;
    }
    _activeRequest = null;
    final current = state;
    if (current is! RelationGroupLoaded) {
      return;
    }

    switch (result) {
      case GraphResultSuccess(:final value):
        final appended = _appendContinuation(current, value);
        if (appended == null) {
          unawaited(_refresh(current));
          return;
        }
        state = appended;
      // Продолжение относится к недоступному снимку: нужна новая основа.
      case GraphResultFailure(failure: RelationGroupSnapshotExpired()):
        unawaited(_refresh(current));
      case GraphResultFailure(:final failure):
        state = current.withProgress(RelationGroupLoadMoreFailure(failure));
    }
  }

  /// Получает новую основу вместо непригодного продолжения.
  ///
  /// Прежняя подтверждённая часть группы и её количества остаются доступными
  /// с состоянием обновления до атомарной публикации согласованной замены.
  Future<void> _refresh(RelationGroupLoaded confirmed) async {
    if (_activeRequest != null) {
      return;
    }
    final request = Object();
    final generation = _generation;
    _activeRequest = request;
    state = confirmed.withProgress(const RelationGroupRefreshing());

    try {
      for (var attempt = 0; attempt < _maxRefreshAttempts; attempt += 1) {
        final assembly = await _assembleGroup(confirmed, request, generation);
        if (!_owns(request, generation)) {
          return;
        }
        switch (assembly) {
          case _AssembledGroup(:final replacement):
            state = replacement;
            return;
          case _AssemblyFailed(:final failure):
            state = confirmed.withProgress(
              RelationGroupRefreshFailure(failure),
            );
            return;
          case _AssemblyInterrupted():
            continue;
        }
      }
      state = confirmed.withProgress(
        const RelationGroupRefreshFailure(RelationGroupUnavailableFailure()),
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
    RelationGroupLoaded confirmed,
    Object request,
    int generation,
  ) async {
    final selection = confirmed.selection;
    final limit = confirmed.items.length + _policy.pageSize;

    final firstResult = await _readPage(selection);
    if (!_owns(request, generation)) {
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
    final totalCount = counts.forGroup(
      scope: selection.scope,
      type: selection.type,
      direction: selection.direction,
    );
    final firstItems = _combine(const [], firstPage.items, selection);
    var cursor = firstPage.nextCursor;
    if (firstItems == null ||
        !_hasConsistentTotal(firstItems.length, cursor, totalCount)) {
      return const _AssemblyFailed(RelationGroupUnexpectedFailure());
    }
    var items = firstItems;

    while (cursor != null && items.length < limit) {
      final result = await _readPage(selection, cursor: cursor);
      if (!_owns(request, generation)) {
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
          counts: counts,
          revision: revision,
        ),
      );
    }
    return _AssembledGroup(
      RelationGroupLoaded(
        intentionId: _intentionId,
        selection: selection,
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
  RelationGroupLoaded? _appendContinuation(
    RelationGroupLoaded confirmed,
    RelationGroupPage page,
  ) {
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
      counts: confirmed.counts,
      revision: confirmed.revision,
      items: combined,
      nextCursor: page.nextCursor,
    );
  }

  RelationNeighborhoodState _stateFromFirstPage(
    RelationGroupSelection selection,
    RelationGroupPage page,
  ) {
    if (page is! RelationGroupFirstPage) {
      return _initialFailure(selection, const RelationGroupUnexpectedFailure());
    }
    final totalCount = page.counts.forGroup(
      scope: selection.scope,
      type: selection.type,
      direction: selection.direction,
    );
    final items = _combine(const [], page.items, selection);
    if (items == null ||
        !_hasConsistentTotal(items.length, page.nextCursor, totalCount)) {
      return _initialFailure(selection, const RelationGroupUnexpectedFailure());
    }
    if (items.isEmpty) {
      return RelationGroupEmpty(
        intentionId: _intentionId,
        selection: selection,
        counts: page.counts,
        revision: page.revision,
      );
    }
    return RelationGroupLoaded(
      intentionId: _intentionId,
      selection: selection,
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

  RelationGroupInitialFailure _initialFailure(
    RelationGroupSelection selection,
    RelationGroupReadFailure failure,
  ) => RelationGroupInitialFailure(
    intentionId: _intentionId,
    selection: selection,
    failure: failure,
  );

  Future<RelationGroupPageResult> _readPage(
    RelationGroupSelection selection, {
    RelationGroupCursor? cursor,
  }) async {
    try {
      return await _repository.getRelationGroupPage(
        RelationGroupQuery(
          intentionId: _intentionId,
          type: selection.type,
          direction: selection.direction,
          scope: selection.scope,
          pageSize: _policy.pageSize,
          cursor: cursor,
        ),
      );
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
