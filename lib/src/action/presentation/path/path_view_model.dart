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

/// Экранная сессия пути по ключу экрана.
///
/// Путь на экране показывается по целому начальному участку, прочитанному
/// по последовательности намерений: участок короче последовательности
/// становится путём на экране. Смена корня и сокращение меняют только путь
/// на экране; граф остаётся прежним.
@riverpod
final class PathViewModel extends _$PathViewModel {
  late PersonalGraphRepository _repository;

  /// Каждая смена последовательности отбрасывает ответы прежних чтений.
  var _generation = 0;

  @override
  PathState build(PathSessionKey sessionKey, ActionPath? original) {
    _repository = ref.watch(personalGraphRepositoryProvider);
    if (original == null) {
      return PathState(original: null, draft: const EmptyPathDraft());
    }
    final draft = LoadingPathDraft(original.intentions);
    unawaited(Future.microtask(() => _read(draft)));
    return PathState(original: original, draft: draft);
  }

  /// Заменяет весь путь одним новым корнем.
  void selectRoot(IntentionId root) {
    final draft = LoadingPathDraft([root]);
    state = state.withDraft(draft);
    unawaited(_read(draft));
  }

  /// Заканчивает путь на промежуточном намерении [intention], отбрасывая
  /// все следующие за ним.
  void endAt(IntentionId intention) {
    final draft = state.draft;
    if (draft is! LoadedPathDraft) return;
    final segment = draft.segment;
    final index = segment.steps.indexWhere(
      (step) => step.intention.id == intention,
    );
    // Последнее намерение пути — не кнопка, а корень сменяется в поиске.
    if (index < 0 || index == segment.steps.length - 1) return;
    state = state.withDraft(
      LoadedPathDraft(
        PathSegment(root: segment.root, steps: segment.steps.take(index + 1)),
      ),
    );
  }

  /// Повторяет чтение участка после доказанно временного отказа.
  Future<void> retry() {
    final current = state.draft;
    if (current is! FailedPathDraft || !current.canRetry) {
      return Future.value();
    }
    final draft = LoadingPathDraft(current.intentions);
    state = state.withDraft(draft);
    return _read(draft);
  }

  /// Путь для возврата вызывающему; `null`, пока «Сохранить» недоступна.
  ActionPath? save() {
    final current = state;
    return current.canSave ? ActionPath(current.draft.intentions) : null;
  }

  PathCloseDecision requestClose() => state.closeDecision;

  Future<void> _read(LoadingPathDraft draft) async {
    final generation = ++_generation;
    final result = await _repository.getPathCandidates(
      PathCandidatesQuery(
        draft: ActionPath(draft.intentions),
        half: LongTermRelationType.need,
        pageSize: PathCandidatesQuery.minPageSize,
      ),
    );
    if (!ref.mounted || generation != _generation) return;
    state = state.withDraft(switch (result) {
      GraphResultSuccess(value: PathCandidatesFirstPage(:final segment)) =>
        LoadedPathDraft(segment),
      GraphResultSuccess(value: EmptyPathSegment()) => const EmptyPathDraft(),
      // Первое чтение без курсора продолжением не отвечает.
      GraphResultSuccess(value: PathCandidatesContinuationPage()) =>
        FailedPathDraft(
          draft.intentions,
          const PathCandidatesUnexpectedFailure(),
        ),
      GraphResultFailure(:final failure) => FailedPathDraft(
        draft.intentions,
        failure,
      ),
    });
  }
}
