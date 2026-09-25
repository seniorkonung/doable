import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/intention_details.dart';
import '../../../intention/application/intention_result.dart'
    as intention_result;
import '../../../intention/domain/intention.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../long_term_relation/application/long_term_relation_projection.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../../long_term_relation/domain/long_term_relation_id.dart';
import '../../application/choice_path_continuations.dart';
import '../../application/choice_path_draft.dart';
import '../../application/confirmed_choice_path.dart';
import 'choice_path_state.dart';

part 'choice_path_view_model.g.dart';

/// Управляет одним обходом. Ответы принимаются только поколением текущего
/// черновика, экранной сессией и ревизией подтверждённого снимка.
@riverpod
final class ChoicePathViewModel extends _$ChoicePathViewModel {
  late PersonalGraphRepository _repository;
  late GraphCommandCoordinator _coordinator;
  StreamSubscription<intention_result.Result<GraphSnapshot<IntentionDetails?>>>?
  _intentionSubscription;
  StreamSubscription<GraphCommandCompletion>? _completionSubscription;
  GraphRevision? _knownRevision;
  var _generation = 0;
  Object _session = Object();

  @override
  ChoicePathState build(
    IntentionId startingIntentionId, {
    ChoicePathDraftDirection direction = ChoicePathDraftDirection.topDown,
  }) {
    _repository = ref.watch(personalGraphRepositoryProvider);
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _knownRevision = null;
    final session = _session = Object();
    final ChoicePathDraft draft = switch (direction) {
      ChoicePathDraftDirection.topDown => ChoicePathDraftStart(
        startingIntentionId,
      ),
      ChoicePathDraftDirection.bottomUp => ChoicePathDraftBottomStart(
        startingIntentionId,
      ),
    };
    _subscribeToChanges(startingIntentionId, session);
    final intentionSubscription = _intentionSubscription;
    final completionSubscription = _completionSubscription;
    ref.onDispose(() {
      unawaited(intentionSubscription?.cancel());
      unawaited(completionSubscription?.cancel());
    });
    final generation = ++_generation;
    unawaited(_loadFirst(generation, draft, const []));
    return ChoicePathLoading(draft, const []);
  }

  /// Переход разрешён только по строке подтверждённой показанной порции.
  bool selectContinuation(LongTermRelationId relationId) {
    final current = state;
    if (current is! ChoicePathData) return false;
    LongTermRelationSummary? selected;
    for (final item in current.items) {
      if (item.relation.id == relationId) {
        selected = item;
        break;
      }
    }
    if (selected == null) return false;
    final relation = selected.relation;
    final step = ConfirmedChoicePathStep(
      relationId: relation.id,
      sourceIntentionId: relation.sourceIntentionId,
      type: relation.type,
      relatedIntentionId: relation.relatedIntentionId,
    );
    final steps = [...current.draft.steps, step];
    final ChoicePathDraft draft = switch (current.draft.direction) {
      ChoicePathDraftDirection.topDown => ChoicePathDraftProgress(
        current.draft.startingIntentionId,
        steps,
      ),
      ChoicePathDraftDirection.bottomUp => ChoicePathDraftBottomProgress(
        current.draft.startingIntentionId,
        steps,
      ),
    };
    final visibleSteps = switch (draft.direction) {
      ChoicePathDraftDirection.topDown => [...current.visibleSteps, selected],
      ChoicePathDraftDirection.bottomUp => [selected, ...current.visibleSteps],
    };
    _restart(draft, visibleSteps);
    return true;
  }

  /// Оставляет указанное число переходов и перечитывает их актуальность.
  bool backToStep(int stepCount) {
    final current = state.draft;
    if (stepCount < 0 || stepCount >= current.steps.length) return false;
    final ChoicePathDraft draft = switch (current.direction) {
      ChoicePathDraftDirection.topDown =>
        stepCount == 0
            ? ChoicePathDraftStart(current.startingIntentionId)
            : ChoicePathDraftProgress(
                current.startingIntentionId,
                current.steps.take(stepCount),
              ),
      ChoicePathDraftDirection.bottomUp =>
        stepCount == 0
            ? ChoicePathDraftBottomStart(current.startingIntentionId)
            : ChoicePathDraftBottomProgress(
                current.startingIntentionId,
                current.steps.take(stepCount),
              ),
    };
    final visibleSteps = switch (current.direction) {
      ChoicePathDraftDirection.topDown => state.visibleSteps.take(stepCount),
      ChoicePathDraftDirection.bottomUp => state.visibleSteps.skip(
        current.steps.length - stepCount,
      ),
    };
    _restart(draft, visibleSteps);
    return true;
  }

  /// После конфликта требуется новая основа; обычная ошибка не повторяется
  /// без отдельного решения вызывающей стороны.
  Future<void> refresh() {
    final current = state;
    if (current is ChoicePathNotFound ||
        (current is ChoicePathFailure && !current.canRetry) ||
        (current is ChoicePathData &&
            current.progress is ChoicePathPageFailure &&
            !(current.progress as ChoicePathPageFailure).canRetry)) {
      return Future.value();
    }
    final draft = current.draft;
    final visibleSteps = current.visibleSteps;
    final generation = ++_generation;
    state = ChoicePathLoading(draft, visibleSteps);
    return _loadFirst(generation, draft, visibleSteps);
  }

  Future<void> retry() {
    final current = state;
    if (current is ChoicePathFailure && current.canRetry) return refresh();
    if (current is ChoicePathData &&
        current.progress is ChoicePathPageFailure &&
        (current.progress as ChoicePathPageFailure).canRetry) {
      return loadMore();
    }
    return Future.value();
  }

  /// Повторные запросы той же страницы не запускаются до первого ответа.
  Future<void> loadMore() async {
    final current = state;
    if (current is! ChoicePathData ||
        current.nextCursor == null ||
        current.progress is ChoicePathPageLoading) {
      return;
    }
    if (current.progress is ChoicePathPageFailure &&
        !(current.progress as ChoicePathPageFailure).canRetry) {
      return;
    }
    final generation = _generation;
    state = current.withProgress(const ChoicePathPageLoading());
    final result = await _read(
      ChoicePathContinuationQuery(
        draft: current.draft,
        cursor: current.nextCursor,
      ),
    );
    if (!_isCurrent(generation)) return;
    if (_precedesKnownRevision(current.revision)) {
      _conflict();
      return;
    }
    switch (result) {
      case GraphResultSuccess(:final value):
        if (!_sameDraft(value.draft, current.draft) ||
            value.revision.compareTo(current.revision) !=
                GraphRevisionOrder.same) {
          _conflict();
          return;
        }
        if (!_validPage(value)) {
          state = current.withProgress(
            const ChoicePathPageFailure(
              ChoicePathContinuationUnexpectedFailure(),
            ),
          );
          return;
        }
        final knownIds = {for (final item in current.items) item.relation.id};
        if (value.items.any((item) => !knownIds.add(item.relation.id)) ||
            (value.items.isEmpty && value.nextCursor != null)) {
          state = current.withProgress(
            const ChoicePathPageFailure(
              ChoicePathContinuationUnexpectedFailure(),
            ),
          );
          return;
        }
        state = ChoicePathData(
          draft: current.draft,
          visibleSteps: current.visibleSteps,
          current: value.current,
          revision: current.revision,
          items: [...current.items, ...value.items],
          nextCursor: value.nextCursor,
        );
      case GraphResultFailure(failure: ChoicePathContinuationSnapshotExpired()):
        _conflict();
      case GraphResultFailure(
        failure: ChoicePathContinuationIntentionNotFoundFailure(),
      ):
        state = ChoicePathNotFound(current.draft, current.visibleSteps);
      case GraphResultFailure(:final failure):
        state = current.withProgress(ChoicePathPageFailure(failure));
    }
  }

  void _restart(
    ChoicePathDraft draft,
    Iterable<LongTermRelationSummary> visibleSteps,
  ) {
    final generation = ++_generation;
    state = ChoicePathLoading(draft, visibleSteps);
    unawaited(_loadFirst(generation, draft, state.visibleSteps));
  }

  Future<void> _loadFirst(
    int generation,
    ChoicePathDraft draft,
    List<LongTermRelationSummary> visibleSteps,
  ) async {
    if (!_isCurrent(generation)) return;
    final result = await _read(ChoicePathContinuationQuery(draft: draft));
    if (!_isCurrent(generation)) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        if (_precedesKnownRevision(value.revision)) {
          _conflict();
          return;
        }
        if (!_sameDraft(value.draft, draft) || !_validPage(value)) {
          state = ChoicePathFailure(
            draft,
            visibleSteps,
            const ChoicePathContinuationUnexpectedFailure(),
          );
          return;
        }
        _knownRevision = value.revision;
        state = value.items.isEmpty
            ? ChoicePathEmpty(
                draft: draft,
                visibleSteps: visibleSteps,
                current: value.current,
                revision: value.revision,
              )
            : ChoicePathData(
                draft: draft,
                visibleSteps: visibleSteps,
                current: value.current,
                revision: value.revision,
                items: value.items,
                nextCursor: value.nextCursor,
              );
      case GraphResultFailure(failure: ChoicePathContinuationSnapshotExpired()):
        _conflict();
      case GraphResultFailure(
        failure: ChoicePathContinuationIntentionNotFoundFailure(),
      ):
        state = ChoicePathNotFound(draft, visibleSteps);
      case GraphResultFailure(:final failure):
        state = ChoicePathFailure(draft, visibleSteps, failure);
    }
  }

  Future<ChoicePathContinuationResult> _read(
    ChoicePathContinuationQuery query,
  ) async {
    try {
      return await _repository.getChoicePathContinuations(query);
    } on Object {
      return const ChoicePathContinuationError(
        ChoicePathContinuationUnexpectedFailure(),
      );
    }
  }

  void _subscribeToChanges(IntentionId sourceIntentionId, Object session) {
    try {
      _intentionSubscription = _repository
          .watchIntention(sourceIntentionId)
          .listen(
            (result) => scheduleMicrotask(() {
              if (identical(_session, session)) _handleIntention(result);
            }),
            onError: (Object _, StackTrace _) => scheduleMicrotask(() {
              if (identical(_session, session)) {
                _observationFailed(
                  const ChoicePathContinuationUnexpectedFailure(),
                );
              }
            }),
          );
    } on Object {
      scheduleMicrotask(() {
        if (identical(_session, session)) {
          _observationFailed(const ChoicePathContinuationUnexpectedFailure());
        }
      });
    }
    _completionSubscription = _coordinator.completions.listen((completion) {
      final revision = completion.revision;
      if (revision != null) {
        scheduleMicrotask(() {
          if (identical(_session, session)) _observeRevision(revision);
        });
      }
    });
  }

  void _handleIntention(
    intention_result.Result<GraphSnapshot<IntentionDetails?>> result,
  ) {
    if (!ref.mounted) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        if (_isOlderObservation(value.revision)) return;
        _observeRevision(value.revision);
        final details = value.value;
        if (details == null) {
          ++_generation;
          state = ChoicePathNotFound(state.draft, state.visibleSteps);
        } else if (details.intention.archiveState !=
                IntentionArchiveState.active ||
            (state.draft.direction == ChoicePathDraftDirection.bottomUp &&
                details.intention.readiness != IntentionReadiness.ready)) {
          _conflict();
        }
      case GraphResultFailure(:final failure):
        _observationFailed(switch (failure) {
          intention_result.IntentionUnavailableFailure() =>
            const ChoicePathContinuationUnavailableFailure(),
          intention_result.IntentionCorruptionFailure() =>
            const ChoicePathContinuationCorruptionFailure(),
          _ => const ChoicePathContinuationUnexpectedFailure(),
        });
    }
  }

  void _observationFailed(ChoicePathContinuationFailure failure) {
    if (!ref.mounted) return;
    ++_generation;
    state = ChoicePathFailure(state.draft, state.visibleSteps, failure);
  }

  void _observeRevision(GraphRevision revision) {
    if (!ref.mounted || _isOlderObservation(revision)) return;
    final known = _knownRevision;
    if (known != null && revision.compareTo(known) == GraphRevisionOrder.same) {
      return;
    }
    _knownRevision = revision;
    final current = state;
    if (current is ChoicePathConfirmedState &&
        revision.compareTo(current.revision) != GraphRevisionOrder.same) {
      _conflict();
    }
  }

  bool _isOlderObservation(GraphRevision revision) {
    final known = _knownRevision;
    return known != null &&
        revision.compareTo(known) == GraphRevisionOrder.older;
  }

  bool _precedesKnownRevision(GraphRevision revision) {
    final known = _knownRevision;
    if (known == null) return false;
    return switch (revision.compareTo(known)) {
      GraphRevisionOrder.older || GraphRevisionOrder.differentEpoch => true,
      GraphRevisionOrder.same || GraphRevisionOrder.newer => false,
    };
  }

  void _conflict() {
    ++_generation;
    state = ChoicePathConflict(state.draft, state.visibleSteps);
  }

  bool _isCurrent(int generation) => ref.mounted && _generation == generation;

  bool _sameDraft(ChoicePathDraft left, ChoicePathDraft right) {
    if (left.direction != right.direction ||
        left.startingIntentionId != right.startingIntentionId ||
        left.steps.length != right.steps.length) {
      return false;
    }
    for (var index = 0; index < left.steps.length; index++) {
      final a = left.steps[index];
      final b = right.steps[index];
      if (a.relationId != b.relationId ||
          a.sourceIntentionId != b.sourceIntentionId ||
          a.relatedIntentionId != b.relatedIntentionId ||
          a.type != b.type) {
        return false;
      }
    }
    return true;
  }

  bool _validPage(ChoicePathContinuationsPage page) {
    if (page.items.isEmpty && page.nextCursor != null) return false;
    final visited = {
      page.draft.startingIntentionId,
      for (final step in page.draft.steps)
        switch (page.draft.direction) {
          ChoicePathDraftDirection.topDown => step.relatedIntentionId,
          ChoicePathDraftDirection.bottomUp => step.sourceIntentionId,
        },
    };
    final ids = <LongTermRelationId>{};
    for (final item in page.items) {
      final relation = item.relation;
      final nextIntentionId = switch (page.draft.direction) {
        ChoicePathDraftDirection.topDown => relation.relatedIntentionId,
        ChoicePathDraftDirection.bottomUp => relation.sourceIntentionId,
      };
      final touchesCurrent = switch (page.draft.direction) {
        ChoicePathDraftDirection.topDown =>
          relation.sourceIntentionId == page.draft.currentIntentionId,
        ChoicePathDraftDirection.bottomUp =>
          relation.relatedIntentionId == page.draft.currentIntentionId,
      };
      if (!ids.add(relation.id) ||
          !touchesCurrent ||
          relation.scope != RelationScope.active ||
          item.source.archiveState != IntentionArchiveState.active ||
          item.related.archiveState != IntentionArchiveState.active ||
          visited.contains(nextIntentionId)) {
        return false;
      }
    }
    return true;
  }
}
