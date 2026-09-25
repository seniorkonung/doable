import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../application/tag_command.dart';
import '../../application/tag_read_result.dart';
import '../../application/tag_result.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';
import '../../domain/tag_name.dart';
import 'tag_editor_state.dart';

part 'tag_editor_view_model.g.dart';

@riverpod
final class TagEditorViewModel extends _$TagEditorViewModel {
  late PersonalGraphRepository _repository;
  late GraphCommandCoordinator _coordinator;
  TagOperationToken? _token;
  bool _closed = false;

  @override
  TagEditorState build(TagEditorContext context) {
    _repository = ref.watch(personalGraphRepositoryProvider);
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    ref.onDispose(closeSession);
    return TagEditorState.initial(context);
  }

  void changeName(String value) {
    if (_closed || state.input == value) return;
    state = state.withInput(value);
  }

  Future<void> submit() async {
    if (_closed || !state.canSubmit) return;

    final TagName name;
    try {
      name = TagName.fromInput(state.input);
    } on TagNameValidationException catch (error) {
      state = state.withStatus(
        TagEditorSubmissionFailed(TagNameInputFailure(error.reason)),
      );
      return;
    }

    final start = switch (state.context) {
      TagEditorCreating(:final formKey) => _coordinator.acceptTagCreation(
        formKey,
        CreateTag(name),
      ),
      TagEditorRenaming(:final tag) => _coordinator.acceptTagRename(
        RenameTag(tagId: tag.id, name: name),
      ),
    };
    switch (start) {
      case TagCommandAccepted(:final token, :final future):
        final previousToken = _token;
        if (previousToken != null) {
          _coordinator.releaseInitiatorPresentation(previousToken);
        }
        _token = token;
        state = state.withStatus(const TagEditorSubmitting());
        await _finish(future);
      case TagCommandAlreadyRunning():
        return;
      case GraphCommandCoordinatorDraining():
        state = state.withStatus(
          const TagEditorSubmissionFailed(TagUnexpectedFailure()),
        );
    }
  }

  Future<void> _finish(Future<TagCommandCompletion> future) async {
    try {
      final completion = await future;
      if (_closed || !ref.mounted || !identical(_token, completion.token)) {
        return;
      }
      switch (completion.result) {
        case GraphResultFailure(:final failure):
          state = state.withStatus(
            TagEditorSubmissionFailed(failure),
            failurePresentation: _coordinator.claimInitiatorFailure(
              completion.token,
            ),
          );
        case GraphResultSuccess(:final value):
          final TagId tagId = switch (value) {
            TagCreated(:final tag) => tag.id,
            TagRenamed(:final after) => after.id,
            TagUnchanged(:final tag) => tag.id,
            TagDeleted() => throw StateError('Unexpected tag command result'),
          };
          await _readCommitted(tagId, completion.confirmedChange?.revision);
      }
    } on Object {
      if (_closed || !ref.mounted) return;
      state = state.withStatus(
        const TagEditorSubmissionFailed(TagUnexpectedFailure()),
      );
    }
  }

  Future<void> useExisting() async {
    if (_closed || !ref.mounted) return;
    final current = state.status;
    final TagId id;
    switch (current) {
      case TagEditorSubmissionFailed(
        failure: TagNameOccupiedFailure(:final existingTagId),
      ):
        id = existingTagId;
      case TagEditorExistingReadFailed(:final tagId, canRetry: true):
        id = tagId;
      default:
        return;
    }
    final token = _token;
    if (token != null) _coordinator.releaseInitiatorPresentation(token);
    state = state.withStatus(TagEditorReadingExisting(id));
    final result = await _readTag(id);
    if (_closed || !ref.mounted) return;
    switch (result) {
      case TagReadSuccess(value: GraphSnapshot(value: final tag)):
        if (tag == null) {
          state = state.withStatus(TagEditorExistingMissing(id));
        } else {
          state = state.withStatus(
            TagEditorExistingResolved(tag),
            event: TagEditorExistingSelected(tag),
          );
        }
      case TagReadError(:final failure):
        state = state.withStatus(TagEditorExistingReadFailed(id, failure));
    }
  }

  Future<void> retryCommittedRead() async {
    if (_closed || !ref.mounted) return;
    final current = state.status;
    if (current is TagEditorCommittedReadFailed && current.canRetry) {
      await _readCommitted(current.tagId, current.requiredRevision);
    }
  }

  Future<void> _readCommitted(
    TagId id,
    GraphRevision? committedRevision,
  ) async {
    if (_closed || !ref.mounted) return;
    state = state.withStatus(TagEditorReadingCommitted(id));
    final result = await _readTag(id);
    if (_closed || !ref.mounted) return;
    switch (result) {
      case TagReadSuccess(:final value):
        final order = committedRevision == null
            ? GraphRevisionOrder.same
            : value.revision.compareTo(committedRevision);
        if (order == GraphRevisionOrder.older ||
            order == GraphRevisionOrder.differentEpoch) {
          state = state.withStatus(
            TagEditorCommittedReadFailed(
              id,
              const TagReadUnavailableFailure(),
              committedRevision,
            ),
          );
        } else if (value.value case final Tag tag) {
          state = state.withStatus(
            TagEditorCompleted(tag),
            event: TagEditorSaved(tag),
          );
        } else {
          state = state.withStatus(TagEditorCommittedMissing(id));
        }
      case TagReadError(:final failure):
        state = state.withStatus(
          TagEditorCommittedReadFailed(id, failure, committedRevision),
        );
    }
  }

  Future<TagReadResult> _readTag(TagId id) async {
    try {
      return await _repository.watchTag(id).first;
    } on Object {
      return const TagReadError(TagReadUnexpectedFailure());
    }
  }

  void consumeEvent() {
    if (!_closed && state.event != null) state = state.withoutEvent();
  }

  /// Явный уход заканчивает владение инлайн-ошибкой, но не отменяет команду.
  void closeSession() {
    if (_closed) return;
    _closed = true;
    final token = _token;
    if (token != null) _coordinator.releaseInitiatorPresentation(token);
  }
}
