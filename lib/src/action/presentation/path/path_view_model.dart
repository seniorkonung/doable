import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_change.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../application/action_command.dart';
import '../../application/action_result.dart';
import '../../application/path_candidates.dart';
import '../../domain/action_id.dart';
import '../../domain/action_path.dart';
import '../path_start/path_start_picker_page.dart';
import 'path_state.dart';

part 'path_view_model.g.dart';

/// Сессия построения пути и порционного чтения его продолжений.
///
/// Для существующего действия сессия сама заменяет его путь. Замена
/// завершается и после ухода с экрана: тогда её отказ предъявляет общая
/// поверхность результатов, а успех виден в данных без сообщения.
@riverpod
final class PathViewModel extends _$PathViewModel {
  late PersonalGraphRepository _repository;
  late GraphCommandCoordinator _coordinator;
  // Поздние ответы прежнего пути или половины не меняют текущий экран.
  var _generation = 0;

  /// Замена, право предъявить отказ которой ещё у экрана.
  ActionOperationToken? _replacement;
  StreamSubscription<GraphCommandCompletion>? _completions;
  var _refreshAfterSaving = false;

  @override
  PathState build(PathSessionKey sessionKey, PathPurpose purpose) {
    _repository = ref.watch(personalGraphRepositoryProvider);
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    unawaited(_completions?.cancel());
    _completions = _coordinator.completions.listen((completion) {
      scheduleMicrotask(() => _onCompletion(completion));
    });
    ref.onDispose(() => unawaited(_completions?.cancel()));
    ref.onDispose(_releaseReplacement);
    final start = purpose.start;
    if (start == null) {
      return PathState(
        original: purpose.original,
        draft: const EmptyPathDraft(),
      );
    }
    final draft = LoadingPathDraft(start.intentions, CandidateState.initial);
    unawaited(Future.microtask(() => _read(draft)));
    final state = PathState(original: purpose.original, draft: draft);
    return switch (purpose) {
      NewActionPathPurpose(createdIntention: true) => state.withCreations(
        const PathCreations(intentions: 1),
      ),
      _ => state,
    };
  }

  void selectRoot(PathStartChoice choice) {
    if (choice is PathStartCreated) acceptCreatedIntention();
    final root = choice.intention;
    final previous = state.draft.intentions.lastOrNull == root
        ? state.candidates
        : null;
    unawaited(
      _reread(LoadingPathDraft([root], previous ?? CandidateState.initial)),
    );
  }

  /// Связи, добавленные к последнему намерению, сами в путь не входят и
  /// половину не переключают: исход может прийти после ухода с поиска, когда
  /// открыта уже другая половина. Кандидатов перечитывает подтверждённое
  /// изменение графа.
  void acceptAddedRelations(List<LongTermRelation> relations) {
    state = state.withCreations(
      state.creations.withRelations(relations.map((relation) => relation.id)),
    );
  }

  void acceptCreatedIntention() {
    state = state.withCreations(state.creations.withIntention());
  }

  void endAt(IntentionId intention) {
    final draft = state.draft;
    if (draft is! LoadedPathDraft) return;
    final segment = draft.segment;
    final index = segment.steps.indexWhere(
      (step) => step.intention.id == intention,
    );
    if (index < 0 ||
        (index == segment.steps.length - 1 && draft.appended == null)) {
      return;
    }
    final shortened = PathSegment(
      root: segment.root,
      steps: segment.steps.take(index + 1),
    );
    unawaited(_read(LoadedPathDraft(shortened, CandidateState.initial)));
  }

  void selectCandidate(PathCandidate candidate) {
    final draft = state.draft;
    if (draft is! LoadedPathDraft) return;
    unawaited(
      _read(
        LoadedPathDraft(
          draft.segment,
          CandidateState.initial,
          appended: candidate,
        ),
      ),
    );
  }

  void selectHalf(LongTermRelationType half) {
    if (state.draft case final NonEmptyPathDraft draft
        when draft.candidates.half != half) {
      unawaited(_read(draft, half: half));
    }
  }

  Future<void> retry() => switch (state.draft) {
    final FailedPathDraft draft when draft.canRetry => _reread(draft),
    final LoadedPathDraft draft
        when draft.candidates.failure is PathCandidatesUnavailableFailure =>
      _reread(draft),
    _ => Future.value(),
  };

  Future<void> loadMore() async {
    final draft = state.draft;
    if (draft is! LoadedPathDraft) return;
    final current = draft.candidates;
    if (current.loading || current.failure != null || current.cursor == null) {
      return;
    }
    final generation = ++_generation;
    final loading = draft.withCandidates(
      CandidateState(
        half: current.half,
        counts: current.counts,
        items: current.items,
        cursor: current.cursor,
        loading: true,
      ),
    );
    state = state.withDraft(loading);
    final result = await _repository.getPathCandidates(
      PathCandidatesQuery(
        draft: ActionPath(loading.intentions),
        half: current.half,
        cursor: current.cursor,
      ),
    );
    if (!ref.mounted || generation != _generation) return;
    switch (result) {
      case GraphResultSuccess(value: PathCandidatesContinuationPage page):
        state = state.withDraft(
          loading.withCandidates(
            CandidateState(
              half: current.half,
              counts: current.counts,
              items: [...current.items, ...page.items],
              cursor: page.nextCursor,
            ),
          ),
        );
      case GraphResultFailure(failure: PathCandidatesSnapshotExpired()):
        await _read(loading, half: current.half);
      case GraphResultFailure(:final failure):
        state = state.withDraft(
          loading.withCandidates(
            CandidateState(
              half: current.half,
              counts: current.counts,
              items: current.items,
              cursor: current.cursor,
              failure: failure,
            ),
          ),
        );
      case GraphResultSuccess():
        state = state.withDraft(
          loading.withCandidates(
            CandidateState(
              half: current.half,
              counts: current.counts,
              items: current.items,
              cursor: current.cursor,
              failure: const PathCandidatesUnexpectedFailure(),
            ),
          ),
        );
    }
  }

  /// Возвращает сохранённый путь, после которого экран закрывается: для
  /// нового действия — сразу, для существующего — после подтверждённой
  /// замены. Отказ замены и уход до её исхода возвращают `null`.
  Future<ActionPath?> save() async {
    if (!state.canSave) return null;
    final path = ActionPath(state.draft.intentions);
    return switch (purpose) {
      NewActionPathPurpose() => path,
      ExistingActionPathPurpose(:final actionId) => _replace(actionId, path),
    };
  }

  PathCloseDecision requestClose() => state.closeDecision;

  Future<ActionPath?> _replace(ActionId actionId, ActionPath path) async {
    _releaseReplacement();
    switch (_coordinator.acceptActionPathUpdate(
      SetActionPath(actionId: actionId, path: path),
    )) {
      case ActionCommandAccepted(:final token, :final future):
        _replacement = token;
        state = state.withSaving(const PathSavingRunning());
        final completion = await future;
        if (!ref.mounted) return null;
        switch (completion.result) {
          case GraphResultSuccess(value: ActionPathUpdated()):
            _replacement = null;
            return path;
          case GraphResultFailure(:final failure):
            state = state.withSaving(
              PathSavingFailed(
                failure,
                presentation: _coordinator.claimInitiatorFailure(token),
              ),
            );
            _refreshAfterFailedSave();
          case GraphResultSuccess():
            state = state.withSaving(
              const PathSavingFailed(ActionUnexpectedFailure()),
            );
            _refreshAfterFailedSave();
        }
      // Действие ещё меняет другая принятая операция, например замена с
      // экрана, с которого ушли до её исхода.
      case ActionCommandAlreadyRunning():
        state = state.withSaving(
          const PathSavingFailed(ActionConflictFailure()),
        );
      case GraphCommandCoordinatorDraining():
        state = state.withSaving(
          const PathSavingFailed(ActionUnexpectedFailure()),
        );
    }
    return null;
  }

  /// Неподтверждённый отказ прежней замены переходит общей поверхности.
  void _releaseReplacement() {
    if (_replacement case final token?) {
      _coordinator.releaseInitiatorPresentation(token);
    }
    _replacement = null;
  }

  void _onCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted) return;
    final changes = completion.confirmedChange?.changes;
    if (changes == null ||
        !changes.any(
          (change) =>
              change is IntentionCatalogMutation ||
              change is LongTermRelationChange ||
              change is GraphReplaced,
        )) {
      return;
    }
    final draft = state.draft;
    if (draft is! NonEmptyPathDraft) return;
    if (state.saving is PathSavingRunning) {
      _refreshAfterSaving = true;
      return;
    }
    unawaited(_reread(draft));
  }

  void _refreshAfterFailedSave() {
    if (!_refreshAfterSaving) return;
    _refreshAfterSaving = false;
    if (state.draft case final NonEmptyPathDraft draft) {
      unawaited(_reread(draft));
    }
  }

  /// Перечитывает участок с выбранной половиной, а если её не выбирали —
  /// снова выбирает половину по умолчанию.
  Future<void> _reread(NonEmptyPathDraft draft) {
    final candidates = draft.candidates;
    return _read(
      draft,
      half: candidates.chooseDefault ? null : candidates.half,
    );
  }

  /// Читает участок [draft]. Числа половин из его кандидатов остаются на
  /// экране до подтверждённого результата: черновик нового последнего
  /// намерения приходит без них.
  Future<void> _read(
    NonEmptyPathDraft draft, {
    LongTermRelationType? half,
  }) async {
    final generation = ++_generation;
    final ids = draft.intentions;
    final selected = half ?? LongTermRelationType.need;
    final counts = draft.candidates.counts;
    final loaded = switch (draft) {
      LoadedPathDraft() => draft,
      LoadingPathDraft() || FailedPathDraft() => null,
    };
    final loading = CandidateState(
      half: selected,
      counts: counts,
      loading: true,
      chooseDefault: half == null,
    );
    state = state.withDraft(
      loaded?.withCandidates(loading) ?? LoadingPathDraft(ids, loading),
    );
    final result = await _repository.getPathCandidates(
      PathCandidatesQuery(draft: ActionPath(ids), half: selected),
    );
    if (!ref.mounted || generation != _generation) return;
    switch (result) {
      case GraphResultSuccess(value: PathCandidatesFirstPage page):
        if (half != null && page.segment.last.id != ids.last) {
          await _read(LoadedPathDraft(page.segment, CandidateState.initial));
        } else if (half == null &&
            page.counts.need == 0 &&
            page.counts.can > 0) {
          await _read(
            LoadedPathDraft(
              page.segment,
              CandidateState(half: selected, counts: page.counts),
            ),
            half: LongTermRelationType.can,
          );
        } else {
          state = state.withDraft(
            LoadedPathDraft(
              page.segment,
              CandidateState(
                half: selected,
                counts: page.counts,
                items: page.items,
                cursor: page.nextCursor,
              ),
            ),
          );
        }
      case GraphResultSuccess(value: EmptyPathSegment()):
        state = state.withDraft(const EmptyPathDraft());
      case GraphResultFailure(:final failure):
        final failed = CandidateState(
          half: selected,
          counts: counts,
          failure: failure,
          chooseDefault: half == null,
        );
        state = state.withDraft(
          loaded?.withCandidates(failed) ??
              FailedPathDraft(ids, failure, failed),
        );
      case GraphResultSuccess():
        state = state.withDraft(
          FailedPathDraft(
            ids,
            const PathCandidatesUnexpectedFailure(),
            CandidateState(
              half: selected,
              counts: counts,
              failure: const PathCandidatesUnexpectedFailure(),
            ),
          ),
        );
    }
  }
}
