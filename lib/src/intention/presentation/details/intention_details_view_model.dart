import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../application/intention_command.dart';
import '../../application/intention_catalog.dart';
import '../../application/intention_details.dart' as application;
import '../../application/intention_result.dart';
import '../../domain/intention.dart';
import '../../domain/intention_id.dart';
import 'intention_details_state.dart';

part 'intention_details_view_model.g.dart';

enum _StateChangeKind {
  enableReadiness,
  disableReadiness,
  archive,
  restore,
  delete,
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

  void enableReadiness() => _startStateChange(_StateChangeKind.enableReadiness);

  void disableReadiness() =>
      _startStateChange(_StateChangeKind.disableReadiness);

  void archive() => _startStateChange(_StateChangeKind.archive);

  void restore() => _startStateChange(_StateChangeKind.restore);

  /// Возвращает успех только собственной принятой команды удаления.
  /// Общее состояние данных по ID не передаёт право закрытия другим страницам.
  Future<bool> delete() async {
    final intentionId = _intentionId;
    final completion = await _startStateChange(_StateChangeKind.delete);
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
        ) ||
        confirmedChange.changes.whereType<DailyChoiceChange>().any(
          (change) => change.intentionCounts.containsKey(_intentionId),
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

  /// Отказ перехода предъявляет общая поверхность: страница не держит его
  /// renderer и освобождает право инициатора сразу при принятии команды.
  Future<IntentionCommandCompletion>? _startStateChange(_StateChangeKind kind) {
    final current = state;
    if (current is! IntentionDetailsLoaded ||
        !_isStateChangeApplicable(current, kind)) {
      return null;
    }

    final start = _coordinator.acceptExisting(
      _commandForStateChange(kind),
      presentationTitle: current.intention.title,
    );
    switch (start) {
      case IntentionCommandAccepted(:final token, :final future):
        _coordinator.releaseInitiatorPresentation(token);
        state = current.copyWith(isOperationRunning: true);
        return future;
      case IntentionCommandAlreadyRunning():
        state = current.copyWith(isOperationRunning: true);
      case GraphCommandCoordinatorDraining():
        // Замена графа ничего не начинает; повтор — новое действие.
        break;
    }
    return null;
  }

  ExistingIntentionCommand _commandForStateChange(_StateChangeKind kind) =>
      switch (kind) {
        _StateChangeKind.enableReadiness => EnableIntentionReadiness(
          _intentionId,
        ),
        _StateChangeKind.disableReadiness => DisableIntentionReadiness(
          _intentionId,
        ),
        _StateChangeKind.archive => ArchiveIntention(_intentionId),
        _StateChangeKind.restore => RestoreIntention(_intentionId),
        _StateChangeKind.delete => DeleteIntention(_intentionId),
      };

  bool _isStateChangeApplicable(
    IntentionDetailsLoaded loaded,
    _StateChangeKind kind,
  ) {
    final details = loaded.details;
    return switch (kind) {
      _StateChangeKind.enableReadiness =>
        details.intention.readiness == IntentionReadiness.notReady,
      _StateChangeKind.disableReadiness =>
        details.intention.readiness == IntentionReadiness.ready,
      _StateChangeKind.archive =>
        details.intention.archiveState == IntentionArchiveState.active,
      _StateChangeKind.restore =>
        details.intention.archiveState == IntentionArchiveState.archived,
      _StateChangeKind.delete => true,
    };
  }

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
          IntentionHasBlockingRelationsFailure() ||
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
