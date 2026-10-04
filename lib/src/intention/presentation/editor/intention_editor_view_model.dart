import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
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
/// отметок меняют только его и не отправляют команд графа. Сессия закрыта
/// после успешного создания или освобождения и отвергает правки черновика.
@riverpod
final class IntentionEditorViewModel extends _$IntentionEditorViewModel {
  late GraphCommandCoordinator _coordinator;
  late IntentionCreationFormKey _formKey;
  late _SessionDraftTagSet _draftTagSet;
  IntentionOperationToken? _activeToken;

  @override
  IntentionEditorState build(IntentionCreationFormKey formKey) {
    _formKey = formKey;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
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
        case IntentionDraftAvailability.editable:
          if (!identical(previous.draft.tagIds, next.draft.tagIds)) {
            draftTagSet._publish(next.draftTagSet);
          }
        case IntentionDraftAvailability.closed:
          draftTagSet._close();
      }
    });
    ref.onDispose(() {
      draftTagSet._close();
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
    if (_acceptsDraftChanges) {
      state = state.withoutTag(id);
    }
  }

  void markFavorite() => _changeFavoriteMark(FavoriteMark.favorite);

  void unmarkFavorite() => _changeFavoriteMark(FavoriteMark.notFavorite);

  /// Включает начальную готовность. Вызывается только после явного
  /// подтверждения человеком обоих критериев действия; другие поля черновика
  /// готовность не включают.
  void confirmReadiness() => _changeReadiness(IntentionReadiness.ready);

  void disableReadiness() => _changeReadiness(IntentionReadiness.notReady);

  void submit() {
    if (!state.canSubmit) {
      return;
    }

    final draft = state.draft;
    final start = _coordinator.acceptCreation(
      _formKey,
      CreateIntention(
        title: draft.title,
        description: draft.description.isEmpty ? null : draft.description,
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
      if (!ref.mounted) {
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

  GraphInitiatorPresentationClaim? _claimFailure(
    IntentionOperationToken token,
  ) => _coordinator.claimInitiatorFailure(token);

  bool get _acceptsDraftChanges =>
      ref.mounted &&
      switch (state.draftAvailability) {
        IntentionDraftAvailability.editable => true,
        IntentionDraftAvailability.closed => false,
      };

  IntentionDraftTagAddition _addTag(Tag tag) {
    if (!_acceptsDraftChanges) {
      return IntentionDraftTagAddition.sessionClosed;
    }
    if (state.draft.tagIds.contains(tag.id)) {
      return IntentionDraftTagAddition.alreadyIncluded;
    }
    state = state.withTag(tag);
    return IntentionDraftTagAddition.added;
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

/// Контракт набора тегов, связанный с одним построением сессии: после её
/// закрытия публикует закрытое состояние, завершает поток и отвергает
/// добавление.
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
