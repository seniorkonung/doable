import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../application/tag_read_result.dart';
import '../../application/tag_result.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';

sealed class TagEditorContext {
  const TagEditorContext();
}

/// Ключ создаётся владельцем маршрута и может пережить повторное открытие формы.
final class TagEditorCreating extends TagEditorContext {
  const TagEditorCreating(this.formKey);

  final TagCreationFormKey formKey;
}

final class TagEditorRenaming extends TagEditorContext {
  const TagEditorRenaming(this.tag);

  final Tag tag;
}

sealed class TagEditorStatus {
  const TagEditorStatus();
}

final class TagEditorIdle extends TagEditorStatus {
  const TagEditorIdle();
}

final class TagEditorSubmitting extends TagEditorStatus {
  const TagEditorSubmitting();
}

final class TagEditorSubmissionFailed extends TagEditorStatus {
  const TagEditorSubmissionFailed(this.failure);

  final TagCommandFailure failure;
}

final class TagEditorReadingCommitted extends TagEditorStatus {
  const TagEditorReadingCommitted(this.tagId);

  final TagId tagId;
}

final class TagEditorCommittedReadFailed extends TagEditorStatus {
  const TagEditorCommittedReadFailed(
    this.tagId,
    this.failure,
    this.requiredRevision,
  );

  final TagId tagId;
  final TagReadFailure failure;
  final GraphRevision? requiredRevision;
  bool get canRetry => failure is TagReadUnavailableFailure;
}

final class TagEditorCommittedMissing extends TagEditorStatus {
  const TagEditorCommittedMissing(this.tagId);

  final TagId tagId;
}

final class TagEditorReadingExisting extends TagEditorStatus {
  const TagEditorReadingExisting(this.tagId);

  final TagId tagId;
}

final class TagEditorExistingReadFailed extends TagEditorStatus {
  const TagEditorExistingReadFailed(this.tagId, this.failure);

  final TagId tagId;
  final TagReadFailure failure;
  bool get canRetry => failure is TagReadUnavailableFailure;
}

final class TagEditorExistingMissing extends TagEditorStatus {
  const TagEditorExistingMissing(this.tagId);

  final TagId tagId;
}

final class TagEditorCompleted extends TagEditorStatus {
  const TagEditorCompleted(this.tag);

  final Tag tag;
}

final class TagEditorExistingResolved extends TagEditorStatus {
  const TagEditorExistingResolved(this.tag);

  final Tag tag;
}

sealed class TagEditorEvent {
  const TagEditorEvent();
}

/// Подтверждённый тег; вызывающий каталог показывает его актуальные операции.
final class TagEditorSaved extends TagEditorEvent {
  const TagEditorSaved(this.tag);

  final Tag tag;
}

/// Выбор по id не является созданием, переименованием или назначением.
final class TagEditorExistingSelected extends TagEditorEvent {
  const TagEditorExistingSelected(this.tag);

  final Tag tag;
}

final class TagEditorState {
  const TagEditorState({
    required this.context,
    required this.input,
    required this.status,
    this.event,
    this.failurePresentation,
  });

  TagEditorState.initial(this.context)
    : input = switch (context) {
        TagEditorCreating() => '',
        TagEditorRenaming(:final tag) => tag.name.value,
      },
      status = const TagEditorIdle(),
      event = null,
      failurePresentation = null;

  final TagEditorContext context;
  final String input;
  final TagEditorStatus status;
  final TagEditorEvent? event;

  /// Инлайн-предъявление принадлежит существующему модулю представления.
  final GraphInitiatorPresentationClaim? failurePresentation;

  bool get canSubmit => switch (status) {
    TagEditorIdle() => true,
    TagEditorSubmissionFailed(failure: TagUnavailableFailure()) => true,
    _ => false,
  };

  TagEditorState withInput(String value) => TagEditorState(
    context: context,
    input: value,
    status: switch (status) {
      TagEditorSubmissionFailed(
        failure: TagNameInputFailure() || TagNameOccupiedFailure(),
      ) =>
        const TagEditorIdle(),
      TagEditorExistingMissing() ||
      TagEditorExistingReadFailed() => const TagEditorIdle(),
      _ => status,
    },
  );

  TagEditorState withStatus(
    TagEditorStatus value, {
    TagEditorEvent? event,
    GraphInitiatorPresentationClaim? failurePresentation,
  }) => TagEditorState(
    context: context,
    input: input,
    status: value,
    event: event,
    failurePresentation: failurePresentation,
  );

  TagEditorState withoutEvent() => TagEditorState(
    context: context,
    input: input,
    status: status,
    failurePresentation: failurePresentation,
  );
}
