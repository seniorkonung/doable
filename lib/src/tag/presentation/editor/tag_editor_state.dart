import '../../../graph/application/graph_command_coordinator.dart';
import '../../application/tag_command.dart';
import '../../application/tag_result.dart';
import '../../domain/tag.dart';
import '../../domain/tag_color.dart';
import '../../domain/tag_name.dart';

sealed class TagEditorContext {
  const TagEditorContext();
}

/// Ключ создаётся владельцем маршрута и может пережить повторное открытие формы.
final class TagEditorCreating extends TagEditorContext {
  const TagEditorCreating(
    this.formKey, {
    this.initialName = '',
    this.initialColor,
    this.placement = TagPlacement.first,
    this.existingNames = const [],
    this.onCreationAccepted,
  });

  final TagCreationFormKey formKey;
  final String initialName;

  /// Начальный выбор цвета; до создания его можно изменить.
  final TagColor? initialColor;

  /// Место нового тега в ручном порядке; формой не меняется.
  final TagPlacement placement;

  /// Названия снимка вызывающего; совпадение с ними занимает название ещё
  /// при вводе. Без снимка занятость определяет запись.
  final List<TagName> existingNames;

  /// Получает принятую команду до её завершения: продолжение после успеха
  /// принадлежит вызывающему, а не экранной сессии формы.
  final void Function(TagCommandAccepted creation)? onCreationAccepted;
}

final class TagEditorRenaming extends TagEditorContext {
  const TagEditorRenaming(this.tag, {this.existingNames = const []});

  final Tag tag;

  /// Названия снимка вызывающего, включая собственное: совпадение с другим
  /// тегом занимает название ещё при вводе, а с собственным — нет. Без
  /// снимка занятость определяет запись.
  final List<TagName> existingNames;
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

final class TagEditorCompleted extends TagEditorStatus {
  const TagEditorCompleted(this.tag);

  final Tag tag;
}

sealed class TagEditorEvent {
  const TagEditorEvent();
}

/// Подтверждённый тег из результата команды.
final class TagEditorSaved extends TagEditorEvent {
  const TagEditorSaved(this.tag);

  final Tag tag;
}

/// Проверка введённого названия; повторяется при каждом вводе.
sealed class TagEditorNameCheck {
  const TagEditorNameCheck();
}

final class TagEditorNameAccepted extends TagEditorNameCheck {
  const TagEditorNameAccepted(this.name);

  final TagName name;
}

/// Пустое после удаления пробелов название; причину поле не показывает.
final class TagEditorNameEmpty extends TagEditorNameCheck {
  const TagEditorNameEmpty();
}

final class TagEditorNameInvalid extends TagEditorNameCheck {
  const TagEditorNameInvalid(this.reason);

  final TagNameFailureReason reason;
}

final class TagEditorNameOccupied extends TagEditorNameCheck {
  const TagEditorNameOccupied();
}

final class TagEditorState {
  const TagEditorState({
    required this.context,
    required this.input,
    required this.nameCheck,
    required this.color,
    required this.status,
    this.event,
  });

  TagEditorState.initial(this.context, this.nameCheck)
    : input = initialInput(context),
      color = switch (context) {
        TagEditorCreating(:final initialColor) => initialColor,
        TagEditorRenaming(:final tag) => tag.color,
      },
      status = const TagEditorIdle(),
      event = null;

  static String initialInput(TagEditorContext context) => switch (context) {
    TagEditorCreating(:final initialName) => initialName,
    TagEditorRenaming(:final tag) => tag.name.value,
  };

  final TagEditorContext context;
  final String input;
  final TagEditorNameCheck nameCheck;

  /// Цвет, который отправит форма вместе с названием; `null` — «Без цвета».
  final TagColor? color;
  final TagEditorStatus status;
  final TagEditorEvent? event;

  bool get canSubmit =>
      switch (nameCheck) {
        TagEditorNameAccepted(:final name) => _isNewValue(name),
        _ => false,
      } &&
      switch (status) {
        TagEditorIdle() => true,
        TagEditorSubmissionFailed(failure: TagUnavailableFailure()) => true,
        _ => false,
      };

  /// Изменению без нового названия или цвета нечего сохранять.
  bool _isNewValue(TagName name) => switch (context) {
    TagEditorCreating() => true,
    TagEditorRenaming(:final tag) => name != tag.name || color != tag.color,
  };

  TagEditorState withInput(String value, TagEditorNameCheck check) =>
      TagEditorState(
        context: context,
        input: value,
        nameCheck: check,
        color: color,
        status: switch (status) {
          TagEditorSubmissionFailed(
            failure: TagNameInputFailure() || TagNameOccupiedFailure(),
          ) =>
            const TagEditorIdle(),
          _ => status,
        },
      );

  TagEditorState withStatus(TagEditorStatus value, {TagEditorEvent? event}) =>
      TagEditorState(
        context: context,
        input: input,
        nameCheck: nameCheck,
        color: color,
        status: value,
        event: event,
      );

  TagEditorState withColor(TagColor? value) => TagEditorState(
    context: context,
    input: input,
    nameCheck: nameCheck,
    color: value,
    status: status,
    event: event,
  );

  TagEditorState withoutEvent() => TagEditorState(
    context: context,
    input: input,
    nameCheck: nameCheck,
    color: color,
    status: status,
  );
}
