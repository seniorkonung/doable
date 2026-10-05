import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../tag/application/tag_read_result.dart';
import '../../../tag/domain/tag.dart';
import '../../../tag/domain/tag_id.dart';
import '../../application/intention_command.dart';
import '../../application/intention_catalog.dart';
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../operation/operation_state.dart';
import 'intention_editor_state.dart';

part 'intention_editor_view_model.g.dart';

/// Экранная сессия создания намерения по собственному ключу формы.
///
/// До отправки владеет черновиком: правки текста, набора тегов и обеих
/// отметок меняют только его и не отправляют команд графа. Отправка передаёт
/// координатору одну команду с неизменяемым снимком всех пяти полей и до
/// результата отвергает правки черновика и повторную отправку. Принятую
/// отправку удерживает координатор: освобождение сессии её не отменяет и не
/// снимает ограничение ключа формы. Сессия закрыта после успешного создания,
/// закрытия по запросу или освобождения и отвергает правки черновика.
///
/// Все способы ухода обращаются к единому решению [requestClose]: неизменённый
/// черновик закрывается сразу, изменённый — после одного подтверждения,
/// связанного с ключом сессии и состоянием отправки. Переходы в выбор и
/// редактор тегов сессию не завершают. Закрытие не отменяет принятую отправку:
/// её результат переходит общей поверхности, а право уже полученной ошибки
/// остаётся у её renderer до его окончательного удаления.
///
/// Отказ сохраняет весь черновик без нормализации и передаёт право
/// предъявления ошибки renderer страницы. Новая отправка становится доступна
/// только после правки, устраняющей типизированную причину отказа, либо как
/// явный повтор устранимой недоступности; сама сессия её не запускает.
///
/// Проекцию выбранных тегов сессия поддерживает собственным наблюдением
/// `watchTag` каждого выбранного идентификатора. Наблюдение меняет только
/// проекцию, не отправляет команд графа и освобождается при снятии тега и
/// завершении сессии.
@riverpod
final class IntentionEditorViewModel extends _$IntentionEditorViewModel {
  late GraphCommandCoordinator _coordinator;
  late IntentionCreationFormKey _formKey;
  late TagReadContract _tagReads;
  late _SessionDraftTagSet _draftTagSet;
  IntentionOperationToken? _activeToken;
  final _tagObservations = <TagId, _DraftTagObservation>{};
  var _tagObservationGeneration = 0;

  @override
  IntentionEditorState build(IntentionCreationFormKey formKey) {
    _formKey = formKey;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _tagReads = ref.watch(personalGraphRepositoryProvider);
    const initial = IntentionEditorState.initial();
    final draftTagSet = _draftTagSet = _SessionDraftTagSet(
      this,
      initial.draftTagSet,
    );
    listenSelf((previous, next) {
      if (previous == null) {
        return;
      }
      switch (next.draftAvailability) {
        case IntentionDraftAvailability.editable ||
            IntentionDraftAvailability.submitting:
          if (!identical(previous.draft.tagIds, next.draft.tagIds) ||
              previous.draftAvailability != next.draftAvailability) {
            draftTagSet._publish(next.draftTagSet);
          }
        case IntentionDraftAvailability.closed:
          draftTagSet._close();
          _releaseTagObservations();
      }
    });
    ref.onDispose(() {
      draftTagSet._close();
      _releaseTagObservations();
      final activeToken = _activeToken;
      if (activeToken != null) {
        _coordinator.releaseInitiatorPresentation(activeToken);
      }
    });
    return initial;
  }

  /// Контракт набора тегов этой сессии для общего выбора тегов.
  IntentionDraftTagSet get draftTagSet => _draftTagSet;

  void changeTitle(String value) {
    if (_acceptsDraftChanges && state.draft.title != value) {
      state = state.withTitle(value);
    }
  }

  void changeDescription(String value) {
    if (_acceptsDraftChanges && state.draft.description != value) {
      state = state.withDescription(value);
    }
  }

  void removeTag(TagId id) {
    if (_acceptsDraftChanges && state.draft.tagIds.contains(id)) {
      state = state.withoutTag(id);
      _releaseTagObservation(id);
    }
  }

  /// Повторяет наблюдение выбранного тега после устранимого отказа чтения.
  /// Повтор меняет только проекцию и доступен, пока сессия не закрыта.
  void retryTagObservation(TagId id) {
    if (!_observesTags) {
      return;
    }
    if (state.selectedTags[id]
        case IntentionDraftTag(
              status: IntentionDraftTagReadFailed(canRetry: true),
            ) &&
            final tag) {
      state = state.withSelectedTag(
        id,
        tag.withStatus(const IntentionDraftTagLoading()),
      );
      _observeTag(id);
    }
  }

  void markFavorite() => _changeFavoriteMark(FavoriteMark.favorite);

  void unmarkFavorite() => _changeFavoriteMark(FavoriteMark.notFavorite);

  /// Включает начальную готовность. Вызывается только после явного
  /// подтверждения человеком обоих критериев действия; другие поля черновика
  /// готовность не включают.
  void confirmReadiness() => _changeReadiness(IntentionReadiness.ready);

  void disableReadiness() => _changeReadiness(IntentionReadiness.notReady);

  /// Передаёт координатору весь черновик одной командой.
  ///
  /// Команда хранит собственный снимок черновика; до результата сессия
  /// отвергает его правки, а повтор не принимается и не ставится в очередь.
  void submit() {
    if (!ref.mounted || !state.canSubmit) {
      return;
    }

    final draft = state.draft;
    final start = _coordinator.acceptCreation(
      _formKey,
      CreateIntention.withInitialState(
        title: draft.title,
        description: draft.description.isEmpty ? null : draft.description,
        readiness: draft.readiness,
        favoriteMark: draft.favoriteMark,
        tagIds: draft.tagIds,
      ),
    );
    switch (start) {
      case IntentionCommandAccepted(:final token, :final future):
        _activeToken = token;
        state = state.withOperation(const OperationRunning<Intention>());
        unawaited(_finish(future));
      case IntentionCommandAlreadyRunning():
        return;
      case GraphCommandCoordinatorDraining():
        state = state.withOperation(
          const OperationFailed<Intention>(IntentionUnexpectedFailure()),
        );
    }
  }

  /// Решает запрос закрытия сессии от любого способа ухода.
  ///
  /// Неизменённый черновик завершает сессию сразу. Изменённый требует одного
  /// подтверждения; повторный запрос до ответа второго не создаёт. Решение
  /// сообщает, продолжится ли принятая отправка после закрытия. Запрос к
  /// завершённой сессии ничего не закрывает.
  IntentionCreationCloseDecision requestClose() {
    if (!ref.mounted) {
      return const IntentionCreationCloseSessionEnded();
    }
    switch (state.closing) {
      case IntentionCreationClosedOnRequest():
        return const IntentionCreationCloseSessionEnded();
      case IntentionCreationCloseConfirming():
        return const IntentionCreationCloseAwaitingConfirmation();
      case IntentionCreationCloseNotRequested():
        break;
    }
    final IntentionCreationSavingOnClose savingOnClose;
    switch (state.draftAvailability) {
      case IntentionDraftAvailability.closed:
        return const IntentionCreationCloseSessionEnded();
      case IntentionDraftAvailability.submitting:
        savingOnClose = IntentionCreationSavingOnClose.continues;
      case IntentionDraftAvailability.editable:
        savingOnClose = IntentionCreationSavingOnClose.notStarted;
    }
    if (!state.draft.isChanged) {
      _endOnRequest();
      return IntentionCreationClosedImmediately(savingOnClose);
    }
    final confirmation = IntentionCreationCloseConfirmation(
      formKey: _formKey,
      savingOnClose: savingOnClose,
    );
    state = state.withCloseConfirmation(confirmation);
    return IntentionCreationCloseNeedsConfirmation(confirmation);
  }

  /// Применяет ответ [choice] на подтверждение [confirmation].
  ///
  /// Ответ действует, только пока [confirmation] остаётся ожидающим
  /// подтверждением этого построения сессии; иначе он ничего не меняет.
  IntentionCreationCloseResolution resolveClose(
    IntentionCreationCloseConfirmation confirmation,
    IntentionCreationCloseChoice choice,
  ) {
    if (!ref.mounted || !identical(confirmation.formKey, _formKey)) {
      return IntentionCreationCloseResolution.outdated;
    }
    final isPending = switch (state.closing) {
      IntentionCreationCloseConfirming(confirmation: final pending) =>
        identical(pending, confirmation),
      IntentionCreationCloseNotRequested() ||
      IntentionCreationClosedOnRequest() => false,
    };
    if (!isPending) {
      return IntentionCreationCloseResolution.outdated;
    }
    switch (choice) {
      case IntentionCreationCloseChoice.continueEditing:
        state = state.withoutCloseConfirmation();
        return IntentionCreationCloseResolution.continued;
      case IntentionCreationCloseChoice.discardDraft:
        _endOnRequest();
        return IntentionCreationCloseResolution.closed;
    }
  }

  void consumeEvent() {
    if (state.event != null) {
      state = state.withoutEvent();
    }
  }

  Future<void> _finish(Future<IntentionCommandCompletion> future) async {
    try {
      final completion = await future;
      if (!ref.mounted || !identical(_activeToken, completion.token)) {
        return;
      }

      _activeToken = null;
      // Success предъявляет оболочка; форма получает его только для закрытия.
      state = switch (completion.result) {
        ResultSuccess(value: IntentionSaved(:final intention)) =>
          state.withOperation(
            OperationSucceeded<Intention>(intention),
            event: const IntentionEditorCreated(),
          ),
        ResultSuccess(value: IntentionDeleted()) => state.withOperation(
          const OperationFailed<Intention>(IntentionUnexpectedFailure()),
        ),
        ResultFailure(:final failure) => state.withOperation(
          OperationFailed<Intention>(failure),
          failurePresentation: _claimFailure(completion.token),
        ),
      };
    } on Object {
      // Закрытая по запросу сессия уже передала результат общей поверхности.
      if (!ref.mounted || state.closing is IntentionCreationClosedOnRequest) {
        return;
      }
      final token = _activeToken;
      _activeToken = null;
      if (token != null) {
        _coordinator.releaseInitiatorPresentation(token);
      }
      state = state.withOperation(
        const OperationFailed<Intention>(IntentionUnexpectedFailure()),
      );
    }
  }

  /// Завершает сессию по запросу закрытия, не отменяя принятую отправку.
  ///
  /// Результат выполняющейся отправки переходит общей поверхности. Право уже
  /// полученной ошибки остаётся у её renderer: временное перекрытие его
  /// сохраняет, а удаление renderer до предъявления передаёт общей
  /// поверхности. Наблюдения тегов и контракт набора освобождаются при
  /// переходе в закрытое состояние.
  void _endOnRequest() {
    final token = _activeToken;
    _activeToken = null;
    if (token != null) {
      _coordinator.releaseInitiatorPresentation(token);
    }
    state = state.closedOnRequest();
  }

  GraphInitiatorPresentationClaim? _claimFailure(
    IntentionOperationToken token,
  ) => _coordinator.claimInitiatorFailure(token);

  bool get _observesTags =>
      ref.mounted &&
      switch (state.draftAvailability) {
        IntentionDraftAvailability.editable ||
        IntentionDraftAvailability.submitting => true,
        IntentionDraftAvailability.closed => false,
      };

  bool get _acceptsDraftChanges =>
      ref.mounted &&
      switch (state.draftAvailability) {
        IntentionDraftAvailability.editable => true,
        IntentionDraftAvailability.submitting ||
        IntentionDraftAvailability.closed => false,
      };

  IntentionDraftTagAddition _addTag(Tag tag) {
    if (!ref.mounted) {
      return IntentionDraftTagAddition.sessionClosed;
    }
    switch (state.draftAvailability) {
      case IntentionDraftAvailability.submitting:
        return IntentionDraftTagAddition.submitting;
      case IntentionDraftAvailability.closed:
        return IntentionDraftTagAddition.sessionClosed;
      case IntentionDraftAvailability.editable:
        if (state.draft.tagIds.contains(tag.id)) {
          return IntentionDraftTagAddition.alreadyIncluded;
        }
        state = state.withTag(tag);
        _observeTag(tag.id);
        return IntentionDraftTagAddition.added;
    }
  }

  /// Начинает новое поколение наблюдения выбранного тега. При повторе
  /// сохраняется ревизия последнего принятого ответа, чтобы более старый
  /// снимок не вернул прежнее название.
  void _observeTag(TagId id) {
    final previous = _tagObservations.remove(id)?..release();
    final generation = ++_tagObservationGeneration;
    final observation = _tagObservations[id] = _DraftTagObservation(
      generation,
      revision: previous?.revision,
    );
    try {
      observation.subscription = _tagReads
          .watchTag(id)
          .listen(
            (result) => _onTagRead(id, generation, result),
            onError: (Object _) => _tagObservationFailed(
              id,
              generation,
              const TagReadUnexpectedFailure(),
            ),
            onDone: () => _tagObservationEnded(id, generation),
          );
    } on Object {
      _tagObservationFailed(id, generation, const TagReadUnexpectedFailure());
    }
  }

  void _onTagRead(TagId id, int generation, TagReadResult result) {
    final observation = _activeTagObservation(id, generation);
    final tag = state.selectedTags[id];
    if (observation == null || tag == null) {
      return;
    }
    switch (result) {
      case TagReadSuccess(:final value):
        final known = observation.revision;
        if (known != null &&
            value.revision.compareTo(known) == GraphRevisionOrder.older) {
          return;
        }
        final observed = value.value;
        if (observed != null && observed.id != id) {
          _tagObservationFailed(
            id,
            generation,
            const TagReadCorruptionFailure(),
          );
          return;
        }
        observation.revision = value.revision;
        // Новая ревизия без изменения тега не публикует проекцию заново.
        switch ((observed, tag.status)) {
          case (null, IntentionDraftTagMissing()):
            return;
          case (final Tag current, IntentionDraftTagAvailable())
              when current.name == tag.name:
            return;
          case (null, _):
            state = state.withSelectedTag(
              id,
              tag.withStatus(const IntentionDraftTagMissing()),
            );
          case (final Tag current, _):
            state = state.withSelectedTag(
              id,
              IntentionDraftTag(
                name: current.name,
                status: const IntentionDraftTagAvailable(),
              ),
            );
        }
      case TagReadError(:final failure):
        _tagObservationFailed(id, generation, failure);
    }
  }

  /// Отказ завершает поколение наблюдения: его поздние ответы не
  /// принимаются, а причина сохраняется до явного повтора.
  void _tagObservationFailed(TagId id, int generation, TagReadFailure failure) {
    final observation = _activeTagObservation(id, generation);
    final tag = state.selectedTags[id];
    if (observation == null || tag == null) {
      return;
    }
    observation.release();
    state = state.withSelectedTag(
      id,
      tag.withStatus(IntentionDraftTagReadFailed(failure)),
    );
  }

  /// Подтверждённое отсутствие окончательно и переживает окончание потока;
  /// иное окончание без установленной причины — неизвестный отказ.
  void _tagObservationEnded(TagId id, int generation) {
    final observation = _activeTagObservation(id, generation);
    final tag = state.selectedTags[id];
    if (observation == null || tag == null) {
      return;
    }
    switch (tag.status) {
      case IntentionDraftTagMissing() || IntentionDraftTagReadFailed():
        observation.release();
      case IntentionDraftTagLoading() || IntentionDraftTagAvailable():
        _tagObservationFailed(id, generation, const TagReadUnexpectedFailure());
    }
  }

  /// Наблюдение, которому ещё принадлежит право менять проекцию тега [id].
  _DraftTagObservation? _activeTagObservation(TagId id, int generation) {
    if (!ref.mounted) {
      return null;
    }
    final observation = _tagObservations[id];
    return observation != null &&
            observation.isActive &&
            observation.generation == generation
        ? observation
        : null;
  }

  void _releaseTagObservation(TagId id) =>
      _tagObservations.remove(id)?.release();

  void _releaseTagObservations() {
    for (final observation in _tagObservations.values) {
      observation.release();
    }
    _tagObservations.clear();
  }

  void _changeFavoriteMark(FavoriteMark value) {
    if (_acceptsDraftChanges) {
      state = state.withFavoriteMark(value);
    }
  }

  void _changeReadiness(IntentionReadiness value) {
    if (_acceptsDraftChanges) {
      state = state.withReadiness(value);
    }
  }
}

/// Контракт набора тегов, связанный с одним построением сессии: публикует
/// изменения набора и его доступности, а после закрытия сессии публикует
/// закрытое состояние, завершает поток и отвергает добавление.
final class _SessionDraftTagSet implements IntentionDraftTagSet {
  _SessionDraftTagSet(this._session, this._current);

  final IntentionEditorViewModel _session;
  final _changes = StreamController<IntentionDraftTagSetSnapshot>.broadcast();
  IntentionDraftTagSetSnapshot _current;
  bool _isClosed = false;

  @override
  IntentionDraftTagSetSnapshot get current => _current;

  @override
  Stream<IntentionDraftTagSetSnapshot> get changes => _changes.stream;

  @override
  IntentionDraftTagAddition add(Tag tag) => _isClosed
      ? IntentionDraftTagAddition.sessionClosed
      : _session._addTag(tag);

  void _publish(IntentionDraftTagSetSnapshot snapshot) {
    if (_isClosed) {
      return;
    }
    _current = snapshot;
    _changes.add(snapshot);
  }

  void _close() {
    if (_isClosed) {
      return;
    }
    _publish(
      IntentionDraftTagSetSnapshot(
        tagIds: _current.tagIds,
        availability: IntentionDraftAvailability.closed,
      ),
    );
    _isClosed = true;
    unawaited(_changes.close());
  }
}

/// Одно поколение наблюдения выбранного тега черновика.
final class _DraftTagObservation {
  _DraftTagObservation(this.generation, {this.revision});

  final int generation;

  /// Ревизия последнего принятого ответа о теге.
  GraphRevision? revision;
  StreamSubscription<TagReadResult>? subscription;
  bool isActive = true;

  void release() {
    isActive = false;
    unawaited(subscription?.cancel());
    subscription = null;
  }
}
