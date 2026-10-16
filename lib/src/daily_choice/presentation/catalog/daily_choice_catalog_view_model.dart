import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../application/daily_choice_catalog.dart';
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice.dart';
import 'daily_choice_catalog_instance.dart';
import 'daily_choice_catalog_snapshot_assembly.dart';
import 'daily_choice_catalog_state.dart';

part 'daily_choice_catalog_view_model.g.dart';

/// Публикует согласованную пару и независимо подгружает её секции.
@riverpod
final class DailyChoiceCatalogViewModel extends _$DailyChoiceCatalogViewModel {
  late PersonalGraphRepository _repository;
  StreamSubscription<GraphCommandCompletion>? _completions;
  late var _selection = DailyChoiceCatalogSelection(date: instance.initialDate);
  var _generation = 0;
  GraphRevision? _requiredRevision;
  Object? _assembly;
  final _pages = <bool, Object>{};

  @override
  DailyChoiceCatalogState build(DailyChoiceCatalogInstance instance) {
    unawaited(_completions?.cancel());
    _repository = ref.watch(personalGraphRepositoryProvider);
    _completions = ref
        .watch(graphCommandCoordinatorProvider.notifier)
        .completions
        .listen((completion) {
          scheduleMicrotask(() => _onCompletion(completion));
        });
    ref.onDispose(() => unawaited(_completions?.cancel()));
    _pages.clear();
    _requiredRevision = null;
    ++_generation;
    unawaited(_assemble());
    return DailyChoiceCatalogInitialLoad(_selection);
  }

  void selectDate(CalendarDate date) {
    if (_selection.date == date) return;
    _selection = _selection.withDate(date);
    ++_generation;
    _pages.clear();
    state = DailyChoiceCatalogInitialLoad(_selection);
    unawaited(_assemble());
  }

  void toggleSection(bool isCompleted) {
    _selection = _selection.toggle(isCompleted);
    state = switch (state) {
      DailyChoiceCatalogInitialLoad() => DailyChoiceCatalogInitialLoad(
        _selection,
      ),
      DailyChoiceCatalogInitialFailure(:final failure) =>
        DailyChoiceCatalogInitialFailure(_selection, failure),
      DailyChoiceCatalogLoaded loaded => loaded.withStatus(
        selection: _selection,
        refreshFailure: loaded.refreshFailure,
      ),
    };
  }

  Future<void> retryFirstPage() {
    if (state case DailyChoiceCatalogInitialFailure(canRetry: true)) {
      state = DailyChoiceCatalogInitialLoad(_selection);
      return _assemble();
    }
    return Future.value();
  }

  Future<void> retryRefresh() {
    final loaded = state;
    if (loaded is DailyChoiceCatalogLoaded &&
        loaded.freshness == DailyChoiceCatalogFreshness.stale &&
        loaded.refreshFailure is DailyChoiceCatalogUnavailableFailure) {
      return _assemble(base: loaded);
    }
    return Future.value();
  }

  Future<void> loadMore({required bool isCompleted}) {
    final current = state;
    if (current is! DailyChoiceCatalogLoaded ||
        current.freshness != DailyChoiceCatalogFreshness.current ||
        current.section(isCompleted).nextCursor == null ||
        current.section(isCompleted).pageStatus
            is! DailyChoiceCatalogPageIdle) {
      return Future.value();
    }
    if (current.needsRebase) {
      return _assemble(base: current, extend: {isCompleted});
    }
    return _loadMore(current, isCompleted);
  }

  Future<void> retryLoadMore({required bool isCompleted}) {
    if (state case DailyChoiceCatalogLoaded loaded) {
      if (loaded.section(isCompleted).pageStatus
          case DailyChoiceCatalogPageFailure(canRetry: true)) {
        state = loaded.withSection(
          isCompleted,
          loaded
              .section(isCompleted)
              .withStatus(const DailyChoiceCatalogPageIdle()),
        );
        return loadMore(isCompleted: isCompleted);
      }
    }
    return Future.value();
  }

  Future<void> _assemble({
    DailyChoiceCatalogLoaded? base,
    Set<bool> extend = const {},
  }) async {
    final request = Object();
    _assembly = request;
    _pages.clear();
    final generation = _generation;
    if (base != null) {
      state = base.withStatus(
        selection: _selection,
        freshness: DailyChoiceCatalogFreshness.refreshing,
        needsRebase: true,
        incomplete: base.incomplete.withStatus(
          const DailyChoiceCatalogPageIdle(),
        ),
        completed: base.completed.withStatus(
          const DailyChoiceCatalogPageIdle(),
        ),
      );
    }
    int target(bool completed) =>
        (base?.section(completed).items.length ?? 0) +
        (extend.contains(completed)
            ? DailyChoiceCatalogQuery.defaultPageSize
            : 0);
    final result = await assembleDailyChoiceCatalogSnapshot(
      date: _selection.date,
      incompleteItemCount: target(false),
      completedItemCount: target(true),
      readPage: _repository.getDailyChoiceCatalogPage,
      isCurrent: () =>
          ref.mounted &&
          generation == _generation &&
          identical(_assembly, request),
      acceptsRevision: (revision) => !_precedesRequired(revision),
    );
    if (!ref.mounted ||
        generation != _generation ||
        !identical(_assembly, request)) {
      return;
    }
    _assembly = null;
    switch (result) {
      case DailyChoiceCatalogAssemblyReady(:final snapshot):
        state = DailyChoiceCatalogLoaded.fromSnapshot(
          selection: _selection,
          snapshot: snapshot,
        );
      case DailyChoiceCatalogAssemblyFailed(:final failure):
        state = base == null
            ? DailyChoiceCatalogInitialFailure(_selection, failure)
            : base.withStatus(
                selection: _selection,
                freshness: DailyChoiceCatalogFreshness.stale,
                refreshFailure: failure,
                needsRebase: true,
                incomplete: base.incomplete.withStatus(
                  const DailyChoiceCatalogPageIdle(),
                ),
                completed: base.completed.withStatus(
                  const DailyChoiceCatalogPageIdle(),
                ),
              );
      case DailyChoiceCatalogAssemblyCancelled():
        break;
    }
  }

  Future<void> _loadMore(
    DailyChoiceCatalogLoaded base,
    bool isCompleted,
  ) async {
    final section = base.section(isCompleted);
    final request = Object();
    final generation = _generation;
    _pages[isCompleted] = request;
    state = base.withSection(
      isCompleted,
      section.withStatus(const DailyChoiceCatalogPageLoading()),
    );
    DailyChoiceCatalogPageResult result;
    try {
      result = await _repository.getDailyChoiceCatalogPage(
        DailyChoiceCatalogQuery(
          date: _selection.date,
          isCompleted: isCompleted,
          cursor: section.nextCursor,
        ),
      );
    } on Object {
      result = const DailyChoiceCatalogPageError(
        DailyChoiceCatalogUnexpectedFailure(),
      );
    }
    if (!ref.mounted ||
        generation != _generation ||
        !identical(_pages[isCompleted], request)) {
      return;
    }
    _pages.remove(isCompleted);
    final current = state as DailyChoiceCatalogLoaded;
    switch (result) {
      case GraphResultSuccess(
        value: final DailyChoiceCatalogContinuationPage page,
      ):
        if (page.revision.compareTo(current.revision) !=
                GraphRevisionOrder.same ||
            _precedesRequired(page.revision)) {
          await _assemble(base: current, extend: {isCompleted, ..._pages.keys});
        } else {
          state = current.withSection(
            isCompleted,
            current.section(isCompleted).append(page),
          );
        }
      case GraphResultFailure(failure: DailyChoiceCatalogSnapshotExpired()):
        await _assemble(base: current, extend: {isCompleted, ..._pages.keys});
      case GraphResultFailure(:final failure):
        state = current.withSection(
          isCompleted,
          section.withStatus(DailyChoiceCatalogPageFailure(failure)),
        );
      case GraphResultSuccess():
        state = current.withSection(
          isCompleted,
          section.withStatus(
            const DailyChoiceCatalogPageFailure(
              DailyChoiceCatalogUnexpectedFailure(),
            ),
          ),
        );
    }
  }

  void _onCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted) return;
    final package = completion.confirmedChange;
    if (package == null) return;
    final current = state;
    for (final known in [
      if (current is DailyChoiceCatalogLoaded) current.revision,
      ?_requiredRevision,
    ]) {
      final order = package.revision.compareTo(known);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    _requiredRevision = package.revision;
    if (current is! DailyChoiceCatalogLoaded || _assembly != null) return;
    if (_affectsVisibleData(package.changes, current) ||
        current.freshness != DailyChoiceCatalogFreshness.current ||
        _pages.isNotEmpty) {
      unawaited(_assemble(base: current, extend: _pages.keys.toSet()));
    } else {
      state = current.withStatus(needsRebase: true);
    }
  }

  bool _affectsVisibleData(
    List<GraphChange> changes,
    DailyChoiceCatalogLoaded current,
  ) {
    final ids = {for (final item in current.items) item.id};
    final participants = {
      for (final item in current.items) ...[item.source.id, item.selected.id],
    };
    for (final change in changes) {
      switch (change) {
        case DailyChoiceChange(:final before, :final after):
          if (ids.contains(before?.id) ||
              ids.contains(after?.id) ||
              _matches(before) ||
              _matches(after)) {
            return true;
          }
        case IntentionCatalogMutation(:final before, :final after):
          if (participants.contains(before?.summary.id) ||
              participants.contains(after?.summary.id)) {
            return true;
          }
        case GraphChange():
          break;
      }
    }
    return false;
  }

  bool _matches(DailyChoice? choice) =>
      choice != null && choice.date == _selection.date;

  bool _precedesRequired(GraphRevision revision) {
    final required = _requiredRevision;
    if (required == null) return false;
    final order = revision.compareTo(required);
    return order == GraphRevisionOrder.older ||
        order == GraphRevisionOrder.differentEpoch;
  }
}
