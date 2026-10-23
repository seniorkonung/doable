import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/catalog_header.dart';
import '../../../design_system/components/empty_state.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../graph/application/graph_revision.dart';
import '../../application/intention_catalog.dart';
import '../../domain/intention_id.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../catalog/intention_catalog_state.dart';
import '../catalog/intention_catalog_view_model.dart';
import 'intention_picker_row.dart';

/// Выдача экрана выбора назначения [purpose]: заголовок с количеством,
/// строки, подгрузка следующей порции, пустая выдача и отказы.
///
/// Элемент один владеет прокруткой списка и возвращает его к началу, когда
/// модель подтверждает выдачу нового запроса.
final class IntentionPickerResults extends ConsumerStatefulWidget {
  const IntentionPickerResults({
    required this.purpose,
    required this.emptyScopeMessage,
    required this.onPick,
    required this.onOpenDetails,
    super.key,
  });

  final IntentionPickerPurpose purpose;

  /// Сообщение страницы о том, что допустимый охват пуст.
  final String emptyScopeMessage;

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
    final kind = _PickedKind.of(widget.purpose);
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
        final IntentionCatalogLoaded loaded => _list(kind, loaded, [
          SliverList.separated(
            itemCount: loaded.items.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: DoableMetrics.space2),
            itemBuilder: (context, index) => _row(loaded, index),
          ),
          if (_continuation(l10n, kind, loaded) case final continuation?)
            SliverToBoxAdapter(child: continuation),
        ]),
        final IntentionCatalogEmpty empty => _list(kind, empty, [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: l10n.intentionPickerEmptyScopeTitle,
              text: widget.emptyScopeMessage,
            ),
          ),
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

  /// Состояние вместо выдачи прокручивается, когда крупный текст не
  /// помещается в оставшуюся высоту.
  Widget _status(ListState state) =>
      ListView(padding: _sidePadding, children: [state]);

  Widget _list(
    _PickedKind kind,
    IntentionCatalogConfirmedState results,
    List<Widget> slivers,
  ) => CustomScrollView(
    key: PageStorageKey<String>('${_keyPrefix(widget.purpose)}-list'),
    controller: _scrollController,
    slivers: [
      SliverPadding(
        padding: _sidePadding,
        sliver: SliverToBoxAdapter(
          child: Container(
            constraints: const BoxConstraints(minHeight: 32),
            margin: const EdgeInsets.only(bottom: DoableMetrics.space1),
            alignment: AlignmentDirectional.centerStart,
            child: CatalogHeader(
              title: kind.header(AppLocalizations.of(context)),
              count: results.totalCount,
            ),
          ),
        ),
      ),
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
        '${_keyPrefix(widget.purpose)}-${summary.id.toCanonicalString()}',
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
    _PickedKind kind,
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

  /// Начало ключей списка и строк, по которым их находят сценарии поисков.
  static String _keyPrefix(IntentionPickerPurpose purpose) => switch (purpose) {
    SelectDailyChoiceAction() => 'daily-choice-action',
    SelectDailyChoiceSource() => 'daily-choice-source',
  };
}

/// Что выбирает поиск: от этого зависят тексты выдачи.
enum _PickedKind {
  action,
  intention;

  static _PickedKind of(IntentionPickerPurpose purpose) => switch (purpose) {
    SelectDailyChoiceAction() => action,
    SelectDailyChoiceSource() => intention,
  };

  String header(AppLocalizations l10n) => switch (this) {
    action => l10n.intentionPickerActionsHeader,
    intention => l10n.intentionPickerIntentionsHeader,
  };

  String loading(AppLocalizations l10n) => switch (this) {
    action => l10n.actionPickerLoading,
    intention => l10n.catalogLoading,
  };

  String loadingMore(AppLocalizations l10n) => switch (this) {
    action => l10n.intentionPickerLoadingMoreActions,
    intention => l10n.intentionPickerLoadingMoreIntentions,
  };

  String unavailable(AppLocalizations l10n) => switch (this) {
    action => l10n.actionPickerUnavailable,
    intention => l10n.catalogUnavailable,
  };

  String corruption(AppLocalizations l10n) => switch (this) {
    action => l10n.actionPickerCorruption,
    intention => l10n.catalogCorruption,
  };

  String unexpected(AppLocalizations l10n) => switch (this) {
    action => l10n.actionPickerUnexpected,
    intention => l10n.catalogUnexpectedFailure,
  };
}
