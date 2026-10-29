import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/details/intention_page_target.dart';
import '../../../long_term_relation/application/relation_counts.dart';
import '../../../long_term_relation/application/relation_group_page.dart';
import '../../../long_term_relation/presentation/relation_group_paging.dart';
import '../../../long_term_relation/presentation/relation_group_paging_policy.dart';
import '../../../long_term_relation/presentation/relation_list_reconciliation.dart';
import '../../application/daily_choice_catalog.dart';
import '../../domain/daily_choice_id.dart';
import 'intention_choices_state.dart';

part 'intention_choices_view_model.g.dart';

/// Порциями получает прямые дневные выборы намерения в роли, сохранённой
/// экземпляром страницы.
///
/// Модель живёт, пока её слушают: освобождение отбрасывает строки,
/// продолжения и подписки, а роль остаётся в экземпляре страницы.
/// Согласование с графом ведёт общий слой списков страницы; модель задаёт
/// чтение роли, принадлежность строки и значимые для роли изменения.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose
@riverpod
final class IntentionChoicesViewModel extends _$IntentionChoicesViewModel {
  late IntentionId _intentionId;
  late IntentionPageInstance _pageInstance;
  late PersonalGraphRepository _repository;
  late DailyChoiceRelationRole _role;
  late RelationListReconciliation<
    DailyChoiceRelationRole,
    DailyChoiceCatalogItem,
    DailyChoiceId
  >
  _list;

  @override
  IntentionChoicesState build(
    IntentionId intentionId,
    IntentionPageInstance pageInstance,
  ) {
    _intentionId = intentionId;
    _pageInstance = pageInstance;
    _repository = ref.watch(personalGraphRepositoryProvider);
    _role = pageInstance.choicesRole;
    final list = _list = RelationListReconciliation(
      intentionId: intentionId,
      watchIntention: _repository.watchIntention,
      completions: ref
          .watch(graphCommandCoordinatorProvider.notifier)
          .completions,
      policy: ref.watch(relationGroupPagingPolicyProvider),
      query: _query(_role),
      publish: (value) => state = _project(value),
    );
    ref.onDispose(list.dispose);
    return IntentionChoicesInitialLoad(role: _role);
  }

  /// Отбрасывает строки прежней роли и запоминает новую в экземпляре.
  void selectRole(DailyChoiceRelationRole role) {
    if (_list.isTerminated || _role == role) return;
    _pageInstance.choicesRole = role;
    _role = role;
    _list.restart(_query(role));
  }

  /// Повторяет первое чтение роли после устранимого отказа.
  Future<void> retryFirstPage() => _list.retryFirstPage();

  /// Подгружает следующую порцию при приближении к концу загруженной части.
  ///
  /// Пока порция ожидается, повторная прокрутка не отправляет её второй раз.
  Future<void> loadMoreIfNeeded({required int visibleIndex}) =>
      _list.loadMoreIfNeeded(part: _role, visibleIndex: visibleIndex);

  Future<void> retryLoadMore() => _list.retryLoadMore(part: _role);

  Future<void> retryRefresh() => _list.retryRefresh();

  /// Список выбранной роли — форма из одной части.
  IntentionChoicesState _project(
    RelationListState<DailyChoiceRelationRole, DailyChoiceCatalogItem> value,
  ) {
    switch (value) {
      case RelationListInitialLoad():
        return IntentionChoicesInitialLoad(role: _role);
      case RelationListInitialFailure(:final failure):
        return IntentionChoicesInitialFailure(role: _role, failure: failure);
      case RelationListIntentionNotFound():
        return IntentionChoicesIntentionNotFound(role: _role);
      case RelationListConfirmed(
        :final parts,
        :final counts,
        :final revision,
        :final summaryStatus,
      ):
        final part = parts[_role]!;
        if (part.data.items.isEmpty) {
          return IntentionChoicesEmpty(
            role: _role,
            counts: counts,
            revision: revision,
            summaryStatus: summaryStatus,
          );
        }
        return IntentionChoicesLoaded(
          role: _role,
          counts: counts,
          revision: revision,
          summaryStatus: summaryStatus,
          items: part.data.items,
          nextCursor: part.data.nextCursor,
          progress: part.progress,
        );
    }
  }

  RelationListQuery<
    DailyChoiceRelationRole,
    DailyChoiceCatalogItem,
    DailyChoiceId
  >
  _query(DailyChoiceRelationRole role) => RelationListQuery(
    parts: {role: _partQuery(role)},
    isSignificant: (change, confirmed) =>
        _isSignificant(change, role, confirmed),
  );

  RelationListPartQuery<DailyChoiceCatalogItem, DailyChoiceId> _partQuery(
    DailyChoiceRelationRole role,
  ) => RelationListPartQuery(
    identify: (item) => _belongsToRole(item, role) ? item.id : null,
    readPage: (cursor, pageSize) async => switch (await _readPage(
      role,
      cursor,
      pageSize,
    )) {
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

  /// Значимы выборы своей роли и загруженные, их участники и сводка
  /// намерения, которая отличается от опубликованной.
  bool _isSignificant(
    GraphChange change,
    DailyChoiceRelationRole role,
    RelationListConfirmed<DailyChoiceRelationRole, DailyChoiceCatalogItem>?
    confirmed,
  ) {
    final items = confirmed?.items ?? const <DailyChoiceCatalogItem>[];
    bool differsFromPublished(RelationCounts counts) =>
        confirmed == null || counts != confirmed.counts;
    switch (change) {
      case IntentionCatalogMutation(:final before, :final after):
        final observedIntentionIds = {
          _intentionId,
          for (final item in items) ...[item.source.id, item.selected.id],
        };
        return observedIntentionIds.contains(before?.summary.id) ||
            observedIntentionIds.contains(after?.summary.id);
      case IntentionRelationCountsChanged(:final intentionId, :final counts)
          when intentionId == _intentionId:
        return differsFromPublished(counts);
      case DailyChoiceChange(
        :final intentionCounts,
        :final before,
        :final after,
      ):
        final counts = intentionCounts[_intentionId];
        final affectsRole = switch (role) {
          DailyChoiceRelationRole.source =>
            before?.sourceIntentionId == _intentionId ||
                after?.sourceIntentionId == _intentionId,
          DailyChoiceRelationRole.selected =>
            before?.selectedIntentionId == _intentionId ||
                after?.selectedIntentionId == _intentionId,
        };
        final changedId = after?.id ?? before?.id;
        return affectsRole ||
            items.any((item) => item.id == changedId) ||
            (counts != null && differsFromPublished(counts));
      case GraphChange():
        return false;
    }
  }

  Future<RelationGroupPageResult> _readPage(
    DailyChoiceRelationRole role,
    RelationGroupCursor? cursor,
    int pageSize,
  ) => _repository.getRelationGroupPage(
    DailyChoiceGroupQuery(
      intentionId: _intentionId,
      role: role,
      pageSize: pageSize,
      cursor: cursor,
    ),
  );
}
