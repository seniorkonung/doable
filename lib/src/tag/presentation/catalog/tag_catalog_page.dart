import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../application/tag_catalog.dart' hide TagCatalogPage;
import '../../application/tag_command.dart';
import '../../application/tag_result.dart';
import '../../application/tag_read_result.dart';
import '../../domain/tag.dart';
import '../editor/tag_editor_state.dart';
import '../tag_failure_message.dart';
import 'tag_catalog_state.dart';
import 'tag_catalog_view_model.dart';
import 'tag_delete_confirmation.dart';

@RoutePage()
final class TagCatalogPage extends ConsumerStatefulWidget {
  const TagCatalogPage({super.key});

  @override
  ConsumerState<TagCatalogPage> createState() => _TagCatalogPageState();
}

final class _TagCatalogPageState extends ConsumerState<TagCatalogPage> {
  final _creationKey = TagCreationFormKey();
  late final GraphCommandCoordinator _coordinator;
  TagOperationToken? _activeDeleteToken;
  TagOperationToken? _failureToken;
  GraphInitiatorPresentationClaim? _failureClaim;
  TagCommandFailure? _deleteFailure;
  bool _confirmationOpen = false;
  bool _deleteBusy = false;

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(graphCommandCoordinatorProvider.notifier);
  }

  @override
  void dispose() {
    _releasePresentation();
    super.dispose();
  }

  void _releasePresentation() {
    if (_activeDeleteToken case final token?) {
      _coordinator.releaseInitiatorPresentation(token);
    }
    if (_failureToken case final token?) {
      _coordinator.releaseInitiatorPresentation(token);
    }
    _failureToken = null;
    _failureClaim = null;
  }

  Future<void> _confirmDelete(Tag tag) async {
    if (_confirmationOpen ||
        _activeDeleteToken != null ||
        !ref.read(tagCatalogViewModelProvider.notifier).canActOn(tag.id)) {
      return;
    }
    setState(() => _confirmationOpen = true);
    final confirmed = await confirmTagDeletion(context, tag);
    if (!mounted) return;
    setState(() => _confirmationOpen = false);
    if (!confirmed) return;
    if (!ref.read(tagCatalogViewModelProvider.notifier).canActOn(tag.id)) {
      return;
    }
    _releasePresentation();
    final start = _coordinator.acceptTagDelete(DeleteTag(tag.id));
    switch (start) {
      case TagCommandAccepted(:final token, :final future):
        setState(() {
          _activeDeleteToken = token;
          _deleteFailure = null;
          _deleteBusy = false;
        });
        unawaited(_finishDelete(tag, token, future));
      case TagCommandAlreadyRunning():
        setState(() {
          _deleteBusy = true;
          _deleteFailure = null;
        });
      case GraphCommandCoordinatorDraining():
        setState(() {
          _deleteBusy = false;
          _deleteFailure = const TagUnexpectedFailure();
        });
    }
  }

  Future<void> _finishDelete(
    Tag tag,
    TagOperationToken token,
    Future<TagCommandCompletion> future,
  ) async {
    try {
      final completion = await future;
      if (!mounted || !identical(_activeDeleteToken, token)) return;
      switch (completion.result) {
        case GraphResultSuccess(value: TagDeleted(:final tagId))
            when tagId == tag.id:
          setState(() {
            _activeDeleteToken = null;
          });
        case GraphResultFailure(:final failure):
          final canPresentHere = ModalRoute.of(context)?.isCurrent ?? false;
          if (!canPresentHere) {
            _coordinator.releaseInitiatorPresentation(token);
          }
          setState(() {
            _activeDeleteToken = null;
            _deleteFailure = canPresentHere ? failure : null;
            _failureToken = canPresentHere ? token : null;
            _failureClaim = canPresentHere
                ? _coordinator.claimInitiatorFailure(token)
                : null;
          });
        case GraphResultSuccess():
          _coordinator.releaseInitiatorPresentation(token);
          setState(() {
            _activeDeleteToken = null;
            _deleteFailure = const TagUnexpectedFailure();
          });
      }
    } on Object {
      if (!mounted || !identical(_activeDeleteToken, token)) return;
      _coordinator.releaseInitiatorPresentation(token);
      setState(() {
        _activeDeleteToken = null;
        _deleteFailure = const TagUnexpectedFailure();
      });
    }
  }

  Future<void> _openEditor(TagEditorContext editorContext) async {
    final selected = await context.router.push<Tag>(
      TagEditorRoute(editorContext: editorContext),
    );
    if (mounted && selected != null) {
      ref.read(tagCatalogViewModelProvider.notifier).selectTag(selected.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(tagCatalogViewModelProvider);
    final model = ref.read(tagCatalogViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.tagCatalogTitle),
        actions: [
          IconButton(
            key: const ValueKey('tag-catalog-create'),
            tooltip: localizations.tagCatalogCreate,
            onPressed: () => _openEditor(TagEditorCreating(_creationKey)),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_activeDeleteToken != null)
            Semantics(
              liveRegion: true,
              child: _CatalogInlineStatus(
                message: localizations.tagDeleteSaving,
                loading: true,
              ),
            ),
          if (_deleteBusy)
            _CatalogInlineStatus(
              message: localizations.tagDeleteAlreadyRunning,
            ),
          if (_deleteFailure case final failure?)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OperationFailurePresentation(
                claim: _failureClaim,
                message: tagFailureMessage(localizations, failure),
                messageKey: const ValueKey('tag-delete-failure'),
              ),
            ),
          Expanded(
            child: switch (state) {
              TagCatalogInitialLoading() => _CatalogStatus(
                message: localizations.tagCatalogLoading,
                loading: true,
              ),
              TagCatalogInitialFailure(:final failure, :final canRetry) =>
                _CatalogStatus(
                  message: _readFailure(localizations, failure),
                  onRetry: canRetry ? model.retryFirstPage : null,
                ),
              TagCatalogLoaded loaded => _LoadedCatalog(
                state: loaded,
                model: model,
                selection: loaded.selection,
                onRename: (tag) {
                  if (model.canActOn(tag.id)) {
                    unawaited(_openEditor(TagEditorRenaming(tag)));
                  }
                },
                onDelete: (tag) => unawaited(_confirmDelete(tag)),
                canDelete: !_confirmationOpen && _activeDeleteToken == null,
              ),
            },
          ),
        ],
      ),
    );
  }
}

final class _LoadedCatalog extends StatelessWidget {
  const _LoadedCatalog({
    required this.state,
    required this.model,
    required this.selection,
    required this.onRename,
    required this.onDelete,
    required this.canDelete,
  });

  final TagCatalogLoaded state;
  final TagCatalogViewModel model;
  final TagCatalogSelection selection;
  final ValueChanged<Tag> onRename;
  final ValueChanged<Tag> onDelete;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (state.isEmpty &&
        state.canUseCurrentItems &&
        selection is TagCatalogNoSelection) {
      return _CatalogStatus(message: localizations.tagCatalogEmpty);
    }
    final selected = switch (selection) {
      TagCatalogSelectionReady(:final tag) => tag,
      _ => null,
    };
    final selectedInPage =
        selected != null && state.items.any((tag) => tag.id == selected.id);
    final selectedOutsidePage = selected != null && !selectedInPage;
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
        if (selection is TagCatalogSelectionLoading)
          _CatalogInlineStatus(
            message: localizations.tagCatalogLoading,
            loading: true,
          ),
        if (selection case TagCatalogSelectionFailure(
          :final failure,
          :final canRetry,
        ))
          _CatalogInlineStatus(
            message: _selectedReadFailure(localizations, failure),
            onRetry: canRetry ? model.retrySelectedTag : null,
          ),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('tag-catalog-list'),
            itemCount: state.items.length + (selectedOutsidePage ? 1 : 0),
            itemBuilder: (context, index) {
              if (selectedOutsidePage && index == 0) {
                final selectedTag = selected;
                return Semantics(
                  container: true,
                  selected: true,
                  child: ListTile(
                    title: Text(selectedTag.name.value),
                    subtitle: Text(localizations.tagCatalogSelected),
                    trailing: state.canUseCurrentItems
                        ? _TagActions(
                            tag: selectedTag,
                            onRename: onRename,
                            onDelete: onDelete,
                            canDelete: canDelete,
                          )
                        : null,
                  ),
                );
              }
              final item = state.items[index - (selectedOutsidePage ? 1 : 0)];
              final tag = item.id == selected?.id ? selected! : item;
              final selectedId = selection.id;
              return Semantics(
                key: ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'),
                container: true,
                selected: tag.id == selectedId,
                child: ListTile(
                  title: Text(tag.name.value),
                  trailing:
                      state.canUseCurrentItems &&
                          (tag.id != selectedId ||
                              selection is TagCatalogSelectionReady)
                      ? _TagActions(
                          tag: tag,
                          onRename: onRename,
                          onDelete: onDelete,
                          canDelete: canDelete,
                        )
                      : null,
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

final class _TagActions extends StatelessWidget {
  const _TagActions({
    required this.tag,
    required this.onRename,
    required this.onDelete,
    required this.canDelete,
  });

  final Tag tag;
  final ValueChanged<Tag> onRename;
  final ValueChanged<Tag> onDelete;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: l10n.tagCatalogRename,
          onPressed: () => onRename(tag),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          key: ValueKey('tag-catalog-delete-${tag.id.toCanonicalString()}'),
          tooltip: l10n.tagCatalogDelete,
          onPressed: canDelete ? () => onDelete(tag) : null,
          icon: const Icon(Icons.delete_outline),
        ),
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

String _selectedReadFailure(
  AppLocalizations localizations,
  TagReadFailure failure,
) => switch (failure) {
  TagReadUnavailableFailure() => localizations.tagEditorReadUnavailable,
  TagReadCorruptionFailure() => localizations.tagEditorReadCorruption,
  TagReadUnexpectedFailure() => localizations.tagEditorReadUnexpected,
};
