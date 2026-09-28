import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../application/tag_change.dart';
import '../../application/tag_read_result.dart';
import '../../application/tagged_entities_page.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';
import '../../domain/tag_target.dart';
import 'tag_navigation_state.dart';

part 'tag_navigation_view_model.g.dart';

final tagNavigationReaderProvider = Provider<TagReadContract>(
  (ref) => ref.watch(personalGraphRepositoryProvider),
);

final tagNavigationChangesProvider =
    Provider<Stream<ConfirmedGraphChangePackage>>(
      (ref) => ref
          .watch(graphCommandCoordinatorProvider.notifier)
          .completions
          .map((completion) => completion.confirmedChange)
          .where((package) => package != null)
          .cast<ConfirmedGraphChangePackage>(),
    );

@riverpod
final class TagNavigationViewModel extends _$TagNavigationViewModel {
  static const _maxStaleReads = 8;

  late TagId _tagId;
  late TagReadContract _reads;
  TaggedEntitiesScope _scope = TaggedEntitiesScope.active;
  Future<void>? _activeRequest;
  bool _firstPagePending = false;
  int _generation = 0;
  int _changesGeneration = 0;
  int _staleReadAttempts = 0;
  bool _tagIsMissing = false;
  // Требуемая ревизия списка и ревизия известного тега согласуются отдельно:
  // посторонний пакет не подтверждает название или существование тега.
  GraphRevision? _requiredRevision;
  // Одно предыдущее значение отвергает запоздалые сигналы сменившейся эпохи.
  // Журнал пакетов и эпох не накапливается.
  GraphRevision? _retiredRevision;
  StreamSubscription<ConfirmedGraphChangePackage>? _changes;
  StreamSubscription<TagReadResult>? _tagReads;
  int _tagGeneration = 0;
  TagReadFailure? _watchFailure;
  _WatchRecovery? _watchRecovery;
  Tag? _knownTag;
  GraphRevision? _tagRevision;

  @override
  TagNavigationState build(TagId tagId) {
    unawaited(_changes?.cancel());
    unawaited(_tagReads?.cancel());
    _tagId = tagId;
    _scope = TaggedEntitiesScope.active;
    _reads = ref.watch(tagNavigationReaderProvider);
    _requiredRevision = null;
    _retiredRevision = null;
    _staleReadAttempts = 0;
    _tagIsMissing = false;
    _knownTag = null;
    _tagRevision = null;
    final changesGeneration = ++_changesGeneration;
    _generation++;
    _changes = ref.watch(tagNavigationChangesProvider).listen((package) {
      if (changesGeneration == _changesGeneration) _onChange(package);
    });
    ref.onDispose(() {
      _generation++;
      _changesGeneration++;
      _tagGeneration++;
      _firstPagePending = false;
      unawaited(_changes?.cancel());
      unawaited(_tagReads?.cancel());
    });
    _watchSelectedTag();
    _requestFirstPage();
    return _loading();
  }

  void setTagId(TagId tagId) {
    if (!ref.mounted || _tagId == tagId) return;
    _tagId = tagId;
    _tagIsMissing = false;
    _knownTag = null;
    _tagRevision = null;
    _watchSelectedTag();
    _changeSelection();
  }

  void setScope(TaggedEntitiesScope scope) {
    if (!ref.mounted || _scope == scope) return;
    _scope = scope;
    _changeSelection();
  }

  void _changeSelection() {
    _generation++;
    _watchRecovery?.firstPage = null;
    _staleReadAttempts = 0;
    if (_tagIsMissing) {
      _tagMissing();
      return;
    }
    state = _loading();
    _requestFirstPage();
  }

  /// Прежний запрос теряет право публикации, но завершается до нового чтения.
  /// Несколько смен выбора объединяются в одну первую порцию последнего выбора.
  void _requestFirstPage() {
    if (_tagIsMissing) return;
    _firstPagePending = _activeRequest != null;
    if (!_firstPagePending) unawaited(_startFirst());
  }

  Future<void> retryFirstPage() {
    if (!ref.mounted) return Future.value();
    if (_activeRequest case final active?) return active;
    final current = state;
    if (current is! TagNavigationInitialFailure || !current.canRetry) {
      return Future.value();
    }
    state = _loading();
    _staleReadAttempts = 0;
    if (_watchFailure != null) _watchSelectedTag(recovering: true);
    return _startFirst();
  }

  bool canActOn(TagTarget target) {
    if (!ref.mounted) return false;
    final current = state;
    return current is TagNavigationLoaded &&
        current.tagId == _tagId &&
        current.scope == _scope &&
        current.canUseCurrentItems &&
        current.contains(target);
  }

  Future<void> retryRefresh() {
    if (!ref.mounted) return Future.value();
    if (_activeRequest case final active?) return active;
    final current = state;
    if (current is! TagNavigationLoaded ||
        current.freshness != TagNavigationFreshness.stale ||
        current.refreshFailure is! TaggedEntitiesUnavailableFailure) {
      return Future.value();
    }
    _staleReadAttempts = 0;
    _beginRefresh(current);
    if (_watchFailure != null) _watchSelectedTag(recovering: true);
    return _startFirst();
  }

  Future<void> loadMore() {
    if (!ref.mounted) return Future.value();
    if (_activeRequest case final active?) return active;
    final current = state;
    if (current is! TagNavigationLoaded ||
        !current.canUseCurrentItems ||
        current.nextCursor == null ||
        current.pageStatus is! TagNavigationPageIdle) {
      return Future.value();
    }
    return _start(() => _loadMore(current, _generation));
  }

  Future<void> retryLoadMore() {
    if (!ref.mounted) return Future.value();
    if (_activeRequest case final active?) return active;
    final current = state;
    if (current case TagNavigationLoaded(
      canUseCurrentItems: true,
      pageStatus: TagNavigationPageFailure(canRetry: true),
    )) {
      state = current.withPageStatus(const TagNavigationPageIdle());
      return loadMore();
    }
    return Future.value();
  }

  Future<void> _startFirst() =>
      _start(() => _loadFirst(_tagId, _scope, _generation));

  Future<void> _start(Future<void> Function() read) {
    if (_activeRequest case final active?) return active;
    final completion = Completer<void>();
    final future = completion.future;
    _activeRequest = future;
    unawaited(
      read().whenComplete(() {
        _activeRequest = null;
        if (_firstPagePending && ref.mounted) {
          _firstPagePending = false;
          unawaited(_startFirst());
        }
        completion.complete();
      }),
    );
    return future;
  }

  Future<void> _loadFirst(
    TagId tagId,
    TaggedEntitiesScope scope,
    int generation,
  ) async {
    final requiredAtStart = _requiredRevision;
    final query = TaggedEntitiesQuery(tagId: tagId, scope: scope);
    final result = await _readPage(query);
    if (!_canPublish(generation)) return;
    if (result is GraphResultFailure && _firstPagePending) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        if (!_matches(value, query) || !_unique(value.items)) {
          _firstPagePending = false;
          _firstFailure(const TaggedEntitiesUnexpectedFailure());
          return;
        }
        final required = _requiredRevision;
        final changedWhileReading =
            required != null &&
            (requiredAtStart == null ||
                required.compareTo(requiredAtStart) != GraphRevisionOrder.same);
        if (_isRetired(value.revision) ||
            (required != null &&
                (value.revision.compareTo(required) ==
                        GraphRevisionOrder.older ||
                    (changedWhileReading &&
                        value.revision.compareTo(required) ==
                            GraphRevisionOrder.differentEpoch)))) {
          _repeatStaleRead();
          return;
        }
        _advanceRevision(value.revision);
        _firstPagePending = false;
        _staleReadAttempts = 0;
        if (_tagRevision?.compareTo(value.revision) ==
                GraphRevisionOrder.same &&
            _knownTag?.name != value.tag.name) {
          _firstFailure(const TaggedEntitiesUnexpectedFailure());
          return;
        }
        final loaded = TagNavigationLoaded(
          tag: value.tag,
          scope: scope,
          items: value.items,
          nextCursor: value.nextCursor,
          revision: value.revision,
        );
        final recovery = _watchRecovery;
        if (recovery != null) {
          recovery.firstPage = (generation: generation, value: loaded);
          _completeWatchRecovery();
        } else {
          _knownTag = value.tag;
          _tagRevision = value.revision;
          state = loaded;
        }
      case GraphResultFailure(failure: TaggedEntitiesTagNotFound()):
        _tagMissing();
      case GraphResultFailure(failure: TaggedEntitiesSnapshotExpired()):
        _repeatStaleRead();
      case GraphResultFailure(:final failure):
        _firstPagePending = false;
        _firstFailure(failure);
    }
  }

  Future<void> _loadMore(TagNavigationLoaded base, int generation) async {
    state = base.withPageStatus(const TagNavigationPageLoading());
    final query = TaggedEntitiesQuery(
      tagId: base.tagId,
      scope: base.scope,
      cursor: base.nextCursor,
    );
    final result = await _readPage(query);
    if (!_canPublish(generation)) return;
    if (_precedesRequired(base.revision)) {
      _firstPagePending = true;
      return;
    }
    switch (result) {
      case GraphResultSuccess(:final value):
        if (!_matches(value, query)) {
          _pageFailure(base, const TaggedEntitiesUnexpectedFailure());
          return;
        }
        if (value.revision.compareTo(base.revision) !=
            GraphRevisionOrder.same) {
          _advanceRevision(value.revision);
          _beginRefresh(base);
          _firstPagePending = true;
          return;
        }
        if (value.tag.name != base.tag.name ||
            identical(value.nextCursor, base.nextCursor) ||
            !_unique([...base.items, ...value.items])) {
          _pageFailure(base, const TaggedEntitiesUnexpectedFailure());
          return;
        }
        state = TagNavigationLoaded(
          tag: value.tag,
          scope: base.scope,
          items: [...base.items, ...value.items],
          nextCursor: value.nextCursor,
          revision: base.revision,
        );
      case GraphResultFailure(failure: TaggedEntitiesTagNotFound()):
        _tagMissing();
      case GraphResultFailure(failure: TaggedEntitiesSnapshotExpired()):
        _beginRefresh(base);
        _firstPagePending = true;
      case GraphResultFailure(:final failure):
        _pageFailure(base, failure);
    }
  }

  bool _canPublish(int generation) => ref.mounted && generation == _generation;

  bool _matches(TaggedEntitiesPage page, TaggedEntitiesQuery query) =>
      page.tag.id == query.tagId &&
      page.scope == query.scope &&
      page.pageSize == query.pageSize;

  bool _unique(List<TaggedEntity> items) {
    final targets = <TagTarget>{};
    return items.every((item) => targets.add(item.target));
  }

  TagNavigationInitialLoading _loading() =>
      TagNavigationInitialLoading(tagId: _tagId, scope: _scope);

  void _tagMissing() {
    _tagIsMissing = true;
    _generation++;
    _firstPagePending = false;
    _knownTag = null;
    _watchRecovery = null;
    _tagGeneration++;
    unawaited(_tagReads?.cancel());
    state = TagNavigationTagMissing(tagId: _tagId, scope: _scope);
  }

  void _firstFailure(TaggedEntitiesReadFailure failure) {
    final current = state;
    if (current is TagNavigationLoaded) {
      state = current.withStatus(
        clearCursor: true,
        freshness: TagNavigationFreshness.stale,
        refreshFailure: failure,
        pageStatus: const TagNavigationPageIdle(),
      );
      return;
    }
    state = TagNavigationInitialFailure(
      tagId: _tagId,
      scope: _scope,
      failure: failure,
    );
  }

  void _onChange(ConfirmedGraphChangePackage package) {
    if (!ref.mounted || _tagIsMissing || _isRetired(package.revision)) {
      return;
    }
    final advanced = _advanceRevision(package.revision);
    var current = state;
    for (final change in package.changes) {
      if (!_acceptsTagRevision(package.revision)) break;
      if (change case TagDeletedChange(tagId: final id) when id == _tagId) {
        _tagMissing();
        return;
      }
      if (change case TagRenamedChange(:final after) when after.id == _tagId) {
        _knownTag = after;
        _tagRevision = package.revision;
        if (current is TagNavigationLoaded && current.tag.name != after.name) {
          current = current.withStatus(
            tag: after,
            refreshFailure: current.refreshFailure,
          );
        }
      }
    }
    if (!advanced) {
      if (!identical(current, state)) state = current;
      return;
    }
    _staleReadAttempts = 0;
    if (current is TagNavigationLoaded) {
      _beginRefresh(current);
    } else {
      state = _loading();
    }
    _requestFirstPage();
  }

  void _watchSelectedTag({bool recovering = false}) {
    unawaited(_tagReads?.cancel());
    final generation = ++_tagGeneration;
    final tagId = _tagId;
    _watchFailure = null;
    _watchRecovery = recovering ? _WatchRecovery() : null;
    try {
      _tagReads = _reads
          .watchTag(tagId)
          .listen(
            (result) {
              if (!ref.mounted || generation != _tagGeneration) return;
              switch (result) {
                case TagReadSuccess(:final value):
                  if (!_acceptsTagRevision(value.revision)) return;
                  final tag = value.value;
                  if (tag != null && tag.id != tagId) {
                    _watchTagFailed(const TagReadCorruptionFailure());
                    return;
                  }
                  final advanced = _advanceRevision(value.revision);
                  if (tag == null) {
                    _tagMissing();
                    return;
                  }
                  _knownTag = tag;
                  _tagRevision = value.revision;
                  _watchRecovery?.observation = GraphSnapshot(
                    value: tag,
                    revision: value.revision,
                  );
                  final current = state;
                  if (current is TagNavigationLoaded) {
                    final updated = current.withStatus(
                      tag: tag,
                      refreshFailure: current.refreshFailure,
                    );
                    if (advanced) {
                      _beginRefresh(updated);
                    } else {
                      state = updated;
                    }
                  }
                  if (advanced) {
                    _staleReadAttempts = 0;
                    _requestFirstPage();
                  }
                  _completeWatchRecovery();
                case TagReadError(:final failure):
                  _watchTagFailed(failure);
              }
            },
            onError: (Object _) {
              if (ref.mounted && generation == _tagGeneration) {
                _watchTagFailed(const TagReadUnexpectedFailure());
              }
            },
            onDone: () {
              if (ref.mounted && generation == _tagGeneration) {
                _watchTagFailed(
                  _watchFailure ?? const TagReadUnexpectedFailure(),
                );
              }
            },
          );
    } on Object {
      // При первом подключении build ещё не опубликовал начальное состояние.
      scheduleMicrotask(() {
        if (ref.mounted && generation == _tagGeneration) {
          _watchTagFailed(const TagReadUnexpectedFailure());
        }
      });
    }
  }

  void _watchTagFailed(TagReadFailure failure) {
    _watchFailure = failure;
    _watchRecovery?.firstPage = null;
    _firstFailure(switch (failure) {
      TagReadUnavailableFailure() => const TaggedEntitiesUnavailableFailure(),
      TagReadCorruptionFailure() => const TaggedEntitiesCorruptionFailure(),
      TagReadUnexpectedFailure() => const TaggedEntitiesUnexpectedFailure(),
    });
  }

  /// Повтор подтверждают новая подписка и согласованная новая первая порция.
  void _completeWatchRecovery() {
    if (_watchFailure != null) return;
    final observation = _watchRecovery?.observation;
    final firstPage = _watchRecovery?.firstPage;
    if (observation == null ||
        firstPage == null ||
        !_canPublish(firstPage.generation) ||
        _precedesRequired(firstPage.value.revision)) {
      return;
    }
    switch (firstPage.value.revision.compareTo(observation.revision)) {
      case GraphRevisionOrder.older || GraphRevisionOrder.differentEpoch:
        return;
      case GraphRevisionOrder.same:
        if (firstPage.value.tag.name != observation.value.name) {
          _watchRecovery?.firstPage = null;
          _firstFailure(const TaggedEntitiesUnexpectedFailure());
          return;
        }
      case GraphRevisionOrder.newer:
        break;
    }
    _watchRecovery = null;
    _knownTag = firstPage.value.tag;
    _tagRevision = firstPage.value.revision;
    state = firstPage.value;
  }

  bool _acceptsTagRevision(GraphRevision revision) =>
      !_isRetired(revision) &&
      (_tagRevision == null ||
          revision.compareTo(_tagRevision!) != GraphRevisionOrder.older);

  void _beginRefresh(TagNavigationLoaded current) {
    _watchRecovery?.firstPage = null;
    state = current.withStatus(
      clearCursor: true,
      freshness: TagNavigationFreshness.refreshing,
      pageStatus: const TagNavigationPageIdle(),
    );
  }

  void _repeatStaleRead() {
    if (++_staleReadAttempts >= _maxStaleReads) {
      _firstPagePending = false;
      _firstFailure(const TaggedEntitiesUnavailableFailure());
    } else {
      _firstPagePending = true;
    }
  }

  bool _isRetired(GraphRevision revision) =>
      _retiredRevision != null &&
      revision.compareTo(_retiredRevision!) !=
          GraphRevisionOrder.differentEpoch;

  bool _precedesRequired(GraphRevision revision) =>
      _requiredRevision != null &&
      switch (revision.compareTo(_requiredRevision!)) {
        GraphRevisionOrder.older || GraphRevisionOrder.differentEpoch => true,
        GraphRevisionOrder.same || GraphRevisionOrder.newer => false,
      };

  bool _advanceRevision(GraphRevision revision) {
    if (_isRetired(revision)) return false;
    final required = _requiredRevision;
    if (required != null) {
      switch (revision.compareTo(required)) {
        case GraphRevisionOrder.older || GraphRevisionOrder.same:
          return false;
        case GraphRevisionOrder.differentEpoch:
          _retiredRevision = required;
        case GraphRevisionOrder.newer:
          break;
      }
    }
    _requiredRevision = revision;
    return true;
  }

  void _pageFailure(
    TagNavigationLoaded base,
    TaggedEntitiesReadFailure failure,
  ) {
    state = base.withPageStatus(
      TagNavigationPageFailure(failure),
      clearCursor: failure is! TaggedEntitiesUnavailableFailure,
    );
  }

  Future<TaggedEntitiesPageResult> _readPage(TaggedEntitiesQuery query) async {
    try {
      return await _reads.getTaggedEntitiesPage(query);
    } on Object {
      return const TaggedEntitiesPageError(TaggedEntitiesUnexpectedFailure());
    }
  }
}

final class _WatchRecovery {
  GraphSnapshot<Tag>? observation;
  ({int generation, TagNavigationLoaded value})? firstPage;
}
