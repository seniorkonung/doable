import 'dart:async';
import 'dart:math';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../long_term_relation/application/relation_counts.dart';
import '../../../tag/application/tag_change.dart';
import '../../../tag/domain/tag.dart';
import '../../../tag/domain/tag_id.dart';
import '../../application/intention_catalog.dart';
import '../../application/intention_result.dart';
import '../../domain/intention_id.dart';
import 'catalog_paging_policy.dart';
import 'intention_catalog_purpose.dart';
import 'intention_catalog_state.dart';

part 'intention_catalog_view_model.g.dart';

/// Ограниченный каталог намерений для одного назначения.
///
/// Назначение задаёт отдельное состояние просмотра: общий каталог и режимы
/// выбора участников не разделяют фильтр и загруженную часть.
@riverpod
final class IntentionCatalogViewModel extends _$IntentionCatalogViewModel {
  late IntentionCatalogPurpose _purpose;
  IntentionScope _scope = IntentionCatalogSelection.initial.scope;
  String _titleFilterText = IntentionCatalogSelection.initial.titleFilterText;
  IntentionTagFilter _tagFilter = IntentionCatalogSelection.initial.tagFilter;
  IntentionCatalogOrder _order = IntentionCatalogSelection.initial.order;
  IntentionCatalogFilterValidationFailure? _filterValidationFailure;
  CatalogPagingPolicy _policy = CatalogPagingPolicy.production;
  Timer? _filterTimer;
  bool _isDebouncingFilter = false;
  int _queryGeneration = 0;
  Object? _activePageRequest;
  bool _isLoadingFirstPage = false;
  final _packagesBeforeFirstPage = <_CatalogChangePackage>[];
  IntentionSummary? _cursorBoundary;
  _PendingCatalogContinuation? _pendingContinuation;
  _AreaReconciliation? _areaReconciliation;

  IntentionCatalogSelection get selection => IntentionCatalogSelection(
    scope: switch (_purpose) {
      BrowseIntentionCatalog() => _scope,
      SelectRelationParticipant(:final scope) => scope,
      SelectDailyChoiceAction() => IntentionScope.active,
      SelectDailyChoiceSource() => IntentionScope.active,
    },
    titleFilterText: _titleFilterText,
    tagFilter: _tagFilter,
    order: _order,
    filterValidationFailure: _filterValidationFailure,
  );

  @override
  Future<IntentionCatalogState> build(IntentionCatalogPurpose purpose) {
    _purpose = purpose;
    _invalidatePageRequest();
    _isLoadingFirstPage = false;
    _packagesBeforeFirstPage.clear();
    _cursorBoundary = null;
    _pendingContinuation = null;
    final repository = ref.watch(personalGraphRepositoryProvider);
    _policy = ref.watch(catalogPagingPolicyProvider);
    final completionSubscription = ref
        .watch(graphCommandCoordinatorProvider.notifier)
        .completions
        .listen(_handleCompletion);
    ref.onDispose(() => unawaited(completionSubscription.cancel()));
    ref.onCancel(() => _filterTimer?.cancel());

    if (_isDebouncingFilter) {
      return Future.value(IntentionCatalogDebouncing(selection: selection));
    }

    final catalogScope = selection.scope;
    late final IntentionCatalogQuery query;
    try {
      query = IntentionCatalogQuery(
        scope: catalogScope,
        readinessFilter: switch (purpose) {
          SelectDailyChoiceAction() => IntentionReadinessFilter.readyOnly,
          BrowseIntentionCatalog() ||
          SelectRelationParticipant() ||
          SelectDailyChoiceSource() => IntentionReadinessFilter.all,
        },
        titleFilter: _titleFilterText,
        tagFilter: _tagFilter,
        excludedIntentionId: switch (purpose) {
          SelectRelationParticipant(:final excludedIntentionId) =>
            excludedIntentionId,
          BrowseIntentionCatalog() ||
          SelectDailyChoiceAction() ||
          SelectDailyChoiceSource() => null,
        },
        order: _order,
        pageSize: _policy.pageSize,
      );
    } on IntentionCatalogQueryValidationException catch (error) {
      _filterValidationFailure = switch (error.failure) {
        IntentionCatalogQueryValidationFailure.invalidUnicodeRepertoire =>
          IntentionCatalogFilterValidationFailure.invalidUnicodeRepertoire,
        IntentionCatalogQueryValidationFailure.titleFilterTooLong =>
          IntentionCatalogFilterValidationFailure.tooLong,
        IntentionCatalogQueryValidationFailure.pageSizeOutOfRange =>
          throw StateError('CatalogPagingPolicy пропустила неверный pageSize.'),
      };
      return Future.value(IntentionCatalogInvalidFilter(selection: selection));
    }

    _filterValidationFailure = null;
    final currentSelection = selection;
    _isLoadingFirstPage = true;
    return _loadFirstPage(
      repository,
      query,
      currentSelection,
      _queryGeneration,
    );
  }

  void changeScope(IntentionScope scope) {
    if (_purpose is! BrowseIntentionCatalog || _scope == scope) {
      return;
    }
    _scope = scope;
    _applyParametersImmediately();
  }

  void changeOrder(IntentionCatalogOrder order) {
    if (_order == order) {
      return;
    }
    _order = order;
    _applyParametersImmediately();
  }

  void changeTitleFilter(String value) {
    if (_titleFilterText == value) {
      return;
    }
    _titleFilterText = value;
    _filterValidationFailure = null;
    _isDebouncingFilter = true;
    _invalidatePageRequest();
    _filterTimer?.cancel();
    ref.invalidateSelf();
    _filterTimer = Timer(_policy.filterDebounce, () {
      if (!ref.mounted) {
        return;
      }
      _isDebouncingFilter = false;
      ref.invalidateSelf();
    });
  }

  /// Сразу применяет оба набора вместе с текущим текстом и ограничениями.
  void changeTagFilter(IntentionTagFilter filter) {
    if (_tagFilter == filter) {
      return;
    }
    _tagFilter = filter;
    _applyParametersImmediately();
  }

  Future<void> retry() async {
    final current = state.value;
    if (current is! IntentionCatalogUnavailable) {
      return;
    }

    state = const AsyncLoading();
    _invalidatePageRequest();
    ref.invalidateSelf();
  }

  /// Повторяет отказавшее согласование загруженной области с текущими
  /// условиями и сохранённым содержимым тем же чтением, которое запускает
  /// подтверждённый после отказа пакет.
  Future<void> retryRefresh() {
    final area = _areaReconciliation;
    if (area == null ||
        !area.isFailed ||
        area.isReading ||
        !_ownsAreaReconciliation(area)) {
      return Future.value();
    }
    return _readArea(area);
  }

  Future<void> loadNextPageIfNeeded({required int visibleIndex}) {
    final current = state.value;
    if (current is! IntentionCatalogLoaded ||
        current.nextCursor == null ||
        current.continuation is! IntentionCatalogContinuationIdle ||
        visibleIndex < 0 ||
        current.items.length - visibleIndex - 1 > _policy.prefetchRemaining) {
      return Future.value();
    }
    return _loadNextPage(current);
  }

  Future<void> retryNextPage() {
    final current = state.value;
    if (current is! IntentionCatalogLoaded ||
        current.continuation is! IntentionCatalogContinuationUnavailable) {
      return Future.value();
    }
    return _loadNextPage(current);
  }

  Future<void> recoverFromInvalidCursor() {
    final current = state.value;
    if (current is! IntentionCatalogLoaded ||
        current.continuation is! IntentionCatalogContinuationValidation) {
      return Future.value();
    }
    return _recoverFirstPage(current);
  }

  Future<void> retryRecovery() {
    final current = state.value;
    if (current is! IntentionCatalogLoaded ||
        current.continuation is! IntentionCatalogRecoveryUnavailable) {
      return Future.value();
    }
    return _recoverFirstPage(current);
  }

  Future<IntentionCatalogState> _loadFirstPage(
    PersonalGraphRepository repository,
    IntentionCatalogQuery query,
    IntentionCatalogSelection selection,
    int generation,
  ) async {
    try {
      final result = await repository.getCatalogPage(query);
      final mapped = switch (result) {
        ResultSuccess(:final value) => _mapPage(selection, query, value),
        ResultFailure(:final failure) => _mapFailure(selection, query, failure),
      };
      if (_queryGeneration != generation) {
        return mapped;
      }
      _isLoadingFirstPage = false;
      if (mapped case final IntentionCatalogConfirmedState confirmed) {
        _cursorBoundary = _boundaryFromFirstPage(confirmed);
        var reconciled = confirmed;
        var requiresAreaReconciliation = false;
        for (final package in _packagesBeforeFirstPage) {
          switch (_applyPackage(reconciled, package)) {
            case null:
              _packagesBeforeFirstPage.clear();
              scheduleMicrotask(_restartFromFirstPage);
              return confirmed;
            case _PackageApplied(:final content):
              reconciled = content;
            case _AreaReconciliationRequired(:final content):
              reconciled = content;
              requiresAreaReconciliation = true;
          }
        }
        _packagesBeforeFirstPage.clear();
        if (requiresAreaReconciliation) {
          // Первая порция согласована целиком на своей ревизии; содержимое
          // после пакетов публикуется только после достраивания области.
          final area = _AreaReconciliation(
            generation: generation,
            content: reconciled,
          );
          _areaReconciliation = area;
          scheduleMicrotask(() => unawaited(_readArea(area)));
          return confirmed;
        }
        return reconciled;
      }
      _packagesBeforeFirstPage.clear();
      return mapped;
    } on Object {
      if (_queryGeneration == generation) {
        _isLoadingFirstPage = false;
        _packagesBeforeFirstPage.clear();
      }
      return IntentionCatalogUnexpected(selection: selection, query: query);
    }
  }

  IntentionSummary? _boundaryFromFirstPage(
    IntentionCatalogConfirmedState confirmed,
  ) {
    if (confirmed.nextCursor == null || confirmed is! IntentionCatalogLoaded) {
      return null;
    }
    return confirmed.items.isEmpty ? null : confirmed.items.last;
  }

  IntentionCatalogState _mapPage(
    IntentionCatalogSelection selection,
    IntentionCatalogQuery query,
    IntentionCatalogPage page,
  ) {
    if (page is! IntentionCatalogFirstPage ||
        page.items.length > query.pageSize) {
      return IntentionCatalogUnexpected(selection: selection, query: query);
    }
    if (page.items.isEmpty) {
      if (page.totalCount != 0 || page.nextCursor != null) {
        return IntentionCatalogUnexpected(selection: selection, query: query);
      }
      return IntentionCatalogEmpty(
        selection: selection,
        query: query,
        revision: page.revision,
      );
    }
    if (page.totalCount == page.items.length && page.nextCursor != null ||
        page.totalCount > page.items.length && page.nextCursor == null) {
      return IntentionCatalogUnexpected(selection: selection, query: query);
    }
    return IntentionCatalogLoaded(
      selection: selection,
      query: query,
      items: page.items,
      totalCount: page.totalCount,
      nextCursor: page.nextCursor,
      revision: page.revision,
    );
  }

  IntentionCatalogState _mapFailure(
    IntentionCatalogSelection selection,
    IntentionCatalogQuery query,
    IntentionFailure failure,
  ) => switch (failure) {
    IntentionUnavailableFailure() => IntentionCatalogUnavailable(
      selection: selection,
      query: query,
    ),
    IntentionCorruptionFailure() => IntentionCatalogCorruption(
      selection: selection,
      query: query,
    ),
    IntentionUnexpectedFailure() => IntentionCatalogUnexpected(
      selection: selection,
      query: query,
    ),
    IntentionValidationFailure() => IntentionCatalogUnexpected(
      selection: selection,
      query: query,
    ),
    IntentionNotFoundFailure() => IntentionCatalogUnexpected(
      selection: selection,
      query: query,
    ),
    IntentionConflictFailure() => IntentionCatalogUnexpected(
      selection: selection,
      query: query,
    ),
    IntentionHasBlockingRelationsFailure() => IntentionCatalogUnexpected(
      selection: selection,
      query: query,
    ),
  };

  Future<void> _loadNextPage(IntentionCatalogLoaded confirmed) async {
    // Во время согласования загруженной области её граница не сдвигается:
    // продолжение прочитало бы строки, не учтённые согласованием.
    if (_activePageRequest != null ||
        _areaReconciliation != null ||
        confirmed.nextCursor == null) {
      return;
    }
    final request = Object();
    final generation = _queryGeneration;
    _activePageRequest = request;
    state = AsyncData(
      _withContinuation(confirmed, const IntentionCatalogContinuationLoading()),
    );

    try {
      final repository = ref.read(personalGraphRepositoryProvider);
      final query = _continuationQuery(confirmed);
      while (_ownsRequest(request, generation)) {
        final result = await repository.getCatalogPage(query);
        if (!_ownsRequest(request, generation)) {
          return;
        }
        final current = state.value;
        if (current is! IntentionCatalogLoaded) {
          return;
        }
        switch (result) {
          case ResultSuccess(:final value):
            if (_handleContinuationPage(current, value, generation)) {
              continue;
            }
          case ResultFailure(:final failure):
            state = AsyncData(
              _withContinuation(current, _continuationFailure(failure)),
            );
        }
        return;
      }
    } on Object {
      if (_ownsRequest(request, generation)) {
        final current = state.value;
        if (current is IntentionCatalogLoaded) {
          state = AsyncData(
            _withContinuation(
              current,
              const IntentionCatalogContinuationUnexpected(),
            ),
          );
        }
      }
    } finally {
      if (identical(_activePageRequest, request)) {
        _activePageRequest = null;
      }
    }
  }

  Future<void> _recoverFirstPage(IntentionCatalogLoaded confirmed) async {
    _invalidatePageRequest();
    final request = Object();
    final generation = _queryGeneration;
    _activePageRequest = request;
    state = AsyncData(
      _withContinuation(
        confirmed,
        const IntentionCatalogContinuationRecovering(),
      ),
    );

    try {
      final repository = ref.read(personalGraphRepositoryProvider);
      final query = _firstPageQuery(confirmed);
      while (_ownsRequest(request, generation)) {
        final result = await repository.getCatalogPage(query);
        if (!_ownsRequest(request, generation)) {
          return;
        }
        final current = state.value;
        switch (result) {
          case ResultSuccess(:final value):
            final mapped = _mapPage(confirmed.selection, query, value);
            if (mapped case final IntentionCatalogConfirmedState page) {
              if (current
                  case final IntentionCatalogConfirmedState currentConfirmed) {
                if (page.revision.compareTo(currentConfirmed.revision) ==
                    GraphRevisionOrder.older) {
                  continue;
                }
              }
              _cursorBoundary = _boundaryFromFirstPage(page);
            }
            state = AsyncData(mapped);
          case ResultFailure(:final failure):
            if (current is IntentionCatalogLoaded) {
              state = AsyncData(
                _withContinuation(current, _recoveryFailure(failure)),
              );
            }
        }
        return;
      }
    } on Object {
      if (_ownsRequest(request, generation)) {
        final current = state.value;
        if (current is IntentionCatalogLoaded) {
          state = AsyncData(
            _withContinuation(
              current,
              const IntentionCatalogRecoveryUnexpected(),
            ),
          );
        }
      }
    } finally {
      if (identical(_activePageRequest, request)) {
        _activePageRequest = null;
      }
    }
  }

  IntentionCatalogState _appendPage(
    IntentionCatalogLoaded confirmed,
    IntentionCatalogPage page,
  ) {
    if (page is! IntentionCatalogContinuationPage ||
        page.items.length > confirmed.query.pageSize ||
        page.nextCursor != null && page.items.isEmpty) {
      return _withContinuation(
        confirmed,
        const IntentionCatalogContinuationUnexpected(),
      );
    }

    final knownIds = confirmed.items.map((item) => item.id).toSet();
    final combined = [...confirmed.items];
    for (final item in page.items) {
      if (knownIds.add(item.id)) {
        combined.add(item);
      }
    }
    if (combined.length > confirmed.totalCount) {
      return _withContinuation(
        confirmed,
        const IntentionCatalogContinuationUnexpected(),
      );
    }
    if (page.nextCursor == null && combined.length != confirmed.totalCount ||
        page.nextCursor != null && combined.length >= confirmed.totalCount) {
      return _withContinuation(
        confirmed,
        const IntentionCatalogContinuationUnexpected(),
      );
    }
    combined.sort(confirmed.query.compare);
    _cursorBoundary = page.nextCursor == null ? null : page.items.last;
    return IntentionCatalogLoaded(
      selection: confirmed.selection,
      query: confirmed.query,
      items: combined,
      totalCount: confirmed.totalCount,
      nextCursor: page.nextCursor,
      revision: confirmed.revision,
    );
  }

  bool _handleContinuationPage(
    IntentionCatalogLoaded confirmed,
    IntentionCatalogPage page,
    int generation,
  ) {
    if (page is! IntentionCatalogContinuationPage ||
        page.items.length > confirmed.query.pageSize) {
      state = AsyncData(
        _withContinuation(
          confirmed,
          const IntentionCatalogContinuationUnexpected(),
        ),
      );
      return false;
    }

    switch (page.revision.compareTo(confirmed.revision)) {
      case GraphRevisionOrder.older:
        return true;
      case GraphRevisionOrder.same:
        state = AsyncData(_appendPage(confirmed, page));
        return false;
      case GraphRevisionOrder.newer:
        _pendingContinuation = _PendingCatalogContinuation(
          generation: generation,
          page: page,
        );
        state = AsyncData(
          _withContinuation(
            confirmed,
            const IntentionCatalogContinuationLoading(),
          ),
        );
        return false;
      case GraphRevisionOrder.differentEpoch:
        _restartFromFirstPage();
        return false;
    }
  }

  IntentionCatalogContinuationState _continuationFailure(
    IntentionFailure failure,
  ) => switch (failure) {
    IntentionUnavailableFailure() =>
      const IntentionCatalogContinuationUnavailable(),
    IntentionCorruptionFailure() =>
      const IntentionCatalogContinuationCorruption(),
    IntentionValidationFailure() =>
      const IntentionCatalogContinuationValidation(),
    IntentionUnexpectedFailure() ||
    IntentionNotFoundFailure() ||
    IntentionConflictFailure() ||
    IntentionHasBlockingRelationsFailure() =>
      const IntentionCatalogContinuationUnexpected(),
  };

  IntentionCatalogContinuationState _recoveryFailure(
    IntentionFailure failure,
  ) => switch (failure) {
    IntentionUnavailableFailure() =>
      const IntentionCatalogRecoveryUnavailable(),
    IntentionCorruptionFailure() => const IntentionCatalogRecoveryCorruption(),
    IntentionValidationFailure() ||
    IntentionUnexpectedFailure() ||
    IntentionNotFoundFailure() ||
    IntentionConflictFailure() ||
    IntentionHasBlockingRelationsFailure() =>
      const IntentionCatalogRecoveryUnexpected(),
  };

  IntentionCatalogRefreshState _refreshFailure(
    IntentionFailure failure,
  ) => switch (failure) {
    IntentionUnavailableFailure() => const IntentionCatalogRefreshUnavailable(),
    IntentionCorruptionFailure() => const IntentionCatalogRefreshCorruption(),
    IntentionValidationFailure() ||
    IntentionUnexpectedFailure() ||
    IntentionNotFoundFailure() ||
    IntentionConflictFailure() ||
    IntentionHasBlockingRelationsFailure() =>
      const IntentionCatalogRefreshUnexpected(),
  };

  IntentionCatalogQuery _continuationQuery(IntentionCatalogLoaded confirmed) =>
      IntentionCatalogQuery(
        scope: confirmed.query.scope,
        readinessFilter: confirmed.query.readinessFilter,
        titleFilter: confirmed.query.titleFilter?.map((value) => value),
        tagFilter: confirmed.query.tagFilter,
        excludedIntentionId: confirmed.query.excludedIntentionId,
        order: confirmed.query.order,
        pageSize: confirmed.query.pageSize,
        cursor: confirmed.nextCursor,
      );

  IntentionCatalogQuery _firstPageQuery(IntentionCatalogLoaded confirmed) =>
      IntentionCatalogQuery(
        scope: confirmed.query.scope,
        readinessFilter: confirmed.query.readinessFilter,
        titleFilter: confirmed.query.titleFilter?.map((value) => value),
        tagFilter: confirmed.query.tagFilter,
        excludedIntentionId: confirmed.query.excludedIntentionId,
        order: confirmed.query.order,
        pageSize: confirmed.query.pageSize,
      );

  IntentionCatalogLoaded _withContinuation(
    IntentionCatalogLoaded confirmed,
    IntentionCatalogContinuationState continuation,
  ) => IntentionCatalogLoaded(
    selection: confirmed.selection,
    query: confirmed.query,
    items: confirmed.items,
    totalCount: confirmed.totalCount,
    nextCursor: confirmed.nextCursor,
    revision: confirmed.revision,
    continuation: continuation,
  );

  bool _ownsRequest(Object request, int generation) =>
      ref.mounted &&
      _queryGeneration == generation &&
      identical(_activePageRequest, request);

  void _invalidatePageRequest() {
    _queryGeneration += 1;
    _activePageRequest = null;
    _areaReconciliation = null;
  }

  void _applyParametersImmediately() {
    _filterTimer?.cancel();
    _isDebouncingFilter = false;
    _invalidatePageRequest();
    ref.invalidateSelf();
  }

  /// Принимает подтверждённые изменения намерений, долговременных и дневных связей.
  ///
  /// Отказ не согласует данные: подтверждённого пакета у него нет.
  void _handleCompletion(GraphCommandCompletion completion) {
    final confirmedChange = completion.confirmedChange;
    if (confirmedChange != null) {
      _reconcilePackage(
        _CatalogChangePackage(
          confirmedChange.revision,
          confirmedChange.changes,
        ),
      );
    }
  }

  void _reconcilePackage(_CatalogChangePackage package) {
    if (!ref.mounted) {
      return;
    }
    final area = _areaReconciliation;
    if (area != null) {
      area.packages.add(package);
      if (!area.isReading) {
        _advanceAreaReconciliation(area, readRequired: true);
      }
      return;
    }
    final current = state.value;
    if (_isLoadingFirstPage || current is! IntentionCatalogConfirmedState) {
      _packagesBeforeFirstPage.add(package);
      return;
    }

    switch (_applyPackage(current, package)) {
      case null:
        _restartFromFirstPage();
      case _PackageApplied(content: final reconciled):
        if (!identical(reconciled, current)) {
          state = AsyncData(reconciled);
        }
        _resolvePendingContinuation(reconciled);
      case _AreaReconciliationRequired(:final content):
        _startAreaReconciliation(current, content);
    }
  }

  /// Начинает достраивание загруженной области после изменения, которое не
  /// перечисляет затронутые намерения.
  ///
  /// Опубликованное содержимое остаётся прежним, пока кандидат не согласован
  /// целиком. Незавершённое продолжение выдачи отменяется: оно читало бы
  /// строки после границы, ещё не учтённой согласованием.
  void _startAreaReconciliation(
    IntentionCatalogConfirmedState published,
    IntentionCatalogConfirmedState content,
  ) {
    if (published is IntentionCatalogLoaded &&
        published.continuation is IntentionCatalogContinuationLoading) {
      _activePageRequest = null;
    }
    _pendingContinuation = null;
    final area = _AreaReconciliation(
      generation: _queryGeneration,
      content: content,
    );
    _areaReconciliation = area;
    unawaited(_readArea(area));
  }

  Future<void> _readArea(_AreaReconciliation area) async {
    if (!_ownsAreaReconciliation(area)) {
      return;
    }
    area.isReading = true;
    if (area.isFailed) {
      area.isFailed = false;
      _publishRefresh(const IntentionCatalogRefreshIdle());
    }
    final _AreaReadOutcome outcome;
    try {
      outcome = await _readMissingAreaMatches(area);
    } on Object {
      if (_ownsAreaReconciliation(area)) {
        _failAreaReconciliation(
          area,
          const IntentionCatalogRefreshUnexpected(),
        );
      }
      return;
    }
    if (!_ownsAreaReconciliation(area)) {
      return;
    }
    area.isReading = false;
    switch (outcome) {
      case _AreaReadCompleted(:final candidate):
        area
          ..content = candidate
          ..isConsistent = true;
        _advanceAreaReconciliation(area, readRequired: false);
      case _AreaReadStale():
        // Пакет более новой ревизии ещё не получен: его приход повторит
        // чтение, а полученные ранее пакеты применяются сразу.
        if (area.packages.isNotEmpty) {
          _advanceAreaReconciliation(area, readRequired: true);
        }
      case _AreaReadFailed(:final refresh):
        _failAreaReconciliation(area, refresh);
      case _AreaReadUnreconcilable():
        _abandonAreaReconciliation();
    }
  }

  /// Сохраняет последнее целиком подтверждённое содержимое с явным отказом
  /// обновления. Пакеты, подтверждённые во время чтения, применяются к
  /// сохранённому содержимому области без нового чтения. Чтение недостающей
  /// части повторяет следующий подтверждённый пакет либо явный повтор:
  /// таймеров и повторов без нового события нет.
  void _failAreaReconciliation(
    _AreaReconciliation area,
    IntentionCatalogRefreshState refresh,
  ) {
    area
      ..isReading = false
      ..isFailed = true;
    _advanceAreaReconciliation(area, readRequired: false);
    if (identical(_areaReconciliation, area)) {
      _publishRefresh(refresh);
    }
  }

  /// Заменяет состояние обновления опубликованного содержимого тем же
  /// объектом запроса, чтобы страница сохранила позицию просмотра.
  /// Продолжение выдачи, отменённое согласованием, снова свободно.
  void _publishRefresh(IntentionCatalogRefreshState refresh) {
    final IntentionCatalogConfirmedState? published = switch (state.value) {
      final IntentionCatalogLoaded loaded => IntentionCatalogLoaded(
        selection: loaded.selection,
        query: loaded.query,
        items: loaded.items,
        totalCount: loaded.totalCount,
        nextCursor: loaded.nextCursor,
        revision: loaded.revision,
        refresh: refresh,
        continuation: switch (loaded.continuation) {
          IntentionCatalogContinuationLoading() =>
            const IntentionCatalogContinuationIdle(),
          final continuation => continuation,
        },
      ),
      final IntentionCatalogEmpty empty => IntentionCatalogEmpty(
        selection: empty.selection,
        query: empty.query,
        revision: empty.revision,
        refresh: refresh,
      ),
      _ => null,
    };
    if (published != null) {
      state = AsyncData(published);
    }
  }

  /// Последовательно применяет пакеты, накопленные во время чтения, к
  /// сохранённому содержимому области и публикует его, если оно согласовано
  /// целиком; иначе повторяет чтение недостающей части для новой ревизии.
  ///
  /// [readRequired] означает пакет, полученный вне чтения, либо устаревшее
  /// чтение: оно повторяется и после отказа. Пакеты, накопленные во время
  /// отказавшего чтения, отказ не снимают.
  void _advanceAreaReconciliation(
    _AreaReconciliation area, {
    required bool readRequired,
  }) {
    var packagesRequireRead = false;
    for (final package in area.packages) {
      switch (_applyPackage(area.content, package)) {
        case null:
          _abandonAreaReconciliation();
          return;
        case _PackageApplied(:final content):
          area.content = content;
        case _AreaReconciliationRequired(:final content):
          area
            ..content = content
            ..isConsistent = false;
          packagesRequireRead = true;
      }
    }
    area.packages.clear();
    if (area.isConsistent) {
      _publishAreaReconciliation(area);
    } else if (readRequired || packagesRequireRead && !area.isFailed) {
      unawaited(_readArea(area));
    }
  }

  /// Читает недостающие совпадения области сохранённого содержимого на его
  /// ревизии: абсолютное количество первой порции заменяет прежнее, поэтому
  /// изменения до этой ревизии не учитываются в количестве повторно.
  ///
  /// Сохранённые строки передаются скользящим окном не больше порции,
  /// следующим за курсором согласования, поэтому вход каждого чтения не
  /// зависит от размера области, а число чтений растёт линейно с числом
  /// сохранённых и недостающих строк.
  Future<_AreaReadOutcome> _readMissingAreaMatches(
    _AreaReconciliation area,
  ) async {
    final repository = ref.read(personalGraphRepositoryProvider);
    final content = area.content;
    final query = content.query;
    final pageSize = query.pageSize;
    final IntentionCatalogReconciliationBoundary boundary = switch (content
        .nextCursor) {
      null => const IntentionCatalogCompletedBoundary(),
      final continuation => IntentionCatalogPartialPrefixBoundary(continuation),
    };
    final stored = switch (content) {
      IntentionCatalogLoaded(:final items) => items,
      IntentionCatalogEmpty() => const <IntentionSummary>[],
    };

    read:
    while (true) {
      int? totalCount;
      final missing = <IntentionSummary>[];
      IntentionCatalogReconciliationCursor? cursor;
      IntentionSummary? position;
      var windowStart = 0;
      while (true) {
        final windowEnd = min(windowStart + pageSize, stored.length);
        final windowRows = stored.sublist(windowStart, windowEnd);
        final IntentionCatalogReconciliationWindow window =
            windowEnd < stored.length
            ? IntentionCatalogInnerReconciliationWindow(windowRows)
            : IntentionCatalogFinalReconciliationWindow(windowRows);
        final result = await repository.getCatalogReconciliationPortion(
          IntentionCatalogReconciliationQuery(
            catalogQuery: query,
            boundary: boundary,
            window: window,
            cursor: cursor,
          ),
        );
        if (!_ownsAreaReconciliation(area)) {
          return const _AreaReadStale();
        }
        final IntentionCatalogReconciliationPortion portion;
        switch (result) {
          case ResultFailure(:final failure):
            return _AreaReadFailed(_refreshFailure(failure));
          case ResultSuccess(value: IntentionCatalogReconciliationRetry()):
            return const _AreaReadStale();
          case ResultSuccess(
            value: final IntentionCatalogReconciliationPortion value,
          ):
            portion = value;
        }
        switch ((portion, totalCount)) {
          case (
            IntentionCatalogReconciliationFirstPortion(totalCount: final count),
            null,
          ):
            totalCount = count;
          case (IntentionCatalogReconciliationContinuationPortion(), _?):
            break;
          default:
            return const _AreaReadFailed(IntentionCatalogRefreshUnexpected());
        }
        if (!_isWithinWindow(query, portion.items, position, window)) {
          return const _AreaReadFailed(IntentionCatalogRefreshUnexpected());
        }
        switch (portion.revision.compareTo(content.revision)) {
          case GraphRevisionOrder.same:
            break;
          case GraphRevisionOrder.older:
            continue read;
          case GraphRevisionOrder.newer:
            return const _AreaReadStale();
          case GraphRevisionOrder.differentEpoch:
            return const _AreaReadUnreconcilable();
        }
        missing.addAll(portion.items);

        final nextCursor = portion.nextCursor;
        switch ((nextCursor, window)) {
          case (null, IntentionCatalogFinalReconciliationWindow()):
            break;
          case (null, IntentionCatalogInnerReconciliationWindow()):
            return const _AreaReadFailed(IntentionCatalogRefreshUnexpected());
          case (_?, _) when portion.items.length == pageSize:
            position = portion.items.last;
          case (
            _?,
            IntentionCatalogInnerReconciliationWindow(:final upperEdgeRow),
          ):
            position = upperEdgeRow;
          case (_?, IntentionCatalogFinalReconciliationWindow()):
            return const _AreaReadFailed(IntentionCatalogRefreshUnexpected());
        }
        if (nextCursor == null) {
          break;
        }
        cursor = nextCursor;
        final nextPosition = position!;
        while (windowStart < stored.length &&
            query.compare(stored[windowStart], nextPosition) <= 0) {
          windowStart += 1;
        }
      }

      final candidate = _areaCandidate(content, stored, missing, totalCount!);
      return candidate == null
          ? const _AreaReadFailed(IntentionCatalogRefreshUnexpected())
          : _AreaReadCompleted(candidate);
    }
  }

  /// Порция не больше размера порции, строго по возрастанию, после позиции
  /// продолжения и не за верхним краем внутреннего окна. Верхний край
  /// последнего окна проверяет сборка кандидата по границе области.
  bool _isWithinWindow(
    IntentionCatalogQuery query,
    List<IntentionSummary> items,
    IntentionSummary? position,
    IntentionCatalogReconciliationWindow window,
  ) {
    if (items.length > query.pageSize) {
      return false;
    }
    var previous = position;
    for (final item in items) {
      if (previous != null && query.compare(previous, item) >= 0) {
        return false;
      }
      previous = item;
    }
    return switch ((window, previous)) {
      (
        IntentionCatalogInnerReconciliationWindow(:final upperEdgeRow),
        final last?,
      ) =>
        query.compare(last, upperEdgeRow) < 0,
      _ => true,
    };
  }

  /// Собирает согласованный префикс из сохранённых строк и недостающих
  /// совпадений в действующем порядке с абсолютным количеством.
  IntentionCatalogConfirmedState? _areaCandidate(
    IntentionCatalogConfirmedState content,
    List<IntentionSummary> stored,
    List<IntentionSummary> missing,
    int totalCount,
  ) {
    final knownIds = {for (final item in stored) item.id};
    final items = [...stored];
    for (final item in missing) {
      if (!knownIds.add(item.id) || !_belongsToLoadedPrefix(content, item)) {
        return null;
      }
      items.add(item);
    }
    if (items.length > totalCount ||
        content.nextCursor == null && items.length != totalCount) {
      return null;
    }
    items.sort(content.query.compare);
    if (items.isEmpty && content.nextCursor == null) {
      return IntentionCatalogEmpty(
        selection: content.selection,
        query: content.query,
        revision: content.revision,
      );
    }
    return IntentionCatalogLoaded(
      selection: content.selection,
      query: content.query,
      items: items,
      totalCount: totalCount,
      nextCursor: content.nextCursor,
      revision: content.revision,
    );
  }

  /// Публикует целиком согласованный префикс тем же объектом запроса, чтобы
  /// страница сохранила позицию просмотра. Отменённое продолжение выдачи
  /// снова доступно; прочие состояния продолжения сохраняются.
  void _publishAreaReconciliation(_AreaReconciliation area) {
    _areaReconciliation = null;
    final current = state.value;
    if (current is! IntentionCatalogConfirmedState) {
      return;
    }
    switch (current.revision.compareTo(area.content.revision)) {
      case GraphRevisionOrder.older:
        break;
      case GraphRevisionOrder.same || GraphRevisionOrder.newer:
        // Опубликованное содержимое уже отражает эту ревизию целиком.
        return;
      case GraphRevisionOrder.differentEpoch:
        _restartFromFirstPage();
        return;
    }
    final published = switch (area.content) {
      final IntentionCatalogLoaded loaded => _withContinuation(
        loaded,
        switch (current) {
          IntentionCatalogLoaded(:final continuation)
              when continuation is! IntentionCatalogContinuationLoading =>
            continuation,
          _ => const IntentionCatalogContinuationIdle(),
        },
      ),
      final IntentionCatalogEmpty empty => empty,
    };
    state = AsyncData(published);
  }

  void _abandonAreaReconciliation() {
    _areaReconciliation = null;
    _restartFromFirstPage();
  }

  bool _ownsAreaReconciliation(_AreaReconciliation area) =>
      ref.mounted &&
      identical(_areaReconciliation, area) &&
      area.generation == _queryGeneration;

  void _resolvePendingContinuation(IntentionCatalogConfirmedState confirmed) {
    final pending = _pendingContinuation;
    if (pending == null || pending.generation != _queryGeneration) {
      return;
    }
    if (confirmed is! IntentionCatalogLoaded) {
      _pendingContinuation = null;
      return;
    }

    switch (pending.page.revision.compareTo(confirmed.revision)) {
      case GraphRevisionOrder.newer:
        return;
      case GraphRevisionOrder.same:
        _pendingContinuation = null;
        state = AsyncData(_appendPage(confirmed, pending.page));
      case GraphRevisionOrder.older:
        _pendingContinuation = null;
        scheduleMicrotask(_retryStalePendingContinuation);
      case GraphRevisionOrder.differentEpoch:
        _pendingContinuation = null;
        _restartFromFirstPage();
    }
  }

  void _retryStalePendingContinuation() {
    if (!ref.mounted || _activePageRequest != null) {
      return;
    }
    final current = state.value;
    if (current is IntentionCatalogLoaded &&
        current.nextCursor != null &&
        current.continuation is IntentionCatalogContinuationLoading) {
      unawaited(_loadNextPage(current));
    }
  }

  void _restartFromFirstPage() {
    if (!ref.mounted) {
      return;
    }
    _pendingContinuation = null;
    _invalidatePageRequest();
    ref.invalidateSelf();
  }

  /// Применяет пакет к подтверждённому содержимому; `null` означает, что
  /// пакет несогласуем и выдачу нужно прочитать заново.
  _PackageApplication? _applyPackage(
    IntentionCatalogConfirmedState confirmed,
    _CatalogChangePackage package,
  ) {
    if (package.hasForeignRevision) {
      return null;
    }

    switch (package.revision.compareTo(confirmed.revision)) {
      case GraphRevisionOrder.older || GraphRevisionOrder.same:
        return _PackageApplied(confirmed);
      case GraphRevisionOrder.differentEpoch:
        return null;
      case GraphRevisionOrder.newer:
        break;
    }

    var reconciled = confirmed;
    final mutatedIds = <IntentionId>{};
    for (final mutation in package.mutations) {
      final changedId =
          mutation.after?.summary.id ?? mutation.before?.summary.id;
      if (changedId == null || !mutatedIds.add(changedId)) {
        return null;
      }
      final next = _applyMutationContent(reconciled, mutation);
      if (next == null) {
        return null;
      }
      reconciled = next;
    }

    final absoluteCounts = <IntentionId, RelationCounts>{};
    for (final change in package.countChanges) {
      if (absoluteCounts.containsKey(change.intentionId)) {
        return null;
      }
      absoluteCounts[change.intentionId] = change.counts;
    }
    for (final change in package.dailyChanges) {
      for (final entry in change.intentionCounts.entries) {
        final previous = absoluteCounts[entry.key];
        if (previous != null && previous != entry.value) {
          return null;
        }
        absoluteCounts[entry.key] = entry.value;
      }
    }
    for (final entry in absoluteCounts.entries) {
      reconciled = _applyCountsContent(
        reconciled,
        entry.key,
        entry.value.active,
      );
    }
    for (final renamed in package.renamedTags) {
      reconciled = _applyRenamedTagContent(reconciled, renamed);
    }
    final tagFilter = confirmed.query.tagFilter;
    var opensExcludedMatches = false;
    var removesRequiredTag = false;
    for (final deletedTagId in package.deletedTagIds) {
      reconciled = _applyDeletedTagContent(reconciled, deletedTagId);
      opensExcludedMatches |= tagFilter.excludedTagIds.contains(deletedTagId);
      removesRequiredTag |= tagFilter.requiredTagIds.contains(deletedTagId);
    }

    final content = _withRevision(reconciled, package.revision);
    // Обязательный удалённый тег оставляет выдачу пустой при любых
    // исключениях, поэтому достраивать область не нужно.
    return opensExcludedMatches && !removesRequiredTag
        ? _AreaReconciliationRequired(content)
        : _PackageApplied(content);
  }

  /// Заменяет абсолютное количество активных связей загруженной строки.
  ///
  /// Состав загруженной части, число совпадений и курсор сохраняются:
  /// у намерения вне выдачи нет строки, которую следует заменить.
  IntentionCatalogConfirmedState _applyCountsContent(
    IntentionCatalogConfirmedState confirmed,
    IntentionId intentionId,
    int activeRelationCount,
  ) {
    if (confirmed is! IntentionCatalogLoaded) {
      return confirmed;
    }
    final index = confirmed.items.indexWhere((item) => item.id == intentionId);
    if (index < 0) {
      return confirmed;
    }

    final items = [...confirmed.items];
    items[index] = items[index].withActiveRelationCount(activeRelationCount);
    return IntentionCatalogLoaded(
      selection: confirmed.selection,
      query: confirmed.query,
      items: items,
      totalCount: confirmed.totalCount,
      nextCursor: confirmed.nextCursor,
      revision: confirmed.revision,
      continuation: confirmed.continuation,
    );
  }

  /// Заменяет название переименованного тега в загруженных строках.
  ///
  /// Условия поиска хранят только идентификаторы тегов, поэтому состав
  /// совпадений, порядок, число совпадений и курсор сохраняются.
  IntentionCatalogConfirmedState _applyRenamedTagContent(
    IntentionCatalogConfirmedState confirmed,
    Tag renamed,
  ) {
    if (confirmed is! IntentionCatalogLoaded) {
      return confirmed;
    }
    final items = [
      for (final item in confirmed.items) item.withRenamedTag(renamed),
    ];
    if (items.indexed.every(
      (entry) => identical(entry.$2, confirmed.items[entry.$1]),
    )) {
      return confirmed;
    }
    return IntentionCatalogLoaded(
      selection: confirmed.selection,
      query: confirmed.query,
      items: items,
      totalCount: confirmed.totalCount,
      nextCursor: confirmed.nextCursor,
      revision: confirmed.revision,
      continuation: confirmed.continuation,
    );
  }

  /// Согласует физическое удаление тега с сохранёнными условиями поиска.
  ///
  /// Условие по удалённому идентификатору не снимается. Обязательный тег
  /// больше не назначен ни одному намерению, поэтому выдача становится
  /// успешно пустой без продолжения. Иначе тег исчезает из загруженных
  /// строк; совпадения, открытые удалением исключённого тега, достраивает
  /// согласование загруженной области.
  IntentionCatalogConfirmedState _applyDeletedTagContent(
    IntentionCatalogConfirmedState confirmed,
    TagId deletedTagId,
  ) {
    final tagFilter = confirmed.query.tagFilter;
    if (tagFilter.requiredTagIds.contains(deletedTagId)) {
      return switch (confirmed) {
        IntentionCatalogEmpty() => confirmed,
        IntentionCatalogLoaded() => IntentionCatalogEmpty(
          selection: confirmed.selection,
          query: confirmed.query,
          revision: confirmed.revision,
        ),
      };
    }
    if (confirmed is! IntentionCatalogLoaded) {
      return confirmed;
    }
    final items = [
      for (final item in confirmed.items) item.withoutTag(deletedTagId),
    ];
    if (items.indexed.every(
      (entry) => identical(entry.$2, confirmed.items[entry.$1]),
    )) {
      return confirmed;
    }
    return IntentionCatalogLoaded(
      selection: confirmed.selection,
      query: confirmed.query,
      items: items,
      totalCount: confirmed.totalCount,
      nextCursor: confirmed.nextCursor,
      revision: confirmed.revision,
      continuation: confirmed.continuation,
    );
  }

  /// Фиксирует ревизию применённого пакета даже без затронутых строк.
  ///
  /// Иначе более новое продолжение ждало бы уже полученное завершение.
  IntentionCatalogConfirmedState _withRevision(
    IntentionCatalogConfirmedState confirmed,
    GraphRevision revision,
  ) {
    if (confirmed.revision.compareTo(revision) == GraphRevisionOrder.same) {
      return confirmed;
    }
    return switch (confirmed) {
      IntentionCatalogLoaded(:final items, :final continuation) =>
        IntentionCatalogLoaded(
          selection: confirmed.selection,
          query: confirmed.query,
          items: items,
          totalCount: confirmed.totalCount,
          nextCursor: confirmed.nextCursor,
          revision: revision,
          continuation: continuation,
        ),
      IntentionCatalogEmpty() => IntentionCatalogEmpty(
        selection: confirmed.selection,
        query: confirmed.query,
        revision: revision,
      ),
    };
  }

  IntentionCatalogConfirmedState? _applyMutationContent(
    IntentionCatalogConfirmedState confirmed,
    IntentionCatalogMutation mutation,
  ) {
    final beforeMatches = mutation.before?.matches(confirmed.query) ?? false;
    final afterMatches = mutation.after?.matches(confirmed.query) ?? false;
    final totalCount =
        confirmed.totalCount + (afterMatches ? 1 : 0) - (beforeMatches ? 1 : 0);
    if (totalCount < 0) {
      return null;
    }

    final items = switch (confirmed) {
      IntentionCatalogLoaded(:final items) => [...items],
      IntentionCatalogEmpty() => <IntentionSummary>[],
    };
    final changedId = mutation.after?.summary.id ?? mutation.before!.summary.id;
    items.removeWhere((item) => item.id == changedId);

    final after = mutation.after;
    if (afterMatches &&
        after != null &&
        _belongsToLoadedPrefix(confirmed, after.summary)) {
      items.add(after.summary);
      items.sort(confirmed.query.compare);
    }

    if (totalCount == 0 && items.isEmpty && confirmed.nextCursor == null) {
      return IntentionCatalogEmpty(
        selection: confirmed.selection,
        query: confirmed.query,
        revision: mutation.revision,
      );
    }
    return IntentionCatalogLoaded(
      selection: confirmed.selection,
      query: confirmed.query,
      items: items,
      totalCount: totalCount,
      nextCursor: confirmed.nextCursor,
      revision: mutation.revision,
      continuation: switch (confirmed) {
        IntentionCatalogLoaded(:final continuation) => continuation,
        IntentionCatalogEmpty() => const IntentionCatalogContinuationIdle(),
      },
    );
  }

  bool _belongsToLoadedPrefix(
    IntentionCatalogConfirmedState confirmed,
    IntentionSummary summary,
  ) {
    if (confirmed.nextCursor == null) {
      return true;
    }
    final boundary = _cursorBoundary;
    return boundary != null && confirmed.query.compare(summary, boundary) <= 0;
  }
}

/// Каталожная часть подтверждённого пакета изменений графа.
///
/// Пакет применяется целиком и ровно один раз: каталожные мутации задают
/// состав загруженной части, а абсолютные количества, включая переданные
/// дневной командой, заменяют числа уже загруженных строк. Факт изменения
/// назначения тега намерению сам принадлежность не меняет: её задаёт
/// каталожная мутация того же намерения, поэтому количество изменяется
/// один раз, а факт без такой мутации делает пакет несогласуемым.
/// Переименование тега меняет только его название в загруженных строках,
/// а физическое удаление тега согласуется по сохранённым условиям поиска.
final class _CatalogChangePackage {
  _CatalogChangePackage(this.revision, Iterable<GraphChange> changes)
    : mutations = List.unmodifiable(
        changes.whereType<IntentionCatalogMutation>(),
      ),
      countChanges = List.unmodifiable(
        changes.whereType<IntentionRelationCountsChanged>(),
      ),
      dailyChanges = List.unmodifiable(changes.whereType<DailyChoiceChange>()),
      tagChanges = List.unmodifiable(changes.whereType<TagChange>());

  final GraphRevision revision;
  final List<IntentionCatalogMutation> mutations;
  final List<IntentionRelationCountsChanged> countChanges;
  final List<DailyChoiceChange> dailyChanges;
  final List<TagChange> tagChanges;

  /// Новые названия тегов, переименованных пакетом.
  Iterable<Tag> get renamedTags =>
      tagChanges.whereType<TagRenamedChange>().map((change) => change.after);

  /// Идентификаторы тегов, физически удалённых пакетом.
  Iterable<TagId> get deletedTagIds =>
      tagChanges.whereType<TagDeletedChange>().map((change) => change.tagId);

  bool get hasForeignRevision =>
      mutations.any(_isForeign) ||
      countChanges.any(_isForeign) ||
      dailyChanges.any(_isForeign) ||
      tagChanges.any(_isForeign);

  bool _isForeign(GraphChange change) =>
      change.revision.compareTo(revision) != GraphRevisionOrder.same;
}

/// Итог применения согласуемого пакета к подтверждённому содержимому.
sealed class _PackageApplication {
  const _PackageApplication(this.content);

  final IntentionCatalogConfirmedState content;
}

/// Содержимое целиком согласовано с пакетом.
final class _PackageApplied extends _PackageApplication {
  const _PackageApplied(super.content);
}

/// Сохранённые строки обновлены по известным фактам пакета, но удаление
/// исключённого тега могло открыть совпадения внутри загруженной области:
/// состав и количество согласует чтение недостающих совпадений.
final class _AreaReconciliationRequired extends _PackageApplication {
  const _AreaReconciliationRequired(super.content);
}

/// Согласование загруженной области одного поколения поиска.
final class _AreaReconciliation {
  _AreaReconciliation({required this.generation, required this.content});

  final int generation;

  /// Сохранённое содержимое со всеми применёнными пакетами. Пока
  /// [isConsistent] ложно, состав области и количество ещё не согласованы.
  IntentionCatalogConfirmedState content;
  bool isConsistent = false;
  bool isReading = false;

  /// Последнее чтение отказало; опубликован явный отказ обновления.
  bool isFailed = false;

  /// Пакеты, подтверждённые во время чтения, в порядке получения.
  final packages = <_CatalogChangePackage>[];
}

sealed class _AreaReadOutcome {
  const _AreaReadOutcome();
}

final class _AreaReadCompleted extends _AreaReadOutcome {
  const _AreaReadCompleted(this.candidate);

  final IntentionCatalogConfirmedState candidate;
}

/// Чтение отражает не ревизию сохранённого содержимого: оно повторяется
/// после применения подтверждённых пакетов.
final class _AreaReadStale extends _AreaReadOutcome {
  const _AreaReadStale();
}

/// Безопасно классифицированный отказ чтения: подтверждённое содержимое
/// сохраняется до повтора.
final class _AreaReadFailed extends _AreaReadOutcome {
  const _AreaReadFailed(this.refresh);

  final IntentionCatalogRefreshState refresh;
}

/// Чтение отражает хранилище другой эпохи: выдачу нужно прочитать заново.
final class _AreaReadUnreconcilable extends _AreaReadOutcome {
  const _AreaReadUnreconcilable();
}

final class _PendingCatalogContinuation {
  const _PendingCatalogContinuation({
    required this.generation,
    required this.page,
  });

  final int generation;
  final IntentionCatalogContinuationPage page;
}
