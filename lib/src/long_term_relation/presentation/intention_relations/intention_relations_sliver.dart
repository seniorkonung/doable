import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/count_tiles.dart';
import '../../../design_system/components/relation_row.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../intention/application/intention_details.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/details/intention_page_target.dart';
import '../../application/intention_relation_group.dart';
import '../../application/long_term_relation_projection.dart';
import '../../application/relation_counts.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_id.dart';
import '../relation_list_reconciliation.dart';
import '../relation_list_status.dart';
import 'intention_relations_state.dart';
import 'intention_relations_view_model.dart';

/// Вкладка «Связи» страницы намерения: плитки четырёх групп и порционный
/// список активных связей выбранной группы.
///
/// Единственный sliver сохраняет ленивое построение строк внутри общего
/// scrollable страницы, а подгрузка следует за построенными строками.
final class IntentionRelationsSliver extends ConsumerStatefulWidget {
  const IntentionRelationsSliver({
    required this.details,
    required this.pageInstance,
    required this.onOpenRelation,
    required this.onWalk,
    super.key,
  });

  /// Подробные данные намерения страницы: строка группы владельца не несёт,
  /// а их сводка даёт числа плиток до первой публикации модели.
  final IntentionDetails details;
  final IntentionPageInstance pageInstance;

  /// Открывает подробные данные связи; маршрут выбирает страница.
  final ValueChanged<LongTermRelationId> onOpenRelation;

  /// Открывает страницу соседа на группе, в которой стоит строка.
  final void Function(IntentionId neighborId, IntentionRelationGroup group)
  onWalk;

  Intention get owner => details.intention;

  @override
  ConsumerState<IntentionRelationsSliver> createState() =>
      _IntentionRelationsSliverState();
}

final class _IntentionRelationsSliverState
    extends ConsumerState<IntentionRelationsSliver> {
  final _rowKeys = <LongTermRelationId, GlobalKey>{};
  ScrollPosition? _scrollPosition;
  var _captureScheduled = false;
  int? _scheduledLoadMoreIndex;

  IntentionRelationsViewModelProvider get _provider =>
      intentionRelationsViewModelProvider(widget.owner.id, widget.pageInstance);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextPosition = Scrollable.maybeOf(context)?.position;
    if (identical(nextPosition, _scrollPosition)) {
      return;
    }
    _scrollPosition?.isScrollingNotifier.removeListener(
      _captureVisibleRelationAfterScroll,
    );
    _scrollPosition = nextPosition;
    _scrollPosition?.isScrollingNotifier.addListener(
      _captureVisibleRelationAfterScroll,
    );
  }

  @override
  void dispose() {
    _scrollPosition?.isScrollingNotifier.removeListener(
      _captureVisibleRelationAfterScroll,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final state = ref.watch(provider);
    // При повторном показе вкладки позицию задаёт страница. Здесь нужны
    // только новые якоря согласования уже открытого списка.
    // https://pub.dev/documentation/flutter_riverpod/3.4.2/flutter_riverpod/WidgetRef/listen.html
    ref.listen(provider, _scheduleAnchorRestoration);
    final viewModel = ref.read(provider.notifier);
    _retainRowKeys(state);
    _scheduleVisibleRelationCapture();

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              DoableMetrics.space5,
              DoableMetrics.space2,
              DoableMetrics.space5,
              DoableMetrics.space2,
            ),
            child: _GroupTiles(
              counts: switch (state) {
                IntentionRelationsConfirmed(:final counts) => counts,
                IntentionRelationsInitialLoad() ||
                IntentionRelationsInitialFailure() ||
                IntentionRelationsIntentionNotFound() =>
                  widget.details.relationCounts,
              },
              selected: state.group,
              onSelect: viewModel.selectGroup,
            ),
          );
        }
        return _buildBodyChild(context, state, index - 1, viewModel);
      }, childCount: _bodyChildCount(state) + 1),
    );
  }

  int _bodyChildCount(IntentionRelationsState state) => switch (state) {
    IntentionRelationsLoaded(:final items) => items.length + 1,
    IntentionRelationsInitialLoad() ||
    IntentionRelationsInitialFailure() ||
    IntentionRelationsIntentionNotFound() ||
    IntentionRelationsEmpty() => 1,
  };

  Widget _buildBodyChild(
    BuildContext context,
    IntentionRelationsState state,
    int index,
    IntentionRelationsViewModel viewModel,
  ) {
    final localizations = AppLocalizations.of(context);
    return switch (state) {
      IntentionRelationsInitialLoad() => RelationListStatus.initialLoad(
        localizations,
      ),
      final IntentionRelationsInitialFailure failure =>
        RelationListStatus.initialFailure(
          localizations,
          failure: failure.failure,
          onRetry: viewModel.retryFirstPage,
        ),
      IntentionRelationsIntentionNotFound() =>
        RelationListStatus.intentionNotFound(localizations),
      final IntentionRelationsEmpty empty => _EmptyGroup(
        summaryStatus: empty.summaryStatus,
        onRetryRefresh: viewModel.retryRefresh,
      ),
      final IntentionRelationsLoaded loaded when index < loaded.items.length =>
        _buildRow(loaded, index, viewModel),
      final IntentionRelationsLoaded loaded => _LoadedGroupFooter(
        state: loaded,
        onRetryLoadMore: loaded.summaryStatus is RelationListSummaryCurrent
            ? () => viewModel.retryLoadMore(scope: RelationScope.active)
            : null,
        onRetryRefresh: viewModel.retryRefresh,
      ),
    };
  }

  Widget _buildRow(
    IntentionRelationsLoaded state,
    int index,
    IntentionRelationsViewModel viewModel,
  ) {
    _scheduleLoadMore(index, viewModel);
    final item = state.items[index];
    final relationId = item.relation.id;
    return Padding(
      key: _rowKeys.putIfAbsent(relationId, GlobalKey.new),
      padding: const EdgeInsets.fromLTRB(
        DoableMetrics.space5,
        0,
        DoableMetrics.space5,
        DoableMetrics.space2,
      ),
      child: _GroupRow(
        key: ValueKey(
          'intention-relations-row-${relationId.toCanonicalString()}',
        ),
        item: item,
        owner: widget.owner,
        onOpen: () => widget.onOpenRelation(relationId),
        onWalk: () => widget.onWalk(item.neighbor.id, state.group),
      ),
    );
  }

  void _scheduleLoadMore(
    int visibleIndex,
    IntentionRelationsViewModel viewModel,
  ) {
    if (_scheduledLoadMoreIndex == visibleIndex) {
      return;
    }
    _scheduledLoadMoreIndex = visibleIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scheduledLoadMoreIndex = null;
      unawaited(
        viewModel.loadMoreIfNeeded(
          scope: RelationScope.active,
          visibleIndex: visibleIndex,
        ),
      );
    });
  }

  void _retainRowKeys(IntentionRelationsState state) {
    final retained = switch (state) {
      IntentionRelationsLoaded(:final items) => {
        for (final item in items) item.relation.id,
      },
      IntentionRelationsInitialLoad() ||
      IntentionRelationsInitialFailure() ||
      IntentionRelationsIntentionNotFound() ||
      IntentionRelationsEmpty() => <LongTermRelationId>{},
    };
    _rowKeys.removeWhere((id, _) => !retained.contains(id));
  }

  void _captureVisibleRelationAfterScroll() {
    if (!(_scrollPosition?.isScrollingNotifier.value ?? false)) {
      _scheduleVisibleRelationCapture();
    }
  }

  /// Запоминает первую строку, видимую под закреплёнными вкладками.
  ///
  /// Смещение, которое открывает строку, уже учитывает закреплённые перед
  /// ней sliver'ы: строка с таким смещением стоит сразу под вкладками.
  /// https://api.flutter.dev/flutter/rendering/RenderViewportBase/maxScrollObstructionExtentBefore.html
  void _scheduleVisibleRelationCapture() {
    if (_captureScheduled || !mounted || _rowKeys.isEmpty) {
      return;
    }
    _captureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureScheduled = false;
      if (!mounted) {
        return;
      }
      final position = _scrollPosition;
      if (position == null || !position.hasPixels) {
        return;
      }
      LongTermRelationId? firstVisible;
      double? firstOffset;
      for (final entry in _rowKeys.entries) {
        final renderObject = entry.value.currentContext?.findRenderObject();
        if (renderObject is! RenderBox || !renderObject.attached) {
          continue;
        }
        final viewport = RenderAbstractViewport.maybeOf(renderObject);
        if (viewport == null) {
          continue;
        }
        final offset = viewport.getOffsetToReveal(renderObject, 0).offset;
        final end = offset + renderObject.size.height;
        final viewportEnd = position.pixels + position.viewportDimension;
        if (end <= position.pixels || offset >= viewportEnd) {
          continue;
        }
        if (firstOffset == null || offset < firstOffset) {
          firstOffset = offset;
          firstVisible = entry.key;
        }
      }
      if (firstVisible != null) {
        ref.read(_provider.notifier).rememberVisibleRelation(firstVisible);
      }
    });
  }

  void _scheduleAnchorRestoration(
    IntentionRelationsState? previous,
    IntentionRelationsState state,
  ) {
    final anchor = switch (state) {
      IntentionRelationsConfirmed(:final scrollAnchor) => scrollAnchor,
      IntentionRelationsInitialLoad() ||
      IntentionRelationsInitialFailure() ||
      IntentionRelationsIntentionNotFound() => null,
    };
    final previousAnchor = switch (previous) {
      IntentionRelationsConfirmed(:final scrollAnchor) => scrollAnchor,
      _ => null,
    };
    if (anchor == null || identical(anchor, previousAnchor)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final rowContext = _rowKeys[anchor.id]?.currentContext;
      if (rowContext != null) {
        // Строка встаёт сразу под закреплёнными вкладками, а не под них.
        unawaited(
          Scrollable.ensureVisible(
            rowContext,
            alignment: 0,
            duration: Duration.zero,
          ),
        );
      }
    });
  }
}

/// Четыре группы связей в две колонки: исходящие сверху, входящие снизу.
final class _GroupTiles extends StatelessWidget {
  const _GroupTiles({
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final RelationCounts counts;
  final IntentionRelationGroup selected;
  final ValueChanged<IntentionRelationGroup> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CountTiles<IntentionRelationGroup>(
      columns: CountTileColumns.two,
      value: selected,
      onPick: onSelect,
      label: l10n.detailsRelationsGroupsLabel,
      tiles: [
        for (final group in IntentionRelationGroup.values) _tile(l10n, group),
      ],
    );
  }

  CountTile<IntentionRelationGroup> _tile(
    AppLocalizations l10n,
    IntentionRelationGroup group,
  ) {
    final name = switch (group) {
      IntentionRelationGroup.needs => l10n.detailsRelationsGroupNeeds,
      IntentionRelationGroup.canUse => l10n.detailsRelationsGroupCanUse,
      IntentionRelationGroup.neededFor => l10n.detailsRelationsGroupNeededFor,
      IntentionRelationGroup.canBeUsedFor =>
        l10n.detailsRelationsGroupCanBeUsedFor,
    };
    int countIn(RelationScope scope) => counts.forGroup(
      scope: scope,
      type: group.type,
      direction: group.direction,
    );
    final active = countIn(RelationScope.active);
    final archived = countIn(RelationScope.archived) > 0;
    return CountTile(
      key: ValueKey('intention-relations-group-${group.name}'),
      id: group,
      count: active,
      name: name,
      semanticLabel: archived
          ? l10n.detailsRelationsGroupTileArchivedSemantic(name, active)
          : l10n.detailsRelationsGroupTileSemantic(name, active),
      archived: archived,
      glyph: CountTileGlyph(
        kind: switch (group.type) {
          LongTermRelationType.need => CountTileGlyphKind.need,
          LongTermRelationType.can => CountTileGlyphKind.can,
        },
        direction: switch (group.direction) {
          RelationDirection.outgoing => CountTileGlyphDirection.fromIntention,
          RelationDirection.incoming => CountTileGlyphDirection.toIntention,
        },
      ),
    );
  }
}

/// Строка связи группы: сосед с отметками, тип и приоритет словами и начало
/// описания связи.
final class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.item,
    required this.owner,
    required this.onOpen,
    required this.onWalk,
    super.key,
  });

  final RelationGroupEntry item;
  final Intention owner;
  final VoidCallback onOpen;
  final VoidCallback onWalk;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final relation = item.relation;
    final neighbor = item.neighbor;
    final priority = switch (relation.priority) {
      RelationPriority.p1 => 'P1',
      RelationPriority.p2 => 'P2',
      RelationPriority.p3 => 'P3',
      RelationPriority.p4 => 'P4',
    };
    // Формулировка сохраняет смысловое направление связи: исходный участник
    // стоит первым и во входящей группе.
    final (source, related) = relation.sourceIntentionId == owner.id
        ? (owner.title, neighbor.title)
        : (neighbor.title, owner.title);
    final archived = relation.scope == RelationScope.archived;
    final neighborArchived =
        neighbor.archiveState == IntentionArchiveState.archived;
    final isAction = neighbor.readiness == IntentionReadiness.ready;
    final note = item.descriptionPreview?.text;
    return RelationRow(
      kind: switch (relation.type) {
        LongTermRelationType.need => RelationRowKind.need,
        LongTermRelationType.can => RelationRowKind.can,
      },
      priority: switch (relation.priority) {
        RelationPriority.p1 => RelationRowPriority.p1,
        RelationPriority.p2 => RelationRowPriority.p2,
        RelationPriority.p3 => RelationRowPriority.p3,
        RelationPriority.p4 => RelationRowPriority.p4,
      },
      label: switch (relation.type) {
        LongTermRelationType.need => l10n.detailsRelationsRowNeed(priority),
        LongTermRelationType.can => l10n.detailsRelationsRowCan(priority),
      },
      name: neighbor.title,
      note: note,
      action: isAction,
      archived: archived,
      intentionArchived: neighborArchived,
      semanticLabel: [
        switch (relation.type) {
          LongTermRelationType.need => l10n.relationNeighborhoodNeedPhrase(
            source,
            related,
          ),
          LongTermRelationType.can => l10n.relationNeighborhoodCanPhrase(
            source,
            related,
          ),
        },
        l10n.relationNeighborhoodPriority(priority),
        if (archived) l10n.relationNeighborhoodRelationArchived,
        if (neighborArchived)
          l10n.detailsRelationsNeighborArchived(neighbor.title),
        ?note,
      ].join('. '),
      walkLabel: isAction
          ? l10n.detailsRelationsWalkAction(neighbor.title)
          : l10n.detailsRelationsWalkIntention(neighbor.title),
      onOpen: onOpen,
      onWalk: onWalk,
    );
  }
}

final class _EmptyGroup extends StatelessWidget {
  const _EmptyGroup({
    required this.summaryStatus,
    required this.onRetryRefresh,
  });

  final RelationListSummaryStatus summaryStatus;
  final Future<void> Function() onRetryRefresh;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      children: [
        RelationListStatus(message: localizations.relationNeighborhoodEmpty),
        if (summaryStatus is RelationListSummaryRefreshing)
          RelationListStatus.refreshing(localizations),
        if (summaryStatus case final RelationListSummaryRefreshFailure refresh)
          RelationListStatus.refreshFailure(
            localizations,
            failure: refresh.failure,
            onRetry: onRetryRefresh,
          ),
      ],
    );
  }
}

final class _LoadedGroupFooter extends StatelessWidget {
  const _LoadedGroupFooter({
    required this.state,
    required this.onRetryLoadMore,
    required this.onRetryRefresh,
  });

  final IntentionRelationsLoaded state;
  final Future<void> Function()? onRetryLoadMore;
  final Future<void> Function() onRetryRefresh;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return switch ((state.progress, state.summaryStatus)) {
      (RelationListLoadingMore(), _) => RelationListStatus.loadingMore(
        localizations,
      ),
      (final RelationListLoadMoreFailure failure, _) =>
        RelationListStatus.loadMoreFailure(
          localizations,
          failure: failure.failure,
          onRetry: onRetryLoadMore,
        ),
      (RelationListIdle(), RelationListSummaryRefreshing()) =>
        RelationListStatus.refreshing(localizations),
      (RelationListIdle(), final RelationListSummaryRefreshFailure refresh) =>
        RelationListStatus.refreshFailure(
          localizations,
          failure: refresh.failure,
          onRetry: onRetryRefresh,
        ),
      (RelationListIdle(), RelationListSummaryCurrent()) =>
        state.hasConfirmedEnd
            ? RelationListStatus.confirmedEnd(localizations)
            : const SizedBox(height: DoableMetrics.space4),
    };
  }
}
