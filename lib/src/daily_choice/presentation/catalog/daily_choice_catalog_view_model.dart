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
import '../../application/daily_choice_command.dart';
import '../../application/daily_choice_result.dart';
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice.dart';
import '../../domain/daily_choice_id.dart';
import 'daily_choice_catalog_instance.dart';
import 'daily_choice_catalog_snapshot_assembly.dart';
import 'daily_choice_catalog_state.dart';

part 'daily_choice_catalog_view_model.g.dart';

/// Публикует согласованную пару и независимо подгружает её секции.
@riverpod
final class DailyChoiceCatalogViewModel extends _$DailyChoiceCatalogViewModel {
  late PersonalGraphRepository _repository;
  late GraphCommandCoordinator _coordinator;
  final _completionTokens = <DailyChoiceId, DailyChoiceOperationToken>{};
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
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _completions = _coordinator.completions.listen((completion) {
      scheduleMicrotask(() => _onCompletion(completion));
    });
    ref.onDispose(() => unawaited(_completions?.cancel()));
    ref.onDispose(() {
      for (final token in _completionTokens.values) {
        _coordinator.releaseInitiatorPresentation(token);
      }
      _completionTokens.clear();
    });
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
    state = DailyChoiceCatalogInitialLoad(
      _selection,
      completionOperations: state.completionOperations,
    );
    unawaited(_assemble());
  }

  void toggleSection(bool isCompleted) {
    _selection = _selection.toggle(isCompleted);
    state = switch (state) {
      DailyChoiceCatalogInitialLoad() => DailyChoiceCatalogInitialLoad(
        _selection,
        completionOperations: state.completionOperations,
      ),
      DailyChoiceCatalogInitialFailure(:final failure) =>
        DailyChoiceCatalogInitialFailure(
          _selection,
          failure,
          completionOperations: state.completionOperations,
        ),
      DailyChoiceCatalogLoaded loaded => loaded.withStatus(
        selection: _selection,
        refreshFailure: loaded.refreshFailure,
      ),
    };
  }

  Future<void> retryFirstPage() {
    if (state case DailyChoiceCatalogInitialFailure(canRetry: true)) {
      state = DailyChoiceCatalogInitialLoad(
        _selection,
        completionOperations: state.completionOperations,
      );
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

  /// Отправляет только выполнение; сохранённая карточка меняется вместе с парой.
  /// Отказ показывается у карточки лишь в открытой [session]; без неё его
  /// предъявляет общая поверхность. Возвращает освобождение права карточки,
  /// которое не отменяет команду.
  void Function()? changeCompletion(
    DailyChoiceId id,
    bool isCompleted, {
    DailyChoiceCompletionSession? session,
  }) {
    final current = state;
    if (current is! DailyChoiceCatalogLoaded ||
        !current.canChangeCompletion(id)) {
      return null;
    }
    if (current.items.firstWhere((item) => item.id == id).isCompleted ==
        isCompleted) {
      return null;
    }
    _releaseCompletionToken(id);
    final start = _coordinator.acceptDailyChoiceUpdate(
      UpdateDailyChoiceFields(
        choiceId: id,
        patch: DailyChoiceFieldsPatch(
          isCompleted: DailyChoiceFieldSet(isCompleted),
        ),
      ),
    );
    switch (start) {
      case DailyChoiceCommandAccepted(:final token, :final future):
        _completionTokens[id] = token;
        _setCompletionOperation(id, const DailyChoiceCompletionSubmitting());
        unawaited(_finishCompletion(id, future, session));
        final coordinator = _coordinator;
        return () => coordinator.releaseInitiatorPresentation(token);
      case DailyChoiceCommandAlreadyRunning():
        _setCompletionOperation(
          id,
          DailyChoiceCompletionFailed(
            const DailyChoiceConflictFailure(
              DailyChoiceConflictReason.dependencyChanged,
            ),
            inline: session == null
                ? null
                : DailyChoiceCompletionInlineFailure(session),
          ),
        );
        return null;
      case GraphCommandCoordinatorDraining():
        _setCompletionOperation(
          id,
          DailyChoiceCompletionFailed(
            const DailyChoiceUnexpectedFailure(),
            inline: session == null
                ? null
                : DailyChoiceCompletionInlineFailure(session),
          ),
        );
        return null;
    }
  }

  /// После конфликта новая пара разрешает только новое явное подтверждение.
  Future<void> refreshCompletion(DailyChoiceId id) async {
    final current = state;
    final operation = current.completionOperations[id];
    if (current is! DailyChoiceCatalogLoaded ||
        operation is! DailyChoiceCompletionFailed ||
        !operation.requiresRefresh ||
        _assembly != null) {
      return;
    }
    await _assemble(base: current);
    if (!ref.mounted) return;
    if (state case DailyChoiceCatalogLoaded(
      freshness: DailyChoiceCatalogFreshness.current,
    )) {
      if (!identical(state.completionOperations[id], operation)) return;
      _releaseCompletionToken(id);
      state = state.withCompletionOperations(
        {...state.completionOperations}..remove(id),
      );
    }
  }

  Future<void> _finishCompletion(
    DailyChoiceId id,
    Future<DailyChoiceCommandCompletion> future,
    DailyChoiceCompletionSession? session,
  ) async {
    final completion = await future;
    if (!ref.mounted || !identical(_completionTokens[id], completion.token)) {
      return;
    }
    switch (completion.confirmedResult) {
      case GraphResultSuccess(value: final confirmed):
        _releaseCompletionToken(id);
        _setCompletionOperation(
          id,
          DailyChoiceCompletionAwaitingSnapshot(confirmed.revision),
        );
        final current = state;
        if (current is DailyChoiceCatalogLoaded &&
            _includesRevision(current.revision, confirmed.revision)) {
          state = current.withCompletionOperations(
            _reconciledOperations(current.revision),
          );
        } else if (_assembly == null) {
          unawaited(
            _assemble(
              base: current is DailyChoiceCatalogLoaded ? current : null,
            ),
          );
        }
      case GraphResultFailure(:final failure):
        if (session == null || !session.canPresentFailure) {
          _coordinator.releaseInitiatorPresentation(completion.token);
          _setCompletionOperation(id, DailyChoiceCompletionFailed(failure));
        } else {
          _setCompletionOperation(
            id,
            DailyChoiceCompletionFailed(
              failure,
              inline: DailyChoiceCompletionInlineFailure(
                session,
                claim: _coordinator.claimInitiatorFailure(completion.token),
              ),
            ),
          );
        }
    }
  }

  void _setCompletionOperation(
    DailyChoiceId id,
    DailyChoiceCompletionOperation operation,
  ) {
    state = state.withCompletionOperations({
      ...state.completionOperations,
      id: operation,
    });
  }

  void _releaseCompletionToken(DailyChoiceId id) {
    final token = _completionTokens.remove(id);
    if (token != null) _coordinator.releaseInitiatorPresentation(token);
  }

  Map<DailyChoiceId, DailyChoiceCompletionOperation> _reconciledOperations(
    GraphRevision revision,
  ) => Map.unmodifiable({
    for (final entry in state.completionOperations.entries)
      if (switch (entry.value) {
        DailyChoiceCompletionAwaitingSnapshot(revision: final required) =>
          !_includesRevision(revision, required),
        _ => true,
      })
        entry.key: entry.value,
  });

  bool _includesRevision(GraphRevision snapshot, GraphRevision required) =>
      switch (snapshot.compareTo(required)) {
        GraphRevisionOrder.same || GraphRevisionOrder.newer => true,
        GraphRevisionOrder.older || GraphRevisionOrder.differentEpoch => false,
      };

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
          completionOperations: _reconciledOperations(snapshot.revision),
        );
      case DailyChoiceCatalogAssemblyFailed(:final failure):
        state = base == null
            ? DailyChoiceCatalogInitialFailure(
                _selection,
                failure,
                completionOperations: state.completionOperations,
              )
            : base.withStatus(
                completionOperations: state.completionOperations,
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
