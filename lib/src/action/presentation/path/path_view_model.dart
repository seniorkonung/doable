import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../application/path_candidates.dart';
import '../../domain/action_path.dart';
import 'path_state.dart';

part 'path_view_model.g.dart';

/// Сессия построения пути и порционного чтения его продолжений.
@riverpod
final class PathViewModel extends _$PathViewModel {
  late PersonalGraphRepository _repository;
  // Поздние ответы прежнего пути или половины не меняют текущий экран.
  var _generation = 0;

  @override
  PathState build(PathSessionKey sessionKey, ActionPath? original) {
    _repository = ref.watch(personalGraphRepositoryProvider);
    if (original == null) {
      return PathState(original: null, draft: const EmptyPathDraft());
    }
    final draft = LoadingPathDraft(original.intentions);
    unawaited(Future.microtask(() => _read(draft.intentions)));
    return PathState(original: original, draft: draft);
  }

  void selectRoot(IntentionId root) {
    state = state.withDraft(LoadingPathDraft([root]));
    unawaited(_read([root]));
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
    state = state
        .withDraft(LoadedPathDraft(shortened))
        .withCandidates(
          const CandidateState(half: LongTermRelationType.need, loading: true),
        );
    unawaited(_read(state.draft.intentions));
  }

  void selectCandidate(PathCandidate candidate) {
    final draft = state.draft;
    if (draft is! LoadedPathDraft) return;
    final ids = [...draft.intentions, candidate.relation.relatedIntentionId];
    state = state.withDraft(
      LoadedPathDraft(draft.segment, appended: candidate),
    );
    unawaited(_read(ids));
  }

  void selectHalf(LongTermRelationType half) {
    final current = state.candidates;
    if (current == null || current.half == half) return;
    unawaited(_read(state.draft.intentions, half: half));
  }

  Future<void> retry() {
    final draft = state.draft;
    if (draft is FailedPathDraft && draft.canRetry) {
      state = state.withDraft(LoadingPathDraft(draft.intentions));
      return _read(draft.intentions);
    }
    final candidates = state.candidates;
    if (candidates?.failure is PathCandidatesUnavailableFailure) {
      return _read(
        draft.intentions,
        half: candidates!.chooseDefault ? null : candidates.half,
      );
    }
    return Future.value();
  }

  Future<void> loadMore() async {
    final current = state.candidates;
    if (current == null ||
        current.loading ||
        current.failure != null ||
        current.cursor == null) {
      return;
    }
    final generation = ++_generation;
    state = state.withCandidates(
      CandidateState(
        half: current.half,
        counts: current.counts,
        items: current.items,
        cursor: current.cursor,
        loading: true,
      ),
    );
    final result = await _repository.getPathCandidates(
      PathCandidatesQuery(
        draft: ActionPath(state.draft.intentions),
        half: current.half,
        cursor: current.cursor,
      ),
    );
    if (!ref.mounted || generation != _generation) return;
    switch (result) {
      case GraphResultSuccess(value: PathCandidatesContinuationPage page):
        state = state.withCandidates(
          CandidateState(
            half: current.half,
            counts: current.counts,
            items: [...current.items, ...page.items],
            cursor: page.nextCursor,
          ),
        );
      case GraphResultFailure(failure: PathCandidatesSnapshotExpired()):
        await _read(state.draft.intentions, half: current.half);
      case GraphResultFailure(:final failure):
        state = state.withCandidates(
          CandidateState(
            half: current.half,
            counts: current.counts,
            items: current.items,
            cursor: current.cursor,
            failure: failure,
          ),
        );
      case GraphResultSuccess():
        state = state.withCandidates(
          CandidateState(
            half: current.half,
            counts: current.counts,
            items: current.items,
            cursor: current.cursor,
            failure: const PathCandidatesUnexpectedFailure(),
          ),
        );
    }
  }

  ActionPath? save() =>
      state.canSave ? ActionPath(state.draft.intentions) : null;
  PathCloseDecision requestClose() => state.closeDecision;

  Future<void> _read(
    List<IntentionId> ids, {
    LongTermRelationType? half,
  }) async {
    final generation = ++_generation;
    final selected = half ?? LongTermRelationType.need;
    if (state.draft is LoadedPathDraft) {
      state = state.withCandidates(
        CandidateState(half: selected, loading: true),
      );
    }
    final result = await _repository.getPathCandidates(
      PathCandidatesQuery(draft: ActionPath(ids), half: selected),
    );
    if (!ref.mounted || generation != _generation) return;
    switch (result) {
      case GraphResultSuccess(value: PathCandidatesFirstPage page):
        state = state.withDraft(LoadedPathDraft(page.segment));
        if (half == null && page.counts.need == 0 && page.counts.can > 0) {
          await _read(state.draft.intentions, half: LongTermRelationType.can);
        } else {
          state = state.withCandidates(
            CandidateState(
              half: selected,
              counts: page.counts,
              items: page.items,
              cursor: page.nextCursor,
            ),
          );
        }
      case GraphResultSuccess(value: EmptyPathSegment()):
        state = state.withDraft(const EmptyPathDraft());
      case GraphResultFailure(:final failure):
        if (state.draft is LoadedPathDraft) {
          state = state.withCandidates(
            CandidateState(
              half: selected,
              failure: failure,
              chooseDefault: half == null,
            ),
          );
        } else {
          state = state.withDraft(FailedPathDraft(ids, failure));
        }
      case GraphResultSuccess():
        state = state.withDraft(
          FailedPathDraft(ids, const PathCandidatesUnexpectedFailure()),
        );
    }
  }
}
