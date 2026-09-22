import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../intention/application/intention_command.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/long_term_relation_command.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import '../../shared/presentation/exclusive_operation.dart';
import 'graph_command_result.dart';
import 'graph_revision.dart';
import 'personal_graph_repository.dart';
import 'personal_graph_repository_provider.dart';

part 'graph_command_coordinator.g.dart';

enum IntentionCommandKind {
  create,
  update,
  enableReadiness,
  disableReadiness,
  archive,
  restore,
  delete,
}

sealed class GraphCommandKey {
  const GraphCommandKey();
}

final class IntentionCreationFormKey extends GraphCommandKey {
  IntentionCreationFormKey();
}

final class ExistingIntentionKey extends GraphCommandKey {
  const ExistingIntentionKey(this.intentionId);

  final IntentionId intentionId;

  @override
  bool operator ==(Object other) =>
      other is ExistingIntentionKey && other.intentionId == intentionId;

  @override
  int get hashCode => intentionId.hashCode;
}

final class LongTermRelationCreationFormKey extends GraphCommandKey {
  LongTermRelationCreationFormKey();
}

final class ExistingLongTermRelationKey extends GraphCommandKey {
  const ExistingLongTermRelationKey(this.relationId);

  final LongTermRelationId relationId;

  @override
  bool operator ==(Object other) =>
      other is ExistingLongTermRelationKey && other.relationId == relationId;

  @override
  int get hashCode => relationId.hashCode;
}

sealed class GraphOperationToken {
  const GraphOperationToken();
}

final class IntentionOperationToken extends GraphOperationToken {
  IntentionOperationToken._();

  @override
  String toString() => 'IntentionOperationToken';
}

final class LongTermRelationOperationToken extends GraphOperationToken {
  LongTermRelationOperationToken._();

  @override
  String toString() => 'LongTermRelationOperationToken';
}

sealed class GraphCommandCompletion {
  const GraphCommandCompletion();

  GraphOperationToken get token;
  ConfirmedGraphChangePackage? get confirmedChange;

  GraphRevision? get revision => confirmedChange?.revision;

  /// Отличает отказ от успеха без знания конкретной предметной операции.
  ///
  /// Владение предъявлением одинаково для намерений и связей: успех сразу
  /// принадлежит оболочке, а отказ — открытой экранной сессии инициатора.
  bool get isFailure;
}

final class IntentionCommandCompletion extends GraphCommandCompletion {
  const IntentionCommandCompletion._({
    required this.token,
    required this.kind,
    required this.target,
    required this.confirmedResult,
  });

  @override
  final IntentionOperationToken token;
  final IntentionCommandKind kind;
  final IntentionOperationTarget target;
  final Result<ConfirmedGraphResult<IntentionCommandSuccess>> confirmedResult;

  Result<IntentionCommandSuccess> get result => switch (confirmedResult) {
    ResultSuccess(:final value) => ResultSuccess(value.value),
    ResultFailure(:final failure) => ResultFailure(failure),
  };

  @override
  ConfirmedGraphChangePackage? get confirmedChange => switch (confirmedResult) {
    ResultSuccess(:final value) => value,
    ResultFailure() => null,
  };

  @override
  bool get isFailure => switch (confirmedResult) {
    ResultSuccess() => false,
    ResultFailure() => true,
  };

  String? get presentationTitle => switch (result) {
    ResultSuccess(value: IntentionSaved(:final intention)) => intention.title,
    ResultSuccess(value: IntentionDeleted()) ||
    ResultFailure() => switch (target) {
      ExistingIntentionOperationTarget(:final title) => title,
      CreatingIntentionOperationTarget() => null,
    },
  };
}

enum LongTermRelationCommandKind { create, update, archive, restore, delete }

final class LongTermRelationCommandCompletion extends GraphCommandCompletion {
  const LongTermRelationCommandCompletion._({
    required this.token,
    required this.kind,
    required this.target,
    required this.confirmedResult,
  });

  @override
  final LongTermRelationOperationToken token;
  final LongTermRelationCommandKind kind;
  final LongTermRelationOperationTarget target;
  final LongTermRelationCommandResult confirmedResult;

  GraphResult<LongTermRelationCommandSuccess, LongTermRelationCommandFailure>
  get result => switch (confirmedResult) {
    GraphResultSuccess(:final value) => GraphResultSuccess(value.value),
    GraphResultFailure(:final failure) => GraphResultFailure(failure),
  };

  @override
  ConfirmedGraphChangePackage? get confirmedChange => switch (confirmedResult) {
    GraphResultSuccess(:final value) => value,
    GraphResultFailure() => null,
  };

  @override
  bool get isFailure => switch (confirmedResult) {
    GraphResultSuccess() => false,
    GraphResultFailure() => true,
  };
}

sealed class IntentionOperationTarget {
  const IntentionOperationTarget();
}

final class CreatingIntentionOperationTarget extends IntentionOperationTarget {
  const CreatingIntentionOperationTarget();
}

final class ExistingIntentionOperationTarget extends IntentionOperationTarget {
  const ExistingIntentionOperationTarget({
    required this.intentionId,
    required this.title,
  });

  final IntentionId intentionId;
  final String title;
}

sealed class LongTermRelationOperationTarget {
  const LongTermRelationOperationTarget();
}

final class CreatingLongTermRelationOperationTarget
    extends LongTermRelationOperationTarget {
  const CreatingLongTermRelationOperationTarget();
}

final class ExistingLongTermRelationOperationTarget
    extends LongTermRelationOperationTarget {
  const ExistingLongTermRelationOperationTarget(this.relationId);

  final LongTermRelationId relationId;
}

sealed class IntentionCommandStart {
  const IntentionCommandStart();
}

final class IntentionCommandAccepted extends IntentionCommandStart {
  const IntentionCommandAccepted({required this.token, required this.future});

  final IntentionOperationToken token;
  final Future<IntentionCommandCompletion> future;
}

final class IntentionCommandAlreadyRunning extends IntentionCommandStart {
  const IntentionCommandAlreadyRunning();
}

sealed class LongTermRelationCommandStart {
  const LongTermRelationCommandStart();
}

final class LongTermRelationCommandAccepted
    extends LongTermRelationCommandStart {
  const LongTermRelationCommandAccepted({
    required this.token,
    required this.future,
  });

  final LongTermRelationOperationToken token;
  final Future<LongTermRelationCommandCompletion> future;
}

final class LongTermRelationCommandAlreadyRunning
    extends LongTermRelationCommandStart {
  const LongTermRelationCommandAlreadyRunning();
}

final class GraphCommandCoordinatorDraining extends IntentionCommandStart
    implements LongTermRelationCommandStart {
  const GraphCommandCoordinatorDraining();
}

/// Исключительное право конкретного владельца предъявить terminal outcome.
///
/// Удержание claim само по себе не означает предъявления: подтверждать его
/// может только компонент, получивший свидетельство первого доступного кадра.
sealed class GraphPresentationClaim {
  const GraphPresentationClaim._(this.token, this.completion, this._entry);

  final GraphOperationToken token;
  final GraphCommandCompletion completion;
  final _PresentationEntry _entry;
}

/// Право открытой экранной сессии предъявить собственную ошибку.
final class GraphInitiatorPresentationClaim extends GraphPresentationClaim {
  const GraphInitiatorPresentationClaim._(
    super.token,
    super.completion,
    super._entry,
  ) : super._();
}

/// Право оболочки предъявить success либо fallback-ошибку.
final class GraphAppPresentationClaim extends GraphPresentationClaim {
  const GraphAppPresentationClaim._(
    super.token,
    super.completion,
    super._entry,
    this._registration,
  ) : super._();

  final GraphAppPresentationRegistration _registration;
}

/// Регистрация получателя общего app-канала предъявления.
///
/// Одновременно выдачу получает только самая ранняя действующая регистрация,
/// и у неё не больше одного неподтверждённого claim. Освобождение возвращает
/// coordinator выданный неподтверждённый claim и ожидающий запрос.
final class GraphAppPresentationRegistration {
  GraphAppPresentationRegistration._(this._coordinator);

  final GraphCommandCoordinator _coordinator;
  Completer<GraphAppPresentationClaim?>? _request;
  GraphAppPresentationClaim? _issued;
  var _isReleased = false;

  /// Запрашивает следующий доступный app-результат в порядке публикации.
  ///
  /// Возвращает `null`, если регистрация освобождена или coordinator завершил
  /// работу до выдачи.
  Future<GraphAppPresentationClaim?> nextClaim() =>
      _coordinator._requestAppClaim(this);

  void release() => _coordinator._releaseRegistration(this);
}

@Riverpod(keepAlive: true)
final class GraphCommandCoordinator extends _$GraphCommandCoordinator {
  final _completionController =
      StreamController<GraphCommandCompletion>.broadcast(sync: true);
  // Публикация завершений последовательна в порядке принятия, поэтому порядок
  // вставки совпадает с порядком публикации terminal outcome.
  final _entries = <GraphOperationToken, _PresentationEntry>{};
  final _registrations = <GraphAppPresentationRegistration>[];
  final _gates =
      <GraphCommandKey, ExclusiveOperation<GraphCommandCompletion>>{};
  final _inFlight = <Future<void>>{};
  late GraphCommandRepository _repository;
  Future<void> _publicationTail = Future<void>.value();
  var _isDraining = false;
  Completer<void>? _shutdownCompleter;

  @override
  void build() {
    _repository = ref.watch(personalGraphRepositoryProvider);
  }

  Stream<GraphCommandCompletion> get completions =>
      _completionController.stream;

  Stream<IntentionCommandCompletion> get intentionCompletions =>
      _completionController.stream
          .where((completion) => completion is IntentionCommandCompletion)
          .map((completion) => completion as IntentionCommandCompletion);

  bool isRunning(IntentionId intentionId) =>
      isKeyRunning(ExistingIntentionKey(intentionId));

  bool isRelationRunning(LongTermRelationId relationId) =>
      isKeyRunning(ExistingLongTermRelationKey(relationId));

  bool isKeyRunning(GraphCommandKey key) => _gates[key]?.isRunning ?? false;

  IntentionCommandStart acceptCreation(
    IntentionCreationFormKey formKey,
    CreateIntention command,
  ) => _accept(formKey, command, const CreatingIntentionOperationTarget());

  IntentionCommandStart acceptExisting(
    ExistingIntentionCommand command, {
    required String presentationTitle,
  }) => _accept(
    ExistingIntentionKey(command.id),
    command,
    ExistingIntentionOperationTarget(
      intentionId: command.id,
      title: presentationTitle,
    ),
  );

  LongTermRelationCommandStart acceptRelationCreation(
    LongTermRelationCreationFormKey formKey,
    CreateLongTermRelation command,
  ) => _acceptRelation(
    key: formKey,
    command: command,
    kind: LongTermRelationCommandKind.create,
    target: const CreatingLongTermRelationOperationTarget(),
  );

  LongTermRelationCommandStart acceptRelationUpdate(
    UpdateLongTermRelation command,
  ) => _acceptRelation(
    key: ExistingLongTermRelationKey(command.relationId),
    command: command,
    kind: LongTermRelationCommandKind.update,
    target: ExistingLongTermRelationOperationTarget(command.relationId),
  );

  LongTermRelationCommandStart acceptRelationArchive(
    ArchiveLongTermRelation command,
  ) => _acceptRelation(
    key: ExistingLongTermRelationKey(command.relationId),
    command: command,
    kind: LongTermRelationCommandKind.archive,
    target: ExistingLongTermRelationOperationTarget(command.relationId),
  );

  LongTermRelationCommandStart acceptRelationRestore(
    RestoreLongTermRelation command,
  ) => _acceptRelation(
    key: ExistingLongTermRelationKey(command.relationId),
    command: command,
    kind: LongTermRelationCommandKind.restore,
    target: ExistingLongTermRelationOperationTarget(command.relationId),
  );

  LongTermRelationCommandStart acceptRelationDelete(
    DeleteLongTermRelation command,
  ) => _acceptRelation(
    key: ExistingLongTermRelationKey(command.relationId),
    command: command,
    kind: LongTermRelationCommandKind.delete,
    target: ExistingLongTermRelationOperationTarget(command.relationId),
  );

  LongTermRelationCommandStart _acceptRelation({
    required GraphCommandKey key,
    required LongTermRelationCommand command,
    required LongTermRelationCommandKind kind,
    required LongTermRelationOperationTarget target,
  }) {
    final token = LongTermRelationOperationToken._();
    final acceptance = _acceptOperation(
      key: key,
      entry: _PresentationEntry(token),
      execute: () async {
        final result = await _executeLongTermRelation(command);
        return LongTermRelationCommandCompletion._(
          token: token,
          kind: kind,
          target: target,
          confirmedResult: result,
        );
      },
    );
    return switch (acceptance) {
      _GraphCommandAccepted(:final future) => LongTermRelationCommandAccepted(
        token: token,
        future: future.then(
          (completion) => completion as LongTermRelationCommandCompletion,
        ),
      ),
      _GraphCommandAlreadyRunning() =>
        const LongTermRelationCommandAlreadyRunning(),
      _GraphCommandDraining() => const GraphCommandCoordinatorDraining(),
    };
  }

  IntentionCommandStart _accept(
    GraphCommandKey key,
    IntentionCommand command,
    IntentionOperationTarget target,
  ) {
    final token = IntentionOperationToken._();
    final kind = _kindOf(command);
    final acceptance = _acceptOperation(
      key: key,
      entry: _PresentationEntry(token),
      execute: () async {
        final result = await _executeIntention(command);
        return IntentionCommandCompletion._(
          token: token,
          kind: kind,
          target: target,
          confirmedResult: result,
        );
      },
    );
    return switch (acceptance) {
      _GraphCommandAccepted(:final future) => IntentionCommandAccepted(
        token: token,
        future: future.then(
          (completion) => completion as IntentionCommandCompletion,
        ),
      ),
      _GraphCommandAlreadyRunning() => const IntentionCommandAlreadyRunning(),
      _GraphCommandDraining() => const GraphCommandCoordinatorDraining(),
    };
  }

  _GraphCommandAcceptance _acceptOperation({
    required GraphCommandKey key,
    required _PresentationEntry entry,
    required Future<GraphCommandCompletion> Function() execute,
  }) {
    if (_isDraining) {
      return const _GraphCommandDraining();
    }

    final gate = _gates.putIfAbsent(
      key,
      ExclusiveOperation<GraphCommandCompletion>.new,
    );
    if (gate.isRunning) {
      return const _GraphCommandAlreadyRunning();
    }

    _entries[entry.token] = entry;
    final started = gate.start(execute);
    if (started is ExclusiveOperationAlreadyRunning<GraphCommandCompletion>) {
      return const _GraphCommandAlreadyRunning();
    }
    final operation =
        started as ExclusiveOperationAccepted<GraphCommandCompletion>;
    final operationFuture = operation.future;

    unawaited(
      operationFuture.whenComplete(() {
        if (identical(_gates[key], gate) && !gate.isRunning) {
          _gates.remove(key);
        }
      }),
    );

    final completionCompleter = Completer<GraphCommandCompletion>();
    late final Future<void> tracked;
    final publication = _publicationTail.then<void>((_) async {
      final completion = await operationFuture;
      entry.completion = completion;
      _completionController.add(completion);
      completionCompleter.complete(completion);
      _dispatchAppPresentation();
    });
    _publicationTail = publication;
    tracked = publication.whenComplete(() {
      _inFlight.remove(tracked);
      _completeShutdownIfDrained();
    });
    _inFlight.add(tracked);

    return _GraphCommandAccepted(completionCompleter.future);
  }

  /// Выдаёт открытой экранной сессии право предъявить её failure.
  ///
  /// Success инициатору не выдаётся: он сразу принадлежит оболочке. После
  /// освобождения сессии или выдачи права оболочке возвращает `null`.
  GraphInitiatorPresentationClaim? claimInitiatorFailure(
    GraphOperationToken token,
  ) {
    final entry = _entries[token];
    final completion = entry?.completion;
    if (entry == null ||
        completion == null ||
        !completion.isFailure ||
        entry.initiatorReleased ||
        entry.appClaim != null) {
      return null;
    }

    return entry.initiatorClaim ??= GraphInitiatorPresentationClaim._(
      token,
      completion,
      entry,
    );
  }

  /// Завершает экранную сессию инициатора.
  ///
  /// Неподтверждённая ошибка становится доступной оболочке в своём прежнем
  /// порядке; прежний initiator claim больше не может её подтвердить.
  void releaseInitiatorPresentation(GraphOperationToken token) {
    final entry = _entries[token];
    if (entry == null || entry.initiatorReleased) {
      return;
    }

    _releaseInitiatorEntry(entry);
  }

  /// Освобождает право только пока [claim] остаётся действующим правом
  /// инициатора.
  ///
  /// Запоздалый renderer прежнего claim не может освободить право, уже
  /// переданное другому владельцу.
  void releaseInitiatorClaim(GraphInitiatorPresentationClaim claim) {
    final entry = _entries[claim.token];
    if (entry == null || !identical(entry.initiatorClaim, claim)) {
      return;
    }

    _releaseInitiatorEntry(entry);
  }

  void _releaseInitiatorEntry(_PresentationEntry entry) {
    entry.initiatorReleased = true;
    entry.initiatorClaim = null;
    _dispatchAppPresentation();
  }

  GraphAppPresentationRegistration registerAppPresentation() {
    final registration = GraphAppPresentationRegistration._(this);
    if (_shutdownCompleter?.isCompleted ?? false) {
      registration._isReleased = true;
    } else {
      _registrations.add(registration);
    }
    return registration;
  }

  /// Атомарно подтверждает фактическое предъявление действующим владельцем.
  ///
  /// Claim освобождённого или сменившегося владельца бездействует.
  void confirmPresentation(GraphPresentationClaim claim) {
    final entry = _entries[claim.token];
    if (entry == null || !identical(entry, claim._entry)) {
      return;
    }

    switch (claim) {
      case GraphInitiatorPresentationClaim():
        if (!identical(entry.initiatorClaim, claim)) {
          return;
        }
        _discardEntry(entry);
      case GraphAppPresentationClaim(:final _registration):
        if (!identical(entry.appClaim, claim)) {
          return;
        }
        if (identical(_registration._issued, claim)) {
          _registration._issued = null;
        }
        _discardEntry(entry);
        _dispatchAppPresentation();
    }
  }

  Future<void> shutdown() {
    final existing = _shutdownCompleter;
    if (existing != null) {
      return existing.future;
    }

    _isDraining = true;
    final shutdown = Completer<void>();
    _shutdownCompleter = shutdown;
    _completeShutdownIfDrained();
    return shutdown.future;
  }

  Future<GraphAppPresentationClaim?> _requestAppClaim(
    GraphAppPresentationRegistration registration,
  ) {
    if (registration._isReleased) {
      return Future.value(null);
    }
    final existing = registration._request;
    if (existing != null) {
      return existing.future;
    }

    final request = Completer<GraphAppPresentationClaim?>();
    registration._request = request;
    _dispatchAppPresentation();
    return request.future;
  }

  void _releaseRegistration(GraphAppPresentationRegistration registration) {
    if (registration._isReleased) {
      return;
    }
    registration._isReleased = true;
    _registrations.remove(registration);

    final issued = registration._issued;
    registration._issued = null;
    if (issued != null && identical(issued._entry.appClaim, issued)) {
      issued._entry.appClaim = null;
    }
    final request = registration._request;
    registration._request = null;
    if (request != null && !request.isCompleted) {
      request.complete(null);
    }
    _dispatchAppPresentation();
  }

  void _dispatchAppPresentation() {
    if (_registrations.isEmpty) {
      return;
    }
    final active = _registrations.first;
    final request = active._request;
    if (request == null || active._issued != null) {
      return;
    }
    final entry = _nextAppPresentableEntry();
    final completion = entry?.completion;
    if (entry == null || completion == null) {
      return;
    }

    final claim = GraphAppPresentationClaim._(
      entry.token,
      completion,
      entry,
      active,
    );
    entry.appClaim = claim;
    active._issued = claim;
    active._request = null;
    request.complete(claim);
  }

  _PresentationEntry? _nextAppPresentableEntry() {
    for (final entry in _entries.values) {
      final completion = entry.completion;
      if (completion == null || entry.appClaim != null) {
        continue;
      }
      final belongsToApp = !completion.isFailure || entry.initiatorReleased;
      if (belongsToApp) {
        return entry;
      }
    }
    return null;
  }

  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>
  _executeIntention(IntentionCommand command) async {
    try {
      return await _repository.execute(command);
    } on Object {
      return const ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>(
        IntentionUnexpectedFailure(),
      );
    }
  }

  Future<LongTermRelationCommandResult> _executeLongTermRelation(
    LongTermRelationCommand command,
  ) async {
    try {
      return await _repository.execute(command);
    } on Object {
      return const GraphCommandFailed<
        LongTermRelationCommandSuccess,
        LongTermRelationCommandFailure
      >(LongTermRelationUnexpectedFailure());
    }
  }

  void _discardEntry(_PresentationEntry entry) {
    if (identical(_entries[entry.token], entry)) {
      _entries.remove(entry.token);
    }
  }

  void _completeShutdownIfDrained() {
    final shutdown = _shutdownCompleter;
    if (shutdown == null || shutdown.isCompleted || _inFlight.isNotEmpty) {
      return;
    }

    _entries.clear();
    for (final registration in _registrations.toList(growable: false)) {
      registration._isReleased = true;
      registration._issued = null;
      final request = registration._request;
      registration._request = null;
      if (request != null && !request.isCompleted) {
        request.complete(null);
      }
    }
    _registrations.clear();
    _gates.clear();
    unawaited(_completionController.close());
    shutdown.complete();
  }
}

final class _PresentationEntry {
  _PresentationEntry(this.token);

  final GraphOperationToken token;
  GraphCommandCompletion? completion;
  bool initiatorReleased = false;
  GraphInitiatorPresentationClaim? initiatorClaim;
  GraphAppPresentationClaim? appClaim;
}

sealed class _GraphCommandAcceptance {
  const _GraphCommandAcceptance();
}

final class _GraphCommandAccepted extends _GraphCommandAcceptance {
  const _GraphCommandAccepted(this.future);

  final Future<GraphCommandCompletion> future;
}

final class _GraphCommandAlreadyRunning extends _GraphCommandAcceptance {
  const _GraphCommandAlreadyRunning();
}

final class _GraphCommandDraining extends _GraphCommandAcceptance {
  const _GraphCommandDraining();
}

IntentionCommandKind _kindOf(IntentionCommand command) => switch (command) {
  CreateIntention() => IntentionCommandKind.create,
  UpdateIntention() => IntentionCommandKind.update,
  EnableIntentionReadiness() => IntentionCommandKind.enableReadiness,
  DisableIntentionReadiness() => IntentionCommandKind.disableReadiness,
  ArchiveIntention() => IntentionCommandKind.archive,
  RestoreIntention() => IntentionCommandKind.restore,
  DeleteIntention() => IntentionCommandKind.delete,
};
