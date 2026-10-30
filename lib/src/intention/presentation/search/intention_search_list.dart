import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/empty_state.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/doable_icon.dart';
import '../../../design_system/doable_metrics.dart';
import '../../application/intention_catalog.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../catalog/intention_catalog_state.dart';
import '../catalog/intention_catalog_view_model.dart';
import 'intention_search_kind.dart';
import 'results_scroll_keeper.dart';

/// Строит строку найденного намерения [summary] выдачи [results].
typedef IntentionSearchRowBuilder = Widget Function(
  BuildContext context,
  IntentionCatalogLoaded results,
  IntentionSummary summary,
);

/// Выдача поиска намерений назначения [purpose]: строки, подгрузка следующей
/// порции, загрузка, отказы и пустая выдача.
///
/// Пустая выдача из-за фильтров предлагает их сбросить, а пустой выбранный
/// тип — показать оба типа. Пустой допустимый охват описывает страница через
/// [emptyScope].
///
/// Место в списке держит [ResultsScrollKeeper]: новая выдача начинается с
/// верхней позиции, а согласование выдачи с подтверждёнными операциями
/// оставляет видимую строку на месте. Элемент один владеет прокруткой
/// списка, а строки строит страница через [rowBuilder].
final class IntentionSearchList extends ConsumerStatefulWidget {
  const IntentionSearchList({
    required this.purpose,
    required this.rowBuilder,
    required this.emptyScope,
    required this.onResetFilters,
    required this.bottomPadding,
    super.key,
  });

  final IntentionCatalogPurpose purpose;

  final IntentionSearchRowBuilder rowBuilder;

  /// Содержание пустой выдачи, когда пуст сам допустимый охват, а не
  /// отобранное фильтрами или типом.
  final EmptyState Function(IntentionCatalogEmpty empty) emptyScope;

  /// Снимает фильтр названия и все условия по тегам: полем названия владеет
  /// страница.
  final VoidCallback onResetFilters;

  /// Отступ под последней строкой списка.
  final double bottomPadding;

  @override
  ConsumerState<IntentionSearchList> createState() =>
      _IntentionSearchListState();
}

final class _IntentionSearchListState
    extends ConsumerState<IntentionSearchList> {
  static const _sideInset = DoableMetrics.space5;

  late final ResultsScrollKeeper _scrollKeeper;

  /// Выдача, по которой построен список.
  late AsyncValue<IntentionCatalogState> _shown;

  IntentionCatalogViewModel get _notifier =>
      ref.read(intentionCatalogViewModelProvider(widget.purpose).notifier);

  @override
  void initState() {
    super.initState();
    _shown = ref.read(intentionCatalogViewModelProvider(widget.purpose));
    // Прокрутка одна для всех состояний и не пересоздаётся, а новая выдача
    // начинается с верхней позиции: сохранённое смещение не нужно.
    _scrollKeeper = ResultsScrollKeeper(
      shown: () => _shown,
      keepScrollOffset: false,
    );
  }

  @override
  void dispose() {
    _scrollKeeper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = IntentionSearchKind.of(widget.purpose);
    final provider = intentionCatalogViewModelProvider(widget.purpose);
    ref.listen(provider, _scrollKeeper.onCatalogChanged);
    final catalog = _shown = ref.watch(provider);
    final slivers = catalog.when(
      skipLoadingOnReload: false,
      skipLoadingOnRefresh: false,
      data: (state) => switch (state) {
        IntentionCatalogDebouncing() => _status(
          ListState.loading(text: kind.loading(l10n)),
        ),
        IntentionCatalogInvalidFilter() => const <Widget>[],
        final IntentionCatalogLoaded loaded => _loaded(l10n, kind, loaded),
        final IntentionCatalogEmpty empty => [
          SliverFillRemaining(hasScrollBody: false, child: _empty(l10n, empty)),
        ],
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
    return CustomScrollView(
      key: PageStorageKey<String>('${kind.keyPrefix}-list'),
      controller: _scrollKeeper.controller,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            _sideInset,
            0,
            _sideInset,
            widget.bottomPadding,
          ),
          sliver: SliverMainAxisGroup(slivers: slivers),
        ),
      ],
    );
  }

  /// Состояние вместо выдачи прокручивается, когда крупный текст не
  /// помещается в оставшуюся высоту.
  List<Widget> _status(ListState state) => [SliverToBoxAdapter(child: state)];

  List<Widget> _loaded(
    AppLocalizations l10n,
    IntentionSearchKind kind,
    IntentionCatalogLoaded loaded,
  ) {
    final rows = loaded.items.length;
    final continuation = _continuation(l10n, kind, loaded);
    return [
      // Продолжение — последний элемент ленивого списка: кольцо подгрузки
      // строится, только когда конец выдачи подходит к экрану, иначе его
      // анимация требовала бы кадров непрерывно.
      SliverList.separated(
        itemCount: continuation == null ? rows : rows + 1,
        separatorBuilder: (_, index) => index < rows - 1
            ? const SizedBox(height: DoableMetrics.space2)
            : const SizedBox.shrink(),
        itemBuilder: (context, index) =>
            index < rows ? _row(context, loaded, index) : continuation!,
      ),
    ];
  }

  Widget _row(BuildContext context, IntentionCatalogLoaded loaded, int index) {
    _requestNextPage(index);
    final summary = loaded.items[index];
    return KeyedSubtree(
      key: _scrollKeeper.keyFor(summary.id),
      child: widget.rowBuilder(context, loaded, summary),
    );
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
        _emptyType(l10n, empty, actionsOnly: actionsOnly),
      (byTitle: false, byTags: false) => widget.emptyScope(empty),
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

  /// Пустой выбранный тип. При открытом охвате заголовок называет охват,
  /// а текст и значок — тип; при закреплённом охвате текст общий.
  EmptyState _emptyType(
    AppLocalizations l10n,
    IntentionCatalogEmpty empty, {
    required bool actionsOnly,
  }) {
    final action = (
      label: l10n.intentionPickerShowBothTypes,
      onPressed: () => _notifier.changeType(IntentionTypeChoice.all),
    );
    return switch (empty.selection.scope) {
      IntentionScopeOpen() => EmptyState(
        icon: actionsOnly ? DoableIconData.bolt : DoableIconData.intention,
        title: l10n.intentionPickerEmptyScopedTypeTitle(
          empty.query.scope.name,
          (actionsOnly
                  ? IntentionTypeChoice.actions
                  : IntentionTypeChoice.intentions)
              .name,
        ),
        text: actionsOnly
            ? l10n.intentionPickerEmptyActionsText
            : l10n.intentionPickerEmptyIntentionsText,
        action: action,
      ),
      IntentionScopeFixed() => EmptyState(
        title: l10n.intentionPickerEmptyTypeTitle,
        text: l10n.intentionPickerEmptyTypeText,
        action: action,
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
}
