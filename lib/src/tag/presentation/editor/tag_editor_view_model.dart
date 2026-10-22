import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../application/tag_command.dart';
import '../../application/tag_result.dart';
import '../../domain/tag.dart';
import '../../domain/tag_color.dart';
import '../../domain/tag_name.dart';
import 'tag_editor_state.dart';

part 'tag_editor_view_model.g.dart';

@riverpod
final class TagEditorViewModel extends _$TagEditorViewModel {
  late GraphCommandCoordinator _coordinator;
  late Set<String> _occupiedNameKeys;
  TagOperationToken? _token;
  StreamSubscription<GraphCommandCompletion>? _busySubscription;
  bool _closed = false;

  @override
  TagEditorState build(TagEditorContext context) {
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _occupiedNameKeys = switch (context) {
      TagEditorCreating(:final existingNames) => {
        for (final name in existingNames) name.matchingKey,
      },
      TagEditorRenaming(:final tag, :final existingNames) => {
        for (final name in existingNames)
          if (name.matchingKey != tag.name.matchingKey) name.matchingKey,
      },
    };
    ref.onDispose(closeSession);
    final input = TagEditorState.initialInput(context);
    return TagEditorState.initial(context, _checkName(input));
  }

  void changeName(String value) {
    if (_closed || state.input == value) return;
    state = state.withInput(value, _checkName(value));
  }

  TagEditorNameCheck _checkName(String input) {
    final TagName name;
    try {
      name = TagName.fromInput(input);
    } on TagNameValidationException catch (error) {
      return switch (error.reason) {
        TagNameFailureReason.empty => const TagEditorNameEmpty(),
        final reason => TagEditorNameInvalid(reason),
      };
    }
    return _occupiedNameKeys.contains(name.matchingKey)
        ? const TagEditorNameOccupied()
        : TagEditorNameAccepted(name);
  }

  void changeColor(TagColor? value) {
    if (_closed || state.color == value) return;
    state = state.withColor(value);
  }

  Future<void> submit() async {
    final name = switch (state.nameCheck) {
      TagEditorNameAccepted(:final name) => name,
      _ => null,
    };
    if (_closed || !state.canSubmit || name == null) return;

    final start = switch (state.context) {
      TagEditorCreating(:final formKey) => _coordinator.acceptTagCreation(
        formKey,
        CreateTag(
          name: name,
          color: state.color,
          placement: TagPlacement.first,
        ),
      ),
      TagEditorRenaming(:final tag) => _coordinator.acceptTagUpdate(
        UpdateTag(tagId: tag.id, name: name, color: state.color),
      ),
    };
    switch (start) {
      case TagCommandAccepted(:final token, :final future):
        _token = token;
        state = state.withStatus(const TagEditorSubmitting());
        if (state.context case TagEditorCreating(:final onCreationAccepted?)) {
          onCreationAccepted(start);
        }
        await _finish(future);
      case TagCommandAlreadyRunning():
        final key = switch (state.context) {
          TagEditorCreating(:final formKey) => formKey,
          TagEditorRenaming(:final tag) => ExistingTagKey(tag.id),
        };
        state = state.withStatus(const TagEditorAlreadyRunning());
        _busySubscription = _coordinator.completions.listen((_) {
          if (_coordinator.isKeyRunning(key)) return;
          unawaited(_busySubscription?.cancel());
          _busySubscription = null;
          if (!_closed &&
              ref.mounted &&
              state.status is TagEditorAlreadyRunning) {
            state = state.withStatus(const TagEditorIdle());
          }
        });
      case GraphCommandCoordinatorDraining():
        state = state.withStatus(const TagEditorSubmissionInterrupted());
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
          state = state.withStatus(TagEditorSubmissionFailed(failure));
        case GraphResultSuccess(:final value):
          final Tag tag = switch (value) {
            TagCreated(:final tag) => tag,
            TagUpdated(:final after) => after,
            TagUnchanged(:final tag) => tag,
            TagDeleted() => throw StateError('Unexpected tag command result'),
            TagAssignmentChanged() || TagAssignmentUnchanged() =>
              throw StateError('Unexpected tag command result'),
          };
          state = state.withStatus(
            TagEditorCompleted(tag),
            event: TagEditorSaved(tag),
          );
      }
    } on Object {
      if (_closed || !ref.mounted) return;
      state = state.withStatus(const TagEditorSubmissionInterrupted());
    }
  }

  void consumeEvent() {
    if (!_closed && state.event != null) state = state.withoutEvent();
  }

  /// Явный уход заканчивает экранную сессию, но не отменяет команду.
  void closeSession() {
    if (_closed) return;
    _closed = true;
    unawaited(_busySubscription?.cancel());
    _busySubscription = null;
  }
}
