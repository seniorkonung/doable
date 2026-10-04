import '../../../graph/application/graph_command_coordinator.dart';
import '../../../tag/domain/tag.dart';
import '../../../tag/domain/tag_id.dart';
import '../../../tag/domain/tag_name.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_text.dart';
import '../operation/operation_state.dart';

sealed class IntentionEditorEvent {
  const IntentionEditorEvent();
}

final class IntentionEditorCreated extends IntentionEditorEvent {
  const IntentionEditorCreated();
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
      readiness = IntentionReadiness.notReady,
      favoriteMark = FavoriteMark.notFavorite;

  /// [tagIds] должен быть неизменяемым; копию создают только методы правки
  /// набора, чтобы неизменённый набор сохранял свою идентичность.
  const IntentionCreationDraft._({
    required this.title,
    required this.description,
    required this.tagIds,
    required this.readiness,
    required this.favoriteMark,
  });

  final String title;
  final String description;
  final Set<TagId> tagIds;

  /// Начальная готовность к действию; включается только явным решением.
  final IntentionReadiness readiness;
  final FavoriteMark favoriteMark;

  /// Отличается ли хотя бы одно из пяти полей от начального значения.
  /// Полностью пробельный текст тоже считается изменением.
  bool get isChanged =>
      title.isNotEmpty ||
      description.isNotEmpty ||
      tagIds.isNotEmpty ||
      readiness != IntentionReadiness.notReady ||
      favoriteMark != FavoriteMark.notFavorite;

  IntentionCreationDraft withTitle(String value) => _copy(title: value);

  IntentionCreationDraft withDescription(String value) =>
      _copy(description: value);

  IntentionCreationDraft withTag(TagId id) => tagIds.contains(id)
      ? this
      : _copy(tagIds: Set.unmodifiable({...tagIds, id}));

  IntentionCreationDraft withoutTag(TagId id) => tagIds.contains(id)
      ? _copy(tagIds: Set.unmodifiable(tagIds.where((tagId) => tagId != id)))
      : this;

  IntentionCreationDraft withReadiness(IntentionReadiness value) =>
      _copy(readiness: value);

  IntentionCreationDraft withFavoriteMark(FavoriteMark value) =>
      _copy(favoriteMark: value);

  IntentionCreationDraft _copy({
    String? title,
    String? description,
    Set<TagId>? tagIds,
    IntentionReadiness? readiness,
    FavoriteMark? favoriteMark,
  }) => IntentionCreationDraft._(
    title: title ?? this.title,
    description: description ?? this.description,
    tagIds: tagIds ?? this.tagIds,
    readiness: readiness ?? this.readiness,
    favoriteMark: favoriteMark ?? this.favoriteMark,
  );
}

/// Принимает ли сессия создания изменения своего черновика.
enum IntentionDraftAvailability {
  editable,

  /// Принятая отправка выполняется: черновик зафиксирован до её результата.
  submitting,

  /// Сессия завершена успешным созданием или освобождена.
  closed,
}

/// Опубликованное состояние набора тегов черновика для общего выбора тегов.
final class IntentionDraftTagSetSnapshot {
  const IntentionDraftTagSetSnapshot({
    required this.tagIds,
    required this.availability,
  });

  /// Неизменяемый набор идентификаторов в порядке добавления.
  final Set<TagId> tagIds;
  final IntentionDraftAvailability availability;
}

enum IntentionDraftTagAddition {
  added,

  /// Тег уже входит в набор; черновик не изменился.
  alreadyIncluded,

  /// Выполняется принятая отправка; черновик не изменился.
  submitting,

  /// Сессия закрыта; черновик не изменился.
  sessionClosed,
}

/// Узкий контракт набора тегов черновика для общего выбора тегов.
///
/// Связан с одной сессией создания: предоставляет только наблюдаемый набор
/// идентификаторов и явное локальное добавление. Добавление меняет только
/// черновик и не записывает назначений; команды графа, ревизии и детали
/// хранилища в контракт не входят. Во время отправки и после закрытия сессии
/// контракт отвергает изменения.
abstract interface class IntentionDraftTagSet {
  IntentionDraftTagSetSnapshot get current;

  /// Изменения набора или его доступности. Поток завершается после
  /// публикации закрытого состояния сессии.
  Stream<IntentionDraftTagSetSnapshot> get changes;

  /// Явно добавляет подтверждённый [tag]; его название сохраняется как
  /// последнее известное для показа. Повторное добавление ничего не меняет.
  IntentionDraftTagAddition add(Tag tag);
}

final class IntentionEditorState {
  const IntentionEditorState._({
    required this.draft,
    required this.selectedTagNames,
    required this.operation,
    required this.event,
    required this.failurePresentation,
  });

  const IntentionEditorState.initial()
    : draft = const IntentionCreationDraft.initial(),
      selectedTagNames = const {},
      operation = const OperationIdle<Intention>(),
      event = null,
      failurePresentation = null;

  final IntentionCreationDraft draft;

  /// Последние известные названия выбранных тегов — неизменяемая проекция
  /// для показа с теми же ключами, что и набор черновика. Она не входит в
  /// черновик и не влияет на его изменённость.
  final Map<TagId, TagName> selectedTagNames;
  final OperationState<Intention> operation;
  final IntentionEditorEvent? event;

  /// Право открытой формы предъявить текущую ошибку; подтверждается страницей
  /// только по кадру с видимым сообщением.
  final GraphInitiatorPresentationClaim? failurePresentation;

  IntentionDraftAvailability get draftAvailability => switch (operation) {
    OperationSucceeded<Intention>() => IntentionDraftAvailability.closed,
    OperationRunning<Intention>() => IntentionDraftAvailability.submitting,
    OperationIdle<Intention>() ||
    OperationFailed<Intention>() => IntentionDraftAvailability.editable,
  };

  IntentionDraftTagSetSnapshot get draftTagSet => IntentionDraftTagSetSnapshot(
    tagIds: draft.tagIds,
    availability: draftAvailability,
  );

  /// Выбранные теги черновика, отсутствие которых подтвердил последний отказ
  /// создания, — данные для показа недоступных тегов. Пока набор не пуст,
  /// новая проверка недоступна: каждый такой тег снимается только явно.
  Set<TagId> get missingTagIds => switch (operation) {
    OperationFailed<Intention>(
      failure: IntentionCreationTagsMissingFailure(:final missingTagIds),
    ) =>
      Set.unmodifiable(draft.tagIds.where(missingTagIds.contains)),
    OperationIdle<Intention>() ||
    OperationRunning<Intention>() ||
    OperationSucceeded<Intention>() ||
    OperationFailed<Intention>() => const {},
  };

  bool get canRetry => switch (operation) {
    OperationFailed<Intention>(failure: IntentionUnavailableFailure()) => true,
    OperationIdle<Intention>() ||
    OperationRunning<Intention>() ||
    OperationSucceeded<Intention>() ||
    OperationFailed<Intention>() => false,
  };

  bool get canSubmit => operation is OperationIdle<Intention> || canRetry;

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
          selectedTagNames: Map.unmodifiable({
            ...selectedTagNames,
            tag.id: tag.name,
          }),
        );

  IntentionEditorState withoutTag(TagId id) => draft.tagIds.contains(id)
      ? _withEditedTags(
          draft.withoutTag(id),
          selectedTagNames: Map.unmodifiable({
            for (final MapEntry(:key, :value) in selectedTagNames.entries)
              if (key != id) key: value,
          }),
        )
      : this;

  IntentionEditorState withReadiness(IntentionReadiness value) =>
      draft.readiness == value ? this : _withDraft(draft.withReadiness(value));

  IntentionEditorState withFavoriteMark(FavoriteMark value) =>
      draft.favoriteMark == value
      ? this
      : _withDraft(draft.withFavoriteMark(value));

  IntentionEditorState withOperation(
    OperationState<Intention> value, {
    IntentionEditorEvent? event,
    GraphInitiatorPresentationClaim? failurePresentation,
  }) => IntentionEditorState._(
    draft: draft,
    selectedTagNames: selectedTagNames,
    operation: value,
    event: event,
    failurePresentation: failurePresentation,
  );

  IntentionEditorState withoutEvent() => IntentionEditorState._(
    draft: draft,
    selectedTagNames: selectedTagNames,
    operation: operation,
    event: null,
    failurePresentation: failurePresentation,
  );

  IntentionEditorState _withDraft(
    IntentionCreationDraft draft, {
    Map<TagId, TagName>? selectedTagNames,
  }) => IntentionEditorState._(
    draft: draft,
    selectedTagNames: selectedTagNames ?? this.selectedTagNames,
    operation: operation,
    event: event,
    failurePresentation: failurePresentation,
  );

  IntentionEditorState _withEditedText({
    required IntentionCreationDraft draft,
    required IntentionTextField field,
  }) {
    final nextOperation = _operationAfterEditing(_DraftTextEdit(field));
    return IntentionEditorState._(
      draft: draft,
      selectedTagNames: selectedTagNames,
      operation: nextOperation,
      event: null,
      failurePresentation: nextOperation is OperationFailed<Intention>
          ? failurePresentation
          : null,
    );
  }

  IntentionEditorState _withEditedTags(
    IntentionCreationDraft draft, {
    required Map<TagId, TagName> selectedTagNames,
  }) {
    final nextOperation = _operationAfterEditing(
      _DraftTagSetEdit(draft.tagIds),
    );
    return IntentionEditorState._(
      draft: draft,
      selectedTagNames: selectedTagNames,
      operation: nextOperation,
      event: event,
      failurePresentation: nextOperation is OperationFailed<Intention>
          ? failurePresentation
          : null,
    );
  }

  /// Снимает отказ, только если правка устраняет его типизированную причину.
  /// Иначе отказ сохраняется вместе с правом предъявления, а повтор остаётся
  /// доступным лишь для устранимой недоступности.
  OperationState<Intention> _operationAfterEditing(_DraftEdit edit) {
    final current = operation;
    if (current is! OperationFailed<Intention>) {
      return current;
    }
    final isResolved = switch (current.failure) {
      IntentionTextInputValidationFailure(:final textFailure) =>
        edit is _DraftTextEdit && edit.field == textFailure.field,
      IntentionGenericValidationFailure() => edit is _DraftTextEdit,
      // Удалённый тег не возвращается с прежним идентификатором: новая
      // проверка имеет смысл только после явного снятия каждого
      // отсутствующего тега, а одноимённая замена отказ не снимает.
      IntentionCreationTagsMissingFailure(:final missingTagIds) =>
        edit is _DraftTagSetEdit && !edit.tagIds.any(missingTagIds.contains),
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

/// Изменение состава набора тегов; [tagIds] — набор после правки.
final class _DraftTagSetEdit extends _DraftEdit {
  const _DraftTagSetEdit(this.tagIds);

  final Set<TagId> tagIds;
}
