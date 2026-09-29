import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../intention/domain/intention.dart';
import '../../application/tagged_intentions_page.dart';
import '../../domain/tag_id.dart';
import 'tag_navigation_state.dart';
import 'tag_navigation_view_model.dart';

@RoutePage()
final class TagNavigationPage extends ConsumerWidget
    implements AutoRouteWrapper {
  const TagNavigationPage({required this.tagId, super.key});

  final TagId tagId;

  /// Новый вход начинает активный охват, сохраняя выбор предыдущего экрана.
  @override
  Widget wrappedRoute(BuildContext context) => ProviderScope(
    overrides: [
      tagNavigationViewModelProvider(tagId)
          .overrideWith(TagNavigationViewModel.new),
    ],
    child: this,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = tagNavigationViewModelProvider(tagId);
    final state = ref.watch(provider);
    final model = ref.read(provider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tagNavigationTitle)),
      body: SafeArea(
        child: CustomScrollView(
          key: PageStorageKey(tagId),
          slivers: [
            if (state case TagNavigationLoaded(:final tag))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.tagNavigationTag(tag.name.value),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.tagNavigationScope),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final scope in TaggedIntentionsScope.values)
                          ChoiceChip(
                            key: ValueKey(scope),
                            label: Text(switch (scope) {
                              TaggedIntentionsScope.active =>
                                l10n.catalogScopeActive,
                              TaggedIntentionsScope.archived =>
                                l10n.catalogScopeArchived,
                            }),
                            selected: state.scope == scope,
                            onSelected: state is TagNavigationTagMissing
                                ? null
                                : (_) => model.setScope(scope),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ...switch (state) {
              TagNavigationInitialLoading() => [
                _NavigationStatus(
                  message: l10n.tagNavigationLoading,
                  loading: true,
                ),
              ],
              TagNavigationTagMissing() => [
                _NavigationStatus(message: l10n.tagNotFound),
              ],
              TagNavigationInitialFailure(:final failure, :final canRetry) => [
                _NavigationStatus(
                  message: _readFailure(l10n, failure),
                  onAction: canRetry ? model.retryFirstPage : null,
                ),
              ],
              final TagNavigationLoaded loaded => [
                if (!loaded.canUseCurrentItems)
                  _NavigationStatus(
                    message:
                        loaded.freshness == TagNavigationFreshness.refreshing
                        ? l10n.tagNavigationRefreshing
                        : _refreshFailure(l10n, loaded.refreshFailure),
                    loading:
                        loaded.freshness == TagNavigationFreshness.refreshing,
                    onAction:
                        loaded.refreshFailure
                            is TaggedIntentionsUnavailableFailure
                        ? model.retryRefresh
                        : null,
                  ),
                if (loaded.isEmpty && loaded.canUseCurrentItems)
                  _NavigationStatus(
                    message: switch (loaded.scope) {
                      TaggedIntentionsScope.active =>
                        l10n.tagNavigationEmptyActive,
                      TaggedIntentionsScope.archived =>
                        l10n.tagNavigationEmptyArchived,
                    },
                  ),
                SliverList.builder(
                  itemCount: loaded.items.length,
                  itemBuilder: (context, index) {
                    final item = loaded.items[index];
                    return _IntentionRow(
                      key: ValueKey(item.id),
                      item: item,
                      onOpen: loaded.canUseCurrentItems
                          ? () {
                              // Между кадром и нажатием могла подтвердиться
                              // новая ревизия: проверяем право перехода заново.
                              if (!model.canActOn(item.id)) return;
                              unawaited(
                                context.router.push(
                                  IntentionDetailsRoute(intentionId: item.id),
                                ),
                              );
                            }
                          : null,
                    );
                  },
                ),
                if (loaded.canUseCurrentItems && !loaded.isEmpty)
                  switch (loaded.pageStatus) {
                    TagNavigationPageLoading() => _NavigationStatus(
                      message: l10n.tagNavigationLoadingMore,
                      loading: true,
                    ),
                    TagNavigationPageFailure(:final failure, :final canRetry) =>
                      _NavigationStatus(
                        message: _pageFailure(l10n, failure),
                        onAction: canRetry ? model.retryLoadMore : null,
                      ),
                    TagNavigationPageIdle() => _NavigationStatus(
                      message: loaded.hasReachedEnd
                          ? l10n.tagNavigationAllShown
                          : l10n.tagNavigationMoreAvailable,
                      actionLabel: l10n.tagNavigationLoadMore,
                      onAction: loaded.hasReachedEnd ? null : model.loadMore,
                    ),
                  },
              ],
            },
          ],
        ),
      ),
    );
  }
}

final class _IntentionRow extends StatelessWidget {
  const _IntentionRow({required this.item, required this.onOpen, super.key});

  final TaggedIntention item;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = item.title;
    final kindAndState = item.archiveState == IntentionArchiveState.active
        ? l10n.tagNavigationIntentionActive
        : l10n.tagNavigationIntentionArchived;
    return Semantics(
      container: true,
      button: true,
      enabled: onOpen != null,
      label: '$kindAndState: $title',
      hint: onOpen == null ? null : l10n.tagNavigationOpenDetails,
      onTap: onOpen,
      excludeSemantics: true,
      child: ListTile(
        enabled: onOpen != null,
        title: Text(title),
        subtitle: Text(kindAndState),
        onTap: onOpen,
      ),
    );
  }
}

/// Все статусы находятся в той же прокрутке, что и строки и переключатель.
final class _NavigationStatus extends StatelessWidget {
  const _NavigationStatus({
    required this.message,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          children: [
            if (loading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
            ],
            Text(message, textAlign: TextAlign.center),
            if (onAction case final action?) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  if (context.mounted) action();
                },
                child: Text(
                  actionLabel ?? AppLocalizations.of(context).commonRetry,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

String _readFailure(
  AppLocalizations l10n,
  TaggedIntentionsReadFailure failure,
) => switch (failure) {
  TaggedIntentionsTagNotFound() => l10n.tagNotFound,
  TaggedIntentionsInvalidCursor() => l10n.tagNavigationInvalidCursor,
  TaggedIntentionsSnapshotExpired() => l10n.tagNavigationSnapshotExpired,
  TaggedIntentionsUnavailableFailure() => l10n.tagNavigationUnavailable,
  TaggedIntentionsCorruptionFailure() => l10n.tagNavigationCorruption,
  TaggedIntentionsUnexpectedFailure() => l10n.tagNavigationUnexpected,
};

String _pageFailure(
  AppLocalizations l10n,
  TaggedIntentionsReadFailure failure,
) => switch (failure) {
  TaggedIntentionsUnavailableFailure() => l10n.tagNavigationLoadMoreUnavailable,
  TaggedIntentionsCorruptionFailure() => l10n.tagNavigationLoadMoreCorruption,
  TaggedIntentionsUnexpectedFailure() => l10n.tagNavigationLoadMoreUnexpected,
  _ => _readFailure(l10n, failure),
};

String _refreshFailure(
  AppLocalizations l10n,
  TaggedIntentionsReadFailure? failure,
) => switch (failure) {
  TaggedIntentionsUnavailableFailure() => l10n.tagNavigationRefreshUnavailable,
  TaggedIntentionsCorruptionFailure() => l10n.tagNavigationRefreshCorruption,
  TaggedIntentionsUnexpectedFailure() ||
  null => l10n.tagNavigationRefreshUnexpected,
  _ => _readFailure(l10n, failure),
};
