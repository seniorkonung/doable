import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_description.dart';
import '../../domain/long_term_relation_id.dart';
import 'relation_editor_state.dart';

part 'relation_editor_view_model.g.dart';

/// Черновик одной формы создания долговременной связи.
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
  LongTermRelationOperationToken? _activeToken;

  @override
  RelationEditorState build(
    LongTermRelationCreationFormKey formKey,
    RelationEditorContext context,
  ) {
    _formKey = formKey;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    ref.onDispose(() {
      final activeToken = _activeToken;
      if (activeToken != null) {
        _coordinator.releaseInitiatorPresentation(activeToken);
      }
    });
    return RelationEditorState.initial(context);
  }

  bool selectParticipant(
    RelationParticipantRole role,
    GraphSnapshot<RelationParticipantSummary> selected,
  ) {
    if (!ref.mounted || state.sessionState == RelationEditorSessionState.left) {
      return false;
    }
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
    if (!ref.mounted || state.sessionState == RelationEditorSessionState.left) {
      return;
    }
    if (state.type != value) {
      state = state.withType(value);
    }
  }

  void selectPriority(RelationPriority value) {
    if (!ref.mounted || state.sessionState == RelationEditorSessionState.left) {
      return;
    }
    if (state.priority != value) {
      state = state.withPriority(value);
    }
  }

  void changeDescription(String value) {
    if (!ref.mounted || state.sessionState == RelationEditorSessionState.left) {
      return;
    }
    if (state.description != value) {
      state = state.withDescription(value);
    }
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

  /// Прекращает создание до удаления маршрута, сохраняя принятую команду.
  void leaveCreation() {
    if (!ref.mounted || state.sessionState == RelationEditorSessionState.left) {
      return;
    }
    final failure = state.failurePresentation;
    final token = _activeToken;
    state = state.withOperation(
      state.operation,
      sessionState: RelationEditorSessionState.left,
    );
    if (failure != null) _coordinator.releaseInitiatorClaim(failure);
    if (token != null) _coordinator.releaseInitiatorPresentation(token);
  }

  void submit() {
    if (!ref.mounted || !state.canSubmit) {
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

    final start = _coordinator.acceptRelationCreation(
      _formKey,
      CreateLongTermRelation(
        sourceIntentionId: draft.sourceIntentionId,
        relatedIntentionId: draft.relatedIntentionId,
        type: draft.type,
        priority: draft.priority,
        description: description,
      ),
    );

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

  /// Восстанавливает занимающую пару архивную связь как отправку формы
  /// создания.
  ///
  /// Полнота черновика не требуется: участник, вид или приоритет могут быть
  /// ещё не выбраны. Успех завершает поток событием [RelationEditorCreated] с
  /// восстановленной связью. Отказ предъявляет оболочка, потому что у поиска
  /// нет собственного renderer, поэтому форма возвращается к тому же
  /// черновику и не показывает его второй раз.
  void restoreRelation(LongTermRelationId relationId) {
    if (!ref.mounted || !state.canEdit) {
      return;
    }

    final start = _coordinator.acceptRelationRestoreFromCreation(
      _formKey,
      RestoreLongTermRelation(relationId),
    );
    switch (start) {
      case LongTermRelationCommandAccepted(:final token, :final future):
        _activeToken = token;
        state = state.withOperation(const RelationEditorSubmitting());
        unawaited(_finishRestore(future));
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

  Future<void> _finishRestore(
    Future<LongTermRelationCommandCompletion> future,
  ) async {
    final completion = await future;
    if (!ref.mounted || !identical(_activeToken, completion.token)) {
      return;
    }

    _activeToken = null;
    // Успех принадлежит оболочке, как у создания, а отказ отдан ей сразу:
    // форма использует только успех, чтобы закрыть поток.
    state = switch (completion.result) {
      GraphResultSuccess(value: LongTermRelationUpdated(:final relation)) =>
        state.withOperation(
          RelationEditorSucceeded(relation),
          event: RelationEditorCreated(relation.id),
        ),
      GraphResultSuccess() ||
      GraphResultFailure() => state.withOperation(const RelationEditorIdle()),
    };
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
        GraphResultSuccess(value: LongTermRelationCreated(:final relation)) =>
          state.withOperation(
            RelationEditorSucceeded(relation),
            event: RelationEditorCreated(relation.id),
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
    LongTermRelationPairOccupiedFailure(:final existingRelationId) =>
      RelationEditorPairOccupied(existingRelationId),
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
    // Создание не изменяет существующую связь и не проверяет шаги пути: эти
    // отказы ему чужды.
    LongTermRelationNotFoundFailure() ||
    LongTermRelationArchivedTypeChangeFailure() ||
    LongTermRelationReferencedByDailyPathFailure() ||
    LongTermRelationUnexpectedFailure() => const RelationEditorUnexpected(),
  };
}
