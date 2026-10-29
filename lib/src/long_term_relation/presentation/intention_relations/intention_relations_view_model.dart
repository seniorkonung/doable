import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/details/intention_details_state.dart';
import '../../../intention/presentation/details/intention_details_view_model.dart';
import '../../../intention/presentation/details/intention_page_target.dart';
import '../../application/intention_relation_group.dart';
import '../../application/long_term_relation_projection.dart';
import '../../application/relation_counts.dart';
import '../../application/relation_group_page.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_id.dart';
import '../relation_group_paging.dart';
import '../relation_group_paging_policy.dart';
import '../relation_list_reconciliation.dart';
import 'intention_relations_state.dart';

part 'intention_relations_view_model.g.dart';

/// Порциями получает активные связи группы, выбранной экземпляром страницы.
///
/// Модель живёт, пока её слушают: освобождение отбрасывает строки,
/// продолжения и подписки, а группа остаётся в экземпляре страницы.
/// Согласование с графом ведёт общий слой списков страницы; модель задаёт
/// чтение группы, принадлежность строки и значимые для группы изменения.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose
@riverpod
final class IntentionRelationsViewModel extends _$IntentionRelationsViewModel {
  late IntentionId _intentionId;
  late IntentionPageInstance _pageInstance;
  late PersonalGraphRepository _repository;
  late IntentionRelationGroup _group;
  late RelationListReconciliation<RelationGroupEntry, LongTermRelationId> _list;
  RelationPagingData<RelationGroupEntry>? _published;
  RelationPagingAnchor<LongTermRelationId>? _scrollAnchor;
  LongTermRelationId? _visibleRelationId;

  @override
  IntentionRelationsState build(
    IntentionId intentionId,
    IntentionPageInstance pageInstance,
  ) {
    _intentionId = intentionId;
    _pageInstance = pageInstance;
    _repository = ref.watch(personalGraphRepositoryProvider);
    _group = pageInstance.relationsGroup ??= switch (pageInstance.target) {
      RelationsTarget(:final group?) => group,
      RelationsTarget() ||
      OverviewTarget() ||
      ChoicesTarget() ||
      StatisticsTarget() => _groupByReadiness(intentionId),
    };
    final list = _list = RelationListReconciliation(
      intentionId: intentionId,
      watchIntention: _repository.watchIntention,
      completions: ref
          .watch(graphCommandCoordinatorProvider.notifier)
          .completions,
      policy: ref.watch(relationGroupPagingPolicyProvider),
      query: _query(_group),
      publish: (value) => state = _project(value),
    );
    ref.onDispose(list.dispose);
    return IntentionRelationsInitialLoad(group: _group);
  }

  /// Отбрасывает строки прежней группы и запоминает новую в экземпляре.
  void selectGroup(IntentionRelationGroup group) {
    if (_list.isTerminated || _group == group) return;
    _pageInstance.relationsGroup = group;
    _group = group;
    _list.restart(_query(group));
  }

  /// Повторяет первое чтение группы после устранимого отказа.
  Future<void> retryFirstPage() => _list.retryFirstPage();

  /// Подгружает следующую порцию при приближении к концу загруженной части.
  ///
  /// Пока порция ожидается, повторная прокрутка не отправляет её второй раз.
  Future<void> loadMoreIfNeeded({required int visibleIndex}) =>
      _list.loadMoreIfNeeded(visibleIndex: visibleIndex);

  Future<void> retryLoadMore() => _list.retryLoadMore();

  Future<void> retryRefresh() => _list.retryRefresh();

  /// Запоминает первую видимую строку для восстановления прокрутки после
  /// замены загруженной части на новой ревизии.
  void rememberVisibleRelation(LongTermRelationId relationId) {
    final current = state;
    if (current is IntentionRelationsLoaded &&
        current.items.any((item) => item.relation.id == relationId)) {
      _visibleRelationId = relationId;
    }
  }

  /// Без группы в цели первая модель экземпляра выбирает её по готовности:
  /// неготовому намерению нужны другие, действие нужно другим.
  IntentionRelationGroup _groupByReadiness(IntentionId intentionId) =>
      switch (ref.read(intentionDetailsViewModelProvider(intentionId))) {
        IntentionDetailsLoaded(:final intention) =>
          switch (intention.readiness) {
            IntentionReadiness.notReady => IntentionRelationGroup.needs,
            IntentionReadiness.ready => IntentionRelationGroup.neededFor,
          },
        IntentionDetailsLoading() ||
        IntentionDetailsNotFound() ||
        IntentionDetailsUnavailable() ||
        IntentionDetailsCorruption() ||
        IntentionDetailsUnexpected() ||
        IntentionDetailsDeleted() => throw StateError(
          'Вкладка «Связи» открывается только над полученными подробными '
          'данными намерения.',
        ),
      };

  IntentionRelationsState _project(
    RelationListState<RelationGroupEntry> value,
  ) {
    switch (value) {
      case RelationListInitialLoad():
        _forgetPublished();
        return IntentionRelationsInitialLoad(group: _group);
      case RelationListInitialFailure(:final failure):
        _forgetPublished();
        return IntentionRelationsInitialFailure(
          group: _group,
          failure: failure,
        );
      case RelationListIntentionNotFound():
        _forgetPublished();
        return IntentionRelationsIntentionNotFound(group: _group);
      case RelationListConfirmed(:final data, :final summaryStatus)
          when data.items.isEmpty:
        _rememberPublished(data);
        return IntentionRelationsEmpty(
          group: _group,
          counts: data.counts,
          revision: data.revision,
          summaryStatus: summaryStatus,
        );
      case RelationListConfirmed(
        :final data,
        :final summaryStatus,
        :final progress,
      ):
        _rememberPublished(data);
        return IntentionRelationsLoaded(
          group: _group,
          counts: data.counts,
          revision: data.revision,
          summaryStatus: summaryStatus,
          items: data.items,
          nextCursor: data.nextCursor,
          progress: progress,
          scrollAnchor: _scrollAnchor,
        );
    }
  }

  void _forgetPublished() {
    _published = null;
    _scrollAnchor = null;
    _visibleRelationId = null;
  }

  /// Подгрузка продолжает часть той же ревизии и сохраняет якорь, а замена
  /// на новой ревизии выбирает ближайшую сохранившуюся видимую строку.
  void _rememberPublished(RelationPagingData<RelationGroupEntry> data) {
    final previous = _published;
    _published = data;
    if (previous == null ||
        previous.revision.compareTo(data.revision) == GraphRevisionOrder.same) {
      return;
    }
    final anchor = RelationGroupPaging().chooseAnchor(
      previous: previous.items,
      replacement: data.items,
      visibleId: _visibleRelationId,
      identify: (item) => item.relation.id,
    );
    _visibleRelationId = anchor?.id;
    _scrollAnchor = anchor;
  }

  RelationListQuery<RelationGroupEntry, LongTermRelationId> _query(
    IntentionRelationGroup group,
  ) => RelationListQuery(
    identify: (item) =>
        _belongsToActivePart(item.relation, group) ? item.relation.id : null,
    isSignificant: (change, confirmed) =>
        _isSignificant(change, group, confirmed),
    readPage: (cursor, pageSize) async =>
        switch (await _readPage(group, cursor, pageSize)) {
          GraphResultSuccess(value: final RelationGroupFirstPage page) =>
            GraphResultSuccess(
              RelationPagingFirstPage(
                items: page.items,
                counts: page.counts,
                totalCount: page.counts.forGroup(
                  scope: RelationScope.active,
                  type: group.type,
                  direction: group.direction,
                ),
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

  bool _belongsToActivePart(
    LongTermRelation relation,
    IntentionRelationGroup group,
  ) =>
      relation.scope == RelationScope.active &&
      relation.type == group.type &&
      switch (group.direction) {
        RelationDirection.outgoing =>
          relation.sourceIntentionId == _intentionId,
        RelationDirection.incoming =>
          relation.relatedIntentionId == _intentionId,
      };

  /// Значимы связи, которые входят в активную часть группы, выходят из неё
  /// или меняют в ней приоритет, загруженные связи, владелец и соседи
  /// загруженных строк и сводка намерения, отличная от опубликованной.
  bool _isSignificant(
    GraphChange change,
    IntentionRelationGroup group,
    RelationPagingData<RelationGroupEntry>? confirmed,
  ) {
    final items = confirmed?.items ?? const <RelationGroupEntry>[];
    bool differsFromPublished(RelationCounts counts) =>
        confirmed == null || counts != confirmed.counts;
    switch (change) {
      case IntentionCatalogMutation(:final before, :final after):
        final observedIntentionIds = {
          _intentionId,
          for (final item in items) item.neighbor.id,
        };
        return observedIntentionIds.contains(before?.summary.id) ||
            observedIntentionIds.contains(after?.summary.id);
      case IntentionRelationCountsChanged(:final intentionId, :final counts)
          when intentionId == _intentionId:
        return differsFromPublished(counts);
      case DailyChoiceChange(:final intentionCounts):
        final counts = intentionCounts[_intentionId];
        return counts != null && differsFromPublished(counts);
      case LongTermRelationChange(:final id, :final before, :final after):
        final wasInPart = before != null && _belongsToActivePart(before, group);
        final isInPart = after != null && _belongsToActivePart(after, group);
        return items.any((item) => item.relation.id == id) ||
            wasInPart != isInPart ||
            (wasInPart && before.priority != after?.priority);
      case GraphChange():
        return false;
    }
  }

  Future<RelationGroupPageResult> _readPage(
    IntentionRelationGroup group,
    RelationGroupCursor? cursor,
    int pageSize,
  ) => _repository.getRelationGroupPage(
    RelationGroupQuery(
      intentionId: _intentionId,
      type: group.type,
      direction: group.direction,
      scope: RelationScope.active,
      pageSize: pageSize,
      cursor: cursor,
    ),
  );
}
