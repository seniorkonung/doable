import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/cascade/intention_cascade.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_description.dart';
import '../../domain/long_term_relation_id.dart';
import 'relation_details_state.dart';

part 'relation_details_view_model.g.dart';

/// Поколение наблюдения: повтор делает ответы прежнего чтения непригодными.
final class _RelationObservationGeneration {
  const _RelationObservationGeneration(this.value);

  static const initial = _RelationObservationGeneration(0);

  final int value;

  _RelationObservationGeneration next() =>
      _RelationObservationGeneration(value + 1);

  @override
  bool operator ==(Object other) =>
      other is _RelationObservationGeneration && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

@riverpod
Stream<LongTermRelationReadResult> _relationDetailsObservation(
  Ref ref,
  LongTermRelationId relationId,
  _RelationObservationGeneration generation,
) => ref.watch(personalGraphRepositoryProvider).watchRelation(relationId);

/// Подробные данные одной связи с актуальными участниками.
///
/// Наблюдение перечитывает зависимости самостоятельно, поэтому просмотр не
/// подписывается на весь граф. Запоздалый ответ более старой ревизии или
/// прежнего поколения не отменяет подтверждённые данные.
@riverpod
final class RelationDetailsViewModel extends _$RelationDetailsViewModel {
  late LongTermRelationId _relationId;
  late GraphCommandCoordinator _coordinator;
  late _RelationObservationGeneration _generation;
  late StreamSubscription<GraphCommandCompletion> _completionSubscription;
  ProviderSubscription<AsyncValue<LongTermRelationReadResult>>?
  _observationSubscription;
  GraphRevision? _acceptedRevision;
  _Command? _command;

  /// Значения, с которыми сравнивается правка. После подтверждения они новее
  /// показанного снимка, пока наблюдение не прочитает его заново.
  ({LongTermRelation relation, LongTermRelationDescription? description})?
  _confirmed;

  /// Право отказа правки, которое публикует текущее состояние.
  GraphInitiatorPresentationClaim? _publishedEditFailureClaim;
  var _isTerminated = false;
  var _isReadingCascadePreview = false;

  @override
  RelationDetailsState build(LongTermRelationId relationId) {
    _relationId = relationId;
    _generation = _RelationObservationGeneration.initial;
    _acceptedRevision = null;
    _confirmed = null;
    _isTerminated = false;
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _completionSubscription = _coordinator.completions.listen(
      _handleCompletion,
    );
    listenSelf(
      (_, next) => _publishEditFailureClaim(switch (next) {
        RelationDetailsLoaded(:final editFailure) =>
          editFailure?.failurePresentation,
        _ => null,
      }),
    );
    ref.onDispose(() {
      final active = _command;
      if (active != null) {
        _coordinator.releaseInitiatorPresentation(active.token);
      }
      _publishEditFailureClaim(null);
      _observationSubscription?.close();
      unawaited(_completionSubscription.cancel());
    });
    return _stateFromObservation(_startObservation());
  }

  /// Повторяет чтение после устранимого отказа.
  void retry() {
    if (!state.canRetry) {
      return;
    }
    _generation = _generation.next();
    final current = state;
    if (current is RelationDetailsLoaded) {
      state = current.copyWith(
        isOperationRunning: _isOperationRunning,
        refreshStatus: const RelationDetailsRefreshing(),
      );
      _startObservation();
      return;
    }
    state = _stateFromObservation(_startObservation());
  }

  /// Меняет тип активной связи: архивированная сохраняет его до восстановления.
  void changeType(LongTermRelationType type) {
    final relation = _confirmed?.relation;
    if (relation == null ||
        relation.type == type ||
        relation.scope == RelationScope.archived) {
      return;
    }
    _startEdit(LongTermRelationPatch(type: LongTermRelationFieldSet(type)));
  }

  /// Меняет приоритет активной или архивированной связи.
  void changePriority(RelationPriority priority) {
    final relation = _confirmed?.relation;
    if (relation == null || relation.priority == priority) {
      return;
    }
    _startEdit(
      LongTermRelationPatch(priority: LongTermRelationFieldSet(priority)),
    );
  }

  /// Проверяет [text] и сохраняет его описанием связи.
  ///
  /// Успех относится только к собственной принятой команде, как у [delete].
  Future<RelationDescriptionSaveOutcome> saveDescription(String text) async {
    final confirmed = _confirmed;
    if (confirmed == null) {
      return const RelationDescriptionSaveFailed();
    }

    final LongTermRelationDescription? description;
    try {
      description = LongTermRelationDescription.fromInput(text);
    } on LongTermRelationTextValidationException catch (exception) {
      return RelationDescriptionInvalid(exception.failure.reason);
    }
    if (description == confirmed.description) {
      return const RelationDescriptionUnchanged();
    }

    final relationId = _relationId;
    final completion = await _startEdit(
      LongTermRelationPatch(
        description: description == null
            ? const LongTermRelationDescriptionCleared()
            : LongTermRelationDescriptionReplaced(description),
      ),
    );
    return switch (completion?.result) {
      GraphResultSuccess(value: LongTermRelationUpdated(:final relation))
          when relation.id == relationId =>
        const RelationDescriptionSaved(),
      _ => const RelationDescriptionSaveFailed(),
    };
  }

  /// Архивирует активную связь независимо от состояния её участников.
  void archive([Future<CascadeChoice?> Function(int count)? choose]) =>
      unawaited(
        _startLifecycleChange(
          RelationDetailsLifecycleKind.archive,
          _Change.new,
          choose: choose,
        ),
      );

  /// Восстанавливает архивную связь вместе с архивными участниками.
  void restore([Future<CascadeChoice?> Function(int count)? choose]) =>
      unawaited(
        _startLifecycleChange(
          RelationDetailsLifecycleKind.restore,
          _Change.new,
          choose: choose,
        ),
      );

  /// Возвращает успех только собственной принятой команды удаления.
  /// Общее состояние данных по ID не передаёт право закрытия другим страницам.
  ///
  /// Снимок без связи до исхода команды не показан, а после подтверждения
  /// состояние становится [RelationDetailsOwnDeletionConfirmed], прежнее
  /// содержимое которого показывает только [initiator].
  Future<bool> delete(
    RelationDeletionInitiator initiator, {
    Future<CascadeChoice?> Function(RelationDeleteCascadePreview preview)?
    confirmDeletion,
  }) async {
    final relationId = _relationId;
    final completion = await _startLifecycleChange(
      RelationDetailsLifecycleKind.delete,
      (token) => _Deletion(token, initiator),
      confirmDeletion: confirmDeletion,
    );
    return switch (completion?.result) {
      GraphResultSuccess(value: LongTermRelationDeleted(:final relation)) =>
        relation.id == relationId,
      _ => false,
    };
  }

  /// Панель [initiator], перекрытая в момент подтверждения своего удаления,
  /// сама не закрывается и отказывается от прежнего содержимого.
  void releaseDeletedContent(RelationDeletionInitiator initiator) {
    if (state case RelationDetailsOwnDeletionConfirmed(initiator: final owner)
        when identical(owner, initiator)) {
      state = const RelationDetailsDeleted();
    }
  }

  /// Повторяет доказанно устранимый отказ архивирования или восстановления.
  /// Удаление повторяет начинающая его панель через [delete].
  void retryLifecycleChange([
    Future<CascadeChoice?> Function(int count, {required bool restoring})?
    choose,
  ]) {
    final current = state;
    final change = current is RelationDetailsLoaded
        ? current.lifecycleChange
        : null;
    if (change is! RelationDetailsLifecycleFailed || !change.canRetry) {
      return;
    }
    switch (change.kind) {
      case RelationDetailsLifecycleKind.archive ||
          RelationDetailsLifecycleKind.restore:
        unawaited(
          _startLifecycleChange(
            change.kind,
            _Change.new,
            choose: choose == null
                ? null
                : (count) => choose(
                    count,
                    restoring:
                        change.kind == RelationDetailsLifecycleKind.restore,
                  ),
          ),
        );
      case RelationDetailsLifecycleKind.delete:
        break;
    }
  }

  /// Отправляет правку, если координатор её принял: пока операция этой связи
  /// выполняется, новая не встаёт в очередь. Поля меняет только новый снимок.
  Future<LongTermRelationCommandCompletion>? _startEdit(
    LongTermRelationPatch patch,
  ) {
    final current = state;
    if (current is! RelationDetailsLoaded) {
      return null;
    }

    switch (_coordinator.acceptRelationUpdate(
      UpdateLongTermRelation(relationId: _relationId, patch: patch),
    )) {
      case LongTermRelationCommandAccepted(:final token, :final future):
        _command = _Change(token);
        state = current.copyWith(
          isOperationRunning: true,
          clearEditFailure: true,
        );
        unawaited(_finishEdit(future));
        return future;
      case LongTermRelationCommandAlreadyRunning():
        state = current.copyWith(isOperationRunning: true);
      case GraphCommandCoordinatorDraining():
        state = current.copyWith(
          editFailure: const RelationDetailsEditFailure(
            LongTermRelationUnexpectedFailure(),
          ),
        );
    }
    return null;
  }

  Future<void> _finishEdit(
    Future<LongTermRelationCommandCompletion> future,
  ) async {
    final completion = await future;
    if (!ref.mounted || !identical(_command?.token, completion.token)) {
      return;
    }

    _command = null;
    final failure = switch (completion.result) {
      GraphResultFailure(:final failure) => failure,
      GraphResultSuccess(value: LongTermRelationUpdated()) => null,
      GraphResultSuccess() => const LongTermRelationUnexpectedFailure(),
    };
    if (failure == null) {
      return;
    }
    final current = state;
    if (current is! RelationDetailsLoaded) {
      _coordinator.releaseInitiatorPresentation(completion.token);
      return;
    }
    state = current.copyWith(
      isOperationRunning: _isOperationRunning,
      editFailure: RelationDetailsEditFailure(
        failure,
        failurePresentation: _coordinator.claimInitiatorFailure(
          completion.token,
        ),
      ),
    );
  }

  /// Учитывает право отказа, которое публикует состояние, и передаёт общей
  /// поверхности прежнее право, переставшее публиковаться. Право, уже
  /// подтверждённое renderer, координатор повторно не выдаёт.
  void _publishEditFailureClaim(GraphInitiatorPresentationClaim? claim) {
    final previous = _publishedEditFailureClaim;
    _publishedEditFailureClaim = claim;
    if (previous != null && !identical(previous, claim)) {
      _coordinator.releaseInitiatorClaim(previous);
    }
  }

  /// Читает предпросмотр каскада при запуске операции и передаёт вариант
  /// выбранный вариант с его составом (D7). Отказ чтения панель
  /// показывает внутри себя, и команда не запускается.
  Future<LongTermRelationCommandCompletion?> _startLifecycleChange(
    RelationDetailsLifecycleKind kind,
    _Command Function(LongTermRelationOperationToken token) command, {
    Future<CascadeChoice?> Function(int count)? choose,
    Future<CascadeChoice?> Function(RelationDeleteCascadePreview preview)?
    confirmDeletion,
  }) async {
    final initial = state;
    if (initial is! RelationDetailsLoaded ||
        _isOperationRunning ||
        _isReadingCascadePreview ||
        !_isLifecycleChangeApplicable(initial, kind)) {
      return null;
    }

    final relationId = _relationId;
    final CascadePreviewResult preview;
    _isReadingCascadePreview = true;
    try {
      preview = await ref
          .read(personalGraphRepositoryProvider)
          .previewCurrentCascade(
            RelationCascadeSubject(relationId),
            switch (kind) {
              RelationDetailsLifecycleKind.archive => CascadeOperation.archive,
              RelationDetailsLifecycleKind.restore => CascadeOperation.restore,
              RelationDetailsLifecycleKind.delete => CascadeOperation.delete,
            },
          );
    } catch (_) {
      _isReadingCascadePreview = false;
      rethrow;
    }
    CascadeChoice? choice = CascadeChoice.withSupporting;
    final count = switch (preview) {
      ArchiveCascadePreview(:final plan) when plan.asksQuestion =>
        plan.withSupporting.departing.length,
      RestoreCascadePreview(:final plan) when plan.asksQuestion =>
        plan.withSupporting.restored
            .toSet()
            .difference(plan.onlyThis.restored.toSet())
            .length,
      _ => 0,
    };
    try {
      if (preview is RelationDeleteCascadePreview && confirmDeletion != null) {
        choice = await confirmDeletion(preview);
      } else if (count > 0) {
        choice = await choose?.call(count);
      }
    } finally {
      _isReadingCascadePreview = false;
    }
    if (choice == null) return null;
    // Отказ операции панели принадлежит самой панели, поэтому без неё
    // операция не начинается.
    final current = ref.mounted && !_isTerminated ? state : null;
    if (current is! RelationDetailsLoaded ||
        !_isLifecycleChangeApplicable(current, kind)) {
      return null;
    }

    final LongTermRelationCommandStart start;
    switch (preview) {
      case ArchiveCascadePreview(:final plan):
        start = _coordinator.acceptRelationArchive(
          ArchiveLongTermRelation(
            relationId,
            execution: CascadeExecution(
              choice: choice,
              expected: choice == CascadeChoice.onlyThis
                  ? plan.onlyThis
                  : plan.withSupporting,
            ),
          ),
        );
      case RestoreCascadePreview(:final plan):
        start = _coordinator.acceptRelationRestore(
          RestoreLongTermRelation(
            relationId,
            execution: CascadeExecution(
              choice: choice,
              expected: choice == CascadeChoice.onlyThis
                  ? plan.onlyThis
                  : plan.withSupporting,
            ),
          ),
        );
      case RelationDeleteCascadePreview(:final plan):
        start = _coordinator.acceptRelationDelete(
          DeleteLongTermRelation(
            relationId,
            execution: CascadeExecution(
              choice: choice,
              expected: choice == CascadeChoice.onlyThis
                  ? plan.onlyThis
                  : plan.withSupporting,
            ),
          ),
        );
      // Предпросмотр связи не бывает предпросмотром удаления намерения.
      case IntentionDeleteCascadePreview():
        state = current.copyWith(
          lifecycleChange: RelationDetailsLifecyclePreviewFailed(
            kind,
            const CascadePreviewUnexpected(),
          ),
        );
        return null;
      case CascadePreviewFailure():
        state = current.copyWith(
          lifecycleChange: RelationDetailsLifecyclePreviewFailed(kind, preview),
        );
        return null;
    }
    switch (start) {
      case LongTermRelationCommandAccepted(:final token, :final future):
        _command = command(token);
        state = current.copyWith(
          isOperationRunning: true,
          lifecycleChange: RelationDetailsLifecycleRunning(kind),
          clearEditFailure: true,
        );
        unawaited(_finishLifecycleChange(kind, future));
        return future;
      case LongTermRelationCommandAlreadyRunning():
        state = current.copyWith(isOperationRunning: true);
      case GraphCommandCoordinatorDraining():
        state = current.copyWith(
          lifecycleChange: RelationDetailsLifecycleCommandFailed(
            kind,
            const LongTermRelationUnexpectedFailure(),
          ),
        );
    }
    return null;
  }

  bool _isLifecycleChangeApplicable(
    RelationDetailsLoaded loaded,
    RelationDetailsLifecycleKind kind,
  ) => switch (kind) {
    RelationDetailsLifecycleKind.archive =>
      loaded.details.relation.scope == RelationScope.active,
    RelationDetailsLifecycleKind.restore =>
      loaded.details.relation.scope == RelationScope.archived,
    RelationDetailsLifecycleKind.delete => true,
  };

  Future<void> _finishLifecycleChange(
    RelationDetailsLifecycleKind kind,
    Future<LongTermRelationCommandCompletion> future,
  ) async {
    try {
      final completion = await future;
      final command = _command;
      if (!ref.mounted ||
          command == null ||
          !identical(command.token, completion.token)) {
        return;
      }

      _command = null;
      final RelationDetailsLoaded current;
      switch ((command, completion.result, state)) {
        // Подтверждённое удаление сохраняет прежнее содержимое для закрытия.
        case (
              _Deletion(:final initiator) ||
                  _DeletionRelationMissing(:final initiator),
              GraphResultSuccess(
                value: LongTermRelationDeleted(:final relation),
              ),
              final RelationDetailsLoaded shown,
            )
            when relation.id == _relationId:
          state = _terminateAsOwnDeletion(shown, initiator);
          return;
        // Иначе проявляется отложенный снимок без связи.
        case (_DeletionRelationMissing(), _, _):
          if (completion.isFailure) {
            _coordinator.releaseInitiatorPresentation(completion.token);
          }
          state = _terminateAsNotFound();
          return;
        case (_Change() || _Deletion(), _, final RelationDetailsLoaded loaded):
          current = loaded;
        case (_Change() || _Deletion(), _, _):
          if (completion.isFailure) {
            _coordinator.releaseInitiatorPresentation(completion.token);
          }
          return;
      }
      state = switch (completion.result) {
        GraphResultSuccess(value: LongTermRelationUpdated(:final relation))
            when relation.id == _relationId &&
                _scopeMatchesLifecycleKind(relation.scope, kind) =>
          current.copyWith(clearLifecycleChange: true),
        GraphResultSuccess() => current.copyWith(
          lifecycleChange: RelationDetailsLifecycleCommandFailed(
            kind,
            const LongTermRelationUnexpectedFailure(),
          ),
        ),
        GraphResultFailure(:final failure) => current.copyWith(
          lifecycleChange: RelationDetailsLifecycleCommandFailed(
            kind,
            failure,
            failurePresentation: _coordinator.claimInitiatorFailure(
              completion.token,
            ),
          ),
        ),
      };
      _scheduleGateRefresh();
    } on Object {
      if (!ref.mounted) {
        return;
      }
      final active = _command;
      _command = null;
      if (active != null) {
        _coordinator.releaseInitiatorPresentation(active.token);
      }
      final current = state;
      if (current is RelationDetailsLoaded) {
        state = current.copyWith(
          lifecycleChange: RelationDetailsLifecycleCommandFailed(
            kind,
            const LongTermRelationUnexpectedFailure(),
          ),
        );
      }
      _scheduleGateRefresh();
    }
  }

  bool _scopeMatchesLifecycleKind(
    RelationScope scope,
    RelationDetailsLifecycleKind kind,
  ) => switch (kind) {
    RelationDetailsLifecycleKind.archive => scope == RelationScope.archived,
    RelationDetailsLifecycleKind.restore => scope == RelationScope.active,
    RelationDetailsLifecycleKind.delete => false,
  };

  AsyncValue<LongTermRelationReadResult> _startObservation() {
    _observationSubscription?.close();
    final generation = _generation;
    final subscription = ref.listen(
      _relationDetailsObservationProvider(_relationId, generation),
      (previous, next) => _handleObservation(generation, next),
    );
    _observationSubscription = subscription;
    return subscription.read();
  }

  void _handleObservation(
    _RelationObservationGeneration generation,
    AsyncValue<LongTermRelationReadResult> observation,
  ) {
    if (!ref.mounted || _isTerminated || generation != _generation) {
      return;
    }
    if (observation case AsyncData(value: GraphResultSuccess(:final value))) {
      if (!_acceptSnapshotRevision(value.revision)) {
        return;
      }
      // Снимок без связи во время собственного удаления ждёт его исхода.
      if (value.value == null) {
        switch (_command) {
          case _Deletion(:final token, :final initiator):
            _command = _DeletionRelationMissing(token, initiator);
            return;
          case _DeletionRelationMissing():
            return;
          case _Change() || null:
            break;
        }
      }
    }
    final current = state;
    state = _stateFromObservation(
      observation,
      previousLoaded: current is RelationDetailsLoaded ? current : null,
    );
  }

  void _handleCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted || _isTerminated) {
      return;
    }
    if (completion
        case LongTermRelationCommandCompletion(
          target: ExistingLongTermRelationOperationTarget(:final relationId),
        )
        when relationId == _relationId) {
      _scheduleGateRefresh();
    }
    final confirmedChange = completion.confirmedChange;
    if (confirmedChange == null) {
      return;
    }
    final changes = confirmedChange.changes;
    final deleted = changes.whereType<LongTermRelationDeletedChange>().any(
      (change) => change.id == _relationId,
    );
    final relationChanged = changes.whereType<LongTermRelationChange>().any(
      (change) => change.id == _relationId,
    );
    final current = state;
    final participantIds = current is RelationDetailsLoaded
        ? <IntentionId>{current.details.source.id, current.details.related.id}
        : <IntentionId>{};
    final participantChanged = changes.any(
      (change) => switch (change) {
        IntentionCatalogMutation(:final before, :final after) =>
          participantIds.contains(before?.summary.id) ||
              participantIds.contains(after?.summary.id),
        LongTermRelationChange() => false,
        GraphChange() => false,
      },
    );
    if ((!relationChanged && !participantChanged) ||
        !_advanceRevisionBarrier(confirmedChange.revision)) {
      return;
    }
    if (deleted) {
      // Собственное удаление завершает исход команды, который приходит сразу
      // после этого пакета.
      if (!identical(completion.token, _command?.token)) {
        state = _terminateAsDeleted();
      }
      return;
    }
    _acceptConfirmedFields(completion, changes);
    _generation = _generation.next();
    state = switch (current) {
      RelationDetailsLoaded() => current.copyWith(
        isOperationRunning: _isOperationRunning,
        refreshStatus: const RelationDetailsRefreshing(),
      ),
      _ => RelationDetailsLoading(isOperationRunning: _isOperationRunning),
    };
    _startObservation();
  }

  /// Запоминает подтверждённые поля пакета, который прошёл барьер ревизий.
  ///
  /// Показанный снимок остаётся прежним до цельного чтения. Описание несёт
  /// только результат команды этой связи: другие пакеты его не меняют.
  void _acceptConfirmedFields(
    GraphCommandCompletion completion,
    List<GraphChange> changes,
  ) {
    final confirmed = _confirmed;
    if (confirmed == null) {
      return;
    }
    var relation = confirmed.relation;
    for (final change in changes) {
      if (change case LongTermRelationChange(:final id, after: final after?)
          when id == _relationId) {
        relation = after;
      }
    }
    _confirmed = (
      relation: relation,
      description: switch (completion) {
        LongTermRelationCommandCompletion(
          result: GraphResultSuccess(
            value: LongTermRelationUpdated(
              relation: LongTermRelation(:final id),
              :final description,
            ),
          ),
        )
            when id == _relationId =>
          description,
        _ => confirmed.description,
      },
    );
  }

  bool _advanceRevisionBarrier(GraphRevision revision) {
    final accepted = _acceptedRevision;
    if (accepted != null) {
      final order = revision.compareTo(accepted);
      if (order == GraphRevisionOrder.older ||
          order == GraphRevisionOrder.same) {
        return false;
      }
    }
    // Завершение задаёт только барьер: поля связи и участников по-прежнему
    // публикуются исключительно полным снимком watchRelation.
    _acceptedRevision = revision;
    return true;
  }

  void _scheduleGateRefresh() {
    unawaited(
      Future<void>.microtask(() {}).then((_) {
        if (!ref.mounted || _isTerminated) {
          return;
        }
        final isRunning = _isOperationRunning;
        if (state.isOperationRunning != isRunning) {
          state = _withOperationRunning(state, isRunning);
        }
      }),
    );
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

  RelationDetailsState _stateFromObservation(
    AsyncValue<LongTermRelationReadResult> observation, {
    RelationDetailsLoaded? previousLoaded,
  }) => switch (observation) {
    AsyncData(:final value) => _stateFromResult(
      value,
      previousLoaded: previousLoaded,
    ),
    AsyncError() when previousLoaded != null => previousLoaded.copyWith(
      isOperationRunning: _isOperationRunning,
      refreshStatus: const RelationDetailsRefreshUnexpected(),
    ),
    AsyncError() => RelationDetailsUnexpected(
      isOperationRunning: _isOperationRunning,
    ),
    AsyncValue<LongTermRelationReadResult>() when previousLoaded != null =>
      previousLoaded.copyWith(
        isOperationRunning: _isOperationRunning,
        refreshStatus: const RelationDetailsRefreshing(),
      ),
    AsyncValue<LongTermRelationReadResult>() => RelationDetailsLoading(
      isOperationRunning: _isOperationRunning,
    ),
  };

  RelationDetailsState _stateFromResult(
    LongTermRelationReadResult result, {
    RelationDetailsLoaded? previousLoaded,
  }) => switch (result) {
    GraphResultSuccess(
      value: GraphSnapshot(value: final details?, :final revision),
    ) =>
      _loadedFromSnapshot(details, revision, previousLoaded),
    GraphResultSuccess() => _terminateAsNotFound(),
    GraphResultFailure(failure: LongTermRelationReadUnavailableFailure()) =>
      previousLoaded?.copyWith(
            isOperationRunning: _isOperationRunning,
            refreshStatus: const RelationDetailsRefreshUnavailable(),
          ) ??
          RelationDetailsUnavailable(isOperationRunning: _isOperationRunning),
    GraphResultFailure(failure: LongTermRelationReadCorruptionFailure()) =>
      previousLoaded?.copyWith(
            isOperationRunning: _isOperationRunning,
            refreshStatus: const RelationDetailsRefreshCorruption(),
          ) ??
          RelationDetailsCorruption(isOperationRunning: _isOperationRunning),
    GraphResultFailure(failure: LongTermRelationReadUnexpectedFailure()) =>
      previousLoaded?.copyWith(
            isOperationRunning: _isOperationRunning,
            refreshStatus: const RelationDetailsRefreshUnexpected(),
          ) ??
          RelationDetailsUnexpected(isOperationRunning: _isOperationRunning),
  };

  /// Цельный снимок не снимает отказ правки: это делает только принятая
  /// операция.
  RelationDetailsLoaded _loadedFromSnapshot(
    LongTermRelationDetails details,
    GraphRevision revision,
    RelationDetailsLoaded? previousLoaded,
  ) {
    _confirmed = (relation: details.relation, description: details.description);
    return RelationDetailsLoaded(
      details: details,
      revision: revision,
      isOperationRunning: _isOperationRunning,
      editFailure: previousLoaded?.editFailure,
    );
  }

  RelationDetailsNotFound _terminateAsNotFound() {
    _terminate();
    return RelationDetailsNotFound(isOperationRunning: _isOperationRunning);
  }

  RelationDetailsDeleted _terminateAsDeleted() {
    _terminate();
    return const RelationDetailsDeleted();
  }

  RelationDetailsOwnDeletionConfirmed _terminateAsOwnDeletion(
    RelationDetailsLoaded shown,
    RelationDeletionInitiator initiator,
  ) {
    _terminate();
    // Пакет этой команды мог уже снять флаг операции, а закрывающаяся панель
    // сохраняет кадр записи с выключенными элементами.
    return RelationDetailsOwnDeletionConfirmed(
      shown.copyWith(isOperationRunning: true),
      initiator: initiator,
    );
  }

  void _terminate() {
    _isTerminated = true;
    _confirmed = null;
    _observationSubscription?.close();
    _observationSubscription = null;
    unawaited(_completionSubscription.cancel());
  }

  bool get _isOperationRunning => _coordinator.isRelationRunning(_relationId);

  RelationDetailsState _withOperationRunning(
    RelationDetailsState current,
    bool isOperationRunning,
  ) => switch (current) {
    RelationDetailsLoading() => RelationDetailsLoading(
      isOperationRunning: isOperationRunning,
    ),
    RelationDetailsLoaded() => current.copyWith(
      isOperationRunning: isOperationRunning,
    ),
    RelationDetailsNotFound() => current,
    RelationDetailsDeleted() => current,
    RelationDetailsOwnDeletionConfirmed() => current,
    RelationDetailsUnavailable() => RelationDetailsUnavailable(
      isOperationRunning: isOperationRunning,
    ),
    RelationDetailsCorruption() => RelationDetailsCorruption(
      isOperationRunning: isOperationRunning,
    ),
    RelationDetailsUnexpected() => RelationDetailsUnexpected(
      isOperationRunning: isOperationRunning,
    ),
  };
}

/// Принятая команда просмотра до её исхода.
sealed class _Command {
  const _Command(this.token);

  final LongTermRelationOperationToken token;
}

/// Правка, архивирование или восстановление связи.
final class _Change extends _Command {
  const _Change(super.token);
}

/// Удаление связи, до исхода которого снимок без связи не приходил.
final class _Deletion extends _Command {
  const _Deletion(super.token, this.initiator);

  final RelationDeletionInitiator initiator;
}

/// Удаление связи, во время которого пришёл снимок без связи. Он показан,
/// только если удаление не подтвердится.
final class _DeletionRelationMissing extends _Command {
  const _DeletionRelationMissing(super.token, this.initiator);

  final RelationDeletionInitiator initiator;
}
