import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/domain/intention_text.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../application/action_command.dart';
import '../../application/action_details.dart';
import '../../application/action_result.dart';
import '../../domain/action_priority.dart';
import '../../domain/action_schedule.dart';
import '../../domain/action_text.dart';
import 'action_editor_state.dart';

part 'action_editor_view_model.g.dart';

/// Сессия черновика одного листа нового действия по ключу формы его запуска.
///
/// Сессия переходит «ввод → создание → ввод с очищенными названием и
/// описанием» и заканчивается только закрытием листа. Отправка передаёт
/// координатору одну команду со снимком черновика и до её результата
/// отвергает правки и повторную отправку. Каждая отправка — своя операция:
/// сессия держит право предъявления только текущей.
///
/// Успех создания предъявляет общая поверхность, а сессия лишь очищает текст.
/// Отказ, выданный координатором инициатору, сессия публикует в состоянии, и
/// renderer листа подтверждает его по кадру с видимым сообщением. Право,
/// которое состояние перестало публиковать — правка сняла отказ, принята
/// новая отправка или лист закрыт, — сессия передаёт общей поверхности.
///
/// Путь черновика сессия наблюдает на текущих данных намерений и связей,
/// чтобы лист отмечал его разрывы; путь черновика от этого не меняется.
///
/// Закрытие во время записи не отменяет команду: сессия отказывается от
/// права на её результат, и отказ предъявит общая поверхность. Поздний
/// результат закрытой или освобождённой сессии её состояние не меняет.
@riverpod
final class ActionEditorViewModel extends _$ActionEditorViewModel {
  late GraphCommandCoordinator _coordinator;
  late PersonalGraphRepository _repository;
  late ActionEditorLaunch _launch;

  /// Наблюдение текущего пути черновика.
  StreamSubscription<ActionPathStateReadResult>? _pathStates;

  /// Выполняющаяся отправка, на результат которой сессия ещё имеет право.
  ActionOperationToken? _activeToken;

  /// Право отказа, которое публикует текущее состояние.
  GraphInitiatorPresentationClaim? _publishedClaim;

  @override
  ActionEditorState build(ActionEditorLaunch launch) {
    _launch = launch;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _repository = ref.watch(personalGraphRepositoryProvider);
    listenSelf((_, next) => _publish(next.failurePresentation));
    ref.onDispose(() {
      _releaseActiveOperation();
      _publish(null);
      unawaited(_pathStates?.cancel());
    });
    _watchPath(launch.path);
    return ActionEditorState.initial(launch);
  }

  void changeTitle(String value) {
    if (_isEditable && state.draft.title != value) {
      state = state.withTitle(value);
    }
  }

  void changeDescription(String value) {
    if (_isEditable && state.draft.description != value) {
      state = state.withDescription(value);
    }
  }

  void changeDate(CalendarDate value) {
    if (_isEditable && state.draft.date != value) {
      state = state.withDate(value);
    }
  }

  void changePath(ActionDraftPath value) {
    if (!_isEditable) return;
    state = state.withPath(value);
    _watchPath(value);
  }

  void changeSchedule(ActionSchedule value) {
    if (_isEditable && state.draft.schedule != value) {
      state = state.withSchedule(value);
    }
  }

  void changePriority(ActionPriority value) {
    if (_isEditable && state.draft.priority != value) {
      state = state.withPriority(value);
    }
  }

  /// Проверяет тексты и передаёт координатору одну команду создания.
  void submit() {
    if (!ref.mounted || !state.canSubmit) return;
    final draft = state.draft;
    ActionTitle? title;
    IntentionTextValidationReason? titleReason;
    try {
      title = ActionTitle(draft.title);
    } on IntentionTextValidationException catch (exception) {
      titleReason = exception.failure.reason;
    }
    ActionDescription? description;
    IntentionTextValidationReason? descriptionReason;
    try {
      description = ActionDescription.fromInput(draft.description);
    } on IntentionTextValidationException catch (exception) {
      descriptionReason = exception.failure.reason;
    }
    if (title == null || descriptionReason != null) {
      state = state.withSubmission(
        ActionEditorInputRejected(
          title: titleReason,
          description: descriptionReason,
        ),
      );
      return;
    }
    final start = _coordinator.acceptActionCreation(
      _launch.formKey,
      CreateAction(
        title: title,
        description: description,
        path: draft.path!.path,
        date: draft.date,
        schedule: draft.schedule,
        priority: draft.priority,
      ),
    );
    switch (start) {
      case ActionCommandAccepted(:final token, :final future):
        _activeToken = token;
        state = state.withSubmission(const ActionEditorCreating());
        unawaited(_finish(token, future));
      case ActionCommandAlreadyRunning():
        // Ключ формы занят только собственной выполняющейся отправкой, а во
        // время неё отправка недоступна.
        return;
      case GraphCommandCoordinatorDraining():
        state = state.withSubmission(
          const ActionEditorFailed(ActionUnexpectedFailure()),
        );
    }
  }

  /// Решает запрос закрытия листа. Без введённого текста и во время записи
  /// сессия завершается сразу; иначе нужен ответ на вопрос, и до него сессия
  /// продолжается.
  ActionEditorCloseDecision requestClose() {
    if (ref.mounted && state.asksOnClose) return ActionEditorCloseDecision.ask;
    close();
    return ActionEditorCloseDecision.close;
  }

  /// Завершает сессию: лист закрыт без вопроса, подтверждённым сбросом или
  /// другим способом ухода. Выполняющаяся команда продолжается, а её
  /// результат предъявит общая поверхность.
  void close() {
    if (!ref.mounted || state.isClosed) return;
    _releaseActiveOperation();
    state = state.closed();
  }

  Future<void> _finish(
    ActionOperationToken token,
    Future<ActionCommandCompletion> future,
  ) async {
    final completion = await future;
    if (!ref.mounted || !identical(_activeToken, token)) return;
    _activeToken = null;
    state = switch (completion.result) {
      GraphResultSuccess(value: ActionCreated()) => state.created(),
      GraphResultSuccess() => state.withSubmission(
        const ActionEditorFailed(ActionUnexpectedFailure()),
      ),
      GraphResultFailure(:final failure) => state.withSubmission(
        ActionEditorFailed(
          failure,
          presentation: _coordinator.claimInitiatorFailure(token),
        ),
      ),
    };
  }

  /// Наблюдает путь [path] вместо прежнего. Отказ чтения возвращает показ
  /// пути таким, каким его знает черновик: создание всё равно проверяет путь.
  void _watchPath(ActionDraftPath? path) {
    unawaited(_pathStates?.cancel());
    _pathStates = path == null
        ? null
        : _repository.watchActionPathState(path).listen((result) {
            if (!ref.mounted) return;
            state = state.withPathState(switch (result) {
              GraphResultSuccess(:final value) => value.value,
              GraphResultFailure() => null,
            });
          });
  }

  /// Отказывается от права на результат выполняющейся отправки: её отказ
  /// переходит общей поверхности.
  void _releaseActiveOperation() {
    final token = _activeToken;
    _activeToken = null;
    if (token != null) _coordinator.releaseInitiatorPresentation(token);
  }

  /// Учитывает опубликованное право отказа и передаёт общей поверхности
  /// прежнее, переставшее публиковаться. Право, уже подтверждённое renderer,
  /// координатор повторно не выдаёт.
  void _publish(GraphInitiatorPresentationClaim? claim) {
    final previous = _publishedClaim;
    _publishedClaim = claim;
    if (previous != null && !identical(previous, claim)) {
      _coordinator.releaseInitiatorClaim(previous);
    }
  }

  bool get _isEditable => ref.mounted && state.isEditable;
}
