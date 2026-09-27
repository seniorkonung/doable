import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../application/tag_catalog.dart';
import '../../application/tag_assignment_status.dart';
import '../../application/tag_change.dart';
import '../../application/tag_command.dart';
import '../../application/tag_read_result.dart';
import '../../application/tag_result.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';
import '../../domain/tag_target.dart';
import 'tag_catalog_state.dart';

part 'tag_catalog_view_model.g.dart';

@riverpod
final class TagCatalogViewModel extends _$TagCatalogViewModel {
  static const _maxStaleReads = 8;

  late PersonalGraphRepository _repository;
  late GraphCommandCoordinator _coordinator;
  TagCatalogMode _mode = const TagCatalogBrowseMode();
  TagCatalogAssignmentStatus _assignmentStatus =
      const TagCatalogAssignmentIdle();
  StreamSubscription<GraphCommandCompletion>? _completions;
  StreamSubscription<TagReadResult>? _selectedReads;
  TagCatalogSelection _selection = const TagCatalogNoSelection();
  GraphRevision? _selectedRevision;
  TagCatalogSelectedAssignment _selectedAssignment =
      TagCatalogSelectedAssignment.unknown;
  GraphRevision? _selectedAssignmentRevision;
  TagId? _newlyCreatedTagId;
  GraphRevision? _newlyCreatedRevision;
  int _selectionGeneration = 0;
  int _assignmentReadGeneration = 0;
  int _assignmentStaleReads = 0;
  GraphRevision? _requiredRevision;
  Future<void>? _activeRequest;
  bool _refreshNeeded = false;
  int _generation = 0;
  int _staleReadAttempts = 0;

  @override
  TagCatalogState build({TagCatalogMode mode = const TagCatalogBrowseMode()}) {
    unawaited(_completions?.cancel());
    unawaited(_selectedReads?.cancel());
    _repository = ref.watch(personalGraphRepositoryProvider);
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _mode = mode;
    _assignmentStatus = const TagCatalogAssignmentIdle();
    _requiredRevision = null;
    _selection = const TagCatalogNoSelection();
    _selectedRevision = null;
    _clearSelectedAssignment();
    _newlyCreatedTagId = null;
    _newlyCreatedRevision = null;
    _selectionGeneration++;
    _assignmentReadGeneration++;
    _assignmentStaleReads = 0;
    _activeRequest = null;
    _refreshNeeded = false;
    _generation++;
    _staleReadAttempts = 0;
    _completions = _coordinator.completions.listen(_onCompletion);
    ref.onDispose(() {
      unawaited(_completions?.cancel());
      unawaited(_selectedReads?.cancel());
    });
    unawaited(_startFirst());
    return TagCatalogInitialLoading(mode: mode);
  }

  /// Смена режима или получателя отменяет право прежних порций и выбора
  /// изменять новое состояние, не прерывая уже принятую команду.
  void setMode(TagCatalogMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _generation++;
    _selectionGeneration++;
    _assignmentReadGeneration++;
    _assignmentStaleReads = 0;
    unawaited(_selectedReads?.cancel());
    _selectedReads = null;
    _selection = const TagCatalogNoSelection();
    _selectedRevision = null;
    _clearSelectedAssignment();
    _newlyCreatedTagId = null;
    _newlyCreatedRevision = null;
    _assignmentStatus = const TagCatalogAssignmentIdle();
    _staleReadAttempts = 0;
    state = TagCatalogInitialLoading(mode: mode);
    if (_activeRequest == null) {
      unawaited(_startFirst());
    } else {
      _refreshNeeded = true;
    }
  }

  Future<void> retryFirstPage() {
    final current = state;
    if (current is! TagCatalogInitialFailure || !current.canRetry) {
      return Future.value();
    }
    state = TagCatalogInitialLoading(mode: _mode);
    _staleReadAttempts = 0;
    return _startFirst();
  }

  void selectTag(TagId id) {
    _selectionGeneration++;
    _assignmentReadGeneration++;
    _assignmentStaleReads = 0;
    final generation = _selectionGeneration;
    unawaited(_selectedReads?.cancel());
    _selectedReads = null;
    _selectedRevision = null;
    _clearSelectedAssignment();
    if (state case TagCatalogLoaded(:final selectionRows, :final revision)) {
      _selectedAssignmentFromRows(selectionRows, id, revision);
    }
    final createdRevision = _newlyCreatedRevision;
    final pageRevision = switch (state) {
      TagCatalogLoaded(:final revision) => revision,
      _ => null,
    };
    if (_selectedAssignment == TagCatalogSelectedAssignment.unknown &&
        _mode is TagCatalogSelectionMode &&
        _newlyCreatedTagId == id &&
        createdRevision != null &&
        (pageRevision == null ||
            pageRevision.compareTo(createdRevision) ==
                GraphRevisionOrder.same ||
            pageRevision.compareTo(createdRevision) ==
                GraphRevisionOrder.older)) {
      _setSelectedAssignment(
        TagCatalogSelectedAssignment.available,
        createdRevision,
      );
    }
    _publishSelection(TagCatalogSelectionLoading(id));
    _readSelectedAssignment();
    try {
      _selectedReads = _repository
          .watchTag(id)
          .listen(
            (result) => _onSelectedRead(id, generation, result),
            onError: (Object _) => _selectedReadFailed(
              id,
              generation,
              const TagReadUnexpectedFailure(),
            ),
            onDone: () {
              if (_selection is TagCatalogSelectionLoading) {
                _selectedReadFailed(
                  id,
                  generation,
                  const TagReadUnexpectedFailure(),
                );
              }
            },
          );
    } on Object {
      _selectedReadFailed(id, generation, const TagReadUnexpectedFailure());
    }
  }

  void retrySelectedTag() {
    final selection = _selection;
    if (selection is TagCatalogSelectionFailure && selection.canRetry) {
      selectTag(selection.id);
    }
  }

  void retrySelectedAssignment() {
    final current = state;
    if (current is! TagCatalogLoaded ||
        _selection.id == null ||
        _selectedAssignment != TagCatalogSelectedAssignment.unavailable) {
      return;
    }
    _clearSelectedAssignment();
    state = current.withStatus(selectedAssignment: _selectedAssignment);
    _readSelectedAssignment();
  }

  void _readSelectedAssignment() {
    final current = state;
    final id = _selection.id;
    if (id == null ||
        current is! TagCatalogLoaded ||
        current.mode is! TagCatalogSelectionMode ||
        current.selectionRows.any((row) => row.tag.id == id) ||
        _selectedAssignment != TagCatalogSelectedAssignment.unknown) {
      return;
    }
    final target = (current.mode as TagCatalogSelectionMode).target;
    final selectionGeneration = _selectionGeneration;
    final readGeneration = ++_assignmentReadGeneration;
    unawaited(
      _fetchSelectedAssignment(id, target, selectionGeneration, readGeneration),
    );
  }

  Future<void> _fetchSelectedAssignment(
    TagId id,
    TagTarget target,
    int selectionGeneration,
    int readGeneration,
  ) async {
    TagAssignmentStatusResult result;
    try {
      result = await _repository.getTagAssignmentStatus(id, target);
    } on Object {
      result = const TagAssignmentStatusError(TagAssignmentStatusUnexpected());
    }
    if (!ref.mounted ||
        selectionGeneration != _selectionGeneration ||
        readGeneration != _assignmentReadGeneration ||
        _selection.id != id ||
        _mode != TagCatalogSelectionMode(target)) {
      return;
    }
    switch (result) {
      case TagAssignmentStatusSuccess(:final value):
        final current = state;
        final required = _requiredRevision;
        if ((required != null &&
                (value.revision.compareTo(required) ==
                        GraphRevisionOrder.older ||
                    value.revision.compareTo(required) ==
                        GraphRevisionOrder.differentEpoch)) ||
            (current is TagCatalogLoaded &&
                (value.revision.compareTo(current.revision) ==
                        GraphRevisionOrder.older ||
                    value.revision.compareTo(current.revision) ==
                        GraphRevisionOrder.differentEpoch))) {
          if (++_assignmentStaleReads >= _maxStaleReads) {
            _selectedAssignmentFailed(TagCatalogSelectedAssignment.unavailable);
          } else {
            _readSelectedAssignment();
          }
          return;
        }
        _assignmentStaleReads = 0;
        _setSelectedAssignment(
          value.value
              ? TagCatalogSelectedAssignment.assigned
              : TagCatalogSelectedAssignment.available,
          value.revision,
        );
        if (state case TagCatalogLoaded loaded) {
          state = loaded.withStatus(selectedAssignment: _selectedAssignment);
        }
      case TagAssignmentStatusError(failure: TagAssignmentStatusTagNotFound()):
        _commandTagMissing(id);
      case TagAssignmentStatusError(
        failure: TagAssignmentStatusTargetNotFound(),
      ):
        _targetMissing(target);
      case TagAssignmentStatusError(:final failure):
        _selectedAssignmentFailed(switch (failure) {
          TagAssignmentStatusUnavailable() =>
            TagCatalogSelectedAssignment.unavailable,
          TagAssignmentStatusCorruption() =>
            TagCatalogSelectedAssignment.corruption,
          _ => TagCatalogSelectedAssignment.unexpected,
        });
    }
  }

  void _selectedAssignmentFailed(TagCatalogSelectedAssignment failure) {
    _selectedAssignment = failure;
    _selectedAssignmentRevision = null;
    if (state case TagCatalogLoaded loaded) {
      state = loaded.withStatus(selectedAssignment: failure);
    }
  }

  bool canActOn(TagId id) {
    final current = state;
    if (current is! TagCatalogLoaded || !current.canUseCurrentItems) {
      return false;
    }
    final selection = _selection;
    if (selection.id == id) {
      return selection is TagCatalogSelectionReady;
    }
    return current.items.any((tag) => tag.id == id);
  }

  /// Назначение начинается только после явного вызова для выбранного TagId.
  /// Уже назначенная строка не отправляется повторно; выбор вне порции
  /// сохраняет идентичность и проверяется командой в хранилище.
  TagCommandStart? assignSelected() {
    final current = state;
    final selection = _selection;
    if (current is! TagCatalogLoaded ||
        current.mode is! TagCatalogSelectionMode ||
        selection is! TagCatalogSelectionReady ||
        !canActOn(selection.id) ||
        _selectedAssignment != TagCatalogSelectedAssignment.available ||
        _assignmentStatus is! TagCatalogAssignmentIdle) {
      return null;
    }
    final mode = current.mode as TagCatalogSelectionMode;
    final start = _coordinator.acceptTagAssign(
      AssignTag(tagId: selection.id, target: mode.target),
    );
    switch (start) {
      case TagCommandAccepted(:final token):
        _assignmentStatus = TagCatalogAssignmentSubmitting(selection.id, token);
      case TagCommandAlreadyRunning():
        _assignmentStatus = TagCatalogAssignmentKeysBusy(selection.id);
      case GraphCommandCoordinatorDraining():
        break;
    }
    state = current.withStatus(assignmentStatus: _assignmentStatus);
    return start;
  }

  void _onSelectedRead(TagId id, int generation, TagReadResult result) {
    if (!ref.mounted || generation != _selectionGeneration) return;
    switch (result) {
      case TagReadSuccess(:final value):
        final required = _selectedRevision;
        if (required != null &&
            value.revision.compareTo(required) != GraphRevisionOrder.same &&
            value.revision.compareTo(required) != GraphRevisionOrder.newer) {
          return;
        }
        final tag = value.value;
        if (tag == null) {
          _confirmedMissing(id, value.revision);
        } else if (tag.id != id) {
          _selectedReadFailed(id, generation, const TagReadCorruptionFailure());
        } else {
          _selectedRevision = value.revision;
          _publishSelection(TagCatalogSelectionReady(tag));
        }
      case TagReadError(:final failure):
        _selectedReadFailed(id, generation, failure);
    }
  }

  void _selectedReadFailed(TagId id, int generation, TagReadFailure failure) {
    if (!ref.mounted || generation != _selectionGeneration) return;
    _publishSelection(TagCatalogSelectionFailure(id, failure));
  }

  void _confirmedMissing(TagId id, GraphRevision revision) {
    final current = state;
    final pageOrder = current is TagCatalogLoaded
        ? current.revision.compareTo(revision)
        : null;
    if (current is TagCatalogLoaded &&
        pageOrder == GraphRevisionOrder.newer &&
        current.items.any((tag) => tag.id == id)) {
      return;
    }
    final required = _requiredRevision;
    if (required == null ||
        revision.compareTo(required) == GraphRevisionOrder.newer ||
        revision.compareTo(required) == GraphRevisionOrder.differentEpoch) {
      _requiredRevision = revision;
    }
    _staleReadAttempts = 0;
    _selectionGeneration++;
    unawaited(_selectedReads?.cancel());
    _selectedReads = null;
    _selectedRevision = null;
    _clearSelectedAssignment();
    _selection = const TagCatalogNoSelection();
    if (current is TagCatalogLoaded) {
      final items = [
        for (final tag in current.items)
          if (tag.id != id) tag,
      ];
      final rows = [
        for (final row in current.selectionRows)
          if (row.tag.id != id) row,
      ];
      final pageIsCurrent =
          (pageOrder == GraphRevisionOrder.same ||
              pageOrder == GraphRevisionOrder.newer) &&
          items.length == current.items.length;
      state = current.withStatus(
        items: items,
        selectionRows: rows,
        selection: _selection,
        selectedAssignment: _selectedAssignment,
        freshness: pageIsCurrent
            ? current.freshness
            : TagCatalogFreshness.refreshing,
        pageStatus: pageIsCurrent
            ? current.pageStatus
            : const TagCatalogPageIdle(),
      );
      if (pageIsCurrent) return;
    }
    _refreshNeeded = true;
    if (_activeRequest == null) {
      _refreshNeeded = false;
      unawaited(_startFirst());
    }
  }

  void _publishSelection(TagCatalogSelection selection) {
    _selection = selection;
    if (state case TagCatalogLoaded loaded) {
      state = loaded.withStatus(
        selection: selection,
        selectedAssignment: _selectedAssignment,
      );
    }
  }

  Future<void> loadMore() {
    final current = state;
    if (current is! TagCatalogLoaded ||
        !current.canUseCurrentItems ||
        current.nextCursor == null ||
        current.pageStatus is! TagCatalogPageIdle) {
      return _activeRequest ?? Future.value();
    }
    return _start(() => _loadMore(current, _generation));
  }

  Future<void> retryLoadMore() {
    final current = state;
    if (current is! TagCatalogLoaded ||
        current.pageStatus is! TagCatalogPageFailure ||
        !(current.pageStatus as TagCatalogPageFailure).canRetry ||
        !current.canUseCurrentItems) {
      return Future.value();
    }
    state = current.withStatus(pageStatus: const TagCatalogPageIdle());
    return loadMore();
  }

  Future<void> retryRefresh() {
    final current = state;
    if (current is! TagCatalogLoaded ||
        current.freshness != TagCatalogFreshness.stale ||
        current.refreshFailure is! TagCatalogUnavailableFailure) {
      return Future.value();
    }
    state = current.withStatus(freshness: TagCatalogFreshness.refreshing);
    _staleReadAttempts = 0;
    return _startFirst();
  }

  Future<void> _startFirst() => _start(() => _loadFirst(_mode, _generation));

  Future<void> _start(Future<void> Function() read) {
    final active = _activeRequest;
    if (active != null) return active;
    final future = read();
    _activeRequest = future;
    unawaited(
      future.whenComplete(() {
        if (!identical(_activeRequest, future)) return;
        _activeRequest = null;
        if (_refreshNeeded && ref.mounted) {
          _refreshNeeded = false;
          unawaited(_startFirst());
        }
      }),
    );
    return future;
  }

  Future<void> _loadFirst(TagCatalogMode mode, int generation) async {
    final result = await _readPage(mode);
    if (!ref.mounted || generation != _generation) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        if (!_matchesMode(value, mode)) {
          _firstFailure(const TagCatalogUnexpectedFailure());
          return;
        }
        final current = state;
        final precedesDisplayed =
            current is TagCatalogLoaded &&
            value.revision.compareTo(current.revision) ==
                GraphRevisionOrder.older;
        if (_precedesRequired(value.revision) || precedesDisplayed) {
          if (++_staleReadAttempts >= _maxStaleReads) {
            _refreshNeeded = false;
            _firstFailure(const TagCatalogUnavailableFailure());
          } else {
            _refreshNeeded = true;
          }
          return;
        }
        if (!_unique(value.items)) {
          _firstFailure(const TagCatalogUnexpectedFailure());
          return;
        }
        _refreshNeeded = false;
        _staleReadAttempts = 0;
        if (mode is TagCatalogSelectionMode && value is TagSelectionPage) {
          final found = _selectedAssignmentFromRows(
            value.rows,
            _selection.id,
            value.revision,
          );
          if (!found &&
              _selection.id != null &&
              _selectedAssignment != TagCatalogSelectedAssignment.unavailable &&
              _selectedAssignment != TagCatalogSelectedAssignment.corruption &&
              _selectedAssignment != TagCatalogSelectedAssignment.unexpected) {
            _assignmentReadGeneration++;
            _clearSelectedAssignment();
          }
        }
        state = TagCatalogLoaded(
          mode: mode,
          items: value.items,
          selectionRows: value is TagSelectionPage ? value.rows : const [],
          nextCursor: value.nextCursor,
          revision: value.revision,
          selection: _selection,
          assignmentStatus: _assignmentStatus,
          selectedAssignment: _selectedAssignment,
        );
        if (mode is TagCatalogSelectionMode &&
            _selection.id != null &&
            _selectedAssignment == TagCatalogSelectedAssignment.unknown) {
          _readSelectedAssignment();
        }
      case GraphResultFailure(failure: TagCatalogTargetNotFound())
          when mode is TagCatalogSelectionMode:
        _refreshNeeded = false;
        _targetMissing(mode.target);
      case GraphResultFailure(:final failure):
        _refreshNeeded = false;
        _firstFailure(failure);
    }
  }

  Future<void> _loadMore(TagCatalogLoaded base, int generation) async {
    state = base.withStatus(pageStatus: const TagCatalogPageLoading());
    final result = await _readPage(base.mode, cursor: base.nextCursor);
    if (!ref.mounted || generation != _generation) return;
    final current = state;
    if (current is! TagCatalogLoaded) return;
    if (current.freshness != TagCatalogFreshness.current ||
        _precedesRequired(base.revision)) {
      _refreshNeeded = true;
      return;
    }
    switch (result) {
      case GraphResultSuccess(:final value):
        if (!_matchesMode(value, base.mode)) {
          state = current.withStatus(
            pageStatus: const TagCatalogPageFailure(
              TagCatalogUnexpectedFailure(),
            ),
          );
          return;
        }
        if (value.revision.compareTo(base.revision) !=
            GraphRevisionOrder.same) {
          _beginRefresh(current);
          _refreshNeeded = true;
          return;
        }
        final ids = <TagId>{for (final item in base.items) item.id};
        if (!ids.addAllChecked(value.items) ||
            (value.items.isEmpty && value.nextCursor != null)) {
          state = current.withStatus(
            pageStatus: const TagCatalogPageFailure(
              TagCatalogUnexpectedFailure(),
            ),
          );
          return;
        }
        if (value is TagSelectionPage) {
          _selectedAssignmentFromRows(
            value.rows,
            _selection.id,
            value.revision,
          );
        }
        state = TagCatalogLoaded(
          mode: base.mode,
          items: [...base.items, ...value.items],
          selectionRows: [
            ...base.selectionRows,
            if (value is TagSelectionPage) ...value.rows,
          ],
          nextCursor: value.nextCursor,
          revision: base.revision,
          selection: _selection,
          assignmentStatus: _assignmentStatus,
          selectedAssignment: _selectedAssignment,
        );
      case GraphResultFailure(failure: TagCatalogSnapshotExpired()):
        _beginRefresh(current);
        _refreshNeeded = true;
      case GraphResultFailure(failure: TagCatalogInvalidCursor()):
        _beginRefresh(current);
        _refreshNeeded = true;
      case GraphResultFailure(failure: TagCatalogTargetNotFound())
          when base.mode is TagCatalogSelectionMode:
        _targetMissing((base.mode as TagCatalogSelectionMode).target);
      case GraphResultFailure(:final failure):
        state = current.withStatus(pageStatus: TagCatalogPageFailure(failure));
    }
  }

  void _onCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted) return;
    _finishAssignmentStatus(completion);
    if (completion case TagCommandCompletion(
      kind: TagCommandKind.assign,
      confirmedResult: GraphResultFailure(
        failure: TagTargetNotFoundFailure(:final target),
      ),
    )) {
      if (_mode case TagCatalogSelectionMode(target: final selectedTarget)
          when selectedTarget == target) {
        _targetMissing(target);
      }
      return;
    }
    if (completion case TagCommandCompletion(
      kind: TagCommandKind.assign,
      confirmedResult: GraphResultFailure(
        failure: TagNotFoundFailure(:final tagId),
      ),
    )) {
      _commandTagMissing(tagId);
      return;
    }
    final package = completion.confirmedChange;
    if (package == null) return;
    if (_requiredRevision case final required?) {
      final order = package.revision.compareTo(required);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    if (_mode case TagCatalogSelectionMode(target: final target)) {
      for (final change in package.changes) {
        switch (change) {
          case TagCreatedChange(:final after):
            _newlyCreatedTagId = after.id;
            _newlyCreatedRevision = package.revision;
          case TagAssignmentChangedChange(:final assignment, :final state) ||
              TagAssignmentUnchangedChange(:final assignment, :final state):
            if (_newlyCreatedTagId == assignment.tagId &&
                assignment.target == target) {
              _newlyCreatedTagId = null;
              _newlyCreatedRevision = null;
            }
            if (assignment.target == target &&
                assignment.tagId == _selection.id) {
              _setSelectedAssignment(
                state == TagAssignmentState.assigned
                    ? TagCatalogSelectedAssignment.assigned
                    : TagCatalogSelectedAssignment.available,
                package.revision,
              );
            }
          case TagDeletedChange(:final tagId):
            if (_newlyCreatedTagId == tagId) {
              _newlyCreatedTagId = null;
              _newlyCreatedRevision = null;
            }
          case TagChange():
            break;
          case GraphChange():
            break;
        }
      }
      final knownRevision = _selectedAssignmentRevision;
      if (knownRevision != null) {
        final order = package.revision.compareTo(knownRevision);
        if (order == GraphRevisionOrder.newer) {
          _selectedAssignmentRevision = package.revision;
        } else if (order == GraphRevisionOrder.differentEpoch) {
          _clearSelectedAssignment();
        }
      }
      final createdRevision = _newlyCreatedRevision;
      if (createdRevision != null) {
        final order = package.revision.compareTo(createdRevision);
        if (order == GraphRevisionOrder.newer) {
          _newlyCreatedRevision = package.revision;
        } else if (order == GraphRevisionOrder.differentEpoch) {
          _newlyCreatedTagId = null;
          _newlyCreatedRevision = null;
        }
      }
    }
    _requiredRevision = package.revision;
    if (_mode is TagCatalogSelectionMode && _selection.id != null) {
      final selectedId = _selection.id;
      final pairChanged = package.changes.any(
        (change) => switch (change) {
          TagAssignmentChangedChange(:final assignment) ||
          TagAssignmentUnchangedChange(:final assignment) =>
            assignment.tagId == selectedId &&
                assignment.target == (_mode as TagCatalogSelectionMode).target,
          _ => false,
        },
      );
      _assignmentReadGeneration++;
      _assignmentStaleReads = 0;
      final selectionOutsidePage = switch (state) {
        TagCatalogLoaded(:final selectionRows) => !selectionRows.any(
          (row) => row.tag.id == selectedId,
        ),
        _ => false,
      };
      if (!pairChanged && selectionOutsidePage) {
        _clearSelectedAssignment();
      }
    }
    _staleReadAttempts = 0;
    final current = state;
    final pageAlreadyIncludes =
        current is TagCatalogLoaded &&
        switch (package.revision.compareTo(current.revision)) {
          GraphRevisionOrder.older || GraphRevisionOrder.same => true,
          GraphRevisionOrder.newer ||
          GraphRevisionOrder.differentEpoch => false,
        };
    final canUpdateSelection =
        _selectedRevision == null ||
        switch (package.revision.compareTo(_selectedRevision!)) {
          GraphRevisionOrder.newer || GraphRevisionOrder.differentEpoch => true,
          GraphRevisionOrder.older || GraphRevisionOrder.same => false,
        };
    var items = current is TagCatalogLoaded ? current.items : <Tag>[];
    var rows = current is TagCatalogLoaded
        ? current.selectionRows
        : <TagSelectionRow>[];
    for (final change in package.changes) {
      switch (change) {
        case TagRenamedChange(:final after):
          if (!pageAlreadyIncludes) {
            items = [
              for (final tag in items)
                if (tag.id == after.id) after else tag,
            ];
            rows = [
              for (final row in rows)
                if (row.tag.id == after.id)
                  TagSelectionRow(tag: after, isAssigned: row.isAssigned)
                else
                  row,
            ];
          }
          if (canUpdateSelection && _selection.id == after.id) {
            var selected = after;
            GraphRevision revision = package.revision;
            if (pageAlreadyIncludes) {
              for (final tag in current.items) {
                if (tag.id == after.id) {
                  selected = tag;
                  revision = current.revision;
                  break;
                }
              }
            }
            _selection = TagCatalogSelectionReady(selected);
            _selectedRevision = revision;
          }
        case TagDeletedChange(:final tagId):
          if (!pageAlreadyIncludes) {
            items = [
              for (final tag in items)
                if (tag.id != tagId) tag,
            ];
            rows = [
              for (final row in rows)
                if (row.tag.id != tagId) row,
            ];
          }
          if (canUpdateSelection && _selection.id == tagId) {
            _selectionGeneration++;
            unawaited(_selectedReads?.cancel());
            _selectedReads = null;
            _selectedRevision = null;
            _clearSelectedAssignment();
            _selection = const TagCatalogNoSelection();
          }
        case TagAssignmentChangedChange(:final assignment, :final state)
            when !pageAlreadyIncludes &&
                current is TagCatalogLoaded &&
                current.mode is TagCatalogSelectionMode &&
                (current.mode as TagCatalogSelectionMode).target ==
                    assignment.target:
          rows = [
            for (final row in rows)
              if (row.tag.id == assignment.tagId)
                TagSelectionRow(
                  tag: row.tag,
                  isAssigned: state == TagAssignmentState.assigned,
                )
              else
                row,
          ];
        case TagChange():
          break;
        case GraphChange():
          break;
      }
    }
    if (current is TagCatalogLoaded) {
      if (pageAlreadyIncludes) {
        if (_selection.id != null &&
            !current.selectionRows.any((row) => row.tag.id == _selection.id)) {
          _assignmentReadGeneration++;
          _clearSelectedAssignment();
        }
        if (!identical(current.selection, _selection) ||
            !identical(current.assignmentStatus, _assignmentStatus) ||
            current.selectedAssignment != _selectedAssignment) {
          state = current.withStatus(
            selection: _selection,
            assignmentStatus: _assignmentStatus,
            selectedAssignment: _selectedAssignment,
          );
        }
        _readSelectedAssignment();
        return;
      }
      state = current.withStatus(
        items: items,
        selectionRows: rows,
        selection: _selection,
        assignmentStatus: _assignmentStatus,
        selectedAssignment: _selectedAssignment,
        freshness: TagCatalogFreshness.refreshing,
        pageStatus: const TagCatalogPageIdle(),
      );
      _readSelectedAssignment();
    }
    _refreshNeeded = true;
    if (_activeRequest == null) {
      _refreshNeeded = false;
      unawaited(_startFirst());
    }
  }

  void _finishAssignmentStatus(GraphCommandCompletion completion) {
    final status = _assignmentStatus;
    final current = state;
    switch (status) {
      case TagCatalogAssignmentSubmitting(:final token)
          when completion is TagCommandCompletion &&
              identical(completion.token, token):
        _assignmentStatus = const TagCatalogAssignmentIdle();
      case TagCatalogAssignmentKeysBusy(:final tagId)
          when current is TagCatalogLoaded &&
              current.mode is TagCatalogSelectionMode &&
              !_coordinator.isTagRunning(tagId) &&
              !_targetRunning((current.mode as TagCatalogSelectionMode).target):
        _assignmentStatus = const TagCatalogAssignmentIdle();
      case TagCatalogAssignmentStatus():
        return;
    }
    if (current is TagCatalogLoaded) {
      state = current.withStatus(assignmentStatus: _assignmentStatus);
    }
  }

  bool _targetRunning(TagTarget target) =>
      _coordinator.isKeyRunning(switch (target) {
        IntentionTagTarget(:final intentionId) => ExistingIntentionKey(
          intentionId,
        ),
        LongTermRelationTagTarget(:final relationId) =>
          ExistingLongTermRelationKey(relationId),
      });

  void _targetMissing(TagTarget target) {
    _selectionGeneration++;
    unawaited(_selectedReads?.cancel());
    _selectedReads = null;
    _selection = const TagCatalogNoSelection();
    _selectedRevision = null;
    _clearSelectedAssignment();
    _assignmentStatus = const TagCatalogAssignmentIdle();
    state = TagCatalogTargetMissing(target);
  }

  void _commandTagMissing(TagId id) {
    final current = state;
    if (current is! TagCatalogLoaded || _selection.id != id) return;
    _selectionGeneration++;
    unawaited(_selectedReads?.cancel());
    _selectedReads = null;
    _selection = const TagCatalogNoSelection();
    _selectedRevision = null;
    _clearSelectedAssignment();
    _generation++;
    state = current.withStatus(
      items: [
        for (final tag in current.items)
          if (tag.id != id) tag,
      ],
      selectionRows: [
        for (final row in current.selectionRows)
          if (row.tag.id != id) row,
      ],
      selection: _selection,
      selectedAssignment: _selectedAssignment,
      freshness: TagCatalogFreshness.refreshing,
      pageStatus: const TagCatalogPageIdle(),
    );
    _refreshNeeded = true;
    if (_activeRequest == null) {
      _refreshNeeded = false;
      unawaited(_startFirst());
    }
  }

  void _beginRefresh(TagCatalogLoaded current) {
    state = current.withStatus(
      freshness: TagCatalogFreshness.refreshing,
      pageStatus: const TagCatalogPageIdle(),
    );
  }

  void _firstFailure(TagCatalogReadFailure failure) {
    final current = state;
    if (current is TagCatalogLoaded) {
      state = current.withStatus(
        freshness: TagCatalogFreshness.stale,
        refreshFailure: failure,
        pageStatus: const TagCatalogPageIdle(),
      );
    } else {
      state = TagCatalogInitialFailure(failure, mode: _mode);
    }
  }

  bool _precedesRequired(GraphRevision revision) {
    final required = _requiredRevision;
    if (required == null) return false;
    final order = revision.compareTo(required);
    return order == GraphRevisionOrder.older ||
        order == GraphRevisionOrder.differentEpoch;
  }

  Future<TagCatalogPageResult> _readPage(
    TagCatalogMode mode, {
    TagCatalogCursor? cursor,
  }) async {
    try {
      return await _repository.getTagCatalogPage(
        TagCatalogQuery(cursor: cursor, mode: mode),
      );
    } on Object {
      return const TagCatalogPageError(TagCatalogUnexpectedFailure());
    }
  }

  bool _matchesMode(TagCatalogPage page, TagCatalogMode mode) =>
      switch ((page, mode)) {
        (TagBrowsePage(), TagCatalogBrowseMode()) => true,
        (
          TagSelectionPage(:final target),
          TagCatalogSelectionMode(target: final modeTarget),
        ) =>
          target == modeTarget,
        _ => false,
      };

  bool _unique(List<Tag> tags) {
    final ids = <TagId>{};
    for (final tag in tags) {
      if (!ids.add(tag.id)) return false;
    }
    return true;
  }

  void _clearSelectedAssignment() {
    _selectedAssignment = TagCatalogSelectedAssignment.unknown;
    _selectedAssignmentRevision = null;
  }

  bool _selectedAssignmentFromRows(
    List<TagSelectionRow> rows,
    TagId? selectedId,
    GraphRevision revision,
  ) {
    for (final row in rows) {
      if (row.tag.id == selectedId) {
        _setSelectedAssignment(
          row.isAssigned
              ? TagCatalogSelectedAssignment.assigned
              : TagCatalogSelectedAssignment.available,
          revision,
        );
        return true;
      }
    }
    return false;
  }

  void _setSelectedAssignment(
    TagCatalogSelectedAssignment value,
    GraphRevision revision,
  ) {
    if (_selectedAssignmentRevision case final known?) {
      if (revision.compareTo(known) == GraphRevisionOrder.older) return;
    }
    _selectedAssignment = value;
    _selectedAssignmentRevision = revision;
  }
}

extension on Set<TagId> {
  bool addAllChecked(List<Tag> tags) {
    for (final tag in tags) {
      if (!add(tag.id)) return false;
    }
    return true;
  }
}
