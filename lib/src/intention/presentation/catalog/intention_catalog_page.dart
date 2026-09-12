import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
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
  late final IntentionCatalogViewModel _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(intentionCatalogViewModelProvider.notifier);
    _notifier.addPresentationListener(_showPresentationEvent);
  }

  @override
  void dispose() {
    _notifier.removePresentationListener(_showPresentationEvent);
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

  void _showPresentationEvent(IntentionCatalogPresentationEvent event) {
    if (!mounted) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    final message = switch (event) {
      IntentionCatalogCreatePresentationEvent(:final outcome) =>
        switch (outcome) {
          IntentionCatalogCreateOutcome.succeeded =>
            localizations.editorCreated,
          IntentionCatalogCreateOutcome.validation =>
            localizations.editorInvalidInput,
          IntentionCatalogCreateOutcome.conflict =>
            localizations.editorCreateConflict,
          IntentionCatalogCreateOutcome.unavailable =>
            localizations.editorCreateUnavailable,
          IntentionCatalogCreateOutcome.corruption =>
            localizations.editorCreateCorruption,
          IntentionCatalogCreateOutcome.unexpected =>
            localizations.editorCreateUnexpected,
        },
      IntentionCatalogUpdatePresentationEvent(:final outcome) =>
        switch (outcome) {
          IntentionCatalogUpdateOutcome.succeeded => localizations.detailsSaved,
          IntentionCatalogUpdateOutcome.validation =>
            localizations.detailsUpdateInvalidInput,
          IntentionCatalogUpdateOutcome.notFound =>
            localizations.detailsUpdateNotFound,
          IntentionCatalogUpdateOutcome.conflict =>
            localizations.detailsUpdateConflict,
          IntentionCatalogUpdateOutcome.unavailable =>
            localizations.detailsUpdateUnavailable,
          IntentionCatalogUpdateOutcome.corruption =>
            localizations.detailsUpdateCorruption,
          IntentionCatalogUpdateOutcome.unexpected =>
            localizations.detailsUpdateUnexpected,
        },
      IntentionCatalogDeletePresentationEvent(:final outcome) =>
        switch (outcome) {
          IntentionCatalogDeleteOutcome.succeeded =>
            localizations.detailsDeleted,
          IntentionCatalogDeleteOutcome.validation =>
            localizations.detailsDeleteInvalid,
          IntentionCatalogDeleteOutcome.notFound =>
            localizations.detailsDeleteNotFound,
          IntentionCatalogDeleteOutcome.conflict =>
            localizations.detailsDeleteConflict,
          IntentionCatalogDeleteOutcome.unavailable =>
            localizations.detailsDeleteUnavailable,
          IntentionCatalogDeleteOutcome.corruption =>
            localizations.detailsDeleteCorruption,
          IntentionCatalogDeleteOutcome.unexpected =>
            localizations.detailsDeleteUnexpected,
        },
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

final class _LoadedCatalog extends ConsumerWidget {
  const _LoadedCatalog({required this.state, required this.scrollController});

  final IntentionCatalogLoaded state;
  final ScrollController scrollController;

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
                return _CatalogContinuationStatus(
                  continuation: state.continuation,
                );
              }
              _requestNextPage(context, ref, index);
              final summary = state.items[index];
              return _IntentionSummaryTile(
                summary: summary,
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
            .read(intentionCatalogViewModelProvider.notifier)
            .loadNextPageIfNeeded(visibleIndex: visibleIndex),
      );
    });
  }
}

final class _CatalogContinuationStatus extends ConsumerWidget {
  const _CatalogContinuationStatus({required this.continuation});

  final IntentionCatalogContinuationState continuation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final notifier = ref.read(intentionCatalogViewModelProvider.notifier);
    return switch (continuation) {
      IntentionCatalogContinuationIdle() => const SizedBox.shrink(),
      IntentionCatalogContinuationLoading() => _CatalogInlineStatus(
        message: localizations.catalogLoadingMore,
      ),
      IntentionCatalogContinuationUnavailable() => _CatalogInlineStatus(
        message: localizations.catalogLoadMoreUnavailable,
        actionLabel: localizations.commonRetry,
        onAction: notifier.retryNextPage,
      ),
      IntentionCatalogContinuationCorruption() => _CatalogInlineStatus(
        message: localizations.catalogLoadMoreCorruption,
      ),
      IntentionCatalogContinuationUnexpected() => _CatalogInlineStatus(
        message: localizations.catalogLoadMoreUnexpected,
      ),
      IntentionCatalogContinuationValidation() => _CatalogInlineStatus(
        message: localizations.catalogLoadMoreValidation,
        actionLabel: localizations.catalogReload,
        onAction: notifier.recoverFromInvalidCursor,
      ),
      IntentionCatalogContinuationRecovering() => _CatalogInlineStatus(
        message: localizations.catalogReloading,
      ),
      IntentionCatalogRecoveryUnavailable() => _CatalogInlineStatus(
        message: localizations.catalogUnavailable,
        actionLabel: localizations.commonRetry,
        onAction: notifier.retryRecovery,
      ),
      IntentionCatalogRecoveryCorruption() => _CatalogInlineStatus(
        message: localizations.catalogCorruption,
      ),
      IntentionCatalogRecoveryUnexpected() => _CatalogInlineStatus(
        message: localizations.catalogUnexpectedFailure,
      ),
    };
  }
}

final class _CatalogInlineStatus extends StatelessWidget {
  const _CatalogInlineStatus({
    required this.message,
    this.actionLabel,
    this.onAction,
  }) : assert((actionLabel == null) == (onAction == null));

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (onAction case final action?) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: action, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

final class _IntentionSummaryTile extends StatelessWidget {
  const _IntentionSummaryTile({required this.summary, required this.onTap});

  final IntentionSummary summary;
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
    return ListTile(
      onTap: onTap,
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
