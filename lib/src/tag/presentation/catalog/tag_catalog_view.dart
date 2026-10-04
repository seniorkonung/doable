import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../intention/presentation/editor/intention_draft_tag_set.dart';
import '../../application/tag_catalog.dart';
import '../../application/tag_command.dart';
import '../../application/tag_result.dart';
import '../../application/tag_read_result.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';
import '../editor/tag_editor_state.dart';
import '../tag_failure_message.dart';
import 'tag_catalog_filter.dart';
import 'tag_catalog_search_controller.dart';
import 'tag_catalog_state.dart';
import 'tag_catalog_view_model.dart';
import 'tag_delete_confirmation.dart';
import 'tag_selection_context.dart';

/// Общий каталог тегов или выбор тега в типизированном контексте.
/// Поиск принадлежит одному открытию; маршруты и контекст задаются
/// потребителем.
final class TagCatalogView extends ConsumerStatefulWidget {
  const TagCatalogView({
    required this.onOpenEditor,
    required this.onOpenNavigation,
    this.selectionContext = const TagBrowseContext(),
    super.key,
  });

  /// Определяет режим чтения каталога и смысл явного действия выбора.
  final TagSelectionContext selectionContext;
  final Future<Tag?> Function(TagEditorContext) onOpenEditor;
  final ValueChanged<TagId> onOpenNavigation;

  @override
  ConsumerState<TagCatalogView> createState() => _TagCatalogViewState();
}

final class _TagCatalogViewState extends ConsumerState<TagCatalogView> {
  final _creationKey = TagCreationFormKey();
  final _scrollController = ScrollController();
  final _searchController = TagCatalogSearchController();
  TagCatalogFilter _filter = TagCatalogFilter.empty;
  bool _searchIsInvalid = false;
  int _modeGeneration = 0;
  TagCatalogOpening _draftOpening = TagCatalogOpening();
  late final GraphCommandCoordinator _coordinator;
  TagOperationToken? _activeDeleteToken;
  TagOperationToken? _failureToken;
  GraphInitiatorPresentationClaim? _failureClaim;
  TagCommandFailure? _deleteFailure;
  bool _confirmationOpen = false;
  bool _deleteBusy = false;
  TagOperationToken? _activeAssignToken;
  TagCommandFailure? _assignFailure;
  StreamSubscription<GraphCommandCompletion>? _busyDeleteSubscription;
  StreamSubscription<IntentionDraftTagSetSnapshot>? _draftSetChanges;

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(graphCommandCoordinatorProvider.notifier);
    _observeDraftSet();
  }

  @override
  void didUpdateWidget(covariant TagCatalogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionContext == widget.selectionContext) return;
    _modeGeneration++;
    _draftOpening = TagCatalogOpening();
    _releasePresentation();
    _activeAssignToken = null;
    _assignFailure = null;
    _activeDeleteToken = null;
    _deleteFailure = null;
    _deleteBusy = false;
    _confirmationOpen = false;
    unawaited(_busyDeleteSubscription?.cancel());
    _busyDeleteSubscription = null;
    _searchController.clear();
    _filter = TagCatalogFilter.empty;
    _searchIsInvalid = false;
    _scrollToStart();
    _observeDraftSet();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    unawaited(_busyDeleteSubscription?.cancel());
    unawaited(_draftSetChanges?.cancel());
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
    if (_activeAssignToken case final token?) {
      _coordinator.releaseInitiatorPresentation(token);
    }
    _failureToken = null;
    _failureClaim = null;
  }

  /// Просмотр и назначение разделяют состояние по режиму чтения; выбор для
  /// черновика читает обычный каталог в собственном открытии, не разделяя
  /// кандидата с каталогом тегов.
  TagCatalogViewModelProvider get _provider => tagCatalogViewModelProvider(
    mode: widget.selectionContext.readMode,
    opening: switch (widget.selectionContext) {
      TagBrowseContext() || TagAssignmentContext() => null,
      TagDraftContext() => _draftOpening,
    },
  );

  /// Признаки строк и доступность добавления читают текущий набор сессии;
  /// изменения набора и его доступности перестраивают выбор без смены
  /// открытия, поиска и прокрутки.
  void _observeDraftSet() {
    unawaited(_draftSetChanges?.cancel());
    _draftSetChanges = switch (widget.selectionContext) {
      TagDraftContext(:final tagSet) => tagSet.changes.listen((_) {
        if (mounted) setState(() {});
      }),
      TagBrowseContext() || TagAssignmentContext() => null,
    };
  }

  bool get _browsing => switch (widget.selectionContext) {
    TagBrowseContext() => true,
    TagAssignmentContext() || TagDraftContext() => false,
  };

  void _updateSearch(String input) {
    final result = TagCatalogFilter.fromInput(input);
    setState(() {
      switch (result) {
        case TagCatalogFilter():
          _filter = result;
          _searchIsInvalid = false;
        case TagCatalogFilterInvalidUnicode():
          _searchIsInvalid = true;
      }
    });
    _scrollToStart();
  }

  void _scrollToStart() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _updateSearch('');
  }

  void _assignSelected(TagAssignmentAction action) {
    if (_activeAssignToken != null) return;
    _releasePresentation();
    final start = action.perform();
    switch (start) {
      case TagCommandAccepted(:final token, :final future):
        setState(() {
          _activeAssignToken = token;
          _assignFailure = null;
        });
        unawaited(_finishAssign(token, future));
      case GraphCommandCoordinatorDraining():
        setState(() => _assignFailure = const TagUnexpectedFailure());
      case TagCommandAlreadyRunning():
        setState(() => _assignFailure = null);
      case null:
        break;
    }
  }

  /// Меняет только набор черновика: команд графа, назначений, сообщений и
  /// чтений каталога добавление не порождает. Набор сессии обновляется
  /// синхронно, поэтому признаки строк перестраиваются в том же кадре.
  void _addToDraft(TagDraftAdditionAction action) {
    if (action.perform() != null) setState(() {});
  }

  void _selectTag(TagId id) {
    if (_activeAssignToken != null) return;
    _releasePresentation();
    setState(() => _assignFailure = null);
    ref.read(_provider.notifier).selectTag(id);
  }

  Future<void> _finishAssign(
    TagOperationToken token,
    Future<TagCommandCompletion> future,
  ) async {
    try {
      final completion = await future;
      if (!mounted || !identical(_activeAssignToken, token)) return;
      switch (completion.result) {
        case GraphResultSuccess():
          setState(() => _activeAssignToken = null);
        case GraphResultFailure(:final failure):
          final canPresentHere = ModalRoute.of(context)?.isCurrent ?? false;
          if (!canPresentHere) {
            _coordinator.releaseInitiatorPresentation(token);
          }
          setState(() {
            _activeAssignToken = null;
            _assignFailure = canPresentHere ? failure : null;
            _failureToken = canPresentHere ? token : null;
            _failureClaim = canPresentHere
                ? _coordinator.claimInitiatorFailure(token)
                : null;
          });
      }
    } on Object {
      if (!mounted || !identical(_activeAssignToken, token)) return;
      _coordinator.releaseInitiatorPresentation(token);
      setState(() {
        _activeAssignToken = null;
        _assignFailure = const TagUnexpectedFailure();
      });
    }
  }

  Future<void> _confirmDelete(Tag tag) async {
    if (_confirmationOpen ||
        _activeDeleteToken != null ||
        !ref.read(_provider.notifier).canActOn(tag.id)) {
      return;
    }
    final generation = _modeGeneration;
    setState(() => _confirmationOpen = true);
    final confirmed = await confirmTagDeletion(context, tag);
    if (!mounted || generation != _modeGeneration) return;
    setState(() => _confirmationOpen = false);
    if (!confirmed) return;
    if (!ref.read(_provider.notifier).canActOn(tag.id)) {
      return;
    }
    _releasePresentation();
    unawaited(_busyDeleteSubscription?.cancel());
    _busyDeleteSubscription = null;
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
        _busyDeleteSubscription = _coordinator.completions.listen((_) {
          if (_coordinator.isTagRunning(tag.id)) return;
          unawaited(_busyDeleteSubscription?.cancel());
          _busyDeleteSubscription = null;
          if (mounted && _deleteBusy) {
            setState(() => _deleteBusy = false);
          }
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
    final generation = _modeGeneration;
    final selected = await widget.onOpenEditor(editorContext);
    if (mounted && selected != null && generation == _modeGeneration) {
      ref.read(_provider.notifier).selectTag(selected.id);
    }
  }

  void _openNavigation(TagId tagId) {
    if (!mounted ||
        !_browsing ||
        !ref.read(_provider.notifier).canActOn(tagId)) {
      return;
    }
    widget.onOpenNavigation(tagId);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(_provider);
    final model = ref.read(_provider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (widget.selectionContext) {
          TagBrowseContext() => localizations.tagCatalogTitle,
          TagAssignmentContext() ||
          TagDraftContext() => localizations.tagCatalogSelectionTitle,
        }),
        actions: [
          if (state is! TagCatalogIntentionMissing)
            IconButton(
              key: const ValueKey('tag-catalog-create'),
              tooltip: localizations.tagCatalogCreate,
              onPressed: () => _openEditor(TagEditorCreating(_creationKey)),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      bottomNavigationBar: switch ((widget.selectionContext, state)) {
        (TagAssignmentContext(), TagCatalogLoaded loaded) => _aboveKeyboard(
          _AssignAction(
            state: loaded,
            filter: _filter,
            action: TagAssignmentAction(model),
            onAssign: _assignSelected,
          ),
        ),
        (TagDraftContext(:final tagSet), TagCatalogLoaded loaded) =>
          _aboveKeyboard(
            _DraftAddAction(
              state: loaded,
              filter: _filter,
              draftSet: tagSet.current,
              action: TagDraftAdditionAction(model, tagSet),
              onAdd: _addToDraft,
            ),
          ),
        _ => null,
      },
      body: SizedBox.expand(
        key: const ValueKey('tag-catalog-viewport'),
        child: CustomScrollView(
          key: const ValueKey('tag-catalog-list'),
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  if (state is! TagCatalogIntentionMissing)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        key: const ValueKey('tag-catalog-search'),
                        controller: _searchController,
                        onChanged: _updateSearch,
                        decoration: InputDecoration(
                          labelText: localizations.tagCatalogSearch,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: localizations.tagCatalogClearSearch,
                                  onPressed: _clearSearch,
                                  icon: const Icon(Icons.clear),
                                ),
                          error: _searchIsInvalid
                              ? Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    localizations.tagCatalogInvalidSearch,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  if (_activeDeleteToken != null)
                    Semantics(
                      liveRegion: true,
                      child: _CatalogInlineStatus(
                        message: localizations.tagDeleteSaving,
                        loading: true,
                      ),
                    ),
                  if (_deleteBusy)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Semantics(
                        key: const ValueKey('tag-delete-already-running'),
                        container: true,
                        liveRegion: true,
                        label: localizations.tagDeleteAlreadyRunning,
                        child: ExcludeSemantics(
                          child: Text(
                            localizations.tagDeleteAlreadyRunning,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
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
                  if (state is TagCatalogLoaded &&
                      state.assignmentStatus is TagCatalogAssignmentSubmitting)
                    _CatalogInlineStatus(
                      message: localizations.tagCatalogAssigning,
                      loading: true,
                    ),
                  if (state is TagCatalogLoaded &&
                      state.assignmentStatus is TagCatalogAssignmentKeysBusy)
                    _CatalogInlineStatus(
                      message: localizations.tagAssignmentAlreadyRunning,
                    ),
                  if (_assignFailure case final failure?)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OperationFailurePresentation(
                        claim: _failureClaim,
                        message: tagAssignmentFailureMessage(
                          localizations,
                          failure,
                        ),
                        messageKey: const ValueKey(
                          'tag-catalog-assign-failure',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            switch (state) {
              TagCatalogInitialLoading() => SliverFillRemaining(
                hasScrollBody: false,
                child: _CatalogStatus(
                  message: localizations.tagCatalogLoading,
                  loading: true,
                ),
              ),
              TagCatalogInitialFailure(:final failure, :final canRetry) =>
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _CatalogStatus(
                    message: _readFailure(localizations, failure),
                    onRetry: canRetry ? model.retryInitialLoad : null,
                  ),
                ),
              TagCatalogIntentionMissing() => SliverFillRemaining(
                hasScrollBody: false,
                child: _CatalogStatus(
                  message: localizations.tagAssignmentIntentionNotFound,
                ),
              ),
              TagCatalogLoaded loaded => _LoadedCatalog(
                selectionContext: widget.selectionContext,
                state: loaded,
                filter: _filter,
                model: model,
                selection: loaded.selection,
                onRename: (tag) {
                  if (model.canActOn(tag.id)) {
                    unawaited(_openEditor(TagEditorRenaming(tag)));
                  }
                },
                onDelete: (tag) => unawaited(_confirmDelete(tag)),
                canDelete: !_confirmationOpen && _activeDeleteToken == null,
                onSelect: _selectTag,
                onOpen: _openNavigation,
              ),
            },
          ],
        ),
      ),
    );
  }

  Widget _aboveKeyboard(Widget action) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: action,
  );
}

final class _LoadedCatalog extends StatelessWidget {
  const _LoadedCatalog({
    required this.selectionContext,
    required this.state,
    required this.filter,
    required this.model,
    required this.selection,
    required this.onRename,
    required this.onDelete,
    required this.canDelete,
    required this.onSelect,
    required this.onOpen,
  });

  final TagSelectionContext selectionContext;
  final TagCatalogLoaded state;
  final TagCatalogFilter filter;
  final TagCatalogViewModel model;
  final TagCatalogSelection selection;
  final ValueChanged<Tag> onRename;
  final ValueChanged<Tag> onDelete;
  final bool canDelete;
  final ValueChanged<TagId> onSelect;
  final ValueChanged<TagId> onOpen;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final (choosing, showsAssignment) = switch (selectionContext) {
      TagBrowseContext() => (false, false),
      TagAssignmentContext() => (true, true),
      TagDraftContext() => (true, false),
    };
    final draftTagIds = switch (selectionContext) {
      TagDraftContext(:final tagSet) => tagSet.current.tagIds,
      TagBrowseContext() || TagAssignmentContext() => const <TagId>{},
    };
    // Признак строки передаётся текстом, а не только цветом: назначение
    // существующему намерению или включение в набор черновика.
    Widget? rowStatus(({Tag tag, bool isAssigned}) row) =>
        switch (selectionContext) {
          TagBrowseContext() => null,
          TagAssignmentContext() => Text(
            row.isAssigned
                ? localizations.tagCatalogAssigned
                : localizations.tagCatalogAvailable,
          ),
          TagDraftContext() => _DraftRowStatus(
            included: draftTagIds.contains(row.tag.id),
          ),
        };
    if (state.isEmpty &&
        filter.isEmpty &&
        state.canUseCurrentItems &&
        selection is TagCatalogNoSelection) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _CatalogStatus(message: localizations.tagCatalogEmpty),
      );
    }
    final selected = switch (selection) {
      TagCatalogSelectionReady(:final tag) => tag,
      _ => null,
    };
    final selectedInSnapshot =
        selected != null && state.items.any((tag) => tag.id == selected.id);
    final selectedOutsideSnapshot =
        !choosing &&
        selected != null &&
        !selectedInSnapshot &&
        filter.matches(selected.name);
    final rows =
        switch (state.mode) {
              TagCatalogBrowseMode() => state.items.map(
                (tag) => (tag: tag, isAssigned: false),
              ),
              TagCatalogSelectionMode() => state.selectionRows.map(
                (row) => (tag: row.tag, isAssigned: row.isAssigned),
              ),
            }
            .map(
              (row) => (
                tag: row.tag.id == selected?.id ? selected! : row.tag,
                isAssigned: row.isAssigned,
              ),
            )
            .where((row) => filter.matches(row.tag.name))
            .toList();
    final assignmentFailure = switch (state.selectedAssignment) {
      TagCatalogSelectedAssignment.unavailable =>
        localizations.tagAssignmentsUnavailable,
      TagCatalogSelectedAssignment.corruption =>
        localizations.tagAssignmentsCorruption,
      TagCatalogSelectedAssignment.unexpected =>
        localizations.tagAssignmentsUnexpected,
      _ => null,
    };
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
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
              if (showsAssignment &&
                  selection.id != null &&
                  assignmentFailure != null)
                _CatalogInlineStatus(
                  message: assignmentFailure,
                  onRetry:
                      state.selectedAssignment ==
                          TagCatalogSelectedAssignment.unavailable
                      ? model.retrySelectedAssignment
                      : null,
                ),
            ],
          ),
        ),
        if (state.canUseCurrentItems &&
            !filter.isEmpty &&
            rows.isEmpty &&
            !selectedOutsideSnapshot)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _CatalogStatus(message: localizations.tagCatalogNoMatches),
          )
        else
          SliverList.builder(
            itemCount: rows.length + (selectedOutsideSnapshot ? 1 : 0),
            itemBuilder: (context, index) {
              if (selectedOutsideSnapshot && index == 0) {
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
                            onOpen: onOpen,
                          )
                        : null,
                  ),
                );
              }
              final row = rows[index - (selectedOutsideSnapshot ? 1 : 0)];
              final tag = row.tag;
              final selectedId = selection.id;
              return Semantics(
                key: ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'),
                container: true,
                selected: tag.id == selectedId,
                child: ListTile(
                  title: Text(tag.name.value),
                  subtitle: rowStatus(row),
                  onTap:
                      choosing &&
                          state.canUseCurrentItems &&
                          state.assignmentStatus is TagCatalogAssignmentIdle
                      ? () => onSelect(tag.id)
                      : null,
                  trailing:
                      !choosing &&
                          state.canUseCurrentItems &&
                          (tag.id != selectedId ||
                              selection is TagCatalogSelectionReady)
                      ? _TagActions(
                          tag: tag,
                          onRename: onRename,
                          onDelete: onDelete,
                          canDelete: canDelete,
                          onOpen: onOpen,
                        )
                      : null,
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Признак включения тега в набор черновика. Строка резервирует высоту
/// большей из двух подписей, поэтому добавление не сдвигает строки списка
/// при любом языке и размере текста; диктору доступна только текущая подпись.
final class _DraftRowStatus extends StatelessWidget {
  const _DraftRowStatus({required this.included});

  final bool included;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return IndexedStack(
      index: included ? 1 : 0,
      children: [
        Text(localizations.tagCatalogAvailableForDraft),
        Text(localizations.tagCatalogInDraft),
      ],
    );
  }
}

final class _AssignAction extends StatelessWidget {
  const _AssignAction({
    required this.state,
    required this.filter,
    required this.action,
    required this.onAssign,
  });

  final TagCatalogLoaded state;
  final TagCatalogFilter filter;
  final TagAssignmentAction action;
  final ValueChanged<TagAssignmentAction> onAssign;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final selected = _readySelection(state);
    final assignmentLabel = switch (state.selectedAssignment) {
      TagCatalogSelectedAssignment.available =>
        localizations.tagCatalogAvailable,
      TagCatalogSelectedAssignment.assigned => localizations.tagCatalogAssigned,
      TagCatalogSelectedAssignment.unknown ||
      TagCatalogSelectedAssignment.unavailable ||
      TagCatalogSelectedAssignment.corruption ||
      TagCatalogSelectedAssignment.unexpected =>
        localizations.tagCatalogAssignmentUnknown,
    };
    return _SelectionActionArea(
      hiddenSelection: switch (_hiddenSelection(state, filter)) {
        final hidden? => (name: hidden.name.value, status: assignmentLabel),
        null => null,
      },
      action: FilledButton(
        key: const ValueKey('tag-catalog-assign'),
        onPressed: action.canPerform ? () => onAssign(action) : null,
        child: Text(
          localizations.tagCatalogAssign,
          semanticsLabel: selected == null
              ? localizations.tagCatalogAssign
              : localizations.tagCatalogAssignNamed(selected.name.value),
        ),
      ),
    );
  }
}

/// Явное добавление кандидата в набор черновика. Подпись и семантика
/// говорят о черновике, а не о сохранённом назначении; уже включённый тег,
/// неподтверждённый кандидат, отправка и закрытая сессия действие отключают.
final class _DraftAddAction extends StatelessWidget {
  const _DraftAddAction({
    required this.state,
    required this.filter,
    required this.draftSet,
    required this.action,
    required this.onAdd,
  });

  final TagCatalogLoaded state;
  final TagCatalogFilter filter;
  final IntentionDraftTagSetSnapshot draftSet;
  final TagDraftAdditionAction action;
  final ValueChanged<TagDraftAdditionAction> onAdd;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final selected = _readySelection(state);
    return _SelectionActionArea(
      hiddenSelection: switch (_hiddenSelection(state, filter)) {
        final hidden? => (
          name: hidden.name.value,
          status: draftSet.tagIds.contains(hidden.id)
              ? localizations.tagCatalogInDraft
              : localizations.tagCatalogAvailableForDraft,
        ),
        null => null,
      },
      unavailableReason: switch (draftSet.availability) {
        IntentionDraftAvailability.editable => null,
        IntentionDraftAvailability.submitting =>
          localizations.tagCatalogDraftSubmitting,
        IntentionDraftAvailability.closed =>
          localizations.tagCatalogDraftClosed,
      },
      action: FilledButton(
        key: const ValueKey('tag-catalog-add-to-draft'),
        onPressed: action.canPerform ? () => onAdd(action) : null,
        child: Text(
          localizations.tagCatalogAddToDraft,
          semanticsLabel: selected == null
              ? localizations.tagCatalogAddToDraftSemantic
              : localizations.tagCatalogAddToDraftNamed(selected.name.value),
        ),
      ),
    );
  }
}

Tag? _readySelection(TagCatalogLoaded state) => switch (state.selection) {
  TagCatalogSelectionReady(:final tag) => tag,
  _ => null,
};

/// Выбранный тег, которого не видно в списке: его скрывает поиск или он ещё
/// не вошёл в отображаемый снимок.
Tag? _hiddenSelection(TagCatalogLoaded state, TagCatalogFilter filter) {
  final selected = _readySelection(state);
  return selected != null &&
          (!filter.matches(selected.name) ||
              !state.items.any((tag) => tag.id == selected.id))
      ? selected
      : null;
}

/// Закреплённая область явного действия общего выбора.
final class _SelectionActionArea extends StatelessWidget {
  const _SelectionActionArea({
    required this.hiddenSelection,
    required this.action,
    this.unavailableReason,
  });

  /// Название и признак выбранного тега, которого не видно в списке.
  final ({String name, String status})? hiddenSelection;

  /// Причина недоступности действия, не зависящая от выбранного тега.
  final String? unavailableReason;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final hiddenSelection = this.hiddenSelection;
    final unavailableReason = this.unavailableReason;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Align(
          heightFactor: 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                // Постоянная высота сохраняет границы списка при смене выбора.
                // Длинное название и увеличенный текст доступны через прокрутку.
                height: 96.0.clamp(0, MediaQuery.sizeOf(context).height / 3),
                child: hiddenSelection == null && unavailableReason == null
                    ? null
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (unavailableReason != null)
                              Semantics(
                                key: const ValueKey(
                                  'tag-catalog-draft-unavailable',
                                ),
                                container: true,
                                liveRegion: true,
                                child: Text(
                                  unavailableReason,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            if (hiddenSelection case (
                              :final name,
                              :final status,
                            ))
                              Semantics(
                                key: const ValueKey(
                                  'tag-catalog-hidden-selection',
                                ),
                                container: true,
                                selected: true,
                                liveRegion: true,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(localizations.tagCatalogSelected),
                                    Text(name, textAlign: TextAlign.center),
                                    Text(status, textAlign: TextAlign.center),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
              action,
            ],
          ),
        ),
      ),
    );
  }
}

final class _TagActions extends StatelessWidget {
  const _TagActions({
    required this.tag,
    required this.onRename,
    required this.onDelete,
    required this.canDelete,
    required this.onOpen,
  });

  final Tag tag;
  final ValueChanged<Tag> onRename;
  final ValueChanged<Tag> onDelete;
  final bool canDelete;
  final ValueChanged<TagId> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('tag-catalog-open-${tag.id.toCanonicalString()}'),
          tooltip: l10n.tagNavigationTitle,
          onPressed: () => onOpen(tag.id),
          icon: const Icon(Icons.arrow_forward),
        ),
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
    child: Padding(
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
    this.onRetry,
  });

  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: _StatusContent(
      message: message,
      loading: loading,
      actionLabel: onRetry == null
          ? null
          : AppLocalizations.of(context).commonRetry,
      onAction: onRetry,
    ),
  );
}

final class _StatusContent extends StatelessWidget {
  const _StatusContent({
    required this.message,
    required this.loading,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool loading;
  final String? actionLabel;
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
          OutlinedButton(onPressed: action, child: Text(actionLabel!)),
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
  TagCatalogIntentionNotFound() ||
  TagCatalogUnexpectedFailure() => localizations.tagCatalogUnexpected,
};

String _selectedReadFailure(
  AppLocalizations localizations,
  TagReadFailure failure,
) => switch (failure) {
  TagReadUnavailableFailure() => localizations.tagEditorReadUnavailable,
  TagReadCorruptionFailure() => localizations.tagEditorReadCorruption,
  TagReadUnexpectedFailure() => localizations.tagEditorReadUnexpected,
};
