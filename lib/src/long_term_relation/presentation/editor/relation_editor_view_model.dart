import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';
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

  @override
  RelationEditorState build(
    LongTermRelationCreationFormKey formKey,
    RelationEditorContext context,
  ) {
    _formKey = formKey;
    _context = context;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    ref.onDispose(() {
      final activeToken = _activeToken;
      if (activeToken != null) {
        _coordinator.releaseInitiatorPresentation(activeToken);
      }
    });
    return RelationEditorState.initial(context);
  }

  void selectParticipant(
    RelationParticipantRole role,
    RelationParticipantSummary participant,
  ) {
    final current = switch (role) {
      RelationParticipantRole.source => state.sourceIntentionId,
      RelationParticipantRole.related => state.relatedIntentionId,
    };
    if (current != participant.id ||
        !_sameParticipantSnapshot(role, participant)) {
      state = state.withParticipant(role, participant);
    }
  }

  bool _sameParticipantSnapshot(
    RelationParticipantRole role,
    RelationParticipantSummary participant,
  ) {
    final current = switch (role) {
      RelationParticipantRole.source => state.sourceParticipant,
      RelationParticipantRole.related => state.relatedParticipant,
    };
    return current?.title == participant.title &&
        current?.archiveState == participant.archiveState &&
        current?.activeRelationCount == participant.activeRelationCount;
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
  void refreshConfirmedDetails(LongTermRelationDetails details) {
    final refreshed = state.withConfirmedDetails(details);
    if (!identical(refreshed, state)) {
      state = refreshed;
    }
  }

  /// Обновляет только показ выбранного участника по его наблюдению.
  void refreshConfirmedParticipant(
    RelationParticipantRole role,
    RelationParticipantSummary participant,
  ) {
    final refreshed = state.withConfirmedParticipant(role, participant);
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
