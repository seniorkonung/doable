import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/intention_catalog.dart';
import '../../domain/intention_id.dart';
import 'intention_catalog_purpose.dart';
import 'intention_catalog_state.dart';
import 'intention_catalog_status_views.dart';
import 'intention_catalog_view_model.dart';

/// Сообщения страницы для состояний, в которых выдачи нет.
final class IntentionSearchResultsMessages {
  const IntentionSearchResultsMessages({
    required this.loading,
    required this.unavailable,
    required this.corruption,
    required this.unexpected,
  });

  final String loading;
  final String unavailable;
  final String corruption;
  final String unexpected;
}

/// Что удерживает позицию просмотра при обновлении выдачи без смены
/// параметров поиска.
enum IntentionSearchResultsViewAnchor {
  /// Сохраняется смещение прокрутки списка.
  scrollOffset,

  /// Сохраняется экранное положение видимого намерения; если оно исчезло из
  /// выдачи, позиция переходит к ближайшему соседу.
  visibleIntention,
}

/// Строит строку загруженного списка для намерения [summary] выдачи
/// [results].
typedef IntentionSearchResultBuilder = Widget Function(
  BuildContext context,
  IntentionCatalogLoaded results,
  IntentionSummary summary,
);

/// Выдача поиска намерений назначения [purpose].
///
/// Элемент один владеет прокруткой списка, переходом к верхней позиции при
/// смене параметров поиска и размещением отказа обновления относительно
/// загруженной и пустой выдачи. Страница передаёт состояние выдачи своего
/// назначения и построение своих строк; элемент не читает граф, не выполняет
/// команд и не меняет условия поиска.
final class IntentionSearchResults extends ConsumerStatefulWidget {
  const IntentionSearchResults({
    required this.purpose,
    required this.catalog,
    required this.listKey,
    required this.messages,
    required this.emptyMessage,
    required this.itemBuilder,
    this.totalCountLabel,
    this.viewAnchor = IntentionSearchResultsViewAnchor.scrollOffset,
    this.trailingInset = 0,
    super.key,
  });

  final IntentionCatalogPurpose purpose;

  /// Состояние выдачи назначения [purpose].
  final AsyncValue<IntentionCatalogState> catalog;

  /// Ключ списка: под ним сохраняется смещение между показами списка той же
  /// выдачи.
  final PageStorageKey<String> listKey;

  final IntentionSearchResultsMessages messages;

  /// Сообщение успешной пустой выдачи.
  final String Function(IntentionCatalogEmpty empty) emptyMessage;

  final IntentionSearchResultBuilder itemBuilder;

  /// Подпись точного количества совпадений над списком; без неё количество
  /// не выводится.
  final String Function(int totalCount)? totalCountLabel;

  final IntentionSearchResultsViewAnchor viewAnchor;

  /// Место после конца выдачи под элемент страницы, лежащий поверх списка:
  /// конец выдачи и состояние продолжения прокручиваются выше него.
  final double trailingInset;

  @override
  ConsumerState<IntentionSearchResults> createState() =>
      _IntentionSearchResultsState();
}

/// Параметры поиска, смена которых начинает новую выдачу.
typedef _SearchParameters = ({
  IntentionScope scope,
  String titleFilterText,
  IntentionTagFilter tagFilter,
  IntentionCatalogOrder order,
});

final class _IntentionSearchResultsState
    extends ConsumerState<IntentionSearchResults> {
  final _scrollController = _ResultsScrollController();
  final _itemKeys = <IntentionId, GlobalKey>{};

  /// Сохранённое смещение списка выдачи между его показами.
  var _listStorage = PageStorageBucket();
  late _SearchParameters _parameters = _currentParameters();
  _VisualAnchor? _pendingVisualAnchor;
  bool _maintenanceScheduled = false;

  IntentionCatalogViewModel get _notifier =>
      ref.read(intentionCatalogViewModelProvider(widget.purpose).notifier);

  @override
  void didUpdateWidget(IntentionSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.purpose != widget.purpose) {
      // Выдача другого назначения не наследует ни позицию, ни якорь.
      _parameters = _currentParameters();
      _pendingVisualAnchor = null;
      _listStorage = PageStorageBucket();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      intentionCatalogViewModelProvider(widget.purpose),
      _handleCatalogStateChanged,
    );
    final messages = widget.messages;
    return PageStorage(
      bucket: _listStorage,
      child: widget.catalog.when(
        skipLoadingOnReload: false,
        skipLoadingOnRefresh: false,
        data: _buildState,
        error: (_, _) =>
            IntentionCatalogStatusView(message: messages.unexpected),
        loading: () => IntentionCatalogStatusView(
          message: messages.loading,
          progressIndicator: true,
        ),
      ),
    );
  }

  Widget _buildState(IntentionCatalogState state) {
    final messages = widget.messages;
    return switch (state) {
      IntentionCatalogDebouncing() => IntentionCatalogStatusView(
        message: messages.loading,
        progressIndicator: true,
      ),
      IntentionCatalogInvalidFilter() => const SizedBox.shrink(),
      final IntentionCatalogLoaded loaded => _buildLoaded(loaded),
      final IntentionCatalogEmpty empty => _buildEmpty(empty),
      IntentionCatalogUnavailable() => IntentionCatalogStatusView(
        message: messages.unavailable,
        retryLabel: AppLocalizations.of(context).commonRetry,
        onRetry: () => unawaited(_notifier.retry()),
      ),
      IntentionCatalogCorruption() => IntentionCatalogStatusView(
        message: messages.corruption,
      ),
      IntentionCatalogUnexpected() => IntentionCatalogStatusView(
        message: messages.unexpected,
      ),
    };
  }

  /// Отказ обновления стоит над сообщением о пустоте, поэтому не обновлённую
  /// выдачу нельзя принять за успешное отсутствие совпадений.
  Widget _buildEmpty(IntentionCatalogEmpty empty) => LayoutBuilder(
    builder: (context, constraints) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntentionCatalogRefreshStatusArea(
          availableHeight: constraints.maxHeight,
          child: IntentionCatalogRefreshStatusView(
            purpose: widget.purpose,
            refresh: empty.refresh,
          ),
        ),
        Expanded(
          child: IntentionCatalogStatusView(
            message: widget.emptyMessage(empty),
          ),
        ),
      ],
    ),
  );

  Widget _buildLoaded(IntentionCatalogLoaded results) {
    final hasContinuationStatus =
        results.continuation is! IntentionCatalogContinuationIdle;
    final list = LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          ListView.builder(
            key: widget.listKey,
            controller: _scrollController,
            padding: EdgeInsets.only(bottom: widget.trailingInset),
            itemCount: results.items.length + (hasContinuationStatus ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == results.items.length) {
                return IntentionCatalogContinuationStatusView(
                  purpose: widget.purpose,
                  continuation: results.continuation,
                );
              }
              _requestNextPage(index);
              final summary = results.items[index];
              final row = widget.itemBuilder(context, results, summary);
              return switch (widget.viewAnchor) {
                IntentionSearchResultsViewAnchor.scrollOffset => row,
                IntentionSearchResultsViewAnchor.visibleIntention =>
                  KeyedSubtree(key: _itemKeyFor(summary.id), child: row),
              };
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
              onChanged: _reserveRefreshStatusExtent,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 1,
                child: IntentionCatalogRefreshStatusArea(
                  availableHeight: constraints.maxHeight,
                  child: IntentionCatalogRefreshStatusView(
                    purpose: widget.purpose,
                    refresh: results.refresh,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final totalCountLabel = widget.totalCountLabel;
    if (totalCountLabel == null) {
      return list;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            totalCountLabel(results.totalCount),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  void _requestNextPage(int visibleIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_notifier.loadNextPageIfNeeded(visibleIndex: visibleIndex));
    });
  }

  void _reserveRefreshStatusExtent(double extent) {
    if (mounted) {
      _scrollController.leadingInset = extent;
    }
  }

  _SearchParameters _currentParameters() {
    final selection = _notifier.selection;
    return (
      scope: selection.scope,
      titleFilterText: selection.titleFilterText,
      tagFilter: selection.tagFilter,
      order: selection.order,
    );
  }

  void _handleCatalogStateChanged(
    AsyncValue<IntentionCatalogState>? previous,
    AsyncValue<IntentionCatalogState> next,
  ) {
    // Модель публикует состояние при каждой смене параметров, в том числе
    // когда список в этот момент не показан.
    final parameters = _currentParameters();
    if (parameters != _parameters) {
      _parameters = parameters;
      _startFromTop();
    }

    final previousState = previous?.value;
    final nextState = next.value;
    if (widget.viewAnchor !=
            IntentionSearchResultsViewAnchor.visibleIntention ||
        nextState is! IntentionCatalogLoaded) {
      return;
    }
    if (_pendingVisualAnchor == null &&
        previousState is IntentionCatalogLoaded &&
        identical(previousState.query, nextState.query) &&
        _layoutChanged(previousState.items, nextState.items)) {
      _pendingVisualAnchor = _captureVisualAnchor(previousState);
    }
    _scheduleMaintenance();
  }

  void _startFromTop() {
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

  bool _layoutChanged(
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

  _VisualAnchor? _captureVisualAnchor(IntentionCatalogLoaded state) {
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
        return _VisualAnchor(
          query: state.query,
          candidateIds: [
            items[index].id,
            if (index + 1 < items.length) items[index + 1].id,
            if (index > 0) items[index - 1].id,
          ],
          offsetWithinItem: currentOffset - extent.start,
          remainingApproaches: _VisualAnchor.maxApproaches,
        );
      }
    }
    return null;
  }

  void _scheduleMaintenance() {
    if (_maintenanceScheduled) {
      return;
    }
    _maintenanceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maintenanceScheduled = false;
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
    final state = widget.catalog.value;
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
    _scheduleMaintenance();
  }

  int? _anchorTargetIndex(_VisualAnchor anchor, List<IntentionSummary> items) {
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
    final state = widget.catalog.value;
    if (state is! IntentionCatalogLoaded) {
      return;
    }
    final currentIds = state.items.map((item) => item.id).toSet();
    _itemKeys.removeWhere((id, _) => !currentIds.contains(id));
  }
}

/// Положение строки в прокручиваемой области списка.
typedef _ItemExtent = ({double start, double end});

final class _VisualAnchor {
  const _VisualAnchor({
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

  _VisualAnchor afterApproach() => _VisualAnchor(
    query: query,
    candidateIds: candidateIds,
    offsetWithinItem: offsetWithinItem,
    remainingApproaches: remainingApproaches - 1,
  );
}

/// Контроллер списка выдачи с местом перед её началом.
///
/// Место отводится под отказ обновления над списком: оно расширяет область
/// прокрутки назад и не меняет ни смещение, ни экранное положение строк.
final class _ResultsScrollController extends ScrollController {
  double _leadingInset = 0;

  set leadingInset(double value) {
    _leadingInset = value;
    for (final position in positions) {
      (position as _ResultsScrollPosition).leadingInset = value;
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _ResultsScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  ).._leadingInset = _leadingInset;
}

final class _ResultsScrollPosition extends ScrollPositionWithSingleContext {
  _ResultsScrollPosition({
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
