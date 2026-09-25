import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tag_catalog.dart' hide TagCatalogPage;
import 'tag_catalog_state.dart';
import 'tag_catalog_view_model.dart';

@RoutePage()
final class TagCatalogPage extends ConsumerWidget {
  const TagCatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(tagCatalogViewModelProvider);
    final model = ref.read(tagCatalogViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(localizations.tagCatalogTitle)),
      body: switch (state) {
        TagCatalogInitialLoading() => _CatalogStatus(
          message: localizations.tagCatalogLoading,
          loading: true,
        ),
        TagCatalogInitialFailure(:final failure, :final canRetry) =>
          _CatalogStatus(
            message: _readFailure(localizations, failure),
            onRetry: canRetry ? model.retryFirstPage : null,
          ),
        TagCatalogLoaded loaded => _LoadedCatalog(state: loaded, model: model),
      },
    );
  }
}

final class _LoadedCatalog extends StatelessWidget {
  const _LoadedCatalog({required this.state, required this.model});

  final TagCatalogLoaded state;
  final TagCatalogViewModel model;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (state.isEmpty && state.canUseCurrentItems) {
      return _CatalogStatus(message: localizations.tagCatalogEmpty);
    }
    return Column(
      children: [
        if (state.freshness == TagCatalogFreshness.refreshing)
          _CatalogInlineStatus(
            message: localizations.tagCatalogRefreshing,
            loading: true,
          ),
        if (state.freshness == TagCatalogFreshness.stale)
          _CatalogInlineStatus(
            message: _readFailure(localizations, state.refreshFailure!),
            onRetry: state.refreshFailure is TagCatalogUnavailableFailure
                ? model.retryRefresh
                : null,
          ),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('tag-catalog-list'),
            itemCount: state.items.length,
            itemBuilder: (context, index) {
              final tag = state.items[index];
              return Semantics(
                key: ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'),
                container: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Text(tag.name.value),
                ),
              );
            },
          ),
        ),
        if (state.canUseCurrentItems)
          switch (state.pageStatus) {
            TagCatalogPageLoading() => _CatalogInlineStatus(
              message: localizations.tagCatalogLoadingMore,
              loading: true,
            ),
            TagCatalogPageFailure(:final failure, :final canRetry) =>
              _CatalogInlineStatus(
                message: _pageFailure(localizations, failure),
                onRetry: canRetry ? model.retryLoadMore : null,
              ),
            TagCatalogPageIdle() =>
              state.nextCursor == null
                  ? _CatalogInlineStatus(
                      message: localizations.tagCatalogAllShown,
                    )
                  : _CatalogInlineStatus(
                      message: localizations.tagCatalogMoreAvailable,
                      actionLabel: localizations.tagCatalogLoadMore,
                      actionKey: const ValueKey('tag-catalog-load-more'),
                      onAction: model.loadMore,
                    ),
          },
      ],
    );
  }
}

final class _CatalogStatus extends StatelessWidget {
  const _CatalogStatus({
    required this.message,
    this.loading = false,
    this.onRetry,
  });

  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _StatusContent(
        message: message,
        loading: loading,
        actionLabel: onRetry == null
            ? null
            : AppLocalizations.of(context).commonRetry,
        onAction: onRetry,
      ),
    ),
  );
}

final class _CatalogInlineStatus extends StatelessWidget {
  const _CatalogInlineStatus({
    required this.message,
    this.loading = false,
    this.actionLabel,
    this.actionKey,
    this.onAction,
    this.onRetry,
  });

  final String message;
  final bool loading;
  final String? actionLabel;
  final Key? actionKey;
  final VoidCallback? onAction;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: _StatusContent(
      message: message,
      loading: loading,
      actionLabel: onRetry == null
          ? actionLabel
          : AppLocalizations.of(context).commonRetry,
      actionKey: actionKey,
      onAction: onRetry ?? onAction,
    ),
  );
}

final class _StatusContent extends StatelessWidget {
  const _StatusContent({
    required this.message,
    required this.loading,
    this.actionLabel,
    this.actionKey,
    this.onAction,
  });

  final String message;
  final bool loading;
  final String? actionLabel;
  final Key? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading) ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
        ],
        Text(message, textAlign: TextAlign.center),
        if (onAction case final action?) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            key: actionKey,
            onPressed: action,
            child: Text(actionLabel!),
          ),
        ],
      ],
    ),
  );
}

String _readFailure(
  AppLocalizations localizations,
  TagCatalogReadFailure failure,
) => switch (failure) {
  TagCatalogUnavailableFailure() => localizations.tagCatalogUnavailable,
  TagCatalogCorruptionFailure() => localizations.tagCatalogCorruption,
  TagCatalogInvalidCursor() ||
  TagCatalogSnapshotExpired() ||
  TagCatalogUnexpectedFailure() => localizations.tagCatalogUnexpected,
};

String _pageFailure(
  AppLocalizations localizations,
  TagCatalogReadFailure failure,
) => switch (failure) {
  TagCatalogUnavailableFailure() => localizations.tagCatalogLoadMoreUnavailable,
  TagCatalogCorruptionFailure() => localizations.tagCatalogLoadMoreCorruption,
  TagCatalogInvalidCursor() ||
  TagCatalogSnapshotExpired() ||
  TagCatalogUnexpectedFailure() => localizations.tagCatalogLoadMoreUnexpected,
};
