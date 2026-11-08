import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../application/cascade/intention_cascade.dart';
import '../../application/intention_command.dart';
import '../../application/intention_catalog.dart';
import '../../application/intention_details.dart' as application;
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
import 'intention_details_state.dart';

part 'intention_details_view_model.g.dart';

/// Принимаемая координатором операция: готовая команда или отказ
/// предпросмотра каскада, прочитанного при её запуске.
sealed class _OperationStart {
  const _OperationStart();
}

final class _CommandStart extends _OperationStart {
  const _CommandStart(this.command);

  final ExistingIntentionCommand command;
}

final class _PreviewFailureStart extends _OperationStart {
  const _PreviewFailureStart(this.operation, this.failure);

  final CascadeOperation operation;
  final CascadePreviewFailure failure;
}

/// Решение человека по каскадной операции. Удаление исполняется только
/// с вариантом из ответа подтверждения, поэтому без него непредставимо.
sealed class _CascadeDecision {
  const _CascadeDecision();

  CascadeOperation get operation;
}

/// Вопрос варианта архивирования или восстановления. Без вопроса исполняется
/// вариант «со вспомогательными».
final class _VariantQuestion extends _CascadeDecision {
  const _VariantQuestion(this.operation, this.choose);

  @override
  final CascadeOperation operation;
  final Future<CascadeChoice?> Function(int count)? choose;

  Future<CascadeChoice?> ask(int count) async =>
      count == 0 ? CascadeChoice.withSupporting : await choose?.call(count);
}

final class _DeletionConfirmation extends _CascadeDecision {
  const _DeletionConfirmation(this.confirm);

  @override
  CascadeOperation get operation => CascadeOperation.delete;

  final Future<CascadeChoice?> Function(IntentionDeleteCascadePreview preview)
  confirm;
}

final class _DetailObservationGeneration {
  const _DetailObservationGeneration(this.value);

  static const initial = _DetailObservationGeneration(0);

  final int value;

  _DetailObservationGeneration next() =>
      _DetailObservationGeneration(value + 1);

  @override
  bool operator ==(Object other) =>
      other is _DetailObservationGeneration && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

@riverpod
Stream<Result<GraphSnapshot<application.IntentionDetails?>>>
_intentionDetailsObservation(
  Ref ref,
  IntentionId intentionId,
  _DetailObservationGeneration generation,
) => ref.watch(personalGraphRepositoryProvider).watchIntention(intentionId);

@riverpod
final class IntentionDetailsViewModel extends _$IntentionDetailsViewModel {
  late IntentionId _intentionId;
  late GraphCommandCoordinator _coordinator;
  late _DetailObservationGeneration _generation;
  late StreamSubscription<GraphCommandCompletion> _completionSubscription;
  ProviderSubscription<
    AsyncValue<Result<GraphSnapshot<application.IntentionDetails?>>>
  >?
  _observationSubscription;
  GraphRevision? _acceptedRevision;
  var _preserveAuthoritativeStateWhileLoading = false;
  var _isDeleted = false;
  var _isReadingCascadePreview = false;

  @override
  IntentionDetailsState build(IntentionId intentionId) {
    _intentionId = intentionId;
    _generation = _DetailObservationGeneration.initial;
    _acceptedRevision = null;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _completionSubscription = _coordinator.completions.listen(
      _handleCompletion,
    );
    ref.onDispose(() {
      _observationSubscription?.close();
      unawaited(_completionSubscription.cancel());
    });

    final initialObservation = _startObservation();
    return _stateFromObservation(initialObservation);
  }

  void retry() {
    if (state is! IntentionDetailsUnavailable) {
      return;
    }
    _advanceGeneration();
    _preserveAuthoritativeStateWhileLoading = false;
    state = _stateFromObservation(_startObservation());
  }

  /// Координатор не сообщает о принятии чужой команды, поэтому страница
  /// перечитывает занятость намерения, когда снова становится текущей.
  void refreshOperationRunning() {
    if (!ref.mounted || _isDeleted) {
      return;
    }
    final isRunning = _isOperationRunning;
    if (state.isOperationRunning != isRunning) {
      state = _withOperationRunning(state, isRunning);
    }
  }

  void changeKind(IntentionKind kind) {
    final current = state;
    if (current is! IntentionDetailsLoaded || current.intention.kind == kind) {
      return;
    }
    _accept(
      current.intention.title,
      _CommandStart(ChangeIntentionKind(_intentionId, kind)),
      releasesInitiator: false,
    );
  }

  void archive([Future<CascadeChoice?> Function(int count)? choose]) =>
      unawaited(
        _startCascadeOperation(
          _VariantQuestion(CascadeOperation.archive, choose),
        ),
      );

  void restore([Future<CascadeChoice?> Function(int count)? choose]) =>
      unawaited(
        _startCascadeOperation(
          _VariantQuestion(CascadeOperation.restore, choose),
        ),
      );

  /// Возвращает успех только собственной принятой команды удаления.
  /// Общее состояние данных по ID не передаёт право закрытия другим страницам.
  Future<bool> delete(
    Future<CascadeChoice?> Function(IntentionDeleteCascadePreview preview)
    confirm,
  ) async {
    final intentionId = _intentionId;
    final completion = await _startCascadeOperation(
      _DeletionConfirmation(confirm),
    );
    return switch (completion?.result) {
      ResultSuccess(value: IntentionDeleted(:final id)) => id == intentionId,
      _ => false,
    };
  }

  AsyncValue<Result<GraphSnapshot<application.IntentionDetails?>>>
  _startObservation() {
    _observationSubscription?.close();
    final generation = _generation;
    final subscription = ref.listen(
      _intentionDetailsObservationProvider(_intentionId, generation),
      (previous, next) => _handleObservation(generation, next),
    );
    _observationSubscription = subscription;
    return subscription.read();
  }

  void _handleObservation(
    _DetailObservationGeneration generation,
    AsyncValue<Result<GraphSnapshot<application.IntentionDetails?>>>
    observation,
  ) {
    if (!ref.mounted || _isDeleted || generation != _generation) {
      return;
    }
    if (observation
            is AsyncLoading<
              Result<GraphSnapshot<application.IntentionDetails?>>
            > &&
        _preserveAuthoritativeStateWhileLoading) {
      return;
    }
    if (observation
        is! AsyncLoading<
          Result<GraphSnapshot<application.IntentionDetails?>>
        >) {
      _preserveAuthoritativeStateWhileLoading = false;
    }
    final snapshot = switch (observation) {
      AsyncData(value: ResultSuccess(:final value)) => value,
      AsyncLoading() || AsyncError() || AsyncData() => null,
    };
    if (snapshot != null && !_acceptSnapshotRevision(snapshot.revision)) {
      return;
    }
    state = _stateFromObservation(observation);
  }

  void _handleCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted || _isDeleted) {
      return;
    }
    if (state.isOperationRunning) {
      _scheduleGateRefresh();
    }
    final confirmedChange = completion.confirmedChange;
    if (confirmedChange == null) {
      return;
    }
    final mutations = confirmedChange.changes
        .whereType<IntentionCatalogMutation>()
        .where(
          (change) =>
              change.before?.summary.id == _intentionId ||
              change.after?.summary.id == _intentionId,
        );
    final deleted = mutations.any((change) => change.after == null);
    final affectsIntention =
        deleted ||
        mutations.isNotEmpty ||
        confirmedChange.changes.whereType<IntentionRelationCountsChanged>().any(
          (change) => change.intentionId == _intentionId,
        );
    if (!affectsIntention ||
        !_acceptSnapshotRevision(confirmedChange.revision)) {
      return;
    }
    if (deleted) {
      _advanceGeneration();
      _isDeleted = true;
      _observationSubscription?.close();
      _observationSubscription = null;
      state = const IntentionDetailsDeleted();
      return;
    }
    _advanceGeneration();
    _preserveAuthoritativeStateWhileLoading = true;
    // Пакет задаёт барьер; поля и сводка публикуются цельным снимком.
    _startObservation();
    // Координатор уже снял занятость, а прежний снимок остаётся на экране
    // до перечитывания: правка не должна начаться с устаревшего текста.
    final current = state;
    if (current is IntentionDetailsLoaded) {
      state = current.copyWith(isAwaitingConfirmedSnapshot: true);
    }
  }

  /// Читает состав при запуске и передаёт выбранный вариант. Отказ чтения
  /// координатор принимает как отказ самой операции.
  Future<IntentionCommandCompletion?> _startCascadeOperation(
    _CascadeDecision decision,
  ) async {
    final operation = decision.operation;
    final current = state;
    if (current is! IntentionDetailsLoaded ||
        _isReadingCascadePreview ||
        !_isCascadeOperationApplicable(current, operation)) {
      return null;
    }
    final intentionId = _intentionId;
    final _OperationStart? start;
    _isReadingCascadePreview = true;
    try {
      final preview = await ref
          .read(personalGraphRepositoryProvider)
          .previewCurrentCascade(
            IntentionCascadeSubject(intentionId),
            operation,
          );
      start = await _decide(intentionId, decision, preview);
    } finally {
      _isReadingCascadePreview = false;
    }
    if (start == null) return null;
    // Выбор уже сделан, поэтому уход со страницы во время чтения не отменяет
    // операцию.
    return _accept(
      current.intention.title,
      start,
      releasesInitiator: operation == CascadeOperation.delete,
    );
  }

  /// Строит команду из варианта, выбранного человеком; `null` — отказ.
  /// Команда исполняет состав именно этого варианта плана (D7).
  Future<_OperationStart?> _decide(
    IntentionId intentionId,
    _CascadeDecision decision,
    CascadePreviewResult preview,
  ) async {
    switch ((decision, preview)) {
      case (_, final CascadePreviewFailure failure):
        return _PreviewFailureStart(decision.operation, failure);
      case (
        final _VariantQuestion question,
        ArchiveCascadePreview(:final plan),
      ):
        final choice = await question.ask(
          plan.asksQuestion ? plan.withSupporting.departing.length : 0,
        );
        if (choice == null) return null;
        return _CommandStart(
          ArchiveIntention(
            intentionId,
            execution: CascadeExecution.of(plan, choice),
          ),
        );
      case (
        final _VariantQuestion question,
        RestoreCascadePreview(:final plan),
      ):
        final choice = await question.ask(
          plan.asksQuestion ? plan.withSupporting.restored.length : 0,
        );
        if (choice == null) return null;
        return _CommandStart(
          RestoreIntention(
            intentionId,
            execution: CascadeExecution.of(plan, choice),
          ),
        );
      case (
        _DeletionConfirmation(:final confirm),
        final IntentionDeleteCascadePreview preview,
      ):
        final choice = await confirm(preview);
        if (choice == null) return null;
        final plan = preview.plan;
        return _CommandStart(
          DeleteIntention(
            intentionId,
            execution: CascadeExecution.of(plan, choice),
          ),
        );
      // Вид предпросмотра соответствует операции; иной вид, включая
      // удаление связи, — отказ чтения, а не команда.
      case _:
        return _PreviewFailureStart(
          decision.operation,
          const CascadePreviewUnexpected(),
        );
    }
  }

  /// Отказ операции предъявляет общая поверхность. У изменения вида,
  /// архивирования и восстановления права инициатора нет, а право удаления
  /// страница освобождает сразу при принятии: renderer отказа она не держит.
  Future<IntentionCommandCompletion>? _accept(
    String presentationTitle,
    _OperationStart start, {
    required bool releasesInitiator,
  }) {
    final acceptance = switch (start) {
      _CommandStart(:final command) => _coordinator.acceptExisting(
        command,
        presentationTitle: presentationTitle,
      ),
      _PreviewFailureStart(:final operation, :final failure) =>
        _coordinator.acceptIntentionPreviewFailure(
          intentionId: _intentionId,
          operation: operation,
          failure: failure,
          presentationTitle: presentationTitle,
        ),
    };
    final isShown = ref.mounted && !_isDeleted;
    switch (acceptance) {
      case IntentionCommandAccepted(:final token, :final future):
        if (releasesInitiator) {
          _coordinator.releaseInitiatorPresentation(token);
        }
        if (isShown) {
          state = _withOperationRunning(state, true);
        }
        return future;
      case IntentionCommandAlreadyRunning():
        if (isShown) {
          state = _withOperationRunning(state, true);
        }
      case GraphCommandCoordinatorDraining():
        // Замена графа ничего не начинает; повтор — новое действие.
        break;
    }
    return null;
  }

  bool _isCascadeOperationApplicable(
    IntentionDetailsLoaded loaded,
    CascadeOperation operation,
  ) => switch (operation) {
    CascadeOperation.archive =>
      loaded.intention.archiveState == IntentionArchiveState.active,
    CascadeOperation.restore =>
      loaded.intention.archiveState == IntentionArchiveState.archived,
    CascadeOperation.delete => true,
  };

  void _scheduleGateRefresh() {
    unawaited(
      Future<void>.microtask(() {}).then((_) => refreshOperationRunning()),
    );
  }

  void _advanceGeneration() {
    _generation = _generation.next();
  }

  bool _acceptSnapshotRevision(GraphRevision revision) {
    final accepted = _acceptedRevision;
    if (accepted != null &&
        revision.compareTo(accepted) == GraphRevisionOrder.older) {
      return false;
    }
    _acceptedRevision = revision;
    return true;
  }

  bool get _isOperationRunning => _coordinator.isRunning(_intentionId);

  IntentionDetailsState _stateFromObservation(
    AsyncValue<Result<GraphSnapshot<application.IntentionDetails?>>>
    observation,
  ) => observation.when(
    data: (result) => _stateFromResult(result, _isOperationRunning),
    error: (_, _) =>
        IntentionDetailsUnexpected(isOperationRunning: _isOperationRunning),
    loading: () =>
        IntentionDetailsLoading(isOperationRunning: _isOperationRunning),
  );

  IntentionDetailsState _stateFromResult(
    Result<GraphSnapshot<application.IntentionDetails?>> result,
    bool isOperationRunning,
  ) => switch (result) {
    ResultSuccess(
      value: GraphSnapshot(
        value: final application.IntentionDetails details,
        :final revision,
      ),
    ) =>
      IntentionDetailsLoaded(
        details: details,
        revision: revision,
        isOperationRunning: isOperationRunning,
      ),
    ResultSuccess(value: GraphSnapshot(value: null)) =>
      IntentionDetailsNotFound(isOperationRunning: isOperationRunning),
    ResultFailure(failure: IntentionUnavailableFailure()) =>
      IntentionDetailsUnavailable(isOperationRunning: isOperationRunning),
    ResultFailure(failure: IntentionCorruptionFailure()) =>
      IntentionDetailsCorruption(isOperationRunning: isOperationRunning),
    ResultFailure(
      failure: IntentionValidationFailure() ||
          IntentionNotFoundFailure() ||
          IntentionConflictFailure() ||
          IntentionCascadeConflictFailure() ||
          IntentionCascadePreviewFailure() ||
          IntentionUnexpectedFailure(),
    ) =>
      IntentionDetailsUnexpected(isOperationRunning: isOperationRunning),
  };

  IntentionDetailsState _withOperationRunning(
    IntentionDetailsState current,
    bool isOperationRunning,
  ) => switch (current) {
    IntentionDetailsLoading() => IntentionDetailsLoading(
      isOperationRunning: isOperationRunning,
    ),
    IntentionDetailsLoaded() => current.copyWith(
      isOperationRunning: isOperationRunning,
    ),
    IntentionDetailsNotFound() => IntentionDetailsNotFound(
      isOperationRunning: isOperationRunning,
    ),
    IntentionDetailsUnavailable() => IntentionDetailsUnavailable(
      isOperationRunning: isOperationRunning,
    ),
    IntentionDetailsCorruption() => IntentionDetailsCorruption(
      isOperationRunning: isOperationRunning,
    ),
    IntentionDetailsUnexpected() => IntentionDetailsUnexpected(
      isOperationRunning: isOperationRunning,
    ),
    IntentionDetailsDeleted() => current,
  };
}
