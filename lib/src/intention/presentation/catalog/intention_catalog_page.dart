import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../application/intention_catalog.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
import '../intention_summary_view.dart';
import 'intention_catalog_purpose.dart';
import 'intention_catalog_state.dart';
import 'intention_catalog_status_views.dart';
import 'intention_catalog_view_model.dart';

/// Назначение общего просмотра каталога намерений.
///
/// Выбор участника связи ведёт отдельное состояние того же каталога: их
/// охваты, фильтры и загруженные части не смешиваются.
const _purpose = BrowseIntentionCatalog();

@RoutePage()
final class IntentionCatalogPage extends ConsumerStatefulWidget {
  const IntentionCatalogPage({super.key});

  @override
  ConsumerState<IntentionCatalogPage> createState() =>
      _IntentionCatalogPageState();
}

final class _IntentionCatalogPageState
    extends ConsumerState<IntentionCatalogPage> {
  final _filterController = TextEditingController();
  final _scrollController = ScrollController();
  final _itemKeys = <IntentionId, GlobalKey>{};
  _CatalogVisualAnchor? _pendingVisualAnchor;
  bool _catalogMaintenanceScheduled = false;

  @override
  void dispose() {
    _filterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final catalog = ref.watch(intentionCatalogViewModelProvider(_purpose));
    ref.listen(
      intentionCatalogViewModelProvider(_purpose),
      _handleCatalogStateChanged,
    );
    final notifier = ref.read(
      intentionCatalogViewModelProvider(_purpose).notifier,
    );
    final selection = catalog.value?.selection ?? notifier.selection;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.catalogTitle),
        actions: [
          IconButton(
            key: const ValueKey('catalog-open-tags'),
            tooltip: localizations.tagCatalogTitle,
            onPressed: () => context.router.push(const TagCatalogRoute()),
            icon: const Icon(Icons.label_outline),
          ),
          IconButton(
            key: const ValueKey('catalog-open-daily-choices'),
            tooltip: localizations.dailyChoiceCatalogTitle,
            onPressed: () =>
                context.router.push(const DailyChoiceCatalogRoute()),
            icon: const Icon(Icons.today),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('catalog-create-intention'),
        onPressed: () {
          context.router.push(const IntentionEditorRoute());
        },
        icon: const Icon(Icons.add),
        label: Text(localizations.editorCreateAction),
      ),
      body: Column(
        children: [
          _CatalogControls(
            selection: selection,
            filterController: _filterController,
            onScopeChanged: (scope) {
              _scrollToTop();
              notifier.changeScope(scope);
            },
            onFilterChanged: (value) {
              _scrollToTop();
              notifier.changeTitleFilter(value);
            },
            onOrderChanged: (order) {
              _scrollToTop();
              notifier.changeOrder(order);
            },
          ),
          Expanded(
            child: catalog.when(
              skipLoadingOnReload: false,
              skipLoadingOnRefresh: false,
              data: (state) => _CatalogContent(
                state: state,
                scrollController: _scrollController,
                itemKeyFor: _itemKeyFor,
              ),
              error: (_, _) => IntentionCatalogStatusView(
                message: localizations.catalogUnexpectedFailure,
              ),
              loading: () => IntentionCatalogStatusView(
                message: localizations.catalogLoading,
                progressIndicator: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  GlobalKey _itemKeyFor(IntentionId id) =>
      _itemKeys.putIfAbsent(id, () => GlobalKey());

  void _handleCatalogStateChanged(
    AsyncValue<IntentionCatalogState>? previous,
    AsyncValue<IntentionCatalogState> next,
  ) {
    final previousState = previous?.value;
    final nextState = next.value;
    if (nextState is! IntentionCatalogLoaded) {
      return;
    }

    if (_pendingVisualAnchor == null &&
        previousState is IntentionCatalogLoaded &&
        identical(previousState.query, nextState.query) &&
        _catalogLayoutChanged(previousState.items, nextState.items)) {
      _pendingVisualAnchor = _captureVisualAnchor(previousState.items);
    }
    _scheduleCatalogMaintenance();
  }

  bool _catalogLayoutChanged(
    List<IntentionSummary> previous,
    List<IntentionSummary> next,
  ) {
    if (previous.length != next.length) {
      return true;
    }
    for (var index = 0; index < previous.length; index++) {
      if (!identical(previous[index], next[index])) {
        return true;
      }
    }
    return false;
  }

  _CatalogVisualAnchor? _captureVisualAnchor(List<IntentionSummary> items) {
    if (!_scrollController.hasClients) {
      return null;
    }
    final currentOffset = _scrollController.position.pixels;
    for (var index = 0; index < items.length; index++) {
      final renderObject = _itemKeys[items[index].id]?.currentContext
          ?.findRenderObject();
      if (renderObject == null || !renderObject.attached) {
        continue;
      }
      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) {
        continue;
      }
      final revealed = viewport.getOffsetToReveal(renderObject, 0);
      final itemStart = revealed.offset;
      final itemEnd = itemStart + revealed.rect.height;
      if (itemStart <= currentOffset && itemEnd > currentOffset) {
        return _CatalogVisualAnchor(
          candidateIds: [
            items[index].id,
            if (index + 1 < items.length) items[index + 1].id,
            if (index > 0) items[index - 1].id,
          ],
          offsetWithinItem: currentOffset - itemStart,
        );
      }
    }
    return null;
  }

  void _scheduleCatalogMaintenance() {
    if (_catalogMaintenanceScheduled) {
      return;
    }
    _catalogMaintenanceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _catalogMaintenanceScheduled = false;
      if (!mounted) {
        return;
      }
      _restoreVisualAnchor();
      _pruneItemKeys();
    });
  }

  void _restoreVisualAnchor() {
    final anchor = _pendingVisualAnchor;
    _pendingVisualAnchor = null;
    if (anchor == null || !_scrollController.hasClients) {
      return;
    }

    for (final id in anchor.candidateIds) {
      final renderObject = _itemKeys[id]?.currentContext?.findRenderObject();
      if (renderObject == null || !renderObject.attached) {
        continue;
      }
      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) {
        continue;
      }
      final target =
          viewport.getOffsetToReveal(renderObject, 0).offset +
          anchor.offsetWithinItem;
      final position = _scrollController.position;
      position.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      return;
    }
  }

  void _pruneItemKeys() {
    final state = ref.read(intentionCatalogViewModelProvider(_purpose)).value;
    if (state is! IntentionCatalogLoaded) {
      return;
    }
    final currentIds = state.items.map((item) => item.id).toSet();
    _itemKeys.removeWhere((id, _) => !currentIds.contains(id));
  }
}

final class _CatalogControls extends StatelessWidget {
  const _CatalogControls({
    required this.selection,
    required this.filterController,
    required this.onScopeChanged,
    required this.onFilterChanged,
    required this.onOrderChanged,
  });

  final IntentionCatalogSelection selection;
  final TextEditingController filterController;
  final ValueChanged<IntentionScope> onScopeChanged;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<IntentionCatalogOrder> onOrderChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          DropdownButtonFormField<IntentionScope>(
            key: const ValueKey('catalog-scope-control'),
            isExpanded: true,
            initialValue: selection.scope,
            decoration: InputDecoration(
              labelText: localizations.catalogScopeLabel,
            ),
            items: [
              for (final scope in IntentionScope.values)
                DropdownMenuItem(
                  value: scope,
                  child: Text(_scopeLabel(localizations, scope)),
                ),
            ],
            onChanged: (scope) {
              if (scope != null) {
                onScopeChanged(scope);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('catalog-filter-field'),
            controller: filterController,
            decoration: InputDecoration(
              labelText: localizations.catalogFilterLabel,
              errorText: _filterError(localizations),
            ),
            onChanged: onFilterChanged,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<IntentionCatalogOrder>(
            key: const ValueKey('catalog-order-control'),
            isExpanded: true,
            initialValue: selection.order,
            decoration: InputDecoration(
              labelText: localizations.catalogOrderLabel,
            ),
            items: [
              for (final order in _orders)
                DropdownMenuItem(
                  value: order,
                  child: Text(_orderLabel(localizations, order)),
                ),
            ],
            onChanged: (order) {
              if (order != null) {
                onOrderChanged(order);
              }
            },
          ),
        ],
      ),
    );
  }

  String? _filterError(AppLocalizations localizations) =>
      switch (selection.filterValidationFailure) {
        IntentionCatalogFilterValidationFailure.invalidUnicodeRepertoire =>
          localizations.catalogFilterInvalidUnicode,
        IntentionCatalogFilterValidationFailure.tooLong =>
          localizations.catalogFilterTooLong,
        null => null,
      };

  static const _orders = [
    IntentionCatalogOrder.createdAtDescending,
    IntentionCatalogOrder.createdAtAscending,
    IntentionCatalogOrder.updatedAtDescending,
    IntentionCatalogOrder.updatedAtAscending,
  ];

  String _scopeLabel(AppLocalizations localizations, IntentionScope scope) =>
      switch (scope) {
        IntentionScope.active => localizations.catalogScopeActive,
        IntentionScope.archived => localizations.catalogScopeArchived,
        IntentionScope.all => localizations.catalogScopeAll,
      };

  String _orderLabel(
    AppLocalizations localizations,
    IntentionCatalogOrder order,
  ) => switch ((order.field, order.direction)) {
    (
      IntentionCatalogSortField.createdAt,
      IntentionCatalogSortDirection.descending,
    ) =>
      localizations.catalogOrderCreatedNewest,
    (
      IntentionCatalogSortField.createdAt,
      IntentionCatalogSortDirection.ascending,
    ) =>
      localizations.catalogOrderCreatedOldest,
    (
      IntentionCatalogSortField.updatedAt,
      IntentionCatalogSortDirection.descending,
    ) =>
      localizations.catalogOrderUpdatedNewest,
    (
      IntentionCatalogSortField.updatedAt,
      IntentionCatalogSortDirection.ascending,
    ) =>
      localizations.catalogOrderUpdatedOldest,
  };
}

final class _CatalogContent extends ConsumerWidget {
  const _CatalogContent({
    required this.state,
    required this.scrollController,
    required this.itemKeyFor,
  });

  final IntentionCatalogState state;
  final ScrollController scrollController;
  final Key Function(IntentionId) itemKeyFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return switch (state) {
      IntentionCatalogDebouncing() => IntentionCatalogStatusView(
        message: localizations.catalogLoading,
        progressIndicator: true,
      ),
      IntentionCatalogInvalidFilter() => const SizedBox.shrink(),
      IntentionCatalogLoaded loaded => _LoadedCatalog(
        state: loaded,
        scrollController: scrollController,
        itemKeyFor: itemKeyFor,
      ),
      IntentionCatalogEmpty empty => IntentionCatalogStatusView(
        message: _emptyMessage(localizations, empty.scope),
      ),
      IntentionCatalogUnavailable() => IntentionCatalogStatusView(
        message: localizations.catalogUnavailable,
        retryLabel: localizations.commonRetry,
        onRetry: () {
          ref
              .read(intentionCatalogViewModelProvider(_purpose).notifier)
              .retry();
        },
      ),
      IntentionCatalogCorruption() => IntentionCatalogStatusView(
        message: localizations.catalogCorruption,
      ),
      IntentionCatalogUnexpected() => IntentionCatalogStatusView(
        message: localizations.catalogUnexpectedFailure,
      ),
    };
  }

  String _emptyMessage(AppLocalizations localizations, IntentionScope scope) =>
      switch (scope) {
        IntentionScope.active => localizations.catalogActiveEmpty,
        IntentionScope.archived => localizations.catalogArchivedEmpty,
        IntentionScope.all => localizations.catalogAllEmpty,
      };
}

final class _LoadedCatalog extends ConsumerWidget {
  const _LoadedCatalog({
    required this.state,
    required this.scrollController,
    required this.itemKeyFor,
  });

  final IntentionCatalogLoaded state;
  final ScrollController scrollController;
  final Key Function(IntentionId) itemKeyFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final hasContinuationStatus =
        state.continuation is! IntentionCatalogContinuationIdle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            localizations.catalogTotalCount(state.totalCount),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const PageStorageKey<String>('intention-catalog-list'),
            controller: scrollController,
            itemCount: state.items.length + (hasContinuationStatus ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == state.items.length) {
                return IntentionCatalogContinuationStatusView(
                  purpose: _purpose,
                  continuation: state.continuation,
                );
              }
              _requestNextPage(context, ref, index);
              final summary = state.items[index];
              return _IntentionSummaryTile(
                key: itemKeyFor(summary.id),
                summary: summary,
                showArchiveState: state.query.scope == IntentionScope.all,
                onTap: () {
                  context.router.push(
                    IntentionDetailsRoute(intentionId: summary.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _requestNextPage(BuildContext context, WidgetRef ref, int visibleIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      unawaited(
        ref
            .read(intentionCatalogViewModelProvider(_purpose).notifier)
            .loadNextPageIfNeeded(visibleIndex: visibleIndex),
      );
    });
  }
}

final class _IntentionSummaryTile extends StatelessWidget {
  const _IntentionSummaryTile({
    required this.summary,
    required this.showArchiveState,
    required this.onTap,
    super.key,
  });

  final IntentionSummary summary;
  final bool showArchiveState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final readiness = switch (summary.readiness) {
      IntentionReadiness.ready => localizations.catalogReady,
      IntentionReadiness.notReady => localizations.catalogNotReady,
    };
    final description = summary.hasDescription
        ? localizations.catalogHasDescription
        : localizations.catalogNoDescription;
    return IntentionSummaryView(
      title: summary.title,
      archiveState: summary.archiveState,
      showArchiveState: showArchiveState,
      traits: [readiness, description],
      activeRelationCount: ConfirmedActiveRelationCount(
        summary.activeRelationCount,
      ),
      onTap: onTap,
    );
  }
}

final class _CatalogVisualAnchor {
  const _CatalogVisualAnchor({
    required this.candidateIds,
    required this.offsetWithinItem,
  });

  final List<IntentionId> candidateIds;
  final double offsetWithinItem;
}
