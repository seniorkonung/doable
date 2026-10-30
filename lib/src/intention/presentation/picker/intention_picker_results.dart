import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/empty_state.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/doable_icon.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../graph/application/graph_revision.dart';
import '../../application/intention_catalog.dart';
import '../../domain/intention_id.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../catalog/intention_catalog_state.dart';
import '../catalog/intention_catalog_view_model.dart';
import '../search/intention_search_kind.dart';
import 'intention_picker_row.dart';

/// Выдача экрана выбора назначения [purpose]: строки, подгрузка следующей
/// порции, пустая выдача и отказы.
///
/// Пустая выдача называет выбранный тип и причину: фильтры можно сбросить,
/// а пустой тип — расширить до обоих типов.
///
/// Элемент один владеет прокруткой списка и возвращает его к началу, когда
/// модель подтверждает выдачу нового запроса.
final class IntentionPickerResults extends ConsumerStatefulWidget {
  const IntentionPickerResults({
    required this.purpose,
    required this.emptyScopeMessage,
    required this.onResetFilters,
    required this.onPick,
    required this.onOpenDetails,
    super.key,
  });

  final IntentionPickerPurpose purpose;

  /// Сообщение страницы о том, что допустимый охват пуст.
  final String emptyScopeMessage;

  /// Снимает фильтр названия и все условия по тегам: полем названия владеет
  /// экран.
  final VoidCallback onResetFilters;

  /// Получает сводку строки с ревизией выдачи, из которой строка построена:
  /// к моменту нажатия модель может держать уже другую выдачу.
  final void Function(GraphSnapshot<IntentionSummary> pick) onPick;

  final void Function(IntentionId id) onOpenDetails;

  @override
  ConsumerState<IntentionPickerResults> createState() =>
      _IntentionPickerResultsState();
}

final class _IntentionPickerResultsState
    extends ConsumerState<IntentionPickerResults> {
  static const _sidePadding = EdgeInsets.symmetric(
    horizontal: DoableMetrics.space5,
  );

  // Список снимается с экрана на время загрузки новой выдачи и не должен
  // возвращать смещение прежней.
  final _scrollController = ScrollController(keepScrollOffset: false);

  /// Запрос последней подтверждённой выдачи. Модель сохраняет его объект,
  /// пока согласует и продолжает ту же выдачу, а каждое чтение первой порции
  /// несёт новый запрос.
  IntentionCatalogQuery? _query;

  IntentionCatalogViewModel get _notifier =>
      ref.read(intentionCatalogViewModelProvider(widget.purpose).notifier);

  @override
  void initState() {
    super.initState();
    _query = _confirmedQuery(
      ref.read(intentionCatalogViewModelProvider(widget.purpose)),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = IntentionSearchKind.of(widget.purpose);
    ref.listen(
      intentionCatalogViewModelProvider(widget.purpose),
      (_, next) => _startNewResultsFromTop(next),
    );
    final catalog = ref.watch(
      intentionCatalogViewModelProvider(widget.purpose),
    );
    return catalog.when(
      skipLoadingOnReload: false,
      skipLoadingOnRefresh: false,
      data: (state) => switch (state) {
        IntentionCatalogDebouncing() => _status(
          ListState.loading(text: kind.loading(l10n)),
        ),
        IntentionCatalogInvalidFilter() => const SizedBox.shrink(),
        final IntentionCatalogLoaded loaded => _loaded(l10n, kind, loaded),
        final IntentionCatalogEmpty empty => _list([
          SliverFillRemaining(hasScrollBody: false, child: _empty(l10n, empty)),
        ]),
        IntentionCatalogUnavailable() => _status(
          ListState.error(
            message: kind.unavailable(l10n),
            retry: (
              label: l10n.commonRetry,
              onPressed: () => unawaited(_notifier.retry()),
            ),
          ),
        ),
        IntentionCatalogCorruption() => _status(
          ListState.error(message: kind.corruption(l10n)),
        ),
        IntentionCatalogUnexpected() => _status(
          ListState.error(message: kind.unexpected(l10n)),
        ),
      },
      error: (_, _) => _status(ListState.error(message: kind.unexpected(l10n))),
      loading: () => _status(ListState.loading(text: kind.loading(l10n))),
    );
  }

  Widget _loaded(
    AppLocalizations l10n,
    IntentionSearchKind kind,
    IntentionCatalogLoaded loaded,
  ) {
    final rows = loaded.items.length;
    final continuation = _continuation(l10n, kind, loaded);
    return _list([
      // Продолжение — последний элемент ленивого списка: кольцо подгрузки
      // строится, только когда конец выдачи подходит к экрану, иначе его
      // анимация требовала бы кадров непрерывно.
      SliverList.separated(
        itemCount: continuation == null ? rows : rows + 1,
        separatorBuilder: (_, index) => index < rows - 1
            ? const SizedBox(height: DoableMetrics.space2)
            : const SizedBox.shrink(),
        itemBuilder: (context, index) =>
            index < rows ? _row(loaded, index) : continuation!,
      ),
    ]);
  }

  /// Причину пустой выдачи называет запрос, который её дал.
  EmptyState _empty(AppLocalizations l10n, IntentionCatalogEmpty empty) {
    final query = empty.query;
    final actionsOnly =
        query.readinessFilter == IntentionReadinessFilter.readyOnly;
    return switch ((
      byTitle: query.titleFilter != null,
      byTags: query.tagFilter != IntentionTagFilter.empty,
    )) {
      (byTitle: false, byTags: false) when (empty.typeCounts?.all ?? 0) > 0 =>
        EmptyState(
          title: l10n.intentionPickerEmptyTypeTitle,
          text: l10n.intentionPickerEmptyTypeText,
          action: (
            label: l10n.intentionPickerShowBothTypes,
            onPressed: () => _notifier.changeType(IntentionTypeChoice.all),
          ),
        ),
      (byTitle: false, byTags: false) => EmptyState(
        title: l10n.intentionPickerEmptyScopeTitle,
        text: widget.emptyScopeMessage,
      ),
      (byTitle: true, byTags: false) => _filteredEmpty(
        l10n,
        title: actionsOnly
            ? l10n.intentionPickerNoActionsByTitle
            : l10n.intentionPickerNoIntentionsByTitle,
        text: l10n.intentionPickerTryShorterTitle,
      ),
      (byTitle: false, byTags: true) => _filteredEmpty(
        l10n,
        title: actionsOnly
            ? l10n.intentionPickerNoActionsByTags
            : l10n.intentionPickerNoIntentionsByTags,
        text: l10n.intentionPickerChangeTags,
      ),
      (byTitle: true, byTags: true) => _filteredEmpty(
        l10n,
        title: actionsOnly
            ? l10n.intentionPickerNoActionsFound
            : l10n.intentionPickerNoIntentionsFound,
        text: l10n.intentionPickerChangeTitleOrTags,
      ),
    };
  }

  EmptyState _filteredEmpty(
    AppLocalizations l10n, {
    required String title,
    required String text,
  }) => EmptyState(
    icon: DoableIconData.search,
    title: title,
    text: text,
    action: (
      label: l10n.intentionPickerResetFilters,
      onPressed: widget.onResetFilters,
    ),
  );

  /// Состояние вместо выдачи прокручивается, когда крупный текст не
  /// помещается в оставшуюся высоту.
  Widget _status(ListState state) =>
      ListView(padding: _sidePadding, children: [state]);

  Widget _list(List<Widget> slivers) => CustomScrollView(
    key: PageStorageKey<String>(
      '${IntentionSearchKind.of(widget.purpose).keyPrefix}-list',
    ),
    controller: _scrollController,
    slivers: [
      SliverPadding(
        padding: _sidePadding.copyWith(bottom: DoableMetrics.space10),
        sliver: SliverMainAxisGroup(slivers: slivers),
      ),
    ],
  );

  Widget _row(IntentionCatalogLoaded results, int index) {
    _requestNextPage(index);
    final summary = results.items[index];
    return IntentionPickerRow(
      key: ValueKey(
        '${IntentionSearchKind.of(widget.purpose).keyPrefix}-${summary.id.toCanonicalString()}',
      ),
      purpose: widget.purpose,
      summary: summary,
      requiredTagIds: results.query.tagFilter.requiredTagIds,
      onPick: () => widget.onPick(
        GraphSnapshot(value: summary, revision: results.revision),
      ),
      onOpenPage: () => widget.onOpenDetails(summary.id),
    );
  }

  Widget? _continuation(
    AppLocalizations l10n,
    IntentionSearchKind kind,
    IntentionCatalogLoaded results,
  ) => switch (results.continuation) {
    IntentionCatalogContinuationIdle() when results.nextCursor == null => null,
    IntentionCatalogContinuationIdle() ||
    IntentionCatalogContinuationLoading() => Padding(
      padding: const EdgeInsets.only(top: DoableMetrics.space4),
      child: ListState.more(text: kind.loadingMore(l10n)),
    ),
    IntentionCatalogContinuationUnavailable() => _continuationFailure(
      ListState.error(
        message: l10n.catalogLoadMoreUnavailable,
        retry: (
          label: l10n.commonRetry,
          onPressed: () => unawaited(_notifier.retryNextPage()),
        ),
      ),
    ),
    IntentionCatalogContinuationCorruption() => _continuationFailure(
      ListState.error(message: l10n.catalogLoadMoreCorruption),
    ),
    IntentionCatalogContinuationUnexpected() => _continuationFailure(
      ListState.error(message: l10n.catalogLoadMoreUnexpected),
    ),
  };

  Widget _continuationFailure(ListState state) => Padding(
    padding: const EdgeInsets.only(top: DoableMetrics.space2),
    child: state,
  );

  void _requestNextPage(int visibleIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_notifier.loadNextPageIfNeeded(visibleIndex: visibleIndex));
    });
  }

  void _startNewResultsFromTop(AsyncValue<IntentionCatalogState> next) {
    final query = _confirmedQuery(next);
    if (query == null || identical(query, _query)) {
      return;
    }
    final startsNewResults = _query != null;
    _query = query;
    // Список остаётся на экране, если новая выдача пришла раньше кадра,
    // который показал бы её загрузку.
    if (startsNewResults && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  static IntentionCatalogQuery? _confirmedQuery(
    AsyncValue<IntentionCatalogState> catalog,
  ) => switch (catalog.value) {
    IntentionCatalogConfirmedState(:final query) => query,
    _ => null,
  };
}
