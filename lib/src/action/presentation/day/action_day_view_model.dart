import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/navigation/graph_generation.dart';
import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../application/action_command.dart';
import '../../application/action_day.dart';
import '../../application/action_result.dart';
import '../../domain/action.dart';
import '../../domain/action_id.dart';
import 'action_day_instance.dart';
import 'action_day_snapshot_assembly.dart';
import 'action_day_state.dart';

part 'action_day_view_model.g.dart';

/// Публикует согласованную пару и независимо подгружает её секции.
@riverpod
final class ActionDayViewModel extends _$ActionDayViewModel {
  late PersonalGraphRepository _repository;
  late GraphCommandCoordinator _coordinator;
  final _completionTokens = <ActionId, ActionOperationToken>{};
  StreamSubscription<GraphCommandCompletion>? _completions;

  /// Поколение графа, для которого задан выбор экрана дня.
  GraphGeneration? _graphGeneration;
  late ActionDaySelection _selection;
  var _generation = 0;
  GraphRevision? _requiredRevision;
  Object? _assembly;
  final _pages = <ActionDaySection, Object>{};

  @override
  ActionDayState build(ActionDayInstance instance) {
    // Новое поколение графа открывает экран дня на начальной дате экземпляра,
    // а другое перестроение сохраняет выбор.
    final graphGeneration = ref.watch(currentGraphGenerationProvider);
    if (graphGeneration != _graphGeneration) {
      _graphGeneration = graphGeneration;
      _selection = ActionDaySelection(date: instance.initialDate);
    }
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
    return ActionDayInitialLoad(_selection);
  }

  void selectDate(CalendarDate date) {
    if (_selection.date == date) return;
    _selection = _selection.withDate(date);
    ++_generation;
    _pages.clear();
    state = ActionDayInitialLoad(
      _selection,
      completionOperations: state.completionOperations,
    );
    unawaited(_assemble());
  }

  /// Заголовки секций есть только над подтверждёнными данными.
  void toggleSection(ActionDaySection section) {
    if (state case final ActionDayLoaded loaded) {
      _selection = _selection.toggle(section);
      state = loaded.withStatus(
        selection: _selection,
        refreshFailure: loaded.refreshFailure,
      );
    }
  }

  Future<void> retryFirstPage() {
    if (state case ActionDayInitialFailure(canRetry: true)) {
      state = ActionDayInitialLoad(
        _selection,
        completionOperations: state.completionOperations,
      );
      return _assemble();
    }
    return Future.value();
  }

  Future<void> retryRefresh() {
    final loaded = state;
    if (loaded is ActionDayLoaded &&
        loaded.freshness == ActionDayFreshness.stale &&
        loaded.canRetryRefresh) {
      return _assemble(base: loaded);
    }
    return Future.value();
  }

  /// Отправляет только выполнение; сохранённая строка меняется вместе с парой.
  /// Отказ показывается у строки лишь в открытой [session]; без неё его
  /// предъявляет общая поверхность. Возвращает освобождение права строки,
  /// которое не отменяет команду.
  void Function()? changeCompletion(
    ActionId id,
    bool isCompleted, {
    ActionCompletionSession? session,
  }) {
    final current = state;
    if (current is! ActionDayLoaded || !current.canChangeCompletion(id)) {
      return null;
    }
    if (current.items.firstWhere((item) => item.id == id).isCompleted ==
        isCompleted) {
      return null;
    }
    _releaseCompletionToken(id);
    final start = _coordinator.acceptActionUpdate(
      UpdateActionFields(
        actionId: id,
        patch: ActionFieldsPatch(isCompleted: ActionFieldSet(isCompleted)),
      ),
    );
    switch (start) {
      case ActionCommandAccepted(:final token, :final future):
        _completionTokens[id] = token;
        _setCompletionOperation(id, const ActionCompletionSubmitting());
        unawaited(_finishCompletion(id, future, session));
        final coordinator = _coordinator;
        return () => coordinator.releaseInitiatorPresentation(token);
      case ActionCommandAlreadyRunning():
        _setCompletionOperation(
          id,
          ActionCompletionFailed(
            const ActionConflictFailure(),
            inline: session == null
                ? null
                : ActionCompletionInlineFailure(session),
          ),
        );
        return null;
      case GraphCommandCoordinatorDraining():
        _setCompletionOperation(
          id,
          ActionCompletionFailed(
            const ActionUnexpectedFailure(),
            inline: session == null
                ? null
                : ActionCompletionInlineFailure(session),
          ),
        );
        return null;
    }
  }

  /// После отказа без явного повтора актуальная пара разрешает только новое
  /// явное подтверждение; отклонённое изменение не отправляется повторно.
  Future<void> refreshCompletion(ActionId id) async {
    final current = state;
    final operation = current.completionOperations[id];
    if (current is! ActionDayLoaded ||
        operation is! ActionCompletionFailed ||
        !operation.requiresRefresh ||
        _assembly != null) {
      return;
    }
    await _assemble(base: current);
    if (!ref.mounted) return;
    if (state case ActionDayLoaded(freshness: ActionDayFreshness.current)) {
      if (!identical(state.completionOperations[id], operation)) return;
      _releaseCompletionToken(id);
      state = state.withCompletionOperations(
        {...state.completionOperations}..remove(id),
      );
    }
  }

  Future<void> _finishCompletion(
    ActionId id,
    Future<ActionCommandCompletion> future,
    ActionCompletionSession? session,
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
          ActionCompletionAwaitingSnapshot(confirmed.revision),
        );
        final current = state;
        if (current is ActionDayLoaded &&
            _includesRevision(current.revision, confirmed.revision)) {
          state = current.withCompletionOperations(
            _reconciledOperations(current.revision),
          );
        } else if (_assembly == null) {
          unawaited(
            _assemble(base: current is ActionDayLoaded ? current : null),
          );
        }
      case GraphResultFailure(:final failure):
        if (session == null || !session.canPresentFailure) {
          _coordinator.releaseInitiatorPresentation(completion.token);
          _setCompletionOperation(id, ActionCompletionFailed(failure));
        } else {
          _setCompletionOperation(
            id,
            ActionCompletionFailed(
              failure,
              inline: ActionCompletionInlineFailure(
                session,
                claim: _coordinator.claimInitiatorFailure(completion.token),
              ),
            ),
          );
        }
    }
  }

  void _setCompletionOperation(
    ActionId id,
    ActionCompletionOperation operation,
  ) {
    state = state.withCompletionOperations({
      ...state.completionOperations,
      id: operation,
    });
  }

  void _releaseCompletionToken(ActionId id) {
    final token = _completionTokens.remove(id);
    if (token != null) _coordinator.releaseInitiatorPresentation(token);
  }

  Map<ActionId, ActionCompletionOperation> _reconciledOperations(
    GraphRevision revision,
  ) => Map.unmodifiable({
    for (final entry in state.completionOperations.entries)
      if (switch (entry.value) {
        ActionCompletionAwaitingSnapshot(revision: final required) =>
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

  Future<void> loadMore({required ActionDaySection section}) {
    final current = state;
    if (current is! ActionDayLoaded ||
        current.freshness != ActionDayFreshness.current ||
        current.section(section).nextCursor == null ||
        current.section(section).pageStatus is! ActionDayContinuationIdle) {
      return Future.value();
    }
    if (current.needsRebase) {
      return _assemble(base: current, extend: {section});
    }
    return _loadMore(current, section);
  }

  Future<void> retryLoadMore({required ActionDaySection section}) {
    if (state case ActionDayLoaded loaded) {
      if (loaded.section(section).pageStatus case ActionDayContinuationFailure(
        canRetry: true,
      )) {
        state = loaded.withSection(
          section,
          loaded.section(section).withStatus(const ActionDayContinuationIdle()),
        );
        return loadMore(section: section);
      }
    }
    return Future.value();
  }

  Future<void> _assemble({
    ActionDayLoaded? base,
    Set<ActionDaySection> extend = const {},
  }) async {
    final request = Object();
    _assembly = request;
    _pages.clear();
    final generation = _generation;
    if (base != null) {
      state = base.withStatus(
        selection: _selection,
        freshness: ActionDayFreshness.refreshing,
        needsRebase: true,
        incomplete: base.incomplete.withStatus(
          const ActionDayContinuationIdle(),
        ),
        completed: base.completed.withStatus(const ActionDayContinuationIdle()),
      );
    }
    int target(ActionDaySection section) =>
        (base?.section(section).items.length ?? 0) +
        (extend.contains(section) ? ActionDayQuery.defaultPageSize : 0);
    final result = await assembleActionDaySnapshot(
      date: _selection.date,
      incompleteItemCount: target(ActionDaySection.incomplete),
      completedItemCount: target(ActionDaySection.completed),
      readPage: _repository.getActionDayPage,
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
      case ActionDayAssemblyReady(:final snapshot):
        state = ActionDayLoaded.fromSnapshot(
          selection: _selection,
          snapshot: snapshot,
          completionOperations: _reconciledOperations(snapshot.revision),
        );
      case ActionDayAssemblyFailed(:final failure):
        state = base == null
            ? ActionDayInitialFailure(
                _selection,
                failure,
                completionOperations: state.completionOperations,
              )
            : base.withStatus(
                completionOperations: state.completionOperations,
                selection: _selection,
                freshness: ActionDayFreshness.stale,
                refreshFailure: failure,
                needsRebase: true,
                incomplete: base.incomplete.withStatus(
                  const ActionDayContinuationIdle(),
                ),
                completed: base.completed.withStatus(
                  const ActionDayContinuationIdle(),
                ),
              );
      case ActionDayAssemblyCancelled():
        break;
    }
  }

  Future<void> _loadMore(ActionDayLoaded base, ActionDaySection section) async {
    final sectionState = base.section(section);
    final request = Object();
    final generation = _generation;
    _pages[section] = request;
    state = base.withSection(
      section,
      sectionState.withStatus(const ActionDayContinuationLoading()),
    );
    ActionDayPageResult result;
    try {
      result = await _repository.getActionDayPage(
        ActionDayQuery(
          date: _selection.date,
          section: section,
          cursor: sectionState.nextCursor,
        ),
      );
    } on Object {
      result = const ActionDayPageError(ActionDayUnexpectedFailure());
    }
    if (!ref.mounted ||
        generation != _generation ||
        !identical(_pages[section], request)) {
      return;
    }
    _pages.remove(section);
    final current = state as ActionDayLoaded;
    switch (result) {
      case GraphResultSuccess(value: final ActionDayContinuationPage page):
        if (page.revision.compareTo(current.revision) !=
                GraphRevisionOrder.same ||
            _precedesRequired(page.revision)) {
          await _assemble(base: current, extend: {section, ..._pages.keys});
        } else {
          state = current.withSection(
            section,
            current.section(section).append(page),
          );
        }
      case GraphResultFailure(failure: ActionDaySnapshotExpired()):
        await _assemble(base: current, extend: {section, ..._pages.keys});
      case GraphResultFailure(:final failure):
        state = current.withSection(
          section,
          sectionState.withStatus(ActionDayContinuationFailure(failure)),
        );
      case GraphResultSuccess():
        state = current.withSection(
          section,
          sectionState.withStatus(
            const ActionDayContinuationFailure(ActionDayUnexpectedFailure()),
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
      if (current is ActionDayLoaded) current.revision,
      ?_requiredRevision,
    ]) {
      final order = package.revision.compareTo(known);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return;
      }
    }
    _requiredRevision = package.revision;
    if (current is! ActionDayLoaded || _assembly != null) return;
    if (_affectsVisibleData(package.changes, current) ||
        current.freshness != ActionDayFreshness.current ||
        _pages.isNotEmpty) {
      unawaited(_assemble(base: current, extend: _pages.keys.toSet()));
    } else {
      state = current.withStatus(needsRebase: true);
    }
  }

  /// Строки зависят от самих действий и названий их корневых намерений.
  bool _affectsVisibleData(List<GraphChange> changes, ActionDayLoaded current) {
    final ids = {for (final item in current.items) item.id};
    final roots = {for (final item in current.items) item.rootIntentionId};
    for (final change in changes) {
      switch (change) {
        case ActionChange(:final before, :final after):
          if (ids.contains(before?.id) ||
              ids.contains(after?.id) ||
              _matches(before) ||
              _matches(after)) {
            return true;
          }
        case IntentionCatalogMutation(:final before, :final after):
          if (roots.contains(before?.summary.id) ||
              roots.contains(after?.summary.id)) {
            return true;
          }
        case GraphChange():
          break;
      }
    }
    return false;
  }

  bool _matches(Action? action) =>
      action != null && action.date == _selection.date;

  bool _precedesRequired(GraphRevision revision) {
    final required = _requiredRevision;
    if (required == null) return false;
    final order = revision.compareTo(required);
    return order == GraphRevisionOrder.older ||
        order == GraphRevisionOrder.differentEpoch;
  }
}
