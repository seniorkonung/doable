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

/// Порциями получает активные связи группы, выбранной экземпляром страницы,
/// и, пока архив группы раскрыт, её архивированные связи.
///
/// Модель живёт, пока её слушают: освобождение отбрасывает строки,
/// продолжения и подписки, а группа и раскрытие архивов остаются в
/// экземпляре страницы. Согласование с графом ведёт общий слой списков
/// страницы и публикует обе части на одной ревизии; модель задаёт чтение
/// частей группы, принадлежность строки и значимые для группы изменения.
// https://riverpod.dev/docs/concepts2/family
// https://riverpod.dev/docs/concepts2/auto_dispose
@riverpod
final class IntentionRelationsViewModel extends _$IntentionRelationsViewModel {
  late IntentionId _intentionId;
  late PersonalGraphRepository _repository;
  late IntentionRelationsSettings _settings;
  late RelationListReconciliation<
    RelationScope,
    RelationGroupEntry,
    LongTermRelationId
  >
  _list;
  _PublishedRows? _published;
  RelationPagingAnchor<LongTermRelationId>? _scrollAnchor;
  LongTermRelationId? _visibleRelationId;

  @override
  IntentionRelationsState build(
    IntentionId intentionId,
    IntentionPageInstance pageInstance,
  ) {
    _intentionId = intentionId;
    _repository = ref.watch(personalGraphRepositoryProvider);
    _settings = pageInstance.relations ??= _initialSettings(
      intentionId,
      pageInstance.target,
    );
    final list = _list = RelationListReconciliation(
      intentionId: intentionId,
      watchIntention: _repository.watchIntention,
      completions: ref
          .watch(graphCommandCoordinatorProvider.notifier)
          .completions,
      policy: ref.watch(relationGroupPagingPolicyProvider),
      query: _query(),
      publish: (value) => state = _project(value),
    );
    ref.onDispose(list.dispose);
    return IntentionRelationsInitialLoad(group: _settings.group);
  }

  /// Отбрасывает строки прежней группы и запоминает новую в экземпляре.
  /// Раскрытый архив новой группы читается вместе с её активными связями.
  void selectGroup(IntentionRelationGroup group) {
    if (_list.isTerminated || _settings.group == group) return;
    _settings.group = group;
    _list.restart(_query());
  }

  /// Раскрывает архив выбранной группы и получает его первую порцию.
  void expandArchive() {
    if (_list.isTerminated ||
        !_settings.expandedArchives.add(_settings.group)) {
      return;
    }
    _list.reshape(_query());
  }

  /// Сворачивает архив выбранной группы и отбрасывает его строки.
  void collapseArchive() {
    if (_list.isTerminated ||
        !_settings.expandedArchives.remove(_settings.group)) {
      return;
    }
    _list.reshape(_query());
  }

  /// Повторяет первое чтение группы после устранимого отказа.
  Future<void> retryFirstPage() => _list.retryFirstPage();

  /// Подгружает следующую порцию части [scope] при приближении к концу её
  /// загруженных строк.
  ///
  /// Пока порция ожидается, повторная прокрутка не отправляет её второй раз.
  Future<void> loadMoreIfNeeded({
    required RelationScope scope,
    required int visibleIndex,
  }) => _list.loadMoreIfNeeded(part: scope, visibleIndex: visibleIndex);

  Future<void> retryLoadMore({required RelationScope scope}) =>
      _list.retryLoadMore(part: scope);

  Future<void> retryRefresh() => _list.retryRefresh();

  /// Запоминает первую видимую строку любой части для восстановления
  /// прокрутки после замены загруженных частей на новой ревизии.
  void rememberVisibleRelation(LongTermRelationId relationId) {
    if (_published?.rows.any((item) => item.relation.id == relationId) ??
        false) {
      _visibleRelationId = relationId;
    }
  }

  /// Первая модель экземпляра выбирает группу из цели, а без неё — по
  /// готовности: неготовому намерению нужны другие, действие нужно другим.
  /// Архивы всех групп раскрыты только у архивированного намерения.
  IntentionRelationsSettings _initialSettings(
    IntentionId intentionId,
    IntentionPageTarget target,
  ) {
    final intention = switch (ref.read(
      intentionDetailsViewModelProvider(intentionId),
    )) {
      IntentionDetailsLoaded(:final intention) => intention,
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
    return IntentionRelationsSettings(
      group: switch (target) {
        RelationsTarget(:final group?) => group,
        RelationsTarget() ||
        OverviewTarget() ||
        ChoicesTarget() ||
        StatisticsTarget() => switch (intention.readiness) {
          IntentionReadiness.notReady => IntentionRelationGroup.needs,
          IntentionReadiness.ready => IntentionRelationGroup.neededFor,
        },
      },
      expandedArchives: switch (intention.archiveState) {
        IntentionArchiveState.archived => IntentionRelationGroup.values.toSet(),
        IntentionArchiveState.active => const {},
      },
    );
  }

  IntentionRelationsState _project(
    RelationListState<RelationScope, RelationGroupEntry> value,
  ) {
    final group = _settings.group;
    switch (value) {
      case RelationListInitialLoad():
        _forgetPublished();
        return IntentionRelationsInitialLoad(group: group);
      case RelationListInitialFailure(:final failure):
        _forgetPublished();
        return IntentionRelationsInitialFailure(group: group, failure: failure);
      case RelationListIntentionNotFound():
        _forgetPublished();
        return IntentionRelationsIntentionNotFound(group: group);
      case RelationListConfirmed(
        :final parts,
        :final counts,
        :final revision,
        :final summaryStatus,
      ):
        // Активная часть есть в каждом запросе модели.
        final active = parts[RelationScope.active]!;
        final archived = parts[RelationScope.archived];
        _rememberPublished(
          _PublishedRows(revision, [
            ...active.data.items,
            ...?archived?.data.items,
          ]),
        );
        final IntentionRelationsArchive archive;
        if (!_settings.expandedArchives.contains(group)) {
          archive = const IntentionRelationsArchiveFolded();
        } else if (archived == null) {
          archive = const IntentionRelationsArchivePending();
        } else {
          archive = IntentionRelationsArchiveExpanded(
            items: archived.data.items,
            nextCursor: archived.data.nextCursor,
            progress: archived.progress,
          );
        }
        if (active.data.items.isEmpty) {
          return IntentionRelationsEmpty(
            group: group,
            counts: counts,
            revision: revision,
            summaryStatus: summaryStatus,
            archive: archive,
            scrollAnchor: _scrollAnchor,
          );
        }
        return IntentionRelationsLoaded(
          group: group,
          counts: counts,
          revision: revision,
          summaryStatus: summaryStatus,
          items: active.data.items,
          nextCursor: active.data.nextCursor,
          progress: active.progress,
          archive: archive,
          scrollAnchor: _scrollAnchor,
        );
    }
  }

  void _forgetPublished() {
    _published = null;
    _scrollAnchor = null;
    _visibleRelationId = null;
  }

  /// Подгрузка продолжает части той же ревизии и сохраняет якорь, а замена
  /// на новой ревизии выбирает ближайшую сохранившуюся видимую строку обеих
  /// частей: перенесённая между ними связь остаётся якорем.
  void _rememberPublished(_PublishedRows published) {
    final previous = _published;
    _published = published;
    if (previous == null ||
        previous.revision.compareTo(published.revision) ==
            GraphRevisionOrder.same) {
      return;
    }
    final anchor = RelationGroupPaging().chooseAnchor(
      previous: previous.rows,
      replacement: published.rows,
      visibleId: _visibleRelationId,
      identify: (item) => item.relation.id,
    );
    _visibleRelationId = anchor?.id;
    _scrollAnchor = anchor;
  }

  /// Активная часть выбранной группы и, пока её архив раскрыт, архивная.
  RelationListQuery<RelationScope, RelationGroupEntry, LongTermRelationId>
  _query() {
    final group = _settings.group;
    final scopes = {
      RelationScope.active,
      if (_settings.expandedArchives.contains(group)) RelationScope.archived,
    };
    return RelationListQuery(
      parts: {for (final scope in scopes) scope: _partQuery(group, scope)},
      isSignificant: (change, confirmed) =>
          _isSignificant(change, group, scopes, confirmed),
    );
  }

  RelationListPartQuery<RelationGroupEntry, LongTermRelationId> _partQuery(
    IntentionRelationGroup group,
    RelationScope scope,
  ) => RelationListPartQuery(
    identify: (item) => _partOf(item.relation, group, {scope}) == scope
        ? item.relation.id
        : null,
    readPage: (cursor, pageSize) async =>
        switch (await _readPage(group, scope, cursor, pageSize)) {
          GraphResultSuccess(value: final RelationGroupFirstPage page) =>
            GraphResultSuccess(
              RelationPagingFirstPage(
                items: page.items,
                counts: page.counts,
                totalCount: page.counts.forGroup(
                  scope: scope,
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

  /// Часть группы, в которой стоит связь, если эта часть читается.
  RelationScope? _partOf(
    LongTermRelation relation,
    IntentionRelationGroup group,
    Set<RelationScope> scopes,
  ) {
    final isInGroup =
        relation.type == group.type &&
        switch (group.direction) {
          RelationDirection.outgoing =>
            relation.sourceIntentionId == _intentionId,
          RelationDirection.incoming =>
            relation.relatedIntentionId == _intentionId,
        };
    return isInGroup && scopes.contains(relation.scope) ? relation.scope : null;
  }

  /// Значимы связи, которые входят в читаемую часть группы, выходят из неё,
  /// переходят между частями или меняют в части приоритет, загруженные
  /// связи, владелец и соседи загруженных строк и сводка намерения, отличная
  /// от опубликованной.
  bool _isSignificant(
    GraphChange change,
    IntentionRelationGroup group,
    Set<RelationScope> scopes,
    RelationListConfirmed<RelationScope, RelationGroupEntry>? confirmed,
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
        final partBefore = before == null
            ? null
            : _partOf(before, group, scopes);
        final partAfter = after == null ? null : _partOf(after, group, scopes);
        return items.any((item) => item.relation.id == id) ||
            partBefore != partAfter ||
            (partBefore != null && before?.priority != after?.priority);
      case GraphChange():
        return false;
    }
  }

  Future<RelationGroupPageResult> _readPage(
    IntentionRelationGroup group,
    RelationScope scope,
    RelationGroupCursor? cursor,
    int pageSize,
  ) => _repository.getRelationGroupPage(
    RelationGroupQuery(
      intentionId: _intentionId,
      type: group.type,
      direction: group.direction,
      scope: scope,
      pageSize: pageSize,
      cursor: cursor,
    ),
  );
}

/// Строки обеих частей в порядке показа на их общей ревизии.
final class _PublishedRows {
  const _PublishedRows(this.revision, this.rows);

  final GraphRevision revision;
  final List<RelationGroupEntry> rows;
}
