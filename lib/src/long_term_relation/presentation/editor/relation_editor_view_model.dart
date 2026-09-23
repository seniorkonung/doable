import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';
import '../../application/long_term_relation_permissions.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_description.dart';
import 'relation_editor_state.dart';

part 'relation_editor_view_model.g.dart';

/// Черновик одной формы создания или изменения долговременной связи.
///
/// ViewModel не хранит связь: он собирает выбор пользователя, проверяет его до
/// отправки и передаёт готовую команду общему coordinator графа. Пока принятая
/// отправка выполняется, вторая команда той же формы не принимается, а уход с
/// экрана завершает только экранную сессию — выполнение продолжается до
/// различимого результата.
@riverpod
final class RelationEditorViewModel extends _$RelationEditorViewModel {
  late GraphCommandCoordinator _coordinator;
  late LongTermRelationCreationFormKey _formKey;
  late RelationEditorContext _context;
  LongTermRelationOperationToken? _activeToken;
  StreamSubscription<GraphCommandCompletion>? _completionSubscription;

  @override
  RelationEditorState build(
    LongTermRelationCreationFormKey formKey,
    RelationEditorContext context,
  ) {
    _formKey = formKey;
    _context = context;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    if (context case RelationEditingContext()) {
      _completionSubscription = _coordinator.completions.listen(
        _handleCompletion,
      );
    }
    ref.onDispose(() {
      unawaited(_completionSubscription?.cancel());
      final activeToken = _activeToken;
      if (activeToken != null) {
        _coordinator.releaseInitiatorPresentation(activeToken);
      }
    });
    return RelationEditorState.initial(context);
  }

  void _handleCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted || _context is! RelationEditingContext) return;
    final confirmed = completion.confirmedChange;
    if (confirmed == null) return;
    final relationId = (_context as RelationEditingContext).details.relation.id;
    LongTermRelationPermissions? confirmedPermissions;
    for (final change in confirmed.changes) {
      switch (change) {
        case DailyChoiceChange(:final relationPermissions):
          confirmedPermissions =
              relationPermissions[relationId] ?? confirmedPermissions;
        case LongTermRelationChange(
              :final id,
              permissions: final relationPermissions,
            )
            when id == relationId && relationPermissions?.isConfirmed == true:
          confirmedPermissions = relationPermissions;
        case GraphChange():
          break;
      }
    }
    if (confirmedPermissions != null) {
      state = state.withPermissions(confirmedPermissions, confirmed.revision);
    }
  }

  bool selectParticipant(
    RelationParticipantRole role,
    GraphSnapshot<RelationParticipantSummary> selected,
  ) {
    final needsNewBasis = state.needsNewBasis(
      role,
      selected.value.id,
      selected.revision,
    );
    final refreshed = state.withParticipant(role, selected);
    if (!identical(refreshed, state)) {
      state = refreshed;
    }
    return needsNewBasis;
  }

  void selectType(LongTermRelationType value) {
    if (state.type != value) {
      state = state.withType(value);
    }
  }

  void selectPriority(RelationPriority value) {
    if (state.priority != value) {
      state = state.withPriority(value);
    }
  }

  void changeDescription(String value) {
    if (state.description != value) {
      state = state.withDescription(value);
    }
  }

  /// Принимает более новый подтверждённый снимок без перезаписи черновика.
  Set<RelationParticipantRole> refreshConfirmedDetails(
    LongTermRelationDetails details,
    GraphRevision revision,
  ) {
    final needsNewBasis = <RelationParticipantRole>{
      if (state.needsNewBasis(
        RelationParticipantRole.source,
        details.source.id,
        revision,
      ))
        RelationParticipantRole.source,
      if (state.needsNewBasis(
        RelationParticipantRole.related,
        details.related.id,
        revision,
      ))
        RelationParticipantRole.related,
    };
    final refreshed = state.withConfirmedDetails(details, revision);
    if (!identical(refreshed, state)) {
      state = refreshed;
    }
    return needsNewBasis;
  }

  /// Обновляет только показ выбранного участника по его наблюдению.
  bool refreshConfirmedParticipant(
    RelationParticipantRole role,
    RelationParticipantSummary participant,
    GraphRevision revision,
  ) {
    final needsNewBasis = state.needsNewBasis(role, participant.id, revision);
    final refreshed = state.withConfirmedParticipant(
      role,
      participant,
      revision,
    );
    if (!identical(refreshed, state)) {
      state = refreshed;
    }
    return needsNewBasis;
  }

  void rebaseConfirmedParticipant(
    RelationParticipantRole role,
    GraphSnapshot<RelationParticipantSummary> snapshot,
    GraphRevision expectedRevision,
  ) {
    final refreshed = state.withNewBasis(role, snapshot, expectedRevision);
    if (!identical(refreshed, state)) {
      state = refreshed;
    }
  }

  void submit() {
    if (!state.canSubmit) {
      return;
    }
    final draft = state.completeness;
    if (draft is! RelationDraftComplete) {
      return;
    }

    final LongTermRelationDescription? description;
    try {
      description = LongTermRelationDescription.fromInput(state.description);
    } on LongTermRelationTextValidationException catch (exception) {
      state = state.withOperation(
        RelationEditorFailed(
          RelationEditorDescriptionInvalid(exception.failure),
        ),
      );
      return;
    }

    if (draft.sourceIntentionId == draft.relatedIntentionId) {
      state = state.withOperation(
        const RelationEditorFailed(RelationEditorSameParticipants()),
      );
      return;
    }

    final start = switch (_context) {
      RelationCreationContext() => _coordinator.acceptRelationCreation(
        _formKey,
        CreateLongTermRelation(
          sourceIntentionId: draft.sourceIntentionId,
          relatedIntentionId: draft.relatedIntentionId,
          type: draft.type,
          priority: draft.priority,
          description: description,
        ),
      ),
      final RelationEditingContext editing => _coordinator.acceptRelationUpdate(
        UpdateLongTermRelation(
          relationId: editing.details.relation.id,
          patch: editing.patchFor(draft, description),
        ),
      ),
    };

    switch (start) {
      case LongTermRelationCommandAccepted(:final token, :final future):
        _activeToken = token;
        state = state.withOperation(const RelationEditorSubmitting());
        unawaited(_finish(future));
      case LongTermRelationCommandAlreadyRunning():
        return;
      case GraphCommandCoordinatorDraining():
        state = state.withOperation(
          const RelationEditorFailed(RelationEditorUnexpected()),
        );
    }
  }

  void consumeEvent() {
    if (state.event != null) {
      state = state.withoutEvent();
    }
  }

  Future<void> _finish(Future<LongTermRelationCommandCompletion> future) async {
    try {
      final completion = await future;
      if (!ref.mounted || !identical(_activeToken, completion.token)) {
        return;
      }

      _activeToken = null;
      // Success предъявляет оболочка; форма получает его только для закрытия.
      state = switch (completion.result) {
        GraphResultSuccess(value: LongTermRelationCreated(:final relation))
            when _context is RelationCreationContext =>
          state.withOperation(
            RelationEditorSucceeded(relation),
            event: RelationEditorCreated(relation.id),
          ),
        GraphResultSuccess(value: LongTermRelationUpdated(:final relation))
            when _context is RelationEditingContext =>
          state.withOperation(
            RelationEditorSucceeded(relation),
            event: RelationEditorUpdated(relation.id),
          ),
        GraphResultSuccess() => state.withOperation(
          const RelationEditorFailed(RelationEditorUnexpected()),
        ),
        GraphResultFailure(:final failure) => state.withOperation(
          RelationEditorFailed(_editorFailure(failure)),
          failurePresentation: _coordinator.claimInitiatorFailure(
            completion.token,
          ),
        ),
      };
    } on Object {
      if (!ref.mounted) {
        return;
      }
      final token = _activeToken;
      _activeToken = null;
      if (token != null) {
        _coordinator.releaseInitiatorPresentation(token);
      }
      state = state.withOperation(
        const RelationEditorFailed(RelationEditorUnexpected()),
      );
    }
  }

  static RelationEditorFailure _editorFailure(
    LongTermRelationCommandFailure failure,
  ) => switch (failure) {
    LongTermRelationCommandValidationFailure(
      reason: CreateLongTermRelationValidationFailure.sameIntention,
    ) =>
      const RelationEditorSameParticipants(),
    LongTermRelationPairOccupiedFailure(:final existingRelationId) =>
      RelationEditorPairOccupied(existingRelationId),
    LongTermRelationNotFoundFailure() => const RelationEditorRelationNotFound(),
    LongTermRelationReferencedByDailyPathFailure() =>
      const RelationEditorReferencedByDailyPath(),
    LongTermRelationParticipantNotFoundFailure(
      :final role,
      :final intentionId,
    ) =>
      RelationEditorParticipantRejected(
        role: role,
        intentionId: intentionId,
        rejection: RelationParticipantRejection.missing,
      ),
    LongTermRelationParticipantArchivedFailure(
      :final role,
      :final intentionId,
    ) =>
      RelationEditorParticipantRejected(
        role: role,
        intentionId: intentionId,
        rejection: RelationParticipantRejection.archived,
      ),
    LongTermRelationUnavailableFailure() => const RelationEditorUnavailable(),
    LongTermRelationCorruptionFailure() => const RelationEditorCorruption(),
    LongTermRelationUnexpectedFailure() => const RelationEditorUnexpected(),
  };
}
