import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/intention_summary_view.dart';
import '../../application/long_term_relation_projection.dart';
import '../../application/relation_counts.dart';
import '../../application/relation_group_page.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_id.dart';
import 'blocking_relations_selection_state.dart';
import 'blocking_relations_selection_view_model.dart';
import 'relation_neighborhood_state.dart';
import 'relation_neighborhood_view_model.dart';

/// Порционное соседство и полная сводка на странице намерения.
///
/// Единственный sliver сохраняет ленивое построение строк внутри общего
/// scrollable страницы. Содержимое невыбранных групп не запрашивается.
final class RelationNeighborhoodSliver extends ConsumerStatefulWidget {
  const RelationNeighborhoodSliver({
    required this.intentionId,
    required this.onOpenRelation,
    required this.onCreateRelation,
    this.selectionMode = false,
    super.key,
  });

  final IntentionId intentionId;

  /// Открывает подробные данные выбранной связи; маршрут выбирает страница.
  final ValueChanged<LongTermRelationId> onOpenRelation;

  /// Открывает создание связи в направлении выбранной группы соседства.
  final ValueChanged<RelationDirection> onCreateRelation;

  /// Показывает явный выбор блокирующих связей в текущих порциях соседства.
  final bool selectionMode;

  @override
  ConsumerState<RelationNeighborhoodSliver> createState() =>
      _RelationNeighborhoodSliverState();
}

final class _RelationNeighborhoodSliverState
    extends ConsumerState<RelationNeighborhoodSliver> {
  final _rowKeys = <LongTermRelationId, GlobalKey>{};
  ScrollPosition? _scrollPosition;
  RelationGroupScrollAnchor? _restoredAnchor;
  var _captureScheduled = false;
  int? _scheduledLoadMoreIndex;

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
    final provider = relationNeighborhoodViewModelProvider(widget.intentionId);
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);
    final selection = widget.selectionMode
        ? ref.watch(
            blockingRelationsSelectionViewModelProvider(widget.intentionId),
          )
        : null;
    final summaryStatus = state is RelationGroupConfirmedState
        ? state.summaryStatus
        : null;
    final onRetryRefresh =
        summaryStatus is RelationSummaryRefreshFailure && summaryStatus.canRetry
        ? viewModel.retryRefresh
        : null;
    _retainRowKeys(state);
    _scheduleAnchorRestoration(state);
    _scheduleVisibleRelationCapture();

    final bodyChildCount = _bodyChildCount(state);
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index == 0) {
          return _NeighborhoodHeader(
            state: state,
            onSelectGroup: viewModel.selectGroup,
            onSelectScope: viewModel.selectScope,
            onSelectType: viewModel.selectType,
            onSelectDirection: viewModel.selectDirection,
            onCreateRelation: widget.onCreateRelation,
            onRetryRefresh: onRetryRefresh,
            selectedCount: selection?.selected.length,
          );
        }
        return _buildBodyChild(context, state, index - 1, viewModel, selection);
      }, childCount: bodyChildCount + 1),
    );
  }

  int _bodyChildCount(RelationNeighborhoodState state) => switch (state) {
    RelationGroupLoaded(:final items) => items.length + 1,
    RelationGroupInitialLoad() ||
    RelationGroupInitialFailure() ||
    RelationNeighborhoodIntentionNotFound() ||
    RelationGroupEmpty() => 1,
  };

  Widget _buildBodyChild(
    BuildContext context,
    RelationNeighborhoodState state,
    int index,
    RelationNeighborhoodViewModel viewModel,
    BlockingRelationsSelectionState? selection,
  ) => switch (state) {
    RelationGroupInitialLoad() => const SizedBox(height: 16),
    final RelationGroupInitialFailure failure => _InitialFailure(
      failure: failure,
      onRetry: failure.canRetry ? viewModel.retryFirstPage : null,
    ),
    RelationNeighborhoodIntentionNotFound() => _NeighborhoodStatus(
      message: AppLocalizations.of(context)
          .relationNeighborhoodIntentionNotFound,
    ),
    final RelationGroupEmpty empty => _EmptyGroup(
      state: empty,
      onRetryRefresh:
          empty.summaryStatus is RelationSummaryRefreshFailure &&
              (empty.summaryStatus as RelationSummaryRefreshFailure).canRetry
          ? viewModel.retryRefresh
          : null,
    ),
    final RelationGroupLoaded loaded when index < loaded.items.length =>
      _buildRelationRow(loaded, index, viewModel, selection),
    final RelationGroupLoaded loaded => _LoadedGroupFooter(
      state: loaded,
      onRetryLoadMore:
          loaded.progress is RelationGroupLoadMoreFailure &&
              (loaded.progress as RelationGroupLoadMoreFailure).canRetry &&
              loaded.summaryFreshness == RelationSummaryFreshness.current
          ? viewModel.retryLoadMore
          : null,
      onRetryRefresh:
          loaded.summaryStatus is RelationSummaryRefreshFailure &&
              (loaded.summaryStatus as RelationSummaryRefreshFailure).canRetry
          ? viewModel.retryRefresh
          : null,
    ),
  };

  Widget _buildRelationRow(
    RelationGroupLoaded state,
    int index,
    RelationNeighborhoodViewModel viewModel,
    BlockingRelationsSelectionState? selection,
  ) {
    _scheduleLoadMore(index, viewModel);
    final item = state.items[index];
    final key = _rowKeys.putIfAbsent(item.relation.id, GlobalKey.new);
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _RelationRow(
        key: ValueKey(
          'relation-neighborhood-row-${item.relation.id.toCanonicalString()}',
        ),
        item: item,
        onOpen: widget.onOpenRelation,
        direction: state.selection.direction,
        isSelected: selection?.selected.containsKey(item.relation.id),
        onToggleSelection: selection is BlockingRelationsSelectionEditing
            ? () {
                final editor = ref.read(
                  blockingRelationsSelectionViewModelProvider(
                    widget.intentionId,
                  ).notifier,
                );
                if (selection.selected.containsKey(item.relation.id)) {
                  editor.unselect(item.relation.id);
                } else {
                  editor.select(item);
                }
              }
            : null,
      ),
    );
  }

  void _scheduleLoadMore(
    int visibleIndex,
    RelationNeighborhoodViewModel viewModel,
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
      unawaited(viewModel.loadMoreIfNeeded(visibleIndex: visibleIndex));
    });
  }

  void _retainRowKeys(RelationNeighborhoodState state) {
    final retained = switch (state) {
      RelationGroupLoaded(:final items) => {
        for (final item in items) item.relation.id,
      },
      RelationGroupInitialLoad() ||
      RelationGroupInitialFailure() ||
      RelationNeighborhoodIntentionNotFound() ||
      RelationGroupEmpty() => <LongTermRelationId>{},
    };
    _rowKeys.removeWhere((id, _) => !retained.contains(id));
  }

  void _captureVisibleRelationAfterScroll() {
    if (!(_scrollPosition?.isScrollingNotifier.value ?? false)) {
      _scheduleVisibleRelationCapture();
    }
  }

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
        ref
            .read(
              relationNeighborhoodViewModelProvider(widget.intentionId)
                  .notifier,
            )
            .rememberVisibleRelation(firstVisible);
      }
    });
  }

  void _scheduleAnchorRestoration(RelationNeighborhoodState state) {
    final anchor = switch (state) {
      RelationGroupConfirmedState(:final scrollAnchor) => scrollAnchor,
      RelationGroupInitialLoad() ||
      RelationGroupInitialFailure() ||
      RelationNeighborhoodIntentionNotFound() => null,
    };
    if (anchor == null || identical(anchor, _restoredAnchor)) {
      return;
    }
    _restoredAnchor = anchor;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final rowContext = _rowKeys[anchor.relationId]?.currentContext;
      if (rowContext != null) {
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

final class _NeighborhoodHeader extends StatelessWidget {
  const _NeighborhoodHeader({
    required this.state,
    required this.onSelectGroup,
    required this.onSelectScope,
    required this.onSelectType,
    required this.onSelectDirection,
    required this.onCreateRelation,
    required this.onRetryRefresh,
    this.selectedCount,
  });

  final RelationNeighborhoodState state;
  final ValueChanged<RelationGroupSelection> onSelectGroup;
  final ValueChanged<RelationScope> onSelectScope;
  final ValueChanged<LongTermRelationType> onSelectType;
  final ValueChanged<RelationDirection> onSelectDirection;
  final ValueChanged<RelationDirection> onCreateRelation;
  final Future<void> Function()? onRetryRefresh;
  final int? selectedCount;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final confirmed = state is RelationGroupConfirmedState
        ? state as RelationGroupConfirmedState
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        key: const ValueKey('relation-neighborhood-summary'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              localizations.relationNeighborhoodTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 12),
          if (selectedCount case final count?) ...[
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                localizations.relationNeighborhoodSelectedCount(count),
                key: const ValueKey('relation-neighborhood-selected-count'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (confirmed case final value?)
            _RelationSummary(
              counts: value.counts,
              selection: state.selection,
              freshness: value.summaryFreshness,
              onSelectGroup: onSelectGroup,
              onRetryRefresh: onRetryRefresh,
            )
          else
            _NeighborhoodStatus(
              message: state is RelationGroupInitialLoad
                  ? localizations.relationNeighborhoodSummaryLoading
                  : localizations.relationNeighborhoodSummaryUnavailable,
              progressIndicator: state is RelationGroupInitialLoad,
              padding: EdgeInsets.zero,
            ),
          const SizedBox(height: 20),
          _SelectionControls(
            selection: state.selection,
            counts: confirmed?.counts,
            onSelectScope: onSelectScope,
            onSelectType: onSelectType,
            onSelectDirection: onSelectDirection,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              key: const ValueKey('relation-neighborhood-create-relation'),
              onPressed: () => onCreateRelation(state.selection.direction),
              icon: const Icon(Icons.add_link),
              label: Text(switch (state.selection.direction) {
                RelationDirection.outgoing =>
                  localizations.relationNeighborhoodCreateOutgoingAction,
                RelationDirection.incoming =>
                  localizations.relationNeighborhoodCreateIncomingAction,
              }),
            ),
          ),
        ],
      ),
    );
  }
}

final class _RelationSummary extends StatelessWidget {
  const _RelationSummary({
    required this.counts,
    required this.selection,
    required this.freshness,
    required this.onSelectGroup,
    required this.onRetryRefresh,
  });

  final RelationCounts counts;
  final RelationGroupSelection selection;
  final RelationSummaryFreshness freshness;
  final ValueChanged<RelationGroupSelection> onSelectGroup;
  final Future<void> Function()? onRetryRefresh;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final totalLabel = localizations.relationNeighborhoodTotal(counts.total);
    final activeLabel = localizations.relationNeighborhoodActiveTotal(
      counts.active,
    );
    final archivedLabel = localizations.relationNeighborhoodArchivedTotal(
      counts.archived,
    );
    final freshnessMessage = switch (freshness) {
      RelationSummaryFreshness.current => null,
      RelationSummaryFreshness.refreshing =>
        localizations.relationNeighborhoodSavedSummaryRefreshing,
      RelationSummaryFreshness.stale =>
        localizations.relationNeighborhoodSavedSummaryStale,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey('relation-neighborhood-summary-numbers'),
          container: true,
          liveRegion: freshness != RelationSummaryFreshness.current,
          label: [
            totalLabel,
            activeLabel,
            archivedLabel,
            ?freshnessMessage,
          ].join('. '),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(totalLabel),
                    Text(activeLabel),
                    Text(archivedLabel),
                  ],
                ),
                if (freshnessMessage != null) ...[
                  const SizedBox(height: 8),
                  _SummaryFreshnessStatus(
                    freshness: freshness,
                    message: freshnessMessage,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (freshness == RelationSummaryFreshness.stale &&
            onRetryRefresh != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: () => unawaited(onRetryRefresh!()),
              child: Text(localizations.commonRetry),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _ScopeSummary(
          scope: RelationScope.active,
          counts: counts,
          selection: selection,
          onSelectGroup: onSelectGroup,
        ),
        const SizedBox(height: 12),
        _ScopeSummary(
          scope: RelationScope.archived,
          counts: counts,
          selection: selection,
          onSelectGroup: onSelectGroup,
        ),
      ],
    );
  }
}

final class _SummaryFreshnessStatus extends StatelessWidget {
  const _SummaryFreshnessStatus({
    required this.freshness,
    required this.message,
  });

  final RelationSummaryFreshness freshness;
  final String message;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (freshness == RelationSummaryFreshness.refreshing)
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      else
        Icon(
          Icons.warning_amber_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.error,
        ),
      const SizedBox(width: 12),
      Expanded(child: Text(message)),
    ],
  );
}

final class _ScopeSummary extends StatelessWidget {
  const _ScopeSummary({
    required this.scope,
    required this.counts,
    required this.selection,
    required this.onSelectGroup,
  });

  final RelationScope scope;
  final RelationCounts counts;
  final RelationGroupSelection selection;
  final ValueChanged<RelationGroupSelection> onSelectGroup;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final scopeTotal = scope == RelationScope.active
        ? counts.active
        : counts.archived;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              scope == RelationScope.active
                  ? localizations.relationNeighborhoodActiveTotal(scopeTotal)
                  : localizations.relationNeighborhoodArchivedTotal(scopeTotal),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _TypeSummary(
              scope: scope,
              type: LongTermRelationType.need,
              counts: counts,
              selection: selection,
              onSelectGroup: onSelectGroup,
            ),
            const SizedBox(height: 8),
            _TypeSummary(
              scope: scope,
              type: LongTermRelationType.can,
              counts: counts,
              selection: selection,
              onSelectGroup: onSelectGroup,
            ),
          ],
        ),
      ),
    );
  }
}

final class _TypeSummary extends StatelessWidget {
  const _TypeSummary({
    required this.scope,
    required this.type,
    required this.counts,
    required this.selection,
    required this.onSelectGroup,
  });

  final RelationScope scope;
  final LongTermRelationType type;
  final RelationCounts counts;
  final RelationGroupSelection selection;
  final ValueChanged<RelationGroupSelection> onSelectGroup;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final typeTotal =
        counts.forGroup(
          scope: scope,
          type: type,
          direction: RelationDirection.incoming,
        ) +
        counts.forGroup(
          scope: scope,
          type: type,
          direction: RelationDirection.outgoing,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          type == LongTermRelationType.need
              ? localizations.relationNeighborhoodNeedTotal(typeTotal)
              : localizations.relationNeighborhoodCanTotal(typeTotal),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final direction in const [
              RelationDirection.outgoing,
              RelationDirection.incoming,
            ])
              _GroupTransition(
                selection: RelationGroupSelection(
                  scope: scope,
                  type: type,
                  direction: direction,
                ),
                count: counts.forGroup(
                  scope: scope,
                  type: type,
                  direction: direction,
                ),
                selected:
                    selection.scope == scope &&
                    selection.type == type &&
                    selection.direction == direction,
                onSelected: onSelectGroup,
              ),
          ],
        ),
      ],
    );
  }
}

final class _GroupTransition extends StatelessWidget {
  const _GroupTransition({
    required this.selection,
    required this.count,
    required this.selected,
    required this.onSelected,
  });

  final RelationGroupSelection selection;
  final int count;
  final bool selected;
  final ValueChanged<RelationGroupSelection> onSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final direction = selection.direction == RelationDirection.outgoing
        ? localizations.relationNeighborhoodDirectionOutgoing
        : localizations.relationNeighborhoodDirectionIncoming;
    return ChoiceChip(
      key: ValueKey(
        'relation-neighborhood-group-${selection.scope.name}-${selection.type.name}-${selection.direction.name}',
      ),
      label: Text('$direction: $count'),
      selected: selected,
      onSelected: (_) => onSelected(selection),
    );
  }
}

final class _SelectionControls extends StatelessWidget {
  const _SelectionControls({
    required this.selection,
    required this.counts,
    required this.onSelectScope,
    required this.onSelectType,
    required this.onSelectDirection,
  });

  final RelationGroupSelection selection;
  final RelationCounts? counts;
  final ValueChanged<RelationScope> onSelectScope;
  final ValueChanged<LongTermRelationType> onSelectType;
  final ValueChanged<RelationDirection> onSelectDirection;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChoiceGroup<RelationScope>(
          label: localizations.relationNeighborhoodScopeLabel,
          selected: selection.scope,
          choices: [
            (
              value: RelationScope.active,
              label: localizations.relationNeighborhoodScopeActive,
              key: const ValueKey('relation-neighborhood-scope-active'),
            ),
            (
              value: RelationScope.archived,
              label: localizations.relationNeighborhoodScopeArchived,
              key: const ValueKey('relation-neighborhood-scope-archived'),
            ),
          ],
          onSelected: onSelectScope,
        ),
        const SizedBox(height: 12),
        _ChoiceGroup<LongTermRelationType>(
          label: localizations.relationNeighborhoodTypeLabel,
          selected: selection.type,
          choices: [
            (
              value: LongTermRelationType.need,
              label: localizations.relationNeighborhoodTypeNeed,
              key: const ValueKey('relation-neighborhood-type-need'),
            ),
            (
              value: LongTermRelationType.can,
              label: localizations.relationNeighborhoodTypeCan,
              key: const ValueKey('relation-neighborhood-type-can'),
            ),
          ],
          onSelected: onSelectType,
        ),
        const SizedBox(height: 12),
        _ChoiceGroup<RelationDirection>(
          label: localizations.relationNeighborhoodDirectionLabel,
          selected: selection.direction,
          choices: [
            (
              value: RelationDirection.outgoing,
              label: localizations.relationNeighborhoodDirectionOutgoing,
              key: const ValueKey('relation-neighborhood-direction-outgoing'),
            ),
            (
              value: RelationDirection.incoming,
              label: localizations.relationNeighborhoodDirectionIncoming,
              key: const ValueKey('relation-neighborhood-direction-incoming'),
            ),
          ],
          onSelected: onSelectDirection,
        ),
        if (counts case final value?) ...[
          const SizedBox(height: 12),
          Text(
            localizations.relationNeighborhoodSelectedGroupCount(
              value.forGroup(
                scope: selection.scope,
                type: selection.type,
                direction: selection.direction,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

typedef _Choice<T> = ({T value, String label, Key key});

final class _ChoiceGroup<T> extends StatelessWidget {
  const _ChoiceGroup({
    required this.label,
    required this.selected,
    required this.choices,
    required this.onSelected,
  });

  final String label;
  final T selected;
  final List<_Choice<T>> choices;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in choices)
              ChoiceChip(
                key: choice.key,
                label: Text(choice.label),
                selected: choice.value == selected,
                onSelected: (_) => onSelected(choice.value),
              ),
          ],
        ),
      ],
    ),
  );
}

final class _RelationRow extends StatelessWidget {
  const _RelationRow({
    required this.item,
    required this.onOpen,
    required this.direction,
    this.isSelected,
    this.onToggleSelection,
    super.key,
  });

  final LongTermRelationSummary item;
  final ValueChanged<LongTermRelationId> onOpen;
  final RelationDirection direction;
  final bool? isSelected;
  final VoidCallback? onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final relation = item.relation;
    final phrase = relation.type == LongTermRelationType.need
        ? localizations.relationNeighborhoodNeedPhrase(
            item.source.title,
            item.related.title,
          )
        : localizations.relationNeighborhoodCanPhrase(
            item.source.title,
            item.related.title,
          );
    final priority = switch (relation.priority) {
      RelationPriority.p1 => 'P1',
      RelationPriority.p2 => 'P2',
      RelationPriority.p3 => 'P3',
      RelationPriority.p4 => 'P4',
    };
    final relationState = relation.scope == RelationScope.active
        ? localizations.relationNeighborhoodRelationActive
        : localizations.relationNeighborhoodRelationArchived;
    final selectionAction = isSelected == true
        ? localizations.relationNeighborhoodRemoveFromSelection
        : localizations.relationNeighborhoodAddToSelection;
    final directionLabel = direction == RelationDirection.outgoing
        ? localizations.relationNeighborhoodDirectionOutgoing
        : localizations.relationNeighborhoodDirectionIncoming;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Переход и выбор остаются разными доступными действиями.
          MergeSemantics(
            child: Semantics(
              hint: localizations.relationNeighborhoodOpenRelation,
              child: InkWell(
                onTap: () => onOpen(relation.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              phrase,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                Text(
                                  localizations.relationNeighborhoodPriority(
                                    priority,
                                  ),
                                ),
                                Text(relationState),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _Participant(
                        label:
                            localizations.relationNeighborhoodSourceParticipant,
                        participant: item.source,
                      ),
                      _Participant(
                        label: localizations
                            .relationNeighborhoodRelatedParticipant,
                        participant: item.related,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isSelected case final checked?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Checkbox(
                    key: ValueKey(
                      'relation-neighborhood-select-${relation.id.toCanonicalString()}',
                    ),
                    value: checked,
                    onChanged: onToggleSelection == null
                        ? null
                        : (_) => onToggleSelection!(),
                    semanticLabel:
                        '$selectionAction: $phrase. $directionLabel. $relationState',
                  ),
                  Expanded(child: Text(selectionAction)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

final class _Participant extends StatelessWidget {
  const _Participant({required this.label, required this.participant});

  final String label;
  final RelationParticipantSummary participant;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
      IntentionSummaryView(
        title: participant.title,
        archiveState: participant.archiveState,
        activeRelationCount: ConfirmedActiveRelationCount(
          participant.activeRelationCount,
        ),
        showArchiveState: true,
      ),
    ],
  );
}

final class _InitialFailure extends StatelessWidget {
  const _InitialFailure({required this.failure, required this.onRetry});

  final RelationGroupInitialFailure failure;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => _NeighborhoodStatus(
    message: _initialFailureMessage(
      AppLocalizations.of(context),
      failure.failure,
    ),
    retry: onRetry,
  );
}

final class _EmptyGroup extends StatelessWidget {
  const _EmptyGroup({required this.state, required this.onRetryRefresh});

  final RelationGroupEmpty state;
  final Future<void> Function()? onRetryRefresh;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      children: [
        _NeighborhoodStatus(message: localizations.relationNeighborhoodEmpty),
        if (state.summaryStatus is RelationSummaryRefreshing)
          _NeighborhoodStatus(
            message: localizations.relationNeighborhoodRefreshing,
            progressIndicator: true,
          ),
        if (state.summaryStatus is RelationSummaryRefreshFailure)
          _NeighborhoodStatus(
            message: localizations.relationNeighborhoodRefreshFailed,
            retry: onRetryRefresh,
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

  final RelationGroupLoaded state;
  final Future<void> Function()? onRetryLoadMore;
  final Future<void> Function()? onRetryRefresh;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final paginationStatus = switch (state.progress) {
      RelationGroupIdle() => null,
      RelationGroupLoadingMore() => _NeighborhoodStatus(
        message: localizations.relationNeighborhoodLoadingMore,
        progressIndicator: true,
      ),
      final RelationGroupLoadMoreFailure failure => _NeighborhoodStatus(
        message: _loadMoreFailureMessage(localizations, failure.failure),
        retry: onRetryLoadMore,
      ),
    };
    if (paginationStatus != null) {
      return paginationStatus;
    }
    return switch (state.summaryStatus) {
      RelationSummaryRefreshing() => _NeighborhoodStatus(
        message: localizations.relationNeighborhoodRefreshing,
        progressIndicator: true,
      ),
      RelationSummaryRefreshFailure() => _NeighborhoodStatus(
        message: localizations.relationNeighborhoodRefreshFailed,
        retry: onRetryRefresh,
      ),
      RelationSummaryCurrent() =>
        state.hasConfirmedEnd
            ? _NeighborhoodStatus(
                message: localizations.relationNeighborhoodConfirmedEnd,
              )
            : const SizedBox(height: 16),
    };
  }
}

final class _NeighborhoodStatus extends StatelessWidget {
  const _NeighborhoodStatus({
    required this.message,
    this.progressIndicator = false,
    this.retry,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16),
  });

  final String message;
  final bool progressIndicator;
  final Future<void> Function()? retry;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: progressIndicator || retry != null,
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (progressIndicator) ...[
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: Text(message)),
            ],
          ),
          if (retry case final retry?) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => unawaited(retry()),
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ],
      ),
    ),
  );
}

String _initialFailureMessage(
  AppLocalizations localizations,
  RelationGroupReadFailure failure,
) => switch (failure) {
  RelationGroupUnavailableFailure() =>
    localizations.relationNeighborhoodInitialUnavailable,
  RelationGroupCorruptionFailure() =>
    localizations.relationNeighborhoodInitialCorruption,
  RelationGroupUnexpectedFailure() =>
    localizations.relationNeighborhoodInitialUnexpected,
  RelationGroupReadValidationFailure() || RelationGroupSnapshotExpired() =>
    localizations.relationNeighborhoodInitialInvalid,
  RelationGroupIntentionNotFoundFailure() =>
    localizations.relationNeighborhoodIntentionNotFound,
};

String _loadMoreFailureMessage(
  AppLocalizations localizations,
  RelationGroupReadFailure failure,
) => switch (failure) {
  RelationGroupUnavailableFailure() =>
    localizations.relationNeighborhoodLoadMoreUnavailable,
  RelationGroupCorruptionFailure() =>
    localizations.relationNeighborhoodLoadMoreCorruption,
  RelationGroupUnexpectedFailure() =>
    localizations.relationNeighborhoodLoadMoreUnexpected,
  RelationGroupReadValidationFailure() ||
  RelationGroupSnapshotExpired() ||
  RelationGroupIntentionNotFoundFailure() =>
    localizations.relationNeighborhoodLoadMoreInvalid,
};
