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
import 'intention_search_layout.dart';
import 'intention_tag_conditions_section.dart';
import 'intention_tag_conditions_view_model.dart';

/// Назначение общего просмотра каталога намерений.
///
/// Выбор участника связи ведёт отдельное состояние того же каталога: их
/// охваты, фильтры и загруженные части не смешиваются.
const _purpose = BrowseIntentionCatalog();

/// Высота кнопки создания намерения вместе с отступами над нижним краем.
const _createActionExtent = 56 + 2 * kFloatingActionButtonMargin;

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
  final _scrollController = _CatalogScrollController();
  final _itemKeys = <IntentionId, GlobalKey>{};

  /// Сохранённое смещение списка выдачи между его показами.
  var _listStorage = PageStorageBucket();
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
    // Добавление, переключение и снятие условия начинают новую выдачу;
    // переименование и удаление тега меняют только предъявление условия.
    ref.listen(intentionTagConditionsViewModelProvider(_purpose), (
      previous,
      next,
    ) {
      if (previous?.tagFilter != next.tagFilter) {
        _scrollToTop();
      }
    });
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
            onPressed: () => context.router.push(TagCatalogRoute()),
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
      body: IntentionSearchLayout(
        controls: _CatalogControls(
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
        results: PageStorage(
          bucket: _listStorage,
          child: catalog.when(
            skipLoadingOnReload: false,
            skipLoadingOnRefresh: false,
            data: (state) => _CatalogContent(
              state: state,
              scrollController: _scrollController,
              itemKeyFor: _itemKeyFor,
              onRefreshStatusExtentChanged: _reserveRefreshStatusExtent,
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
      ),
    );
  }

  void _scrollToTop() {
    // Новые параметры начинают выдачу с верхней позиции: отложенный якорь
    // прежней выдачи больше не действует.
    _pendingVisualAnchor = null;
    // Список может быть снят с экрана пустой выдачей: сохранённое смещение
    // прежней выдачи тогда вернулось бы вместе с ним. Новое хранилище не
    // переносит его в выдачу новых параметров.
    setState(() => _listStorage = PageStorageBucket());
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  GlobalKey _itemKeyFor(IntentionId id) =>
      _itemKeys.putIfAbsent(id, () => GlobalKey());

  void _reserveRefreshStatusExtent(double extent) {
    if (mounted) {
      _scrollController.leadingInset = extent;
    }
  }

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
      _pendingVisualAnchor = _captureVisualAnchor(previousState);
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

  _CatalogVisualAnchor? _captureVisualAnchor(IntentionCatalogLoaded state) {
    if (!_scrollController.hasClients) {
      return null;
    }
    final items = state.items;
    final currentOffset = _scrollController.position.pixels;
    for (var index = 0; index < items.length; index++) {
      final extent = _builtItemExtent(items[index].id);
      if (extent == null) {
        continue;
      }
      if (extent.start <= currentOffset && extent.end > currentOffset) {
        return _CatalogVisualAnchor(
          query: state.query,
          candidateIds: [
            items[index].id,
            if (index + 1 < items.length) items[index + 1].id,
            if (index > 0) items[index - 1].id,
          ],
          offsetWithinItem: currentOffset - extent.start,
          remainingApproaches: _CatalogVisualAnchor.maxApproaches,
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
    final state = ref.read(intentionCatalogViewModelProvider(_purpose)).value;
    if (anchor == null ||
        !_scrollController.hasClients ||
        state is! IntentionCatalogLoaded ||
        !identical(state.query, anchor.query)) {
      return;
    }

    final targetIndex = _anchorTargetIndex(anchor, state.items);
    if (targetIndex == null) {
      return;
    }
    final position = _scrollController.position;
    final exact = _builtItemExtent(state.items[targetIndex].id);
    if (exact != null) {
      _jumpWithinExtent(position, exact.start + anchor.offsetWithinItem);
      return;
    }

    // Много строк, вставленных или удалённых перед якорем, уводят его за
    // пределы построенной области списка. Сначала приближаемся к нему по
    // размеру построенных строк, а точное положение восстанавливаем в
    // следующем кадре, когда якорь уже построен.
    final estimate = _estimateItemStart(state.items, targetIndex);
    if (estimate == null || anchor.remainingApproaches == 0) {
      return;
    }
    _jumpWithinExtent(position, estimate + anchor.offsetWithinItem);
    _pendingVisualAnchor = anchor.afterApproach();
    _scheduleCatalogMaintenance();
  }

  int? _anchorTargetIndex(
    _CatalogVisualAnchor anchor,
    List<IntentionSummary> items,
  ) {
    for (final id in anchor.candidateIds) {
      final index = items.indexWhere((item) => item.id == id);
      if (index >= 0) {
        return index;
      }
    }
    return null;
  }

  double? _estimateItemStart(List<IntentionSummary> items, int targetIndex) {
    ({int index, _ItemExtent extent})? first;
    ({int index, _ItemExtent extent})? last;
    for (var index = 0; index < items.length; index++) {
      final extent = _builtItemExtent(items[index].id);
      if (extent == null) {
        continue;
      }
      first ??= (index: index, extent: extent);
      last = (index: index, extent: extent);
    }
    if (first == null || last == null) {
      return null;
    }
    final averageExtent =
        (last.extent.end - first.extent.start) / (last.index - first.index + 1);
    if (targetIndex > last.index) {
      return last.extent.end + (targetIndex - last.index - 1) * averageExtent;
    }
    return first.extent.start - (first.index - targetIndex) * averageExtent;
  }

  _ItemExtent? _builtItemExtent(IntentionId id) {
    final renderObject = _itemKeys[id]?.currentContext?.findRenderObject();
    if (renderObject == null || !renderObject.attached) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) {
      return null;
    }
    final revealed = viewport.getOffsetToReveal(renderObject, 0);
    return (
      start: revealed.offset,
      end: revealed.offset + revealed.rect.height,
    );
  }

  void _jumpWithinExtent(ScrollPosition position, double target) {
    position.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
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
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: IntentionTagConditionsSection(purpose: _purpose),
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
    required this.onRefreshStatusExtentChanged,
  });

  final IntentionCatalogState state;
  final ScrollController scrollController;
  final Key Function(IntentionId) itemKeyFor;
  final ValueChanged<double> onRefreshStatusExtentChanged;

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
        onRefreshStatusExtentChanged: onRefreshStatusExtentChanged,
      ),
      // Отказ обновления стоит над сообщением о пустоте, поэтому не
      // обновлённую выдачу нельзя принять за успешное отсутствие совпадений.
      IntentionCatalogEmpty empty => LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntentionCatalogRefreshStatusArea(
              availableHeight: constraints.maxHeight,
              child: IntentionCatalogRefreshStatusView(
                purpose: _purpose,
                refresh: empty.refresh,
              ),
            ),
            Expanded(
              child: IntentionCatalogStatusView(
                message: _emptyMessage(localizations, empty.query),
              ),
            ),
          ],
        ),
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

  String _emptyMessage(
    AppLocalizations localizations,
    IntentionCatalogQuery query,
  ) {
    // Условия по тегам сужают охват: пустая выдача не означает, что в нём
    // нет намерений.
    if (query.tagFilter != IntentionTagFilter.empty) {
      return localizations.catalogTagConditionsEmpty;
    }
    return switch (query.scope) {
      IntentionScope.active => localizations.catalogActiveEmpty,
      IntentionScope.archived => localizations.catalogArchivedEmpty,
      IntentionScope.all => localizations.catalogAllEmpty,
    };
  }
}

final class _LoadedCatalog extends ConsumerWidget {
  const _LoadedCatalog({
    required this.state,
    required this.scrollController,
    required this.itemKeyFor,
    required this.onRefreshStatusExtentChanged,
  });

  final IntentionCatalogLoaded state;
  final ScrollController scrollController;
  final Key Function(IntentionId) itemKeyFor;
  final ValueChanged<double> onRefreshStatusExtentChanged;

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
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                ListView.builder(
                  key: const PageStorageKey<String>('intention-catalog-list'),
                  controller: scrollController,
                  // Конец выдачи и состояние продолжения прокручиваются выше
                  // кнопки создания намерения.
                  padding: const EdgeInsets.only(bottom: _createActionExtent),
                  itemCount:
                      state.items.length + (hasContinuationStatus ? 1 : 0),
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
                // Отказ обновления ложится поверх верхнего края списка и не
                // сдвигает строки; место под него список отводит перед своим
                // началом, поэтому первые строки остаются достижимыми.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _ExtentObserver(
                    onChanged: onRefreshStatusExtentChanged,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: 1,
                      child: IntentionCatalogRefreshStatusArea(
                        availableHeight: constraints.maxHeight,
                        child: IntentionCatalogRefreshStatusView(
                          purpose: _purpose,
                          refresh: state.refresh,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
      confirmedTags: summary.tags,
      activeRelationCount: ConfirmedActiveRelationCount(
        summary.activeRelationCount,
      ),
      onTap: onTap,
    );
  }
}

/// Положение строки в прокручиваемой области списка.
typedef _ItemExtent = ({double start, double end});

final class _CatalogVisualAnchor {
  const _CatalogVisualAnchor({
    required this.query,
    required this.candidateIds,
    required this.offsetWithinItem,
    required this.remainingApproaches,
  });

  /// Предел кадров приближения к якорю за пределами построенной области.
  static const maxApproaches = 3;

  /// Якорь действует только для выдачи того же запроса.
  final IntentionCatalogQuery query;
  final List<IntentionId> candidateIds;
  final double offsetWithinItem;
  final int remainingApproaches;

  _CatalogVisualAnchor afterApproach() => _CatalogVisualAnchor(
    query: query,
    candidateIds: candidateIds,
    offsetWithinItem: offsetWithinItem,
    remainingApproaches: remainingApproaches - 1,
  );
}

/// Контроллер списка каталога с местом перед началом выдачи.
///
/// Место отводится под отказ обновления над списком: оно расширяет область
/// прокрутки назад и не меняет ни смещение, ни экранное положение строк.
final class _CatalogScrollController extends ScrollController {
  double _leadingInset = 0;

  set leadingInset(double value) {
    _leadingInset = value;
    for (final position in positions) {
      (position as _CatalogScrollPosition).leadingInset = value;
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _CatalogScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  ).._leadingInset = _leadingInset;
}

final class _CatalogScrollPosition extends ScrollPositionWithSingleContext {
  _CatalogScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  double _leadingInset = 0;
  double _appliedLeadingInset = 0;

  set leadingInset(double value) {
    if (value == _leadingInset) {
      return;
    }
    _leadingInset = value;
    // Границы прокрутки меняются только при компоновке списка: появление
    // места перед началом может сделать прокручиваемым список, который
    // помещался на экране. Уведомление запрашивает эту компоновку.
    notifyListeners();
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final insetChanged = _leadingInset != _appliedLeadingInset;
    final wasAtStart =
        insetChanged && hasContentDimensions && pixels <= this.minScrollExtent;
    _appliedLeadingInset = _leadingInset;
    final accepted = super.applyContentDimensions(
      minScrollExtent - _leadingInset,
      maxScrollExtent,
    );
    // Список в начале выдачи остаётся в начале: строки уходят из-под
    // появившегося отказа и возвращаются на место после его снятия.
    if (insetChanged &&
        (wasAtStart || pixels < this.minScrollExtent) &&
        pixels != this.minScrollExtent) {
      correctPixels(this.minScrollExtent);
      return false;
    }
    return accepted;
  }
}

/// Сообщает высоту потомка после кадра, в котором она изменилась.
final class _ExtentObserver extends SingleChildRenderObjectWidget {
  const _ExtentObserver({required this.onChanged, super.child});

  final ValueChanged<double> onChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderExtentObserver(onChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderExtentObserver renderObject,
  ) {
    renderObject.onChanged = onChanged;
  }
}

final class _RenderExtentObserver extends RenderProxyBox {
  _RenderExtentObserver(this.onChanged);

  ValueChanged<double> onChanged;
  double? _reportedExtent;

  @override
  void performLayout() {
    super.performLayout();
    final extent = size.height;
    if (extent == _reportedExtent) {
      return;
    }
    _reportedExtent = extent;
    // Область прокрутки нельзя менять во время компоновки её соседа.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached && _reportedExtent == extent) {
        onChanged(extent);
      }
    });
  }
}
