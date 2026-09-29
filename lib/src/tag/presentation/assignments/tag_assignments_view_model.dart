import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/tag_assignments.dart';
import '../../application/tag_change.dart';
import '../../application/tag_read_result.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';
import 'tag_assignments_state.dart';

part 'tag_assignments_view_model.g.dart';

/// Узкие зависимости позволяют проверять согласование без команд записи.
final tagAssignmentsReaderProvider = Provider<TagReadContract>(
  (ref) => ref.watch(personalGraphRepositoryProvider),
);

final tagAssignmentsChangesProvider =
    Provider<Stream<ConfirmedGraphChangePackage>>(
      (ref) => ref
          .watch(graphCommandCoordinatorProvider.notifier)
          .completions
          .map((completion) => completion.confirmedChange)
          .where((package) => package != null)
          .cast<ConfirmedGraphChangePackage>(),
    );

@riverpod
final class TagAssignmentsViewModel extends _$TagAssignmentsViewModel {
  static const _maxStaleReads = 8;

  late IntentionId _intentionId;
  late TagReadContract _reads;
  StreamSubscription<ConfirmedGraphChangePackage>? _changes;
  GraphRevision? _requiredRevision;
  Future<void>? _activeRequest;
  bool _refreshNeeded = false;
  int _generation = 0;
  int _staleReadAttempts = 0;

  @override
  TagAssignmentsState build(IntentionId intentionId) {
    unawaited(_changes?.cancel());
    final active = _activeRequest;
    _intentionId = intentionId;
    _reads = ref.watch(tagAssignmentsReaderProvider);
    _requiredRevision = null;
    _refreshNeeded = false;
    _staleReadAttempts = 0;
    _generation++;
    _changes = ref.watch(tagAssignmentsChangesProvider).listen(_onChange);
    ref.onDispose(() => unawaited(_changes?.cancel()));
    if (active == null) {
      unawaited(_startRead());
    } else {
      _refreshNeeded = true;
    }
    return const TagAssignmentsInitialLoading();
  }

  /// При повторном использовании той же модели прежнее чтение теряет право
  /// публикации. Пока оно выполняется, новый запрос ждёт его завершения.
  void setIntentionId(IntentionId intentionId) {
    if (_intentionId == intentionId) return;
    _intentionId = intentionId;
    _generation++;
    _staleReadAttempts = 0;
    state = const TagAssignmentsInitialLoading();
    if (_activeRequest == null) {
      unawaited(_startRead());
    } else {
      _refreshNeeded = true;
    }
  }

  bool canActOn(TagId id) {
    final current = state;
    return current is TagAssignmentsLoaded &&
        current.intentionId == _intentionId &&
        current.canUseCurrentItems &&
        current.contains(id);
  }

  Future<void> retryInitialLoad() {
    final current = state;
    if (current is! TagAssignmentsInitialFailure || !current.canRetry) {
      return Future.value();
    }
    state = const TagAssignmentsInitialLoading();
    _staleReadAttempts = 0;
    return _startRead();
  }

  Future<void> retryRefresh() {
    final current = state;
    if (current is! TagAssignmentsLoaded ||
        current.freshness != TagAssignmentsFreshness.stale ||
        current.refreshFailure is! TagAssignmentsUnavailableFailure) {
      return Future.value();
    }
    state = current.withStatus(freshness: TagAssignmentsFreshness.refreshing);
    _staleReadAttempts = 0;
    return _startRead();
  }

  Future<void> _startRead() =>
      _start(() => _loadAssignments(_intentionId, _generation));

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
          unawaited(_startRead());
        }
      }),
    );
    return future;
  }

  Future<void> _loadAssignments(IntentionId intentionId, int generation) async {
    final result = await _readAssignments(intentionId);
    if (!ref.mounted ||
        generation != _generation ||
        intentionId != _intentionId) {
      return;
    }
    if (result is GraphResultFailure && _refreshNeeded) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        final current = state;
        final precedesDisplayed =
            current is TagAssignmentsLoaded &&
            value.revision.compareTo(current.revision) ==
                GraphRevisionOrder.older;
        if (value.intentionId != intentionId || !_unique(value.items)) {
          _readFailure(const TagAssignmentsUnexpectedFailure());
          return;
        }
        if (_precedesRequired(value.revision) || precedesDisplayed) {
          if (++_staleReadAttempts >= _maxStaleReads) {
            _refreshNeeded = false;
            _readFailure(const TagAssignmentsUnavailableFailure());
          } else {
            _refreshNeeded = true;
          }
          return;
        }
        _refreshNeeded = false;
        _staleReadAttempts = 0;
        state = TagAssignmentsLoaded(
          intentionId: intentionId,
          items: value.items,
          revision: value.revision,
        );
      case GraphResultFailure(failure: TagAssignmentsIntentionNotFound()):
        _refreshNeeded = false;
        state = const TagAssignmentsIntentionMissing();
      case GraphResultFailure(:final failure):
        _refreshNeeded = false;
        _readFailure(failure);
    }
  }

  void _onChange(ConfirmedGraphChangePackage package) {
    if (!ref.mounted) return;
    final required = _requiredRevision;
    if (required != null) {
      final order = package.revision.compareTo(required);
      if (order == GraphRevisionOrder.same ||
          order == GraphRevisionOrder.older) {
        return;
      }
    }
    _requiredRevision = package.revision;
    _staleReadAttempts = 0;
    final current = state;
    if (current is TagAssignmentsIntentionMissing) return;
    final snapshotAlreadyIncludes =
        current is TagAssignmentsLoaded &&
        switch (package.revision.compareTo(current.revision)) {
          GraphRevisionOrder.older || GraphRevisionOrder.same => true,
          GraphRevisionOrder.newer ||
          GraphRevisionOrder.differentEpoch => false,
        };
    if (snapshotAlreadyIncludes) return;
    if (package.changes.any(
      (change) =>
          change is IntentionCatalogDeleted &&
          change.entry.summary.id == _intentionId,
    )) {
      _generation++;
      _refreshNeeded = false;
      state = const TagAssignmentsIntentionMissing();
      return;
    }
    if (current is TagAssignmentsLoaded) {
      var items = current.items;
      for (final change in package.changes) {
        switch (change) {
          case TagRenamedChange(:final after):
            items = [
              for (final tag in items)
                if (tag.id == after.id) after else tag,
            ];
          case TagDeletedChange(:final tagId):
            items = [
              for (final tag in items)
                if (tag.id != tagId) tag,
            ];
          case TagAssignmentChangedChange(:final assignment, :final state)
              when assignment.intentionId == _intentionId &&
                  state == TagAssignmentState.absent:
            items = [
              for (final tag in items)
                if (tag.id != assignment.tagId) tag,
            ];
          case TagChange():
            break;
          case GraphChange():
            break;
        }
      }
      state = current.withStatus(
        items: items,
        freshness: TagAssignmentsFreshness.refreshing,
      );
    } else {
      state = const TagAssignmentsInitialLoading();
    }
    _refreshNeeded = true;
    if (_activeRequest == null) {
      _refreshNeeded = false;
      unawaited(_startRead());
    }
  }

  void _readFailure(TagAssignmentsReadFailure failure) {
    final current = state;
    if (current is TagAssignmentsLoaded) {
      state = current.withStatus(
        freshness: TagAssignmentsFreshness.stale,
        refreshFailure: failure,
      );
    } else {
      state = TagAssignmentsInitialFailure(failure);
    }
  }

  bool _precedesRequired(GraphRevision revision) {
    final required = _requiredRevision;
    if (required == null) return false;
    final order = revision.compareTo(required);
    return order == GraphRevisionOrder.older ||
        order == GraphRevisionOrder.differentEpoch;
  }

  Future<TagAssignmentsResult> _readAssignments(IntentionId intentionId) async {
    try {
      return await _reads.getTagAssignments(intentionId);
    } on Object {
      return const TagAssignmentsError(TagAssignmentsUnexpectedFailure());
    }
  }

  bool _unique(List<Tag> tags) {
    final ids = <TagId>{};
    for (final tag in tags) {
      if (!ids.add(tag.id)) return false;
    }
    return true;
  }
}
