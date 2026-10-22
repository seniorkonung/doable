import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../application/tag_read_result.dart';
import '../../application/tag_result.dart';
import '../../domain/tag.dart';
import '../../domain/tag_color.dart';
import '../../domain/tag_id.dart';
import '../../domain/tag_name.dart';

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

final class TagEditorAlreadyRunning extends TagEditorStatus {
  const TagEditorAlreadyRunning();
}

/// Название не прошло проверку до отправки; ошибку рисует поле.
final class TagEditorNameInvalid extends TagEditorStatus {
  const TagEditorNameInvalid(this.reason);

  final TagNameFailureReason reason;
}

/// Отказ принятой отправки. Его предъявляет общая поверхность, а форма
/// только сохраняет ввод для исправления или допустимого повтора.
final class TagEditorSubmissionFailed extends TagEditorStatus {
  const TagEditorSubmissionFailed(this.failure);

  final TagCommandFailure failure;
}

/// Отправка не дала результата операции: координатор её не принял или
/// исход не соответствует отправке. Сообщение рисует сама форма.
final class TagEditorSubmissionInterrupted extends TagEditorStatus {
  const TagEditorSubmissionInterrupted();
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
    required this.color,
    required this.status,
    this.event,
  });

  TagEditorState.initial(this.context)
    : input = switch (context) {
        TagEditorCreating() => '',
        TagEditorRenaming(:final tag) => tag.name.value,
      },
      color = switch (context) {
        TagEditorCreating() => null,
        TagEditorRenaming(:final tag) => tag.color,
      },
      status = const TagEditorIdle(),
      event = null;

  final TagEditorContext context;
  final String input;

  /// Цвет, который отправит форма вместе с названием; `null` — «Без цвета».
  final TagColor? color;
  final TagEditorStatus status;
  final TagEditorEvent? event;

  bool get canSubmit => switch (status) {
    TagEditorIdle() => true,
    TagEditorSubmissionFailed(failure: TagUnavailableFailure()) => true,
    _ => false,
  };

  TagEditorState withInput(String value) => TagEditorState(
    context: context,
    input: value,
    color: color,
    status: switch (status) {
      TagEditorNameInvalid() ||
      TagEditorSubmissionFailed(
        failure: TagNameInputFailure() || TagNameOccupiedFailure(),
      ) => const TagEditorIdle(),
      TagEditorExistingMissing() ||
      TagEditorExistingReadFailed() => const TagEditorIdle(),
      _ => status,
    },
  );

  TagEditorState withStatus(TagEditorStatus value, {TagEditorEvent? event}) =>
      TagEditorState(
        context: context,
        input: input,
        color: color,
        status: value,
        event: event,
      );

  TagEditorState withColor(TagColor? value) => TagEditorState(
    context: context,
    input: input,
    color: value,
    status: status,
    event: event,
  );

  TagEditorState withoutEvent() => TagEditorState(
    context: context,
    input: input,
    color: color,
    status: status,
  );
}
