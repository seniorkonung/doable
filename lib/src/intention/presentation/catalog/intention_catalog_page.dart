import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/intention_repository.dart';
import '../../domain/intention.dart';
import 'intention_catalog_state.dart';
import 'intention_catalog_view_model.dart';

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

  @override
  void dispose() {
    _filterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final catalog = ref.watch(intentionCatalogViewModelProvider);
    final notifier = ref.read(intentionCatalogViewModelProvider.notifier);
    final selection = catalog.value?.selection ?? notifier.selection;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.catalogTitle)),
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
              ),
              error: (_, _) => _CatalogStatus(
                message: localizations.catalogUnexpectedFailure,
              ),
              loading: () => _CatalogStatus(
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
  const _CatalogContent({required this.state, required this.scrollController});

  final IntentionCatalogState state;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return switch (state) {
      IntentionCatalogDebouncing() => _CatalogStatus(
        message: localizations.catalogLoading,
        progressIndicator: true,
      ),
      IntentionCatalogInvalidFilter() => const SizedBox.shrink(),
      IntentionCatalogLoaded loaded => _LoadedCatalog(
        state: loaded,
        scrollController: scrollController,
      ),
      IntentionCatalogEmpty empty => _CatalogStatus(
        message: _emptyMessage(localizations, empty.scope),
      ),
      IntentionCatalogUnavailable() => _CatalogStatus(
        message: localizations.catalogUnavailable,
        retryLabel: localizations.commonRetry,
        onRetry: () {
          ref.read(intentionCatalogViewModelProvider.notifier).retry();
        },
      ),
      IntentionCatalogCorruption() => _CatalogStatus(
        message: localizations.catalogCorruption,
      ),
      IntentionCatalogUnexpected() => _CatalogStatus(
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

final class _LoadedCatalog extends StatelessWidget {
  const _LoadedCatalog({required this.state, required this.scrollController});

  final IntentionCatalogLoaded state;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
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
            key: const ValueKey('catalog-list'),
            controller: scrollController,
            itemCount: state.items.length,
            itemBuilder: (context, index) =>
                _IntentionSummaryTile(summary: state.items[index]),
          ),
        ),
      ],
    );
  }
}

final class _IntentionSummaryTile extends StatelessWidget {
  const _IntentionSummaryTile({required this.summary});

  final IntentionSummary summary;

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
    return ListTile(
      title: Text(summary.title),
      subtitle: Wrap(
        spacing: 12,
        children: [Text(readiness), Text(description)],
      ),
    );
  }
}

final class _CatalogStatus extends StatelessWidget {
  const _CatalogStatus({
    required this.message,
    this.progressIndicator = false,
    this.retryLabel,
    this.onRetry,
  }) : assert((retryLabel == null) == (onRetry == null));

  final String message;
  final bool progressIndicator;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (progressIndicator) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
              ],
              Text(message, textAlign: TextAlign.center),
              if (onRetry case final retry?) ...[
                const SizedBox(height: 24),
                FilledButton(onPressed: retry, child: Text(retryLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
