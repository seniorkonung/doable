import '../../../graph/application/graph_command_coordinator.dart';
import '../../../tag/application/tag_read_result.dart';
import '../../../tag/domain/tag.dart';
import '../../../tag/domain/tag_color.dart';
import '../../../tag/domain/tag_id.dart';
import '../../../tag/domain/tag_name.dart';
import '../../../tag/domain/tag_position.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
import '../../domain/intention_text.dart';
import '../operation/operation_state.dart';
import 'intention_creation_close.dart';

export 'intention_creation_close.dart';
export 'intention_draft_tag_set.dart';

/// Принимает ли сессия создания изменения своего черновика.
enum IntentionDraftAvailability {
  editable,

  /// Принятая отправка выполняется: черновик зафиксирован до её результата.
  submitting,

  /// Сессия завершена успешным созданием, закрытием по запросу или
  /// освобождена.
  closed,
}

sealed class IntentionEditorEvent {
  const IntentionEditorEvent();
}

final class IntentionEditorCreated extends IntentionEditorEvent {
  const IntentionEditorCreated(this.intentionId);

  final IntentionId intentionId;
}

/// Черновик создания намерения: данные будущего намерения, которое ещё не
/// создано и поэтому не имеет идентификатора.
///
/// Строки хранятся сырыми, без нормализации: их проверяет только команда
/// создания. Набор тегов неизменяем и определяет теги идентификаторами в
/// порядке добавления. Поиск, кандидат выбора, фокус и размер панели не
/// входят в черновик.
final class IntentionCreationDraft {
  const IntentionCreationDraft.initial()
    : title = '',
      description = '',
      tagIds = const {},
      readiness = IntentionReadiness.notReady;

  /// [tagIds] должен быть неизменяемым; копию создают только методы правки
  /// набора, чтобы неизменённый набор сохранял свою идентичность.
  const IntentionCreationDraft._({
    required this.title,
    required this.description,
    required this.tagIds,
    required this.readiness,
  });

  final String title;
  final String description;
  final Set<TagId> tagIds;

  /// Начальная готовность к действию; включается только явным решением.
  final IntentionReadiness readiness;

  /// Отличается ли хотя бы одно из четырёх полей от начального значения.
  /// Полностью пробельный текст тоже считается изменением.
  bool get isChanged =>
      title.isNotEmpty ||
      description.isNotEmpty ||
      tagIds.isNotEmpty ||
      readiness != IntentionReadiness.notReady;

  IntentionCreationDraft withTitle(String value) => _copy(title: value);

  IntentionCreationDraft withDescription(String value) =>
      _copy(description: value);

  IntentionCreationDraft withTag(TagId id) => tagIds.contains(id)
      ? this
      : _copy(tagIds: Set.unmodifiable({...tagIds, id}));

  IntentionCreationDraft withoutTags(Set<TagId> ids) => tagIds.any(ids.contains)
      ? _copy(tagIds: Set.unmodifiable(tagIds.where((id) => !ids.contains(id))))
      : this;

  IntentionCreationDraft withReadiness(IntentionReadiness value) =>
      _copy(readiness: value);

  IntentionCreationDraft _copy({
    String? title,
    String? description,
    Set<TagId>? tagIds,
    IntentionReadiness? readiness,
  }) => IntentionCreationDraft._(
    title: title ?? this.title,
    description: description ?? this.description,
    tagIds: tagIds ?? this.tagIds,
    readiness: readiness ?? this.readiness,
  );
}

/// Выбранный тег черновика для показа: последние известные название, цвет
/// и место в ручном порядке и состояние его наблюдения.
///
/// Проекция отделена от набора идентичностей черновика: её изменения не
/// меняют состав набора, изменённость черновика и данные отправки и не
/// заменяют проверку существования тегов при сохранении.
final class IntentionDraftTag {
  const IntentionDraftTag({
    required this.name,
    required this.color,
    required this.position,
    required this.status,
  });

  /// Последнее подтверждённое название: сначала из выбора, затем из
  /// наблюдения. Сохраняется при отказе чтения.
  final TagName name;

  /// Последний подтверждённый цвет; `null` — «Без цвета». Источник и
  /// сохранение те же, что у [name].
  final TagColor? color;

  /// Последнее подтверждённое место; источник и сохранение те же, что у
  /// [name].
  final TagPosition position;
  final IntentionDraftTagStatus status;

  IntentionDraftTag withStatus(IntentionDraftTagStatus value) =>
      IntentionDraftTag(
        name: name,
        color: color,
        position: position,
        status: value,
      );
}

sealed class IntentionDraftTagStatus {
  const IntentionDraftTagStatus();
}

/// Наблюдение ещё не подтвердило тег; показываются название и цвет из
/// выбора.
final class IntentionDraftTagLoading extends IntentionDraftTagStatus {
  const IntentionDraftTagLoading();
}

/// Наблюдение подтвердило тег и его актуальные название и цвет.
final class IntentionDraftTagAvailable extends IntentionDraftTagStatus {
  const IntentionDraftTagAvailable();
}

/// Наблюдение завершилось отказом чтения; это не отсутствие тега.
final class IntentionDraftTagReadFailed extends IntentionDraftTagStatus {
  const IntentionDraftTagReadFailed(this.failure);

  final TagReadFailure failure;

  /// Повтор наблюдения предлагается только при устранимой недоступности.
  bool get canRetry => switch (failure) {
    TagReadUnavailableFailure() => true,
    TagReadCorruptionFailure() || TagReadUnexpectedFailure() => false,
  };
}

final class IntentionEditorState {
  const IntentionEditorState._({
    required this.draft,
    required this.selectedTags,
    required this.operation,
    required this.event,
    required this.failurePresentation,
    required this.closing,
  });

  const IntentionEditorState.initial()
    : draft = const IntentionCreationDraft.initial(),
      selectedTags = const {},
      operation = const OperationIdle<Intention>(),
      event = null,
      failurePresentation = null,
      closing = const IntentionCreationCloseNotRequested();

  final IntentionCreationDraft draft;

  /// Выбранные теги для показа — неизменяемая проекция с теми же ключами,
  /// что и набор черновика, в ручном порядке по месту тега. Она не входит в
  /// черновик и не влияет на его изменённость.
  final Map<TagId, IntentionDraftTag> selectedTags;
  final OperationState<Intention> operation;
  final IntentionEditorEvent? event;

  /// Право сессии предъявить текущую ошибку в своей форме.
  ///
  /// Публикуется, пока отказ действует и сессия не закрыта по запросу.
  /// Renderer формы подтверждает его только по кадру с видимым сообщением.
  /// Право, которое состояние перестало публиковать неподтверждённым, сессия
  /// передаёт общей поверхности.
  final GraphInitiatorPresentationClaim? failurePresentation;

  /// Ход закрытия сессии. Ожидающее подтверждение связано с текущим
  /// состоянием отправки: его смена делает подтверждение недействительным.
  final IntentionCreationClosing closing;

  IntentionDraftAvailability get draftAvailability => switch (closing) {
    IntentionCreationClosedOnRequest() => IntentionDraftAvailability.closed,
    IntentionCreationCloseNotRequested() ||
    IntentionCreationCloseConfirming() => switch (operation) {
      OperationSucceeded<Intention>() => IntentionDraftAvailability.closed,
      OperationRunning<Intention>() => IntentionDraftAvailability.submitting,
      OperationIdle<Intention>() ||
      OperationFailed<Intention>() => IntentionDraftAvailability.editable,
    },
  };

  bool get canRetry => switch (operation) {
    OperationFailed<Intention>(failure: IntentionUnavailableFailure()) => true,
    OperationIdle<Intention>() ||
    OperationRunning<Intention>() ||
    OperationSucceeded<Intention>() ||
    OperationFailed<Intention>() => false,
  };

  /// Отправка недоступна, пока ожидается ответ на подтверждение закрытия
  /// или после завершения сессии. После отказа из-за отсутствующих тегов
  /// черновик уже без них, поэтому новая отправка доступна сразу.
  bool get canSubmit => switch (closing) {
    IntentionCreationCloseNotRequested() => switch (operation) {
      OperationIdle<Intention>() ||
      OperationFailed<Intention>(
        failure: IntentionCreationTagsMissingFailure(),
      ) => true,
      OperationRunning<Intention>() ||
      OperationSucceeded<Intention>() ||
      OperationFailed<Intention>() => canRetry,
    },
    IntentionCreationCloseConfirming() ||
    IntentionCreationClosedOnRequest() => false,
  };

  IntentionEditorState withTitle(String value) => _withEditedText(
    draft: draft.withTitle(value),
    field: IntentionTextField.title,
  );

  IntentionEditorState withDescription(String value) => _withEditedText(
    draft: draft.withDescription(value),
    field: IntentionTextField.description,
  );

  IntentionEditorState withTag(Tag tag) => draft.tagIds.contains(tag.id)
      ? this
      : _withEditedTags(
          draft.withTag(tag.id),
          selectedTags: _inManualOrder({
            ...selectedTags,
            tag.id: IntentionDraftTag(
              name: tag.name,
              color: tag.color,
              position: tag.position,
              status: const IntentionDraftTagLoading(),
            ),
          }),
        );

  IntentionEditorState withoutTag(TagId id) => draft.tagIds.contains(id)
      ? _withEditedTags(
          draft.withoutTags({id}),
          selectedTags: _selectedTagsWithout({id}),
        )
      : this;

  /// Убирает из набора теги [ids], удаление которых подтверждено.
  ///
  /// Удаление — не правка пользователя: отправка и право предъявления
  /// ошибки не меняются.
  IntentionEditorState withoutDeletedTags(Set<TagId> ids) =>
      draft.tagIds.any(ids.contains)
      ? IntentionEditorState._(
          draft: draft.withoutTags(ids),
          selectedTags: _selectedTagsWithout(ids),
          operation: operation,
          event: event,
          failurePresentation: failurePresentation,
          closing: closing,
        )
      : this;

  /// Заменяет проекцию тега [id], только пока он входит в набор черновика:
  /// проекция не возвращает снятый тег. Черновик, отправка и право
  /// предъявления ошибки не меняются.
  IntentionEditorState withSelectedTag(TagId id, IntentionDraftTag tag) =>
      draft.tagIds.contains(id)
      ? IntentionEditorState._(
          draft: draft,
          selectedTags: _inManualOrder({...selectedTags, id: tag}),
          operation: operation,
          event: event,
          failurePresentation: failurePresentation,
          closing: closing,
        )
      : this;

  IntentionEditorState withReadiness(IntentionReadiness value) =>
      draft.readiness == value ? this : _withDraft(draft.withReadiness(value));

  /// Меняет состояние отправки и публикует только переданное право ошибки
  /// [failurePresentation]; прежнее неподтверждённое право сессия передаёт
  /// общей поверхности. Ожидающее подтверждение закрытия объясняло прежнее
  /// состояние отправки и потому перестаёт действовать.
  ///
  /// Отказ из-за отсутствующих тегов сам доказывает их удаление, поэтому они
  /// уходят из набора вместе с отказом.
  IntentionEditorState withOperation(
    OperationState<Intention> value, {
    IntentionEditorEvent? event,
    GraphInitiatorPresentationClaim? failurePresentation,
  }) {
    final next = IntentionEditorState._(
      draft: draft,
      selectedTags: selectedTags,
      operation: value,
      event: event,
      failurePresentation: failurePresentation,
      closing: switch (closing) {
        IntentionCreationCloseConfirming() =>
          const IntentionCreationCloseNotRequested(),
        IntentionCreationCloseNotRequested() ||
        IntentionCreationClosedOnRequest() => closing,
      },
    );
    return switch (value) {
      OperationFailed<Intention>(
        failure: IntentionCreationTagsMissingFailure(:final missingTagIds),
      ) =>
        next.withoutDeletedTags(missingTagIds),
      OperationIdle<Intention>() ||
      OperationRunning<Intention>() ||
      OperationSucceeded<Intention>() ||
      OperationFailed<Intention>() => next,
    };
  }

  IntentionEditorState withoutEvent() => IntentionEditorState._(
    draft: draft,
    selectedTags: selectedTags,
    operation: operation,
    event: null,
    failurePresentation: failurePresentation,
    closing: closing,
  );

  /// Ожидает ответа на [confirmation]; черновик и отправка не меняются.
  IntentionEditorState withCloseConfirmation(
    IntentionCreationCloseConfirmation confirmation,
  ) => _withClosing(IntentionCreationCloseConfirming(confirmation));

  /// Продолжает сессию после ответа на подтверждение закрытия.
  IntentionEditorState withoutCloseConfirmation() =>
      _withClosing(const IntentionCreationCloseNotRequested());

  /// Завершает сессию запросом закрытия. Черновик больше не меняется, а право
  /// предъявления ошибки больше не публикуется: сессия передаёт его общей
  /// поверхности.
  IntentionEditorState closedOnRequest() => IntentionEditorState._(
    draft: draft,
    selectedTags: selectedTags,
    operation: operation,
    event: event,
    failurePresentation: null,
    closing: const IntentionCreationClosedOnRequest(),
  );

  Map<TagId, IntentionDraftTag> _selectedTagsWithout(Set<TagId> ids) =>
      Map.unmodifiable({
        for (final MapEntry(:key, :value) in selectedTags.entries)
          if (!ids.contains(key)) key: value,
      });

  IntentionEditorState _withClosing(IntentionCreationClosing value) =>
      IntentionEditorState._(
        draft: draft,
        selectedTags: selectedTags,
        operation: operation,
        event: event,
        failurePresentation: failurePresentation,
        closing: value,
      );

  IntentionEditorState _withDraft(IntentionCreationDraft draft) =>
      IntentionEditorState._(
        draft: draft,
        selectedTags: selectedTags,
        operation: operation,
        event: event,
        failurePresentation: failurePresentation,
        closing: closing,
      );

  IntentionEditorState _withEditedText({
    required IntentionCreationDraft draft,
    required IntentionTextField field,
  }) {
    final nextOperation = _operationAfterEditing(_DraftTextEdit(field));
    return IntentionEditorState._(
      draft: draft,
      selectedTags: selectedTags,
      operation: nextOperation,
      event: null,
      failurePresentation: nextOperation is OperationFailed<Intention>
          ? failurePresentation
          : null,
      closing: closing,
    );
  }

  IntentionEditorState _withEditedTags(
    IntentionCreationDraft draft, {
    required Map<TagId, IntentionDraftTag> selectedTags,
  }) {
    final nextOperation = _operationAfterEditing(const _DraftTagSetEdit());
    return IntentionEditorState._(
      draft: draft,
      selectedTags: selectedTags,
      operation: nextOperation,
      event: event,
      failurePresentation: nextOperation is OperationFailed<Intention>
          ? failurePresentation
          : null,
      closing: closing,
    );
  }

  /// Снимает отказ, только если правка устраняет его типизированную причину;
  /// право снятого отказа больше не публикуется, и сессия передаёт его общей
  /// поверхности. Иначе отказ сохраняется вместе с правом предъявления, а
  /// повтор остаётся доступным лишь для устранимой недоступности.
  OperationState<Intention> _operationAfterEditing(_DraftEdit edit) {
    final current = operation;
    if (current is! OperationFailed<Intention>) {
      return current;
    }
    final isResolved = switch (current.failure) {
      IntentionTextInputValidationFailure(:final textFailure) =>
        edit is _DraftTextEdit && edit.field == textFailure.field,
      IntentionGenericValidationFailure() => edit is _DraftTextEdit,
      // Отсутствующие теги ушли из набора вместе с отказом; его объяснение
      // остаётся до правки набора.
      IntentionCreationTagsMissingFailure() => edit is _DraftTagSetEdit,
      IntentionNotFoundFailure() ||
      IntentionConflictFailure() ||
      IntentionHasBlockingRelationsFailure() ||
      IntentionUnavailableFailure() ||
      IntentionCorruptionFailure() ||
      IntentionUnexpectedFailure() => false,
    };
    return isResolved ? const OperationIdle<Intention>() : current;
  }
}

/// Изменённая часть черновика, по которой правка может снять отказ.
sealed class _DraftEdit {
  const _DraftEdit();
}

final class _DraftTextEdit extends _DraftEdit {
  const _DraftTextEdit(this.field);

  final IntentionTextField field;
}

final class _DraftTagSetEdit extends _DraftEdit {
  const _DraftTagSetEdit();
}

/// Неизменяемая проекция [tags] в ручном порядке по месту тега.
Map<TagId, IntentionDraftTag> _inManualOrder(
  Map<TagId, IntentionDraftTag> tags,
) => Map.unmodifiable(
  Map.fromEntries(
    tags.entries.toList()
      ..sort((a, b) => a.value.position.compareTo(b.value.position)),
  ),
);
