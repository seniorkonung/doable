import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/doable_metrics.dart';
import '../../application/intention_catalog.dart';
import '../search/results_scroll_keeper.dart';
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

/// Строит строку загруженного списка для намерения [summary] выдачи
/// [results].
typedef IntentionSearchResultBuilder = Widget Function(
  BuildContext context,
  IntentionCatalogLoaded results,
  IntentionSummary summary,
);

/// Выдача поиска намерений назначения [purpose].
///
/// Место в списке держит [ResultsScrollKeeper]: новая выдача начинается с
/// верхней позиции, а обновление выдачи без смены параметров поиска сохраняет
/// видимое намерение на экране. Страница передаёт состояние выдачи своего назначения
/// и построение своих строк; элемент не читает граф, не выполняет команд и
/// не меняет условия поиска.
final class IntentionSearchResults extends ConsumerStatefulWidget {
  const IntentionSearchResults({
    required this.purpose,
    required this.catalog,
    required this.listKey,
    required this.messages,
    required this.emptyMessage,
    required this.itemBuilder,
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

  @override
  ConsumerState<IntentionSearchResults> createState() =>
      _IntentionSearchResultsState();
}

final class _IntentionSearchResultsState
    extends ConsumerState<IntentionSearchResults> {
  late final ResultsScrollKeeper _scrollKeeper;

  /// Сохранённое смещение списка выдачи между его показами.
  var _listStorage = PageStorageBucket();

  IntentionCatalogViewModel get _notifier =>
      ref.read(intentionCatalogViewModelProvider(widget.purpose).notifier);

  @override
  void initState() {
    super.initState();
    // База не ждёт первого уведомления модели: иначе первая новая выдача
    // после уже загруженной сама стала бы базой и не началась бы с верхней
    // позиции. Список снимается с экрана загрузкой и пустой выдачей:
    // смещение той же выдачи возвращается из [_listStorage], когда список
    // показан снова.
    _scrollKeeper = ResultsScrollKeeper(
      shown: () => widget.catalog,
      keepScrollOffset: true,
    );
  }

  @override
  void dispose() {
    _scrollKeeper.dispose();
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

  Widget _buildEmpty(IntentionCatalogEmpty empty) =>
      IntentionCatalogStatusView(message: widget.emptyMessage(empty));

  Widget _buildLoaded(IntentionCatalogLoaded results) {
    final hasContinuationStatus =
        results.continuation is! IntentionCatalogContinuationIdle;
    return ListView.builder(
      key: widget.listKey,
      controller: _scrollKeeper.controller,
      padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space5),
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
        return KeyedSubtree(
          key: _scrollKeeper.keyFor(summary.id),
          child: widget.itemBuilder(context, results, summary),
        );
      },
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

  void _handleCatalogStateChanged(
    AsyncValue<IntentionCatalogState>? previous,
    AsyncValue<IntentionCatalogState> next,
  ) {
    if (_scrollKeeper.onCatalogChanged(previous, next)) {
      // Список снят с экрана загрузкой или пустой выдачей: сохранённое
      // смещение прежней выдачи вернулось бы вместе с ним. Новое хранилище
      // не переносит его в новую выдачу.
      setState(() => _listStorage = PageStorageBucket());
    }
  }
}
